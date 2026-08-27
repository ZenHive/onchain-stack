defmodule Cartouche.Solana.Transaction do
  @moduledoc """
  Build, serialize, sign, and deserialize Solana transactions (legacy format).

  A Solana transaction consists of signatures and a message. The message
  contains a header, ordered account keys, a recent blockhash, and compiled
  instructions. Each signer signs the raw serialized message bytes.

  ## Example: Build and sign a SOL transfer

      fee_payer = <<...>>  # 32-byte pubkey
      recipient = <<...>>  # 32-byte pubkey
      blockhash = <<...>>  # 32 bytes from getLatestBlockhash

      instruction = Cartouche.Solana.SystemProgram.transfer(fee_payer, recipient, 1_000_000_000)

      message = Cartouche.Solana.Transaction.build_message(fee_payer, [instruction], blockhash)
      transaction = Cartouche.Solana.Transaction.sign(message, [fee_payer_seed])

      # Serialize for RPC submission
      bytes = Cartouche.Solana.Transaction.serialize(transaction)
  """

  use Descripex, namespace: "/solana/transaction"

  import Bitwise

  defmodule AccountMeta do
    @moduledoc "Account reference with permission flags."
    @type t :: %__MODULE__{
            pubkey: <<_::256>>,
            is_signer: boolean(),
            is_writable: boolean()
          }
    defstruct [:pubkey, :is_signer, :is_writable]
  end

  defmodule Instruction do
    @moduledoc "A high-level instruction before compilation."
    @type t :: %__MODULE__{
            program_id: <<_::256>>,
            accounts: [AccountMeta.t()],
            data: binary()
          }
    defstruct [:program_id, :accounts, :data]
  end

  defmodule Header do
    @moduledoc "Message header with account permission counts."
    @type t :: %__MODULE__{
            num_required_signatures: non_neg_integer(),
            num_readonly_signed_accounts: non_neg_integer(),
            num_readonly_unsigned_accounts: non_neg_integer()
          }
    defstruct num_required_signatures: 0,
              num_readonly_signed_accounts: 0,
              num_readonly_unsigned_accounts: 0
  end

  defmodule CompiledInstruction do
    @moduledoc "An instruction compiled to account indices."
    @type account_index() :: 0..255
    @type t :: %__MODULE__{
            program_id_index: account_index(),
            accounts: [account_index()],
            data: binary()
          }
    defstruct [:program_id_index, :accounts, :data]
  end

  defmodule Message do
    @moduledoc "The transaction message that gets signed."
    @type t :: %__MODULE__{
            header: Header.t(),
            account_keys: [<<_::256>>],
            recent_blockhash: <<_::256>>,
            instructions: [CompiledInstruction.t()]
          }
    defstruct [:header, :account_keys, :recent_blockhash, :instructions]
  end

  @type t :: %__MODULE__{
          signatures: [<<_::512>>],
          message: Message.t()
        }
  defstruct [:signatures, :message]

  # ---------------------------------------------------------------------------
  # Compact-u16 encoding
  # ---------------------------------------------------------------------------

  api(:encode_compact_u16, "Encode a non-negative integer as Solana compact-u16 bytes.",
    params: [
      value: [kind: :value, description: "Integer in the compact-u16 range 0..65535."]
    ],
    returns: %{
      type: :binary,
      description: "Variable-length compact-u16 encoding used by Solana transaction messages."
    }
  )

  @doc """
  Encode a non-negative integer as a compact-u16 (variable-length).

  ## Examples

      iex> Cartouche.Solana.Transaction.encode_compact_u16(0)
      <<0>>

      iex> Cartouche.Solana.Transaction.encode_compact_u16(127)
      <<127>>

      iex> Cartouche.Solana.Transaction.encode_compact_u16(128)
      <<128, 1>>

      iex> Cartouche.Solana.Transaction.encode_compact_u16(16384)
      <<128, 128, 1>>
  """
  @spec encode_compact_u16(non_neg_integer()) :: binary()
  def encode_compact_u16(value) when value >= 0 and value <= 0xFFFF do
    encode_compact_u16_acc(value, <<>>)
  end

  @spec encode_compact_u16_acc(non_neg_integer(), binary()) :: binary()
  defp encode_compact_u16_acc(value, acc) when value < 0x80 do
    acc <> <<value>>
  end

  defp encode_compact_u16_acc(value, acc) do
    encode_compact_u16_acc(value >>> 7, acc <> <<(value &&& 0x7F) ||| 0x80>>)
  end

  api(:decode_compact_u16, "Decode a Solana compact-u16 prefix.",
    params: [
      binary: [kind: :value, description: "Binary beginning with a compact-u16 value."]
    ],
    returns: %{
      type: :tuple,
      description: "`{value, rest}` with the decoded non-negative integer and remaining bytes."
    }
  )

  @doc """
  Decode a compact-u16 from the beginning of a binary.

  Returns `{value, rest}`. Raises `FunctionClauseError` on empty or truncated
  input — internal callers that need an error tuple use `safe_decode_compact_u16/1`.

  ## Examples

      iex> Cartouche.Solana.Transaction.decode_compact_u16(<<0, 99>>)
      {0, <<99>>}

      iex> Cartouche.Solana.Transaction.decode_compact_u16(<<128, 1, 99>>)
      {128, <<99>>}
  """
  @spec decode_compact_u16(binary()) :: {non_neg_integer(), binary()}
  def decode_compact_u16(binary) do
    decode_compact_u16_acc(binary, 0, 0)
  end

  @spec decode_compact_u16_acc(binary(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  defp decode_compact_u16_acc(<<byte, rest::binary>>, acc, shift) when byte >= 0x80 do
    decode_compact_u16_acc(rest, acc ||| (byte &&& 0x7F) <<< shift, shift + 7)
  end

  defp decode_compact_u16_acc(<<byte, rest::binary>>, acc, shift) do
    {acc ||| byte <<< shift, rest}
  end

  @spec safe_decode_compact_u16(binary()) ::
          {:ok, non_neg_integer(), binary()} | {:error, :truncated_compact_u16}
  defp safe_decode_compact_u16(binary), do: safe_decode_compact_u16_acc(binary, 0, 0)

  @spec safe_decode_compact_u16_acc(binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer(), binary()} | {:error, :truncated_compact_u16}
  defp safe_decode_compact_u16_acc(<<byte, rest::binary>>, acc, shift) when byte >= 0x80 do
    safe_decode_compact_u16_acc(rest, acc ||| (byte &&& 0x7F) <<< shift, shift + 7)
  end

  defp safe_decode_compact_u16_acc(<<byte, rest::binary>>, acc, shift) do
    {:ok, acc ||| byte <<< shift, rest}
  end

  defp safe_decode_compact_u16_acc(<<>>, _acc, _shift), do: {:error, :truncated_compact_u16}

  # ---------------------------------------------------------------------------
  # Building messages
  # ---------------------------------------------------------------------------

  api(:build_message, "Build a compiled Solana transaction message from high-level instructions.",
    params: [
      fee_payer: [
        kind: :value,
        description: "32-byte Solana fee-payer public key; encode with Base58 for the address string."
      ],
      instructions: [
        kind: :value,
        description: "List of `%Cartouche.Solana.Transaction.Instruction{}` values to compile."
      ],
      recent_blockhash: [
        kind: :exchange_data,
        source: "Cartouche.Solana.RPC.get_latest_blockhash/1",
        description: "32-byte recent blockhash returned by Solana RPC."
      ]
    ],
    returns: %{
      type: :solana_message,
      description: "`%Cartouche.Solana.Transaction.Message{}` with ordered account keys and compiled instructions."
    }
  )

  @doc """
  Build a compiled message from high-level instructions.

  Handles account deduplication, permission merging, ordering, and index
  compilation. The fee payer is always placed first as a writable signer.
  """
  @spec build_message(<<_::256>>, [Instruction.t()], <<_::256>>) :: Message.t()
  def build_message(<<fee_payer::binary-32>>, instructions, <<recent_blockhash::binary-32>>) do
    # 1. Collect all unique accounts with merged permissions
    account_map = collect_accounts(fee_payer, instructions)

    # 2. Sort into the four groups
    {writable_signers, readonly_signers, writable_nonsigners, readonly_nonsigners} =
      partition_accounts(account_map, fee_payer)

    # 3. Build the ordered account keys list
    ordered_keys =
      writable_signers ++ readonly_signers ++ writable_nonsigners ++ readonly_nonsigners

    # 4. Build index lookup map
    index_map =
      ordered_keys
      |> Enum.with_index()
      |> Map.new()

    # 5. Compile instructions
    compiled =
      Enum.map(instructions, fn ix ->
        %CompiledInstruction{
          program_id_index: Map.fetch!(index_map, ix.program_id),
          accounts: Enum.map(ix.accounts, fn am -> Map.fetch!(index_map, am.pubkey) end),
          data: ix.data
        }
      end)

    # 6. Build header
    readonly_signers_count = length(readonly_signers)

    header = %Header{
      num_required_signatures: length(writable_signers) + readonly_signers_count,
      num_readonly_signed_accounts: readonly_signers_count,
      num_readonly_unsigned_accounts: length(readonly_nonsigners)
    }

    %Message{
      header: header,
      account_keys: ordered_keys,
      recent_blockhash: recent_blockhash,
      instructions: compiled
    }
  end

  @spec collect_accounts(<<_::256>>, [Instruction.t()]) :: %{<<_::256>> => {boolean(), boolean()}}
  defp collect_accounts(fee_payer, instructions) do
    # Start with fee payer as writable + signer
    init = %{fee_payer => {true, true}}
    Enum.reduce(instructions, init, &merge_instruction_accounts/2)
  end

  @spec merge_instruction_accounts(Instruction.t(), %{<<_::256>> => {boolean(), boolean()}}) :: %{
          <<_::256>> => {boolean(), boolean()}
        }
  defp merge_instruction_accounts(ix, acc) do
    # Program ID is a readonly non-signer
    acc = Map.update(acc, ix.program_id, {false, false}, fn {s, w} -> {s, w} end)
    Enum.reduce(ix.accounts, acc, &merge_account_meta/2)
  end

  @spec merge_account_meta(AccountMeta.t(), %{<<_::256>> => {boolean(), boolean()}}) :: %{
          <<_::256>> => {boolean(), boolean()}
        }
  defp merge_account_meta(am, acc) do
    Map.update(acc, am.pubkey, {am.is_signer, am.is_writable}, fn {s, w} ->
      {s or am.is_signer, w or am.is_writable}
    end)
  end

  @spec partition_accounts(%{<<_::256>> => {boolean(), boolean()}}, <<_::256>>) ::
          {[<<_::256>>], [<<_::256>>], [<<_::256>>], [<<_::256>>]}
  defp partition_accounts(account_map, fee_payer) do
    # Remove fee payer from the map; it's always first in writable_signers
    rest = Map.delete(account_map, fee_payer)

    {ws, rs, wn, rn} =
      Enum.reduce(rest, {[], [], [], []}, fn {pubkey, {is_signer, is_writable}}, {ws, rs, wn, rn} ->
        case {is_signer, is_writable} do
          {true, true} -> {[pubkey | ws], rs, wn, rn}
          {true, false} -> {ws, [pubkey | rs], wn, rn}
          {false, true} -> {ws, rs, [pubkey | wn], rn}
          {false, false} -> {ws, rs, wn, [pubkey | rn]}
        end
      end)

    # Fee payer is always first writable signer
    {[fee_payer | Enum.sort(ws)], Enum.sort(rs), Enum.sort(wn), Enum.sort(rn)}
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  api(:serialize_message, "Serialize a Solana message to the bytes that signers sign.",
    params: [
      msg: [
        kind: :value,
        description: "`%Cartouche.Solana.Transaction.Message{}` to serialize."
      ]
    ],
    returns: %{type: :binary, description: "Canonical Solana message bytes used for Ed25519 signing."}
  )

  @doc """
  Serialize a message to the bytes that get signed.
  """
  @spec serialize_message(Message.t()) :: binary()
  def serialize_message(%Message{} = msg) do
    # Preserve the pre-iodata raise-on-malformed contract that the original
    # `Enum.reduce(..., fn <<key::binary-32>>, acc -> acc <> key end)` enforced:
    # a non-32-byte account key must fail at this boundary, not silently flatten
    # into the wire format (where the compact-u16 length prefix would lie about
    # how many keys are present and downstream parsers would consume the
    # blockhash / instruction bytes as "remainder of the account-key region").
    Enum.each(msg.account_keys, fn <<_::binary-32>> -> :ok end)

    header_bytes =
      <<msg.header.num_required_signatures, msg.header.num_readonly_signed_accounts,
        msg.header.num_readonly_unsigned_accounts>>

    instructions_iodata = Enum.map(msg.instructions, &serialize_compiled_instruction/1)

    IO.iodata_to_binary([
      header_bytes,
      encode_compact_u16(length(msg.account_keys)),
      msg.account_keys,
      msg.recent_blockhash,
      encode_compact_u16(length(msg.instructions)),
      instructions_iodata
    ])
  end

  @spec serialize_compiled_instruction(CompiledInstruction.t()) :: binary()
  defp serialize_compiled_instruction(%CompiledInstruction{} = ix) do
    <<ix.program_id_index>> <>
      encode_compact_u16(length(ix.accounts)) <>
      :binary.list_to_bin(ix.accounts) <>
      encode_compact_u16(byte_size(ix.data)) <>
      ix.data
  end

  api(:serialize, "Serialize a full legacy Solana transaction for RPC submission.",
    params: [
      transaction: [
        kind: :value,
        description: "`%Cartouche.Solana.Transaction{}` containing signatures and a message."
      ]
    ],
    returns: %{type: :binary, description: "Legacy Solana transaction bytes suitable for RPC submission."}
  )

  @doc """
  Serialize a full transaction (signatures + message) for RPC submission.
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{signatures: sigs, message: msg}) do
    # Same raise-on-malformed contract as `serialize_message/1` above:
    # the original `Enum.reduce(sigs, <<>>, fn <<sig::binary-64>>, acc -> ... end)`
    # rejected non-64-byte signatures via FunctionClauseError. Preserve that
    # boundary so a malformed sig fails here instead of silently producing a
    # malformed transaction whose compact-u16 length prefix lies.
    Enum.each(sigs, fn <<_::binary-64>> -> :ok end)

    IO.iodata_to_binary([
      encode_compact_u16(length(sigs)),
      sigs,
      serialize_message(msg)
    ])
  end

  # ---------------------------------------------------------------------------
  # Deserialization
  # ---------------------------------------------------------------------------

  api(:deserialize, "Deserialize legacy Solana transaction bytes.",
    params: [
      binary: [kind: :value, description: "Binary legacy Solana transaction payload."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.Solana.Transaction{}}` on complete well-formed input, or `{:error, reason}` for malformed input."
    }
  )

  @doc """
  Deserialize a legacy transaction from binary.

  Returns `{:ok, t()}` on a complete, well-formed transaction; `{:error, atom()}`
  on malformed input. Possible error atoms:

    * `:truncated_compact_u16` — compact-u16 prefix ends mid-byte
    * `:insufficient_signature_data` — signature-count exceeds remaining bytes
    * `:insufficient_pubkey_data` — pubkey-count exceeds remaining bytes
    * `:insufficient_instruction_data` — instruction-count, account-list, or data-payload exceeds remaining bytes
    * `:invalid_message_header` — fewer than 3 header bytes
    * `:invalid_message_body` — blockhash truncated or other structural mismatch the inner clauses didn't tag
    * `:invalid_transaction` — message parsed but trailing bytes remain
  """
  @spec deserialize(binary()) :: {:ok, t()} | {:error, term()}
  def deserialize(binary) do
    with {:ok, num_sigs, rest} <- safe_decode_compact_u16(binary),
         {:ok, sigs, rest} <- read_signatures(rest, num_sigs, []),
         {:ok, msg, <<>>} <- deserialize_message(rest) do
      {:ok, %__MODULE__{signatures: sigs, message: msg}}
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_transaction}
    end
  end

  api(:deserialize_message, "Deserialize a Solana transaction message prefix.",
    params: [
      binary: [kind: :value, description: "Binary beginning with a legacy Solana message."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.Solana.Transaction.Message{}, rest}` when a message parses, or `{:error, reason}` for malformed input."
    }
  )

  @doc """
  Deserialize a message from binary.

  Returns `{:ok, Message.t(), rest :: binary()}` on success — `rest` is whatever
  bytes follow the message (callers like `deserialize/1` enforce `rest == <<>>`).

  Returns `{:error, :invalid_message_header}` when fewer than 3 header bytes are
  present. Specific atoms surface from inner parse clauses
  (`:truncated_compact_u16`, `:insufficient_pubkey_data`, `:insufficient_instruction_data`);
  `{:error, :invalid_message_body}` is the catch-all for structural mismatches the
  inner clauses didn't tag (notably a truncated blockhash).
  """
  @spec deserialize_message(binary()) :: {:ok, Message.t(), binary()} | {:error, term()}
  def deserialize_message(<<num_required_signatures, num_readonly_signed, num_readonly_unsigned, rest::binary>>) do
    header = %Header{
      num_required_signatures: num_required_signatures,
      num_readonly_signed_accounts: num_readonly_signed,
      num_readonly_unsigned_accounts: num_readonly_unsigned
    }

    with {:ok, num_keys, rest} <- safe_decode_compact_u16(rest),
         {:ok, keys, rest} <- read_pubkeys(rest, num_keys, []),
         <<recent_blockhash::binary-32, rest::binary>> <- rest,
         {:ok, num_ix, rest} <- safe_decode_compact_u16(rest),
         {:ok, instructions, rest} <- read_instructions(rest, num_ix, []) do
      msg = %Message{
        header: header,
        account_keys: keys,
        recent_blockhash: recent_blockhash,
        instructions: instructions
      }

      {:ok, msg, rest}
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_message_body}
    end
  end

  def deserialize_message(_), do: {:error, :invalid_message_header}

  @spec read_signatures(binary(), non_neg_integer(), [<<_::512>>]) ::
          {:ok, [<<_::512>>], binary()} | {:error, :insufficient_signature_data}
  defp read_signatures(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_signatures(<<sig::binary-64, rest::binary>>, n, acc) when n > 0 do
    read_signatures(rest, n - 1, [sig | acc])
  end

  defp read_signatures(_, _, _), do: {:error, :insufficient_signature_data}

  @spec read_pubkeys(binary(), non_neg_integer(), [<<_::256>>]) ::
          {:ok, [<<_::256>>], binary()} | {:error, :insufficient_pubkey_data}
  defp read_pubkeys(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_pubkeys(<<key::binary-32, rest::binary>>, n, acc) when n > 0 do
    read_pubkeys(rest, n - 1, [key | acc])
  end

  defp read_pubkeys(_, _, _), do: {:error, :insufficient_pubkey_data}

  @spec read_instructions(binary(), non_neg_integer(), [CompiledInstruction.t()]) ::
          {:ok, [CompiledInstruction.t()], binary()} | {:error, :insufficient_instruction_data}
  defp read_instructions(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_instructions(<<program_id_index, rest::binary>>, n, acc) when n > 0 do
    with {:ok, num_accounts, rest} <- safe_decode_compact_u16(rest),
         {:ok, account_bytes, rest} <- read_size_prefixed(rest, num_accounts),
         {:ok, data_len, rest} <- safe_decode_compact_u16(rest),
         {:ok, data, rest} <- read_size_prefixed(rest, data_len) do
      ix = %CompiledInstruction{
        program_id_index: program_id_index,
        accounts: :binary.bin_to_list(account_bytes),
        data: data
      }

      read_instructions(rest, n - 1, [ix | acc])
    end
  end

  defp read_instructions(_, _, _), do: {:error, :insufficient_instruction_data}

  # Both callsites are inside read_instructions/3, so this shared helper deliberately
  # returns the instruction reader's error tag (:insufficient_instruction_data); it
  # parallels the sibling readers' tags. Parameterize only if a foreign caller appears.
  @spec read_size_prefixed(binary(), non_neg_integer()) ::
          {:ok, binary(), binary()} | {:error, :insufficient_instruction_data}
  defp read_size_prefixed(binary, size) when byte_size(binary) >= size do
    <<chunk::binary-size(^size), rest::binary>> = binary
    {:ok, chunk, rest}
  end

  defp read_size_prefixed(_, _), do: {:error, :insufficient_instruction_data}

  # ---------------------------------------------------------------------------
  # Signing
  # ---------------------------------------------------------------------------

  api(:sign, "Sign a Solana message with ordered Ed25519 seeds.",
    params: [
      message: [
        kind: :value,
        description: "`%Cartouche.Solana.Transaction.Message{}` to serialize and sign."
      ],
      seeds: [
        kind: :value,
        description: "Ordered list of 32-byte Ed25519 seeds matching the required signer account positions."
      ]
    ],
    returns: %{
      type: :solana_transaction,
      description: "`%Cartouche.Solana.Transaction{}` with one 64-byte signature per supplied seed."
    }
  )

  @doc """
  Sign a message with one or more seeds and produce a full transaction.

  Seeds must be ordered to match the signer positions in the message's
  account keys (i.e., the first `num_required_signatures` accounts).

  Raises `ArgumentError` if `length(seeds) != message.header.num_required_signatures`.
  Solana's runtime rejects transactions whose `signatures` array length doesn't
  match `num_required_signatures`, so emitting a mismatched count would surface
  only as an opaque submission failure downstream — guard at the boundary.
  """
  @spec sign(Message.t(), [<<_::256>>]) :: t()
  def sign(%Message{} = message, seeds) when is_list(seeds) do
    expected = message.header.num_required_signatures
    supplied = length(seeds)

    if supplied != expected do
      raise ArgumentError,
            "signer count mismatch: supplied #{supplied} seed(s) but message.header.num_required_signatures is #{expected}"
    end

    msg_bytes = serialize_message(message)

    signatures =
      Enum.map(seeds, fn <<seed::binary-32>> ->
        :crypto.sign(:eddsa, :none, msg_bytes, [seed, :ed25519])
      end)

    %__MODULE__{signatures: signatures, message: message}
  end

  api(:sign_partial, "Partially sign a Solana message by signer account index.",
    params: [
      message: [
        kind: :value,
        description: "`%Cartouche.Solana.Transaction.Message{}` to serialize and sign."
      ],
      signers: [
        kind: :value,
        description: "Map of zero-based signer account index to 32-byte Ed25519 seed."
      ]
    ],
    returns: %{
      type: :solana_transaction,
      description:
        "`%Cartouche.Solana.Transaction{}` with required signer slots filled by signatures where provided and zero-filled placeholder signatures elsewhere; an empty signer map returns the unsigned transaction message with every required signature slot set to `<<0::512>>`."
    }
  )

  @doc """
  Partially sign a message, filling only the specified signer positions.

  This is the core primitive for **sponsored transactions** (where one party
  pays fees on behalf of another). The typical flow is:

  1. User builds a message with the **sponsor's pubkey** as the fee payer
  2. User calls `sign_partial/2` with their own seed to sign their position
  3. User serializes the partially-signed transaction and sends it to the sponsor
  4. Sponsor deserializes and calls `add_signature/3` to fill in their position
  5. Sponsor submits the fully-signed transaction via `Cartouche.Solana.RPC.send_transaction/2`

  `signers` is a map of `%{account_index => seed}` where `account_index` is
  the position of the signer in the message's account keys list (0-based).
  Positions not present in the map get zero-filled placeholder signatures.

  ## Examples

      # User is account[1], sponsor is account[0] (fee payer)
      partial = Transaction.sign_partial(message, %{1 => user_seed})
      # => %Transaction{signatures: [<<0::512>>, <user_sig>], ...}

      # Serialize and send to sponsor
      bytes = Transaction.serialize(partial)
  """
  @spec sign_partial(Message.t(), %{non_neg_integer() => <<_::256>>}) :: t()
  def sign_partial(%Message{} = message, signers) when is_map(signers) do
    msg_bytes = serialize_message(message)
    num_signers = message.header.num_required_signatures

    signatures =
      Enum.map(0..(num_signers - 1)//1, fn index ->
        case Map.get(signers, index) do
          nil -> <<0::512>>
          <<seed::binary-32>> -> :crypto.sign(:eddsa, :none, msg_bytes, [seed, :ed25519])
        end
      end)

    %__MODULE__{signatures: signatures, message: message}
  end

  api(:add_signature, "Add or replace a signature at a signer position in a Solana transaction.",
    params: [
      transaction: [
        kind: :value,
        description: "`%Cartouche.Solana.Transaction{}` to update."
      ],
      index: [
        kind: :value,
        description: "Zero-based signature slot index matching the signer account position."
      ],
      signature: [kind: :value, description: "64-byte Ed25519 signature."]
    ],
    returns: %{
      type: :solana_transaction,
      description: "Updated `%Cartouche.Solana.Transaction{}` with the signature stored at the requested index."
    }
  )

  @doc """
  Add a signature to a transaction at a specific signer position.

  Used to fill in a missing signature on a partially-signed transaction,
  typically by a sponsor or co-signer who receives the transaction from
  another party. See `sign_partial/2` for the full sponsored transaction flow.

  The `index` is the position in the signatures array (matching the account
  keys order in the message). The existing signature at that position is
  replaced.

  ## Examples

      # Sponsor receives a partially-signed transaction and adds their signature
      {:ok, partial} = Transaction.deserialize(bytes_from_user)
      msg_bytes = Transaction.serialize_message(partial.message)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [sponsor_seed, :ed25519])
      full_trx = Transaction.add_signature(partial, 0, sponsor_sig)

  Raises `ArgumentError` if `index` is out of bounds for `transaction.signatures`
  (i.e., `index < 0` or `index >= length(transaction.signatures)`). `List.replace_at/3`
  silently returns the list unchanged on out-of-bounds indices, which would mask a
  partially-signed transaction as successfully signed in sponsored-transaction flows
  — guard at the boundary.
  """
  @spec add_signature(t(), non_neg_integer(), <<_::512>>) :: t()
  def add_signature(%__MODULE__{} = transaction, index, <<signature::binary-64>>) when is_integer(index) do
    sig_count = length(transaction.signatures)

    if index < 0 or index >= sig_count do
      raise ArgumentError,
            "invalid signature slot: index #{index} is out of bounds for transaction.signatures (length #{sig_count})"
    end

    signatures = List.replace_at(transaction.signatures, index, signature)
    %{transaction | signatures: signatures}
  end
end
