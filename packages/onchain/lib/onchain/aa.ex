defmodule Onchain.AA do
  @moduledoc """
  ERC-4337 Account Abstraction: UserOperation construction, hashing, signing,
  and bundler JSON-RPC.

  Supports both EntryPoint versions, whose wire formats differ:

  - **v0.6** (`0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`) — the original
    `UserOperation` with separate `callGasLimit`/`verificationGasLimit` and
    `maxFeePerGas`/`maxPriorityFeePerGas` words, plus `initCode` and
    `paymasterAndData` byte fields.
  - **v0.7** (`0x0000000071727De22E5E9d8BAf0edAc6f37da032`) — the
    `PackedUserOperation`: `accountGasLimits = verificationGasLimit (high 128) ‖
    callGasLimit (low 128)` and `gasFees = maxPriorityFeePerGas (high 128) ‖
    maxFeePerGas (low 128)`, with `initCode`/`paymasterAndData` derived from the
    unpacked `factory*`/`paymaster*` fields. The JSON-RPC representation sent to
    bundlers stays *unpacked* (separate `factory`, `factoryData`,
    `paymasterVerificationGasLimit`, etc.).

  The version is selected per call via the `:version` option (`:v0_6` | `:v0_7`,
  default `:v0_7`).

  ## userOpHash

  Both versions hash as
  `keccak256(abi.encode(keccak256(packed), entryPoint, chainId))`, where `packed`
  is the version-specific `abi.encode` of the op (variable-length byte fields
  hashed with keccak first). This matches `EntryPoint.getUserOpHash`. Verified
  against reference vectors in `test/onchain/aa_test.exs` (cross-checked with
  viem's `getUserOperationHash` test vectors).

  ## Signing

  `sign_user_operation/5` signs the `userOpHash` and returns the op with its
  `:signature` populated. Two schemes:

  - `:eip191` (default) — ECDSA over `keccak256("\\x19Ethereum Signed
    Message:\\n32" ‖ userOpHash)`, matching the canonical eth-infinitism
    `SimpleAccount` (`userOpHash.toEthSignedMessageHash()`).
  - `:raw` — ECDSA over the raw 32-byte `userOpHash` (accounts that recover
    directly without the EIP-191 envelope).

  The signature is `r ‖ s ‖ v` with `v ∈ {27, 28}`. Accounts with bespoke
  signature schemes (Safe, multisig, passkey) should call `user_op_hash/4` and
  build the signature themselves.

  ## Bundler RPC

  `send_user_operation/3`, `estimate_user_operation_gas/3`,
  `get_user_operation_by_hash/2`, `get_user_operation_receipt/2`, and
  `supported_entry_points/1` wrap the standard bundler methods. The bundler URL
  is passed via `:bundler_url` (or `:rpc_url`); results are returned raw
  (decoded JSON) since shapes are bundler-defined.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `entry_point/1` | Canonical EntryPoint address for a version |
  | `new/1` | Build + validate a `UserOperation` from fields |
  | `user_op_hash/4` | Compute the EntryPoint `userOpHash` |
  | `sign_user_operation/5` | Sign a UserOperation, return it with `:signature` |
  | `to_rpc_params/2` | Serialize a UserOperation to bundler JSON-RPC params |
  | `send_user_operation/3` | `eth_sendUserOperation` → userOpHash |
  | `estimate_user_operation_gas/3` | `eth_estimateUserOperationGas` → gas map |
  | `get_user_operation_by_hash/2` | `eth_getUserOperationByHash` |
  | `get_user_operation_receipt/2` | `eth_getUserOperationReceipt` |
  | `supported_entry_points/1` | `eth_supportedEntryPoints` → addresses |
  """

  use Descripex, namespace: "/aa"

  import Bitwise

  alias Cartouche.Hash
  alias Cartouche.Signer.Curvy, as: CurvySigner
  alias Onchain.AA.UserOperation
  alias Onchain.Address
  alias Onchain.Hex
  alias Onchain.RPC

  @entry_point_v0_6 "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
  @entry_point_v0_7 "0x0000000071727De22E5E9d8BAf0edAc6f37da032"
  @versions [:v0_6, :v0_7]
  @eip191_prefix "\x19Ethereum Signed Message:\n32"
  @tx_hash_hex_length 66
  @address_byte_size 20

  @uint256_fields ~w(nonce call_gas_limit verification_gas_limit pre_verification_gas
                     max_fee_per_gas max_priority_fee_per_gas)a
  @optional_uint128_fields ~w(paymaster_verification_gas_limit paymaster_post_op_gas_limit)a
  @hex_fields ~w(init_code call_data paymaster_and_data signature)a
  @optional_hex_fields ~w(factory factory_data paymaster paymaster_data)a
  @known_keys [:sender | @uint256_fields ++ @optional_uint128_fields ++ @hex_fields ++ @optional_hex_fields]

  # --- entry_point ---

  api(:entry_point, "Canonical EntryPoint contract address for a version.",
    params: [
      version: [kind: :value, description: "EntryPoint version: :v0_6 or :v0_7"]
    ],
    returns: %{type: :string, description: "0x-prefixed checksummed EntryPoint address"}
  )

  @spec entry_point(:v0_6 | :v0_7) :: String.t()
  def entry_point(:v0_6), do: @entry_point_v0_6
  def entry_point(:v0_7), do: @entry_point_v0_7

  # --- new ---

  api(:new, "Build and validate a UserOperation from a map or keyword of fields.",
    params: [
      fields: [
        kind: :value,
        description:
          ~s|Map/keyword of UserOperation fields. Required: :sender (address). Numeric fields (:nonce, :call_gas_limit, :verification_gas_limit, :pre_verification_gas, :max_fee_per_gas, :max_priority_fee_per_gas) default to 0. Byte fields (:init_code, :call_data, :paymaster_and_data, :signature) default to "0x". v0.7 unpacked fields :factory, :factory_data, :paymaster, :paymaster_verification_gas_limit, :paymaster_post_op_gas_limit, :paymaster_data default to nil.|
      ]
    ],
    returns: %{
      type: "{:ok, %Onchain.AA.UserOperation{}} | {:error, term}",
      description: "Validated UserOperation struct, or a validation error"
    }
  )

  @spec new(map() | keyword()) :: {:ok, UserOperation.t()} | {:error, term()}
  def new(fields) when is_list(fields) do
    if Keyword.keyword?(fields),
      do: new(Map.new(fields)),
      else: {:error, {:invalid_fields, fields}}
  end

  def new(%{} = fields) do
    with :ok <- reject_unknown_keys(fields),
         {:ok, sender} <- require_sender(fields),
         {:ok, normalized} <- normalize_all(fields) do
      {:ok, struct(UserOperation, Map.put(normalized, :sender, sender))}
    end
  end

  def new(other), do: {:error, {:invalid_fields, other}}

  # --- user_op_hash ---

  api(:user_op_hash, "Compute the EntryPoint userOpHash for a UserOperation.",
    params: [
      user_op: [kind: :value, description: "%Onchain.AA.UserOperation{} struct"],
      entry_point: [kind: :value, description: "EntryPoint address (hex string or 20-byte binary)"],
      chain_id: [kind: :value, description: "Chain ID integer (1 = mainnet, 11155111 = Sepolia)"],
      opts: [kind: :value, default: [], description: "Options: :version (:v0_6 | :v0_7, default :v0_7)"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term}",
      description: "0x-prefixed 32-byte userOpHash",
      example: "0x1903d62bb5dc75af6fed866aa46d8e80063d9e288aa7f2caad0ff1fcae22e40d"
    }
  )

  @spec user_op_hash(UserOperation.t(), String.t() | binary(), pos_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def user_op_hash(%UserOperation{} = user_op, entry_point, chain_id, opts \\ []) do
    version = Keyword.get(opts, :version, :v0_7)

    with :ok <- validate_version(version),
         :ok <- validate_chain_id(chain_id),
         {:ok, ep_bin} <- validate_address(entry_point, :entry_point),
         {:ok, packed} <- pack(user_op, version) do
      struct_hash = Hash.keccak(packed)
      full = Hash.keccak(struct_hash <> word_address(ep_bin) <> <<chain_id::256>>)
      {:ok, Hex.encode(full)}
    end
  end

  # --- sign_user_operation ---

  api(:sign_user_operation, "Sign a UserOperation and return it with :signature populated.",
    params: [
      user_op: [kind: :value, description: "%Onchain.AA.UserOperation{} struct"],
      private_key: [kind: :value, description: "32-byte binary or hex private key (with or without 0x)"],
      entry_point: [kind: :value, description: "EntryPoint address (hex string or 20-byte binary)"],
      chain_id: [kind: :value, description: "Chain ID integer"],
      opts: [
        kind: :value,
        default: [],
        description:
          "Options: :version (:v0_6 | :v0_7, default :v0_7), :scheme (:eip191 default, or :raw to sign the userOpHash directly)"
      ]
    ],
    returns: %{
      type: "{:ok, %Onchain.AA.UserOperation{}} | {:error, term}",
      description: "UserOperation with :signature set to a 65-byte r‖s‖v hex string"
    }
  )

  @spec sign_user_operation(
          UserOperation.t(),
          binary(),
          String.t() | binary(),
          pos_integer(),
          keyword()
        ) :: {:ok, UserOperation.t()} | {:error, term()}
  def sign_user_operation(%UserOperation{} = user_op, private_key, entry_point, chain_id, opts \\ []) do
    scheme = Keyword.get(opts, :scheme, :eip191)

    with :ok <- validate_scheme(scheme),
         {:ok, hash_hex} <- user_op_hash(user_op, entry_point, chain_id, opts),
         {:ok, key_bin} <- decode_private_key(private_key),
         {:ok, signer_addr} <- safe_get_address(key_bin, private_key),
         {:ok, digest} <- signing_digest(hash_hex, scheme),
         {:ok, sig_hex} <- sign_digest(digest, key_bin, signer_addr) do
      {:ok, %{user_op | signature: sig_hex}}
    end
  end

  # --- to_rpc_params ---

  api(:to_rpc_params, "Serialize a UserOperation to bundler JSON-RPC params.",
    params: [
      user_op: [kind: :value, description: "%Onchain.AA.UserOperation{} struct"],
      opts: [kind: :value, default: [], description: "Options: :version (:v0_6 | :v0_7, default :v0_7)"]
    ],
    returns: %{
      type: "{:ok, map} | {:error, term}",
      description:
        "JSON-RPC UserOperation object with string keys and 0x-quantity numeric fields. v0.7 includes factory/paymaster fields only when set."
    }
  )

  @spec to_rpc_params(UserOperation.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def to_rpc_params(%UserOperation{} = user_op, opts \\ []) do
    version = Keyword.get(opts, :version, :v0_7)

    with :ok <- validate_version(version),
         {:ok, sender_bin} <- validate_address(user_op.sender, :sender) do
      rpc_map(user_op, Hex.encode(sender_bin), version)
    end
  end

  # --- send_user_operation ---

  api(:send_user_operation, "Submit a UserOperation to a bundler (eth_sendUserOperation).",
    params: [
      user_op: [kind: :value, description: "Signed %Onchain.AA.UserOperation{} struct"],
      entry_point: [kind: :value, description: "EntryPoint address the bundler should use"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :version (default :v0_7), :bundler_url (or :rpc_url), :timeout"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term}",
      description: "0x-prefixed userOpHash returned by the bundler"
    }
  )

  @spec send_user_operation(UserOperation.t(), String.t() | binary(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def send_user_operation(%UserOperation{} = user_op, entry_point, opts \\ []) do
    bundler_call("eth_sendUserOperation", user_op, entry_point, opts)
  end

  # --- estimate_user_operation_gas ---

  api(:estimate_user_operation_gas, "Estimate gas for a UserOperation (eth_estimateUserOperationGas).",
    params: [
      user_op: [kind: :value, description: "%Onchain.AA.UserOperation{} struct (signature may be a dummy)"],
      entry_point: [kind: :value, description: "EntryPoint address the bundler should use"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :version (default :v0_7), :bundler_url (or :rpc_url), :timeout"
      ]
    ],
    returns: %{
      type: "{:ok, map} | {:error, term}",
      description:
        "Gas estimate map (e.g. preVerificationGas, verificationGasLimit, callGasLimit) with bundler-defined hex values"
    }
  )

  @spec estimate_user_operation_gas(UserOperation.t(), String.t() | binary(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def estimate_user_operation_gas(%UserOperation{} = user_op, entry_point, opts \\ []) do
    bundler_call("eth_estimateUserOperationGas", user_op, entry_point, opts)
  end

  # --- get_user_operation_by_hash ---

  api(:get_user_operation_by_hash, "Look up a UserOperation by its hash (eth_getUserOperationByHash).",
    params: [
      user_op_hash: [kind: :value, description: "0x-prefixed 32-byte userOpHash"],
      opts: [kind: :value, default: [], description: "Options: :bundler_url (or :rpc_url), :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description: "UserOperation + inclusion info map, or nil if the bundler has not seen it"
    }
  )

  @spec get_user_operation_by_hash(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_user_operation_by_hash(user_op_hash, opts \\ []) do
    with {:ok, hash} <- validate_hash(user_op_hash) do
      RPC.call("eth_getUserOperationByHash", [hash], bundler_opts(opts))
    end
  end

  # --- get_user_operation_receipt ---

  api(:get_user_operation_receipt, "Fetch a UserOperation receipt (eth_getUserOperationReceipt).",
    params: [
      user_op_hash: [kind: :value, description: "0x-prefixed 32-byte userOpHash"],
      opts: [kind: :value, default: [], description: "Options: :bundler_url (or :rpc_url), :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description: "Receipt map (success, actualGasUsed, logs, receipt, …), or nil if not yet mined"
    }
  )

  @spec get_user_operation_receipt(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_user_operation_receipt(user_op_hash, opts \\ []) do
    with {:ok, hash} <- validate_hash(user_op_hash) do
      RPC.call("eth_getUserOperationReceipt", [hash], bundler_opts(opts))
    end
  end

  # --- supported_entry_points ---

  api(:supported_entry_points, "List EntryPoint addresses the bundler supports (eth_supportedEntryPoints).",
    params: [
      opts: [kind: :value, default: [], description: "Options: :bundler_url (or :rpc_url), :timeout"]
    ],
    returns: %{
      type: "{:ok, [String.t()]} | {:error, term}",
      description: "List of 0x-prefixed EntryPoint addresses"
    }
  )

  @spec supported_entry_points(keyword()) :: {:ok, term()} | {:error, term()}
  def supported_entry_points(opts \\ []) do
    RPC.call("eth_supportedEntryPoints", [], bundler_opts(opts))
  end

  # --- Private: validation ---

  defp reject_unknown_keys(fields) do
    case Map.keys(fields) -- @known_keys do
      [] -> :ok
      extra -> {:error, {:unknown_fields, extra}}
    end
  end

  defp require_sender(%{sender: sender}) do
    case Address.validate(sender) do
      {:ok, bin} -> {:ok, Hex.encode(bin)}
      {:error, _} -> {:error, {:invalid_field, :sender, sender}}
    end
  end

  defp require_sender(_), do: {:error, {:missing_field, :sender}}

  defp normalize_all(fields) do
    fields
    |> Map.delete(:sender)
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_field(key, value) do
        {:ok, normalized} -> {:cont, {:ok, Map.put(acc, key, normalized)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp normalize_field(key, value) when key in @uint256_fields do
    if uint?(value, 256), do: {:ok, value}, else: {:error, {:invalid_field, key, value}}
  end

  defp normalize_field(key, nil) when key in @optional_uint128_fields, do: {:ok, nil}

  defp normalize_field(key, value) when key in @optional_uint128_fields do
    if uint?(value, 128), do: {:ok, value}, else: {:error, {:invalid_field, key, value}}
  end

  defp normalize_field(key, nil) when key in @optional_hex_fields, do: {:ok, nil}

  defp normalize_field(key, value) when key in @hex_fields or key in @optional_hex_fields do
    case normalize_hex(value) do
      {:ok, hex} -> {:ok, hex}
      :error -> {:error, {:invalid_field, key, value}}
    end
  end

  defp uint?(value, bits), do: is_integer(value) and value >= 0 and value < bsl(1, bits)

  defp normalize_hex(value) when is_binary(value) do
    if Hex.valid?(value) do
      body = value |> String.replace_prefix("0x", "") |> String.downcase()

      if rem(byte_size(body), 2) == 0, do: {:ok, "0x" <> body}, else: :error
    else
      :error
    end
  end

  defp normalize_hex(_), do: :error

  defp validate_version(version) when version in @versions, do: :ok
  defp validate_version(other), do: {:error, {:invalid_version, other}}

  defp validate_scheme(scheme) when scheme in [:eip191, :raw], do: :ok
  defp validate_scheme(other), do: {:error, {:invalid_scheme, other}}

  defp validate_chain_id(id) when is_integer(id) and id > 0, do: :ok
  defp validate_chain_id(other), do: {:error, {:invalid_chain_id, other}}

  defp validate_address(input, field) do
    case Address.validate(input) do
      {:ok, bin} -> {:ok, bin}
      {:error, _} -> {:error, {:invalid_address, field, input}}
    end
  end

  defp validate_hash("0x" <> _ = hash) do
    cond do
      not Hex.valid?(hash) -> {:error, {:invalid_user_op_hash, hash}}
      byte_size(hash) != @tx_hash_hex_length -> {:error, {:invalid_user_op_hash, hash}}
      true -> {:ok, String.downcase(hash)}
    end
  end

  defp validate_hash(other), do: {:error, {:invalid_user_op_hash, other}}

  # --- Private: hashing ---

  # v0.6 pack: abi.encode of the 10 static words (variable-length fields keccak-hashed).
  defp pack(op, :v0_6) do
    with {:ok, sender} <- validate_address(op.sender, :sender),
         {:ok, init_code} <- decode_hex_field(op.init_code, :init_code),
         {:ok, call_data} <- decode_hex_field(op.call_data, :call_data),
         {:ok, paymaster} <- decode_hex_field(op.paymaster_and_data, :paymaster_and_data) do
      {:ok,
       word_address(sender) <>
         <<op.nonce::256>> <>
         Hash.keccak(init_code) <>
         Hash.keccak(call_data) <>
         <<op.call_gas_limit::256>> <>
         <<op.verification_gas_limit::256>> <>
         <<op.pre_verification_gas::256>> <>
         <<op.max_fee_per_gas::256>> <>
         <<op.max_priority_fee_per_gas::256>> <>
         Hash.keccak(paymaster)}
    end
  end

  # v0.7 encode: PackedUserOperation with accountGasLimits and gasFees bytes32 words.
  defp pack(op, :v0_7) do
    with {:ok, sender} <- validate_address(op.sender, :sender),
         {:ok, v0_7_fields} <- derive_v0_7_fields(op),
         {:ok, call_data} <- decode_hex_field(op.call_data, :call_data),
         {:ok, account_gas_limits} <-
           pack_two_uint128(op.verification_gas_limit, op.call_gas_limit, :account_gas_limits),
         {:ok, gas_fees} <-
           pack_two_uint128(op.max_priority_fee_per_gas, op.max_fee_per_gas, :gas_fees) do
      {:ok,
       word_address(sender) <>
         <<op.nonce::256>> <>
         Hash.keccak(v0_7_fields.init_code) <>
         Hash.keccak(call_data) <>
         account_gas_limits <>
         <<op.pre_verification_gas::256>> <>
         gas_fees <>
         Hash.keccak(v0_7_fields.paymaster_and_data)}
    end
  end

  defp decode_hex_field(hex, field) do
    case Hex.decode(hex) do
      {:ok, bin} -> {:ok, bin}
      {:error, _} -> {:error, {:invalid_field, field, hex}}
    end
  end

  defp decode_optional_hex(nil, _field), do: {:ok, <<>>}
  defp decode_optional_hex(hex, field), do: decode_hex_field(hex, field)

  defp uint128_word(nil, _field), do: {:ok, <<0::128>>}

  defp uint128_word(value, field) do
    if uint?(value, 128), do: {:ok, <<value::128>>}, else: {:error, {:invalid_field, field, value}}
  end

  defp derive_v0_7_fields(%UserOperation{} = op) do
    with {:ok, init_code, factory_fields} <- derive_factory_fields(op),
         {:ok, paymaster_and_data, paymaster_fields} <- derive_paymaster_fields(op) do
      {:ok,
       %{
         init_code: init_code,
         factory_fields: factory_fields,
         paymaster_and_data: paymaster_and_data,
         paymaster_fields: paymaster_fields
       }}
    end
  end

  # v0.7 initCode = factory ‖ factoryData when factory is set; otherwise the raw
  # init_code must be empty or unpackable into factory/factoryData for bundler RPC.
  defp derive_factory_fields(%UserOperation{factory: nil, init_code: init_code}) do
    with {:ok, init_code_bin} <- decode_hex_field(init_code, :init_code) do
      case init_code_bin do
        <<>> ->
          {:ok, init_code_bin, nil}

        <<factory_bin::binary-size(@address_byte_size), factory_data::binary>> ->
          {:ok, init_code_bin,
           %{
             "factory" => Hex.encode(factory_bin),
             "factoryData" => encode_optional_bytes(factory_data)
           }}

        _ ->
          {:error, {:invalid_field, :init_code, init_code}}
      end
    end
  end

  defp derive_factory_fields(%UserOperation{factory: factory} = op) do
    with {:ok, factory_bin} <- validate_address(factory, :factory),
         {:ok, factory_data} <- decode_optional_hex(op.factory_data, :factory_data) do
      {:ok, factory_bin <> factory_data,
       %{
         "factory" => Hex.encode(factory_bin),
         "factoryData" => encode_optional_bytes(factory_data)
       }}
    end
  end

  # v0.7 paymasterAndData = paymaster ‖ verificationGasLimit(16) ‖
  # postOpGasLimit(16) ‖ data.
  defp derive_paymaster_fields(%UserOperation{paymaster: nil, paymaster_and_data: paymaster_and_data}) do
    with {:ok, paymaster_bin} <- decode_hex_field(paymaster_and_data, :paymaster_and_data) do
      case paymaster_bin do
        <<>> ->
          {:ok, paymaster_bin, nil}

        <<paymaster::binary-size(@address_byte_size), ver_gas::128, post_gas::128, data::binary>> ->
          {:ok, paymaster_bin,
           %{
             "paymaster" => Hex.encode(paymaster),
             "paymasterVerificationGasLimit" => Hex.from_integer(ver_gas),
             "paymasterPostOpGasLimit" => Hex.from_integer(post_gas),
             "paymasterData" => encode_optional_bytes(data)
           }}

        _ ->
          {:error, {:invalid_field, :paymaster_and_data, paymaster_and_data}}
      end
    end
  end

  defp derive_paymaster_fields(%UserOperation{paymaster: paymaster} = op) do
    with {:ok, paymaster_bin} <- validate_address(paymaster, :paymaster),
         {:ok, ver_gas} <- uint128_word(op.paymaster_verification_gas_limit, :paymaster_verification_gas_limit),
         {:ok, post_op_gas} <- uint128_word(op.paymaster_post_op_gas_limit, :paymaster_post_op_gas_limit),
         {:ok, data} <- decode_optional_hex(op.paymaster_data, :paymaster_data) do
      {:ok, paymaster_bin <> ver_gas <> post_op_gas <> data,
       %{
         "paymaster" => Hex.encode(paymaster_bin),
         "paymasterVerificationGasLimit" => Hex.from_integer(op.paymaster_verification_gas_limit || 0),
         "paymasterPostOpGasLimit" => Hex.from_integer(op.paymaster_post_op_gas_limit || 0),
         "paymasterData" => encode_optional_bytes(data)
       }}
    end
  end

  defp pack_two_uint128(high, low, field) do
    if uint?(high, 128) and uint?(low, 128),
      do: {:ok, <<high::128, low::128>>},
      else: {:error, {:value_too_large, field, {high, low}}}
  end

  # Left-pad a 20-byte address to a 32-byte ABI word.
  defp word_address(<<addr::binary-size(@address_byte_size)>>), do: <<0::96, addr::binary-size(@address_byte_size)>>

  # --- Private: signing ---

  defp signing_digest(hash_hex, :raw), do: Hex.decode(hash_hex)

  defp signing_digest(hash_hex, :eip191) do
    with {:ok, hash_bin} <- Hex.decode(hash_hex) do
      {:ok, Hash.keccak(@eip191_prefix <> hash_bin)}
    end
  end

  # Signs a final 32-byte digest directly (no further hashing) and finds the
  # recovery id, producing a 65-byte r‖s‖v signature with v ∈ {27, 28}.
  defp sign_digest(digest, key_bin, signer_addr) do
    with {:ok, sig} <- CurvySigner.sign_digest(digest, key_bin),
         {:ok, recid} <- find_recid(digest, sig, signer_addr) do
      {:ok, Hex.encode(<<sig.r::256, sig.s::256, 27 + recid::8>>)}
    else
      {:error, reason} -> {:error, {:sign_error, reason}}
    end
  end

  defp find_recid(digest, sig, address) do
    recid =
      Enum.find(0..1, fn candidate ->
        recover_address(%{sig | recid: candidate}, digest) == address
      end)

    if recid, do: {:ok, recid}, else: {:error, :recovery_failed}
  end

  defp recover_address(sig, digest) do
    sig
    |> Curvy.recover_key(digest, hash: :keccak)
    |> Curvy.Key.to_pubkey(compressed: false)
    |> Cartouche.Address.from_public_key()
  end

  defp decode_private_key(input), do: Onchain.PrivateKey.decode(input)

  # Verified against Cartouche.Signer.Curvy: a scalar outside [1, n-1] fails the
  # `<<0>>` pubkey-prefix match (MatchError); a non-32-byte or non-binary key has no
  # matching `Curvy.Key.from_privkey/2` clause (FunctionClauseError). Every other
  # exception — a typo'd call, a missing dep — propagates as the bug it is.
  defp safe_get_address(key_bin, original_input) do
    CurvySigner.get_address(key_bin)
  rescue
    _ in [FunctionClauseError, MatchError] -> {:error, {:invalid_private_key, original_input}}
  end

  # --- Private: RPC ---

  defp bundler_call(method, user_op, entry_point, opts) do
    version = Keyword.get(opts, :version, :v0_7)

    with :ok <- validate_version(version),
         {:ok, ep_bin} <- validate_address(entry_point, :entry_point),
         {:ok, params} <- to_rpc_params(user_op, version: version) do
      RPC.call(method, [params, Hex.encode(ep_bin)], bundler_opts(opts))
    end
  end

  # Bundler URL may arrive as :bundler_url (preferred) or :rpc_url; map to the
  # :rpc_url key Onchain.RPC understands. :timeout passes through.
  defp bundler_opts(opts) do
    url = Keyword.get(opts, :bundler_url) || Keyword.get(opts, :rpc_url)

    opts
    |> Keyword.take([:timeout])
    |> maybe_put_url(url)
  end

  defp maybe_put_url(opts, nil), do: opts
  defp maybe_put_url(opts, url), do: Keyword.put(opts, :rpc_url, url)

  defp rpc_map(op, sender_hex, :v0_6) do
    {:ok,
     %{
       "sender" => sender_hex,
       "nonce" => Hex.from_integer(op.nonce),
       "initCode" => op.init_code,
       "callData" => op.call_data,
       "callGasLimit" => Hex.from_integer(op.call_gas_limit),
       "verificationGasLimit" => Hex.from_integer(op.verification_gas_limit),
       "preVerificationGas" => Hex.from_integer(op.pre_verification_gas),
       "maxFeePerGas" => Hex.from_integer(op.max_fee_per_gas),
       "maxPriorityFeePerGas" => Hex.from_integer(op.max_priority_fee_per_gas),
       "paymasterAndData" => op.paymaster_and_data,
       "signature" => op.signature
     }}
  end

  defp rpc_map(op, sender_hex, :v0_7) do
    with {:ok, v0_7_fields} <- derive_v0_7_fields(op) do
      params =
        %{
          "sender" => sender_hex,
          "nonce" => Hex.from_integer(op.nonce),
          "callData" => op.call_data,
          "callGasLimit" => Hex.from_integer(op.call_gas_limit),
          "verificationGasLimit" => Hex.from_integer(op.verification_gas_limit),
          "preVerificationGas" => Hex.from_integer(op.pre_verification_gas),
          "maxFeePerGas" => Hex.from_integer(op.max_fee_per_gas),
          "maxPriorityFeePerGas" => Hex.from_integer(op.max_priority_fee_per_gas),
          "signature" => op.signature
        }
        |> merge_optional_fields(v0_7_fields.factory_fields)
        |> merge_optional_fields(v0_7_fields.paymaster_fields)

      {:ok, params}
    end
  end

  defp merge_optional_fields(map, nil), do: map
  defp merge_optional_fields(map, fields), do: Map.merge(map, fields)

  defp encode_optional_bytes(<<>>), do: "0x"
  defp encode_optional_bytes(bin), do: Hex.encode(bin)
end
