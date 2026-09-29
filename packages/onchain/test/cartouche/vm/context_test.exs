defmodule Cartouche.VM.ContextTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  import Cartouche.VmTestHelpers

  alias Cartouche.Assembly
  alias Cartouche.VM
  alias Cartouche.VM.Context

  @max_stack_depth 1_024

  describe "init_from/2" do
    test "builds a fresh context with assembled code and initial execution state" do
      ffi = fn <<>> -> {:return, <<1>>} end
      ffis = %{<<1::160>> => ffi}
      code = [{:push, 1, <<0x2A>>}, :stop]

      assert %Context{} = context = Context.init_from(code, ffis)
      assert context.code == code
      assert context.code_encoded == Assembly.assemble(code)
      assert context.op_map == %{0 => {:push, 1, <<0x2A>>}, 2 => :stop}
      assert context.pc == 0
      refute context.halted
      assert context.stack == []
      assert context.memory == <<>>
      assert context.tstorage == %{}
      refute context.reverted
      assert context.return_data == <<>>
      assert context.ffis == ffis
    end

    test "handles empty code and an empty FFI table" do
      assert %Context{
               code: [],
               code_encoded: <<>>,
               op_map: %{},
               ffis: %{}
             } = Context.init_from([], %{})
    end
  end

  describe "fetch_ffi/2" do
    test "returns registered FFI functions and explicit unknown-ffi errors" do
      ffi = fn _args -> {:return, <<>>} end
      address = <<1::160>>
      context = Context.init_from([], %{address => ffi})

      assert {:ok, ^ffi} = Context.fetch_ffi(context, address)
      assert {:error, {:unknown_ffi, <<2::160>>}} = Context.fetch_ffi(context, <<2::160>>)
    end
  end

  describe "show_stack/1" do
    test "renders empty and populated stacks with padded byte offsets" do
      assert Context.show_stack([]) == ""

      {:ok, context} =
        []
        |> Context.init_from(%{})
        |> VM.push_word(word(1))
        |> then(fn {:ok, context} -> VM.push_word(context, word(2)) end)

      assert Context.show_stack(context.stack) ==
               "\t00 #{to_hex(word(1))}\n\t20 #{to_hex(word(2))}"
    end
  end

  describe "show/1" do
    test "renders the program counter and stack section" do
      context = %{Context.init_from([], %{}) | pc: 16, stack: [word(1)]}

      assert Context.show(context) == Enum.join(["pc=16", "stack:", "\t00 #{to_hex(word(1))}"], "\n")
    end
  end

  describe "stack underflow" do
    test "returns explicit errors for empty-stack pop operations" do
      context = Context.init_from([], %{})

      assert {:error, :stack_underflow} = VM.pop_unsigned(context)
      assert {:error, :stack_underflow} = VM.pop2(context)
      assert {:error, :stack_underflow} = VM.pop2_unsigned(context)
      assert {:error, :stack_underflow} = VM.pop3_unsigned(context)
      assert {:error, :stack_underflow} = VM.pop2_unsigned_word(context)
      assert {:error, :stack_underflow} = VM.pop3(context)
    end
  end

  describe "push_word/2" do
    test "rejects a word when the stack is full" do
      context = %{Context.init_from([], %{}) | stack: List.duplicate(word(0), @max_stack_depth)}

      assert {:error, :stack_overflow} = VM.push_word(context, word(1))
    end
  end
end
