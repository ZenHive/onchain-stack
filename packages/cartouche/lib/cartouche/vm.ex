defmodule Cartouche.VM do
  @moduledoc ~S"""
  An Ethereum VM in Cartouche, that can only execute pure functions.
  """
  use Cartouche.Hex

  import Bitwise

  alias Cartouche.Assembly

  require Logger

  @type signed :: integer()
  @type unsigned :: non_neg_integer()

  @type opcode :: Assembly.opcode()
  @type code :: [opcode()]
  @type word :: <<_::256>>
  @type address :: <<_::160>>
  @type ffi :: (binary() -> {:return, binary()} | {:revert, binary()})
  @type ffis :: %{address() => ffi()}
  @type context_result :: {:ok, __MODULE__.Context.t()} | {:error, vm_error()}
  @type exec_opts :: [
          callvalue: integer(),
          ffis: ffis()
        ]
  @type vm_error ::
          :pc_out_of_bounds
          | :value_overflow
          | :stack_underflow
          | :stack_overflow
          | :signed_integer_out_of_bounds
          | :out_of_memory
          | :invalid_operation
          | {:unknown_ffi, address()}
          | {:invalid_push, integer(), binary()}
          | {:impure, opcode()}
          | {:not_implemented, opcode()}

  @word_one <<1::256>>
  @word_zero <<0::256>>
  @two_pow_256 2 ** 256
  @max_uint256 @two_pow_256 - 1
  @gas_amount 4_000_000
  @max_stack_depth 1_024

  defmodule FFIs do
    @moduledoc false
    @doc false
    @spec log_ffi(binary()) :: {:return, binary()}
    def log_ffi(args) do
      case Cartouche.Contract.IConsole.decode_call(args) do
        {:ok, f, values} ->
          IO.puts("console.#{f}: #{inspect(values, limit: :infinity, printable_limit: :infinity)}")

        _ ->
          nil
      end

      {:return, <<>>}
    end
  end

  @builtin_ffis %{
    ~h[0x000000000000000000636F6e736F6c652e6c6f67] => &FFIs.log_ffi/1
  }

  defmodule Input do
    @moduledoc """
    Input to a `Cartouche.VM` execution: the calldata handed to the EVM
    entrypoint and the call's `msg.value`.
    """
    defstruct [:calldata, :value]

    @type t :: %__MODULE__{
            calldata: binary(),
            value: Cartouche.VM.unsigned()
          }
  end

  defmodule Context do
    @moduledoc """
    Runtime execution state of a `Cartouche.VM` step: program counter, stack,
    memory, transient storage, halt/revert flags, return data, and the FFI
    table available to the VM.
    """
    defstruct [
      :code,
      :code_encoded,
      :op_map,
      :pc,
      :halted,
      :stack,
      :memory,
      :tstorage,
      :reverted,
      :return_data,
      :ffis
    ]

    @type op_map :: %{integer() => Cartouche.VM.opcode()}
    @type t :: %__MODULE__{
            code: Cartouche.VM.code(),
            code_encoded: binary(),
            op_map: op_map(),
            pc: integer(),
            halted: boolean(),
            stack: [binary()],
            memory: binary(),
            tstorage: %{binary() => binary()},
            reverted: boolean(),
            return_data: binary(),
            ffis: Cartouche.VM.ffis()
          }

    @doc """
    Builds a fresh `Context` for executing `code` with the given FFI table.
    Pre-computes the program-counter-keyed `op_map` from the assembled
    bytecode so subsequent steps can resolve operations in O(1).
    """
    @spec init_from(Cartouche.VM.code(), Cartouche.VM.ffis()) :: %__MODULE__{
            code: Cartouche.VM.code(),
            code_encoded: binary(),
            op_map: op_map(),
            pc: 0,
            halted: false,
            stack: [],
            memory: <<>>,
            tstorage: %{},
            reverted: false,
            return_data: <<>>,
            ffis: Cartouche.VM.ffis()
          }
    def init_from(code, ffis) do
      code_encoded = Assembly.assemble(code)

      %__MODULE__{
        code: code,
        code_encoded: code_encoded,
        op_map: build_op_map(code),
        pc: 0,
        halted: false,
        stack: [],
        memory: <<>>,
        tstorage: %{},
        reverted: false,
        return_data: <<>>,
        ffis: ffis
      }
    end

    @doc """
    Looks up the FFI registered at `address` in the context's FFI table.
    Returns `{:error, {:unknown_ffi, address}}` when no FFI is registered.
    """
    @spec fetch_ffi(t(), Cartouche.VM.address()) ::
            {:ok, Cartouche.VM.ffi()} | {:error, Cartouche.VM.vm_error()}
    def fetch_ffi(context, address) do
      with :error <- Map.fetch(context.ffis, address) do
        {:error, {:unknown_ffi, address}}
      end
    end

    @spec build_op_map(Cartouche.VM.code()) :: op_map()
    defp build_op_map(code) do
      code
      |> Enum.reduce({0, %{}}, fn operation, {pc, op_map} ->
        new_pc = pc + Assembly.opcode_size(operation)
        {new_pc, Map.put(op_map, pc, operation)}
      end)
      |> elem(1)
    end

    @spec show_hex(integer(), nil | non_neg_integer()) :: String.t()
    defp show_hex(i, padding \\ nil) do
      hex = Integer.to_string(i, 16)

      if padding == nil do
        hex
      else
        String.pad_leading(hex, padding, "0")
      end
    end

    @doc """
    Renders the EVM stack as a debugger-style multi-line string with
    descending offsets and word values in hex.
    """
    @spec show_stack([binary()]) :: String.t()
    def show_stack(stack) do
      hex_length = String.length(show_hex(length(stack) * 32))

      stack
      |> Enum.reverse()
      |> Enum.with_index(fn el, i ->
        "\t#{show_hex(i * 32, hex_length)} #{to_hex(el)}"
      end)
      |> Enum.join("\n")
    end

    @doc """
    Renders the context as a multi-line string showing the program counter
    and stack contents. Used for verbose VM tracing.
    """
    @spec show(t()) :: String.t()
    def show(context) do
      Enum.join(["pc=#{context.pc}", "stack:", show_stack(context.stack)], "\n")
    end
  end

  defmodule ExecutionResult do
    @moduledoc """
    Terminal result of a `Cartouche.VM` run: the final stack, whether the
    call reverted, and the return data.
    """
    defstruct [:stack, :reverted, :return_data]

    @type t :: %__MODULE__{
            stack: [binary()],
            reverted: boolean(),
            return_data: binary()
          }

    @doc """
    Projects a halted execution `Context` down to the public-facing
    `ExecutionResult` — keeping only the final stack, revert flag, and
    return data.
    """
    @spec from_context(Cartouche.VM.Context.t()) :: t()
    def from_context(context) do
      %__MODULE__{
        stack: context.stack,
        reverted: context.reverted,
        return_data: context.return_data
      }
    end
  end

  @spec get_operation(Context.t()) :: {:ok, opcode()} | {:error, vm_error()}
  defp get_operation(context) do
    with :error <- Map.fetch(context.op_map, context.pc) do
      {:error, :pc_out_of_bounds}
    end
  end

  @doc false
  @spec pad_to_word(binary()) :: {:ok, <<_::256>>} | {:error, vm_error()}
  def pad_to_word(bin) when is_binary(bin) do
    if byte_size(bin) > 32 do
      {:error, :value_overflow}
    else
      padded_bin = :binary.copy(<<0>>, 32 - byte_size(bin)) <> bin
      {:ok, padded_bin}
    end
  end

  @doc false
  @spec pop(Context.t()) :: {:ok, Context.t(), word()} | {:error, vm_error()}
  def pop(context) do
    case context.stack do
      [x | rest] ->
        {:ok, %{context | stack: rest}, x}

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec peek(Context.t(), integer()) :: {:ok, word()} | {:error, vm_error()}
  def peek(context, n) do
    case Enum.at(context.stack, n) do
      nil ->
        {:error, :stack_underflow}

      x ->
        {:ok, x}
    end
  end

  @doc false
  @spec pop_unsigned(Context.t()) ::
          {:ok, Context.t(), unsigned()} | {:error, vm_error()}
  def pop_unsigned(context) do
    case context.stack do
      [x_enc | rest] ->
        with {:ok, x} <- word_to_uint(x_enc) do
          {:ok, %{context | stack: rest}, x}
        end

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec pop2(Context.t()) :: {:ok, Context.t(), word(), word()} | {:error, vm_error()}
  def pop2(context) do
    case context.stack do
      [x, y | rest] ->
        {:ok, %{context | stack: rest}, x, y}

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec pop2_unsigned(Context.t()) ::
          {:ok, Context.t(), unsigned(), unsigned()} | {:error, vm_error()}
  def pop2_unsigned(context) do
    case context.stack do
      [x_enc, y_enc | rest] ->
        with {:ok, x} <- word_to_uint(x_enc),
             {:ok, y} <- word_to_uint(y_enc) do
          {:ok, %{context | stack: rest}, x, y}
        end

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec pop3_unsigned(Context.t()) ::
          {:ok, Context.t(), unsigned(), unsigned(), unsigned()} | {:error, vm_error()}
  def pop3_unsigned(context) do
    case context.stack do
      [x_enc, y_enc, z_enc | rest] ->
        with {:ok, x} <- word_to_uint(x_enc),
             {:ok, y} <- word_to_uint(y_enc),
             {:ok, z} <- word_to_uint(z_enc) do
          {:ok, %{context | stack: rest}, x, y, z}
        end

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec pop2_unsigned_word(Context.t()) ::
          {:ok, Context.t(), unsigned(), word()} | {:error, vm_error()}
  def pop2_unsigned_word(context) do
    case context.stack do
      [x_enc, y_enc | rest] ->
        with {:ok, x} <- word_to_uint(x_enc) do
          {:ok, %{context | stack: rest}, x, y_enc}
        end

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec pop3(Context.t()) :: {:ok, Context.t(), word(), word(), word()} | {:error, vm_error()}
  def pop3(context) do
    case context.stack do
      [x, y, z | rest] ->
        {:ok, %{context | stack: rest}, x, y, z}

      [] ->
        {:error, :stack_underflow}
    end
  end

  @doc false
  @spec push_word(Context.t(), word()) :: {:ok, Context.t()} | {:error, vm_error()}
  def push_word(context, v) when is_binary(v) and bit_size(v) == 256 do
    if Enum.count_until(context.stack, @max_stack_depth) == @max_stack_depth do
      {:error, :stack_overflow}
    else
      {:ok, %{context | stack: [v | context.stack]}}
    end
  end

  @doc false
  @spec word_to_uint(binary()) :: {:ok, unsigned()} | {:error, vm_error()}
  def word_to_uint(v) when is_binary(v) do
    {:ok, :binary.decode_unsigned(v)}
  end

  @doc false
  @spec uint_to_word(unsigned()) :: {:ok, binary()} | {:error, vm_error()}
  def uint_to_word(v) when is_integer(v) do
    enc = :binary.encode_unsigned(v)

    pad_to_word(enc)
  end

  @doc false
  @spec word_to_sint(binary()) :: {:ok, signed()} | {:error, vm_error()}
  def word_to_sint(<<value::signed-size(256)>>) do
    {:ok, value}
  end

  def word_to_sint(_) do
    {:error, :signed_integer_out_of_bounds}
  end

  @doc false
  @spec sint_to_word(signed()) :: {:ok, binary()} | {:error, atom()}
  def sint_to_word(v) when is_integer(v) do
    min_value = -2 ** 255
    max_value = 2 ** 255 - 1

    if v >= min_value and v <= max_value do
      {:ok, <<v::signed-size(256)>>}
    else
      {:error, :signed_integer_out_of_bounds}
    end
  end

  @spec pop2_and_push(Context.t(), (word(), word() -> {:ok, word()})) :: context_result()
  defp pop2_and_push(context, fun) do
    with {:ok, context, a, b} <- pop2(context),
         {:ok, v_enc} <- fun.(a, b) do
      push_word(context, v_enc)
    end
  end

  @spec unsigned_op1(Context.t(), (unsigned() -> unsigned())) :: context_result()
  defp unsigned_op1(context, fun) do
    with {:ok, context, a} <- pop(context),
         {:ok, a_int} <- word_to_uint(a),
         v = fun.(a_int),
         {:ok, v_enc} <- uint_to_word(v) do
      push_word(context, v_enc)
    end
  end

  @spec unsigned_op2(Context.t(), (unsigned(), unsigned() -> unsigned())) :: context_result()
  defp unsigned_op2(context, fun) do
    with {:ok, context, a, b} <- pop2(context),
         {:ok, a_int} <- word_to_uint(a),
         {:ok, b_int} <- word_to_uint(b),
         v = fun.(a_int, b_int),
         {:ok, v_enc} <- uint_to_word(v) do
      push_word(context, v_enc)
    end
  end

  @spec unsigned_op3(Context.t(), (unsigned(), unsigned(), unsigned() -> unsigned())) ::
          context_result()
  defp unsigned_op3(context, fun) do
    with {:ok, context, a, b, c} <- pop3(context),
         {:ok, a_int} <- word_to_uint(a),
         {:ok, b_int} <- word_to_uint(b),
         {:ok, c_int} <- word_to_uint(c),
         v = fun.(a_int, b_int, c_int),
         {:ok, v_enc} <- uint_to_word(v) do
      push_word(context, v_enc)
    end
  end

  @spec signed_op2(Context.t(), (signed(), signed() -> signed())) :: context_result()
  defp signed_op2(context, fun) do
    with {:ok, context, a, b} <- pop2(context),
         {:ok, a_int} <- word_to_sint(a),
         {:ok, b_int} <- word_to_sint(b),
         v = fun.(a_int, b_int),
         {:ok, v_enc} <- sint_to_word(v) do
      push_word(context, v_enc)
    end
  end

  @spec unsigned_signed_op2(Context.t(), (unsigned(), signed() -> signed())) :: context_result()
  defp unsigned_signed_op2(context, fun) do
    with {:ok, context, a, b} <- pop2(context),
         {:ok, a_int} <- word_to_uint(a),
         {:ok, b_int} <- word_to_sint(b),
         v = fun.(a_int, b_int),
         {:ok, v_enc} <- sint_to_word(v) do
      push_word(context, v_enc)
    end
  end

  @spec push_n(Context.t(), integer(), binary()) :: context_result()
  defp push_n(context, n, v) do
    if byte_size(v) > n do
      {:error, {:invalid_push, n, v}}
    else
      with {:ok, word_padded} <- pad_to_word(v) do
        push_word(context, word_padded)
      end
    end
  end

  @doc false
  @spec inc_pc(context_result(), opcode()) :: context_result()
  def inc_pc(context_result, operation) do
    with {:ok, context} <- context_result do
      # Note: we can increment even when there's a jump, since either
      # we'll increment over the jump _or_ the jumpdest
      {:ok, %{context | pc: context.pc + Assembly.opcode_size(operation)}}
    end
  end

  @doc false
  @spec cap_to_range(integer(), integer(), integer()) :: integer()
  def cap_to_range(x, min, max) do
    cond do
      x > max ->
        max

      x < min ->
        min

      true ->
        x
    end
  end

  defmodule Memory do
    # 10MB
    @moduledoc false
    alias Cartouche.VM.Context

    @max_memory 10_000_000

    @spec expand_memory(binary(), Cartouche.VM.unsigned()) ::
            {:ok, binary()} | {:error, Cartouche.VM.vm_error()}
    defp expand_memory(memory, total_size) do
      memory_size = byte_size(memory)

      cond do
        total_size > @max_memory ->
          {:error, :out_of_memory}

        memory_size >= total_size ->
          {:ok, memory}

        true ->
          padding = total_size - memory_size

          {:ok, memory <> :binary.copy(<<0x0>>, padding)}
      end
    end

    @doc false
    @spec read_memory(binary(), Cartouche.VM.unsigned(), Cartouche.VM.unsigned()) ::
            {:ok, binary(), binary()} | {:error, Cartouche.VM.vm_error()}
    def read_memory(memory, index, count) do
      with {:ok, memory_expanded} <- expand_memory(memory, index + count) do
        <<_::binary-size(^index), res::binary-size(^count), _::binary>> = memory_expanded
        {:ok, memory_expanded, res}
      end
    end

    @doc false
    @spec write_memory(Context.t(), Cartouche.VM.unsigned(), binary()) ::
            {:ok, Context.t()} | {:error, Cartouche.VM.vm_error()}
    def write_memory(context, offset, value) do
      value_size = byte_size(value)

      with {:ok, memory_expanded} <- expand_memory(context.memory, offset + value_size) do
        <<start::binary-size(^offset), _::binary-size(^value_size), final::binary>> =
          memory_expanded

        memory_final = <<start::binary, value::binary, final::binary>>
        {:ok, %{context | memory: memory_final}}
      end
    end
  end

  defmodule Operations do
    @moduledoc false
    @doc false
    @spec sign_extend(<<_::256>>, <<_::256>>) ::
            {:ok, <<_::256>>} | {:error, Cartouche.VM.vm_error()}
    def sign_extend(b, x) do
      with {:ok, b_int} <- Cartouche.VM.word_to_uint(b) do
        do_sign_extend(b_int, x)
      end
    end

    @spec do_sign_extend(non_neg_integer(), <<_::256>>) :: {:ok, <<_::256>>}
    defp do_sign_extend(b_int, x) when b_int >= 31, do: {:ok, x}

    defp do_sign_extend(b_int, x) do
      val_len = b_int + 1
      <<_::binary-size(32 - ^val_len), low_word::binary-size(^val_len)>> = x
      extend_with_sign(low_word, val_len, x)
    end

    @spec extend_with_sign(binary(), pos_integer(), <<_::256>>) :: {:ok, <<_::256>>}
    defp extend_with_sign(low_word, val_len, x) do
      if Bitwise.band(Bitwise.bsr(:binary.decode_unsigned(low_word), 8 * val_len - 1), 1) == 1 do
        {:ok, :binary.copy(<<0xFF>>, 32 - val_len) <> low_word}
      else
        {:ok, x}
      end
    end

    @doc false
    @spec get_byte(<<_::256>>, <<_::256>>) ::
            {:ok, <<_::256>>} | {:error, Cartouche.VM.vm_error()}
    def get_byte(i, x) do
      with {:ok, i} <- Cartouche.VM.word_to_uint(i) do
        if i < 32 do
          <<_::binary-size(^i), word::binary-size(1), _::binary-size(31 - ^i)>> = x
          Cartouche.VM.pad_to_word(word)
        else
          {:ok, <<0::256>>}
        end
      end
    end
  end

  # Calls
  @spec static_call(Context.t()) :: context_result()
  defp static_call(context) do
    with {:ok, context, _gas, address, args_offset, args_size, ret_offset, ret_size} <-
           pop_call_args(context),
         {:ok, memory_expanded, args} <-
           Memory.read_memory(context.memory, args_offset, args_size),
         context = %{context | memory: memory_expanded},
         {:ok, ffi} <- Context.fetch_ffi(context, address) do
      handle_static_call_result(ffi.(args), context, ret_offset, ret_size)
    end
  end

  @spec handle_static_call_result({:return | :revert, binary()}, Context.t(), non_neg_integer(), non_neg_integer()) ::
          context_result()
  defp handle_static_call_result({:return, return_data}, context, ret_offset, ret_size) do
    return_data_to_copy = pad_or_truncate_return(return_data, ret_size)

    with {:ok, context} <-
           context
           |> Map.put(:return_data, return_data)
           |> Memory.write_memory(ret_offset, return_data_to_copy) do
      push_word(context, @word_one)
    end
  end

  defp handle_static_call_result({:revert, revert}, context, _ret_offset, _ret_size) do
    context
    |> Map.merge(%{return_data: revert, halted: true, reverted: true})
    |> push_word(@word_zero)
  end

  @spec pad_or_truncate_return(binary(), non_neg_integer()) :: binary()
  defp pad_or_truncate_return(return_data, ret_size) when byte_size(return_data) >= ret_size do
    <<v::binary-size(^ret_size), _::binary>> = return_data
    v
  end

  defp pad_or_truncate_return(return_data, ret_size) do
    return_data <> :binary.copy(<<0x0>>, ret_size - byte_size(return_data))
  end

  @spec pop_call_args(Context.t()) ::
          {:ok, Context.t(), non_neg_integer(), address(), non_neg_integer(), non_neg_integer(), non_neg_integer(),
           non_neg_integer()}
          | {:error, vm_error()}
  defp pop_call_args(context) do
    with {:ok, context, gas} <- pop_unsigned(context),
         {:ok, context, address_word} <- pop(context),
         {:ok, context, args_offset} <- pop_unsigned(context),
         {:ok, context, args_size} <- pop_unsigned(context),
         {:ok, context, ret_offset} <- pop_unsigned(context),
         {:ok, context, ret_size} <- pop_unsigned(context) do
      {:ok, context, gas, word_to_address(address_word), args_offset, args_size, ret_offset, ret_size}
    end
  end

  @spec word_to_address(word()) :: address()
  defp word_to_address(word) do
    <<_preface::binary-size(12), address::binary-size(20)>> = word

    address
  end

  @doc false
  @spec run_single_op(Context.t(), Input.t(), Keyword.t()) :: context_result()
  # EVM opcode dispatch table — every opcode needs a clause; splitting into helpers
  # adds indirection without reducing real complexity. CC reflects the EVM spec.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def run_single_op(context, input, opts) do
    if opts[:verbose] do
      Logger.debug(Context.show(context))
    end

    with {:ok, operation} <- get_operation(context) do
      if opts[:verbose] do
        Logger.debug("Operation: #{Assembly.show_opcode(operation)}")
      end

      case_result =
        case operation do
          :stop ->
            {:ok, %{context | return_data: <<>>, halted: true}}

          :add ->
            unsigned_op2(context, &rem(&1 + &2, @two_pow_256))

          :sub ->
            unsigned_op2(context, &rem(@two_pow_256 + &1 - &2, @two_pow_256))

          :mul ->
            unsigned_op2(context, &rem(&1 * &2, @two_pow_256))

          :div ->
            unsigned_op2(context, &safe_floor_div/2)

          :sdiv ->
            signed_op2(context, &safe_floor_div/2)

          :mod ->
            unsigned_op2(context, &safe_rem/2)

          :smod ->
            signed_op2(context, &safe_rem/2)

          :addmod ->
            unsigned_op3(context, &safe_addmod/3)

          :mulmod ->
            unsigned_op3(context, &safe_mulmod/3)

          :exp ->
            unsigned_op2(context, &rem(&1 ** &2, @two_pow_256))

          :signextend ->
            pop2_and_push(context, &Operations.sign_extend/2)

          :lt ->
            unsigned_op2(context, &int_lt/2)

          :gt ->
            unsigned_op2(context, &int_gt/2)

          :slt ->
            signed_op2(context, &int_lt/2)

          :sgt ->
            signed_op2(context, &int_gt/2)

          :eq ->
            unsigned_op2(context, &int_eq/2)

          :iszero ->
            unsigned_op1(context, &int_is_zero/1)

          :and ->
            unsigned_op2(context, &Bitwise.band(&1, &2))

          :or ->
            unsigned_op2(context, &Bitwise.bor(&1, &2))

          :xor ->
            unsigned_op2(context, &Bitwise.bxor(&1, &2))

          :not ->
            unsigned_op1(context, &Bitwise.bxor(&1, @max_uint256))

          :byte ->
            pop2_and_push(context, &Operations.get_byte/2)

          :shl ->
            unsigned_op2(context, &rem(Bitwise.bsl(&2, cap_to_range(&1, 0, 255)), @two_pow_256))

          :shr ->
            unsigned_op2(context, &Bitwise.bsr(&2, cap_to_range(&1, 0, 255)))

          :sar ->
            unsigned_signed_op2(context, &(&2 >>> cap_to_range(&1, 0, 255)))

          :sha3 ->
            do_sha3(context)

          :callvalue ->
            do_callvalue(context, input)

          :calldataload ->
            do_calldataload(context, input)

          :calldatasize ->
            do_calldatasize(context, input)

          :calldatacopy ->
            do_calldatacopy(context, input)

          :codesize ->
            do_codesize(context)

          :codecopy ->
            do_codecopy(context)

          :pop ->
            do_pop_op(context)

          :mload ->
            do_mload(context)

          :mstore ->
            do_mstore(context)

          :mstore8 ->
            do_mstore8(context)

          :jump ->
            do_jump_op(context)

          :jumpi ->
            do_jumpi_op(context)

          :pc ->
            do_pc(context)

          :msize ->
            do_msize(context)

          :gas ->
            do_gas(context)

          :jumpdest ->
            {:ok, context}

          :tload ->
            do_tload(context)

          :tstore ->
            do_tstore(context)

          :mcopy ->
            do_mcopy(context)

          {:push, n, v} ->
            push_n(context, n, v)

          {:dup, n} ->
            do_dup(context, n)

          {:swap, n} ->
            do_swap(context, n)

          :return ->
            do_return(context)

          :revert ->
            do_revert(context)

          {:invalid, _} ->
            {:error, :invalid_operation}

          :staticcall ->
            static_call(context)

          :returndatasize ->
            do_returndatasize(context)

          :returndatacopy ->
            do_returndatacopy(context)

          op
          when op in [
                 :address,
                 :balance,
                 :origin,
                 :caller,
                 :gasprice,
                 :extcodesize,
                 :extcodecopy,
                 :extcodehash,
                 :blockhash,
                 :coinbase,
                 :timestamp,
                 :number,
                 :prevrandao,
                 :gaslimit,
                 :chainid,
                 :selfbalance,
                 :basefee,
                 :blobhash,
                 :blobbasefee,
                 :sload,
                 :sstore,
                 :log,
                 :create,
                 :call,
                 :callcode,
                 :delegatecall,
                 :create2,
                 :selfdestruct
               ] ->
            {:error, {:impure, operation}}

          _ ->
            {:error, {:not_implemented, operation}}
        end

      inc_pc(case_result, operation)
    end
  end

  @spec do_jump(Context.t(), non_neg_integer()) :: context_result()
  defp do_jump(context, jump_dest) do
    case Map.get(context.op_map, jump_dest) do
      :jumpdest -> {:ok, %{context | pc: jump_dest}}
      _ -> {:error, :invalid_jump_dest}
    end
  end

  @spec do_jumpi(Context.t(), non_neg_integer(), non_neg_integer()) :: context_result()
  defp do_jumpi(context, _jump_dest, 0), do: {:ok, context}
  defp do_jumpi(context, jump_dest, _b), do: do_jump(context, jump_dest)

  @spec do_returndatacopy(Context.t()) :: context_result()
  defp do_returndatacopy(context) do
    with {:ok, context, dest_offset, offset, size} <- pop3_unsigned(context),
         {:ok, _, calldata} <- Memory.read_memory(context.return_data, offset, size) do
      Memory.write_memory(context, dest_offset, calldata)
    end
  end

  @spec do_returndatasize(Context.t()) :: context_result()
  defp do_returndatasize(context) do
    with {:ok, return_data_size} <- uint_to_word(byte_size(context.return_data)) do
      push_word(context, return_data_size)
    end
  end

  @spec do_return(Context.t()) :: context_result()
  defp do_return(context) do
    with {:ok, context, offset, size} <- pop2_unsigned(context),
         {:ok, memory_expanded, return_data} <-
           Memory.read_memory(context.memory, offset, size) do
      {:ok, %{context | memory: memory_expanded, return_data: return_data, halted: true}}
    end
  end

  @spec do_revert(Context.t()) :: context_result()
  defp do_revert(context) do
    with {:ok, context, offset, size} <- pop2_unsigned(context),
         {:ok, memory_expanded, return_data} <-
           Memory.read_memory(context.memory, offset, size) do
      {:ok,
       %{
         context
         | memory: memory_expanded,
           return_data: return_data,
           halted: true,
           reverted: true
       }}
    end
  end

  @spec do_swap(Context.t(), non_neg_integer()) :: context_result()
  defp do_swap(context, n) do
    with {:ok, high} <- peek(context, n),
         {:ok, low} <- peek(context, 0) do
      stack =
        context.stack
        |> List.replace_at(n, low)
        |> List.replace_at(0, high)

      {:ok, %{context | stack: stack}}
    end
  end

  @spec do_dup(Context.t(), pos_integer()) :: context_result()
  defp do_dup(context, n) do
    with {:ok, val} <- peek(context, n - 1) do
      push_word(context, val)
    end
  end

  @spec do_sha3(Context.t()) :: context_result()
  defp do_sha3(context) do
    with {:ok, context, offset, size} <- pop2_unsigned(context),
         {:ok, memory_expanded, data} <- Memory.read_memory(context.memory, offset, size) do
      push_word(%{context | memory: memory_expanded}, Cartouche.Hash.keccak(data))
    end
  end

  @spec do_callvalue(Context.t(), Input.t()) :: context_result()
  defp do_callvalue(context, input) do
    with {:ok, value} <- uint_to_word(input.value) do
      push_word(context, value)
    end
  end

  @spec do_calldataload(Context.t(), Input.t()) :: context_result()
  defp do_calldataload(context, input) do
    with {:ok, context, i} <- pop_unsigned(context),
         {:ok, _, res} <- Memory.read_memory(input.calldata, i, 32) do
      push_word(context, res)
    end
  end

  @spec do_calldatasize(Context.t(), Input.t()) :: context_result()
  defp do_calldatasize(context, input) do
    with {:ok, calldata_size} <- uint_to_word(byte_size(input.calldata)) do
      push_word(context, calldata_size)
    end
  end

  @spec do_calldatacopy(Context.t(), Input.t()) :: context_result()
  defp do_calldatacopy(context, input) do
    with {:ok, context, dest_offset, offset, size} <- pop3_unsigned(context),
         {:ok, _, calldata} <- Memory.read_memory(input.calldata, offset, size) do
      Memory.write_memory(context, dest_offset, calldata)
    end
  end

  @spec do_codesize(Context.t()) :: context_result()
  defp do_codesize(context) do
    with {:ok, codesize} <- uint_to_word(byte_size(context.code_encoded)) do
      push_word(context, codesize)
    end
  end

  @spec do_codecopy(Context.t()) :: context_result()
  defp do_codecopy(context) do
    with {:ok, context, dest_offset, offset, size} <- pop3_unsigned(context),
         {:ok, _, code} <- Memory.read_memory(context.code_encoded, offset, size) do
      Memory.write_memory(context, dest_offset, code)
    end
  end

  @spec do_pop_op(Context.t()) :: context_result()
  defp do_pop_op(context) do
    with {:ok, context, _} <- pop(context) do
      {:ok, context}
    end
  end

  @spec do_mload(Context.t()) :: context_result()
  defp do_mload(context) do
    with {:ok, context, i} <- pop_unsigned(context),
         {:ok, memory_expanded, res} <- Memory.read_memory(context.memory, i, 32) do
      push_word(%{context | memory: memory_expanded}, res)
    end
  end

  @spec do_mstore(Context.t()) :: context_result()
  defp do_mstore(context) do
    with {:ok, context, offset, value} <- pop2_unsigned_word(context) do
      Memory.write_memory(context, offset, value)
    end
  end

  @spec do_mstore8(Context.t()) :: context_result()
  defp do_mstore8(context) do
    with {:ok, context, offset, value} <- pop2_unsigned_word(context) do
      <<_::binary-size(31), byte::binary>> = value
      Memory.write_memory(context, offset, byte)
    end
  end

  @spec do_jump_op(Context.t()) :: context_result()
  defp do_jump_op(context) do
    with {:ok, context, jump_dest} <- pop_unsigned(context) do
      do_jump(context, jump_dest)
    end
  end

  @spec do_jumpi_op(Context.t()) :: context_result()
  defp do_jumpi_op(context) do
    with {:ok, context, jump_dest, b} <- pop2_unsigned(context) do
      do_jumpi(context, jump_dest, b)
    end
  end

  @spec do_pc(Context.t()) :: context_result()
  defp do_pc(context) do
    with {:ok, pc} <- uint_to_word(context.pc) do
      push_word(context, pc)
    end
  end

  @spec do_msize(Context.t()) :: context_result()
  defp do_msize(context) do
    with {:ok, memory_sz} <- uint_to_word(byte_size(context.memory)) do
      push_word(context, memory_sz)
    end
  end

  @spec do_gas(Context.t()) :: context_result()
  defp do_gas(context) do
    with {:ok, gas_amount} <- uint_to_word(@gas_amount) do
      push_word(context, gas_amount)
    end
  end

  @spec do_tload(Context.t()) :: context_result()
  defp do_tload(context) do
    with {:ok, context, res} <- pop_unsigned(context) do
      push_word(context, Map.get(context.tstorage, res, <<0::256>>))
    end
  end

  @spec do_tstore(Context.t()) :: context_result()
  defp do_tstore(context) do
    with {:ok, context, key, value} <- pop2_unsigned_word(context) do
      {:ok, %{context | tstorage: Map.put(context.tstorage, key, value)}}
    end
  end

  @spec do_mcopy(Context.t()) :: context_result()
  defp do_mcopy(context) do
    with {:ok, context, dest_offset, offset, size} <- pop3_unsigned(context),
         {:ok, memory_expanded, value} <- Memory.read_memory(context.memory, offset, size) do
      Memory.write_memory(%{context | memory: memory_expanded}, dest_offset, value)
    end
  end

  @spec safe_floor_div(integer(), integer()) :: integer()
  defp safe_floor_div(_a, 0), do: 0
  defp safe_floor_div(a, b), do: Integer.floor_div(a, b)

  @spec safe_rem(integer(), integer()) :: integer()
  defp safe_rem(_a, 0), do: 0
  defp safe_rem(a, b), do: rem(a, b)

  @spec safe_addmod(integer(), integer(), integer()) :: integer()
  defp safe_addmod(_a, _b, 0), do: 0
  defp safe_addmod(a, b, n), do: rem(a + b, n)

  @spec safe_mulmod(integer(), integer(), integer()) :: integer()
  defp safe_mulmod(_a, _b, 0), do: 0
  defp safe_mulmod(a, b, n), do: rem(a * b, n)

  @spec int_lt(integer(), integer()) :: 0 | 1
  defp int_lt(a, b) when a < b, do: 1
  defp int_lt(_a, _b), do: 0

  @spec int_gt(integer(), integer()) :: 0 | 1
  defp int_gt(a, b) when a > b, do: 1
  defp int_gt(_a, _b), do: 0

  @spec int_eq(integer(), integer()) :: 0 | 1
  defp int_eq(a, b) when a == b, do: 1
  defp int_eq(_a, _b), do: 0

  @spec int_is_zero(integer()) :: 0 | 1
  defp int_is_zero(0), do: 1
  defp int_is_zero(_), do: 0

  @spec run_code(Context.t(), Input.t(), Keyword.t()) ::
          {:ok, ExecutionResult.t()} | {:error, vm_error()}
  defp run_code(context, input, opts \\ []) do
    case run_single_op(context, input, opts) do
      {:ok, %Context{halted: true} = context} ->
        {:ok, ExecutionResult.from_context(context)}

      {:ok, context} ->
        run_code(context, input)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~S"""
  Executes the Ethereum Virtual Machine (EVM) with the given `code` and `input`.

  **Parameters**
    - `code`: The bytecode to be executed, either as a `binary` or decoded.
    - `calldata`: The call data for the execution.
    - `opts`: Execution options (see below)

  **Options**
    - `:callvalue`: value passed as callvalue for the execution.
    - `:ffis`: A mapping of address to functions to run as natively implemented ffis

  Returns the result of the execution.
  """
  @spec exec(code() | binary(), binary(), exec_opts()) ::
          {:ok, ExecutionResult.t()} | {:error, vm_error()}
  def exec(code, calldata, opts \\ [])

  def exec(code, calldata, opts) when is_binary(code) do
    exec(Assembly.disassemble(code), calldata, opts)
  end

  def exec(code, calldata, opts) when is_list(code) do
    run_code(
      Context.init_from(code, Map.merge(@builtin_ffis, Keyword.get(opts, :ffis, %{}))),
      %Input{
        calldata: calldata,
        value: Keyword.get(opts, :callvalue, 0)
      },
      opts
    )
  end

  defmodule InvalidVm do
    @moduledoc """
    Raised by `Cartouche.VM.exec/3` (and friends) when the EVM run terminates
    in a non-recoverable error state — e.g. invalid opcode, stack underflow,
    or unhandled exception inside an opcode handler.

    Public callers can `rescue Cartouche.VM.InvalidVm` to handle these.
    """
    defexception message: "InvalidVm"
  end

  @doc ~S"""
  Runs the given EVM, returning the `RETURN` data or the `REVERT` data.

  Raises on any other exceptional state.

  **Parameters**
    - `code`: The bytecode to be executed, either as a `binary` or decoded.
    - `calldata`: The call data for the execution.
    - `opts`: Execution options (see below)

  **Options**
    - `:callvalue`: value passed as callvalue for the execution.
    - `:ffis`: A mapping of address to functions to run as natively implemented ffis
  """
  @spec exec_call(code() | binary(), binary(), exec_opts()) ::
          {:ok, binary()} | {:revert, binary()}
  def exec_call(code, calldata, opts \\ []) do
    case exec(code, calldata, opts) do
      {:ok, %ExecutionResult{reverted: reverted, return_data: return_data}} ->
        if reverted do
          {:revert, return_data}
        else
          {:ok, return_data}
        end

      {:error, error} ->
        raise InvalidVm, "InvalidVm: #{inspect(error)}"
    end
  end
end
