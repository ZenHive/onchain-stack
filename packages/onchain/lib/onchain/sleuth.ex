defmodule Onchain.Sleuth do
  @moduledoc """
  Compound-style "deploy-as-call" primitive for arbitrary read-only logic
  against live chain state.

  Sends an `eth_call` with no `to` and creation bytecode as `data`. The node
  executes the constructor in-memory against live state; the response is
  the bytes the constructor would have deployed. The caller ABI-decodes
  those bytes as the query result.

  Complements `Onchain.Multicall` (batches existing view functions) and
  `onchain_evm` / revm (local simulation). Use Sleuth when you need
  derived or conditional logic that isn't exposed as a view function and
  you want live-state execution in one RPC round-trip.

  Inspired by Compound's Sleuth: https://github.com/compound-finance/sleuth

  Bytecode must be supplied by the caller. Solidity source → bytecode
  compilation is out of scope — use `OnchainJs.Solc.compile/2`
  (onchain_js Task 2) or an external build step (foundry, hardhat).

  ## Error Format

  Pass-through from underlying modules:

  | Source | Shape |
  |--------|-------|
  | `Onchain.Hex.decode/1` on bytecode | `{:error, {:invalid_hex, _}}` |
  | `Onchain.ABI.encode_call/2` on ctor args | `{:error, {:encode_error, _}}` |
  | `Onchain.RPC.call/3` | `{:error, {:rpc_error, _}}` |
  | `Onchain.ABI.decode_response/2` | `{:error, {:decode_error, _}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `query/5` | Execute deploy-as-call → decoded values list |
  | `query!/5` | Same, raises on error |
  """

  use Descripex, namespace: "/sleuth"

  alias Onchain.ABI
  alias Onchain.Hex
  alias Onchain.RPC.Helpers, as: RPCHelpers

  # --- query ---

  api(:query, "Execute a Sleuth deploy-as-call: encode ctor args, append to bytecode, eth_call, decode.",
    params: [
      bytecode: [
        kind: :value,
        description: "Creation bytecode as 0x-prefixed hex string (output of `solc --bin` or `OnchainJs.Solc.compile/2`)"
      ],
      constructor_types: [
        kind: :value,
        description: ~s|Tuple type signature for constructor args, e.g. "(uint256,address)" or "()" for none|
      ],
      constructor_args: [
        kind: :value,
        description: "Tuple of constructor argument values matching constructor_types, e.g. {42, addr_bin} or {}"
      ],
      return_type: [
        kind: :value,
        description: ~s|Tuple type signature for decoding the returned bytes, e.g. "(uint256)" or "(uint256[])"|
      ],
      opts: [
        kind: :value,
        default: [],
        description: ~s{Options: :rpc_url, :timeout, :block (integer, "latest", "finalized", ...)}
      ]
    ],
    returns: %{
      type: "{:ok, [decoded]} | {:error, term()}",
      description: "List of decoded return values from the constructor's returned bytes"
    }
  )

  @spec query(String.t(), String.t(), tuple(), String.t(), keyword()) ::
          {:ok, list()} | {:error, term()}
  def query(bytecode, constructor_types, constructor_args, return_type, opts \\ []) do
    with {:ok, bytecode_bin} <- Hex.decode(bytecode),
         {:ok, ctor_bin} <- encode_ctor(constructor_types, constructor_args),
         data_hex = Hex.encode(bytecode_bin <> ctor_bin),
         {:ok, response_hex} <- eth_call_no_to(data_hex, opts) do
      ABI.decode_response(return_type, response_hex)
    end
  end

  # --- query! ---

  api(:query!, "Execute a Sleuth deploy-as-call. Raises on error.",
    params: [
      bytecode: [kind: :value, description: "Creation bytecode as 0x-prefixed hex"],
      constructor_types: [kind: :value, description: ~s|Tuple type signature, e.g. "(uint256,address)" or "()"|],
      constructor_args: [kind: :value, description: "Tuple of ctor values, e.g. {42, addr_bin} or {}"],
      return_type: [kind: :value, description: ~s|Return tuple type, e.g. "(uint256[])"|],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: "[decoded]", description: "List of decoded return values"}
  )

  @spec query!(String.t(), String.t(), tuple(), String.t(), keyword()) :: list()
  def query!(bytecode, constructor_types, constructor_args, return_type, opts \\ []) do
    case query(bytecode, constructor_types, constructor_args, return_type, opts) do
      {:ok, values} -> values
      {:error, reason} -> raise "Sleuth query failed: #{inspect(reason)}"
    end
  end

  # --- private ---

  # Encode constructor args as a raw ABI tuple (no 4-byte selector).
  # ABI.encode_call/2 wraps abi's ABI.encode/2 which, when given a type-only
  # signature like "(uint,address)", produces a bare encoded tuple — see
  # deps/abi/lib/abi.ex doctest (ABI.encode("(uint,address)", [{50, <<1::160>>}])).
  @spec encode_ctor(String.t(), tuple()) :: {:ok, binary()} | {:error, term()}
  defp encode_ctor("()", {}), do: {:ok, <<>>}

  defp encode_ctor(types, args) do
    with {:ok, hex} <- ABI.encode_call(types, [args]) do
      Hex.decode(hex)
    end
  end

  # eth_call with no `to` field — the Compound deploy-as-call pattern.
  # Onchain.RPC.eth_call/3 requires an address, so drop to the generic
  # passthrough (Task 59) and build the call object directly.
  @spec eth_call_no_to(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp eth_call_no_to(data_hex, opts) do
    with {:ok, block} <- RPCHelpers.normalize_block(Keyword.get(opts, :block, "latest")) do
      call_obj = %{"data" => data_hex}
      Onchain.RPC.call("eth_call", [call_obj, block], opts)
    end
  end
end
