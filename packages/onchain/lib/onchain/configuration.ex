defmodule Onchain.Configuration do
  @moduledoc """
  Configuration and API discovery for the signing, transaction and RPC modules
  (formerly the `Cartouche` root module). Application-env keys stay under
  `:cartouche`.

  ## API discovery

  This module exposes a machine-readable API surface for AI agents and
  introspection tooling via [`descripex`](https://hexdocs.pm/descripex):

      Onchain.Configuration.describe()                  # registered modules + namespaces
      Onchain.Configuration.describe(:signer)            # function list for one module
      Onchain.Configuration.describe(:signer, :sign_direct)   # full param/return detail
      Onchain.Configuration.describe(:transaction_v1)    # nested Transaction.V1 helpers
      Onchain.Configuration.describe(:transaction_v2)    # nested Transaction.V2 helpers

  The registered module list is built up as Phase 12 lands; see the root
  `ROADMAP.md` Phase 2012 for the annotation pass.
  """

  use Descripex, namespace: "/cartouche"

  alias Onchain.ERC20.Call
  alias Onchain.ERC20.CallData
  alias Onchain.Transaction.V1
  alias Onchain.Transaction.V2

  @descripex_modules [
    Onchain.Configuration,
    Onchain.Signer,
    Onchain.Keys,
    Onchain.Hex,
    Onchain.ERC20,
    CallData,
    Call,
    Onchain.Sleuth,
    Onchain.Hash,
    Onchain.Address,
    Onchain.Wei,
    Onchain.Chain,
    Onchain.RecoveryBit,
    Onchain.Transaction,
    V1,
    V2,
    Onchain.RPC,
    Onchain.Block,
    Onchain.Block.Withdrawal,
    Onchain.Receipt,
    Onchain.Filter.Log,
    Onchain.FeeHistory,
    Onchain.DebugTrace,
    Onchain.DebugTrace.StructLog,
    Onchain.RPC.Trace,
    Onchain.RPC.Trace.Action,
    Onchain.TraceCall
  ]

  @descripex_aliases %{
    cartouche: Onchain.Configuration,
    signer: Onchain.Signer,
    keys: Onchain.Keys,
    transaction: Onchain.Transaction,
    transaction_v1: V1,
    transaction_v2: V2,
    erc20_call_data: CallData,
    erc20_call: Call
  }

  @descripex_summary_names Map.new(@descripex_aliases, fn {short_name, module} -> {module, short_name} end)

  @type address :: <<_::160>>
  # Packed `r (32) || s (32) || v`. `v` is one or more bytes: 65 bytes when
  # `v` fits in a single byte, longer otherwise. At chain id 110, EIP-155
  # `v` is 255 or 256 depending on recovery parity.
  @type signature :: <<_::520, _::_*8>>
  @type bytes32 :: <<_::256>>
  @type contract :: address() | atom()

  api(:describe, "Describe Cartouche's registered API surface at progressive levels of detail.",
    params: [
      mod_or_short: [
        kind: :value,
        description: "Full module atom, Descripex short name, or Cartouche alias to drill into."
      ],
      func_name: [
        kind: :value,
        description: "Function name atom for Level 3 detail."
      ]
    ],
    returns: %{
      type: :list_or_map,
      description: "Level 1 module overview list, Level 2 function summary list, or Level 3 function detail map."
    },
    errors: [
      argument_error: "Raised when the requested module short name or alias cannot be resolved."
    ]
  )

  @doc "Return a Level 1 overview of all modules in this library."
  @spec describe() :: [map()]
  def describe do
    @descripex_modules
    |> Descripex.Describe.describe()
    |> Enum.map(&normalize_descripex_summary/1)
  end

  @doc "Return Level 2 function list for a module by full atom, Descripex short name, or Cartouche alias."
  @spec describe(module() | atom()) :: [map()]
  def describe(mod_or_short),
    do: Descripex.Describe.describe(@descripex_modules, normalize_descripex_module(mod_or_short))

  @doc "Return Level 3 function detail for a module by full atom, Descripex short name, or Cartouche alias."
  @spec describe(module() | atom(), atom()) :: map() | nil
  def describe(mod_or_short, func_name) do
    Descripex.Describe.describe(@descripex_modules, normalize_descripex_module(mod_or_short), func_name)
  end

  @doc false
  @spec __descripex_modules__() :: [module()]
  def __descripex_modules__, do: @descripex_modules

  api(
    :get_contract_address,
    "Resolve a configured contract reference (raw address, 0x-hex, or alias atom) to a 20-byte address.",
    params: [
      address: [
        kind: :value,
        description:
          "Either a 20-byte binary, a `0x`-hex address string, or an atom alias registered under " <>
            "`config :cartouche, :contracts, [alias: \"0x...\"]`."
      ]
    ],
    returns: %{
      type: :address,
      description: "20-byte binary address."
    },
    errors: [
      key_error: "Raised by `Keyword.fetch!/2` when an atom alias is not found in `:cartouche, :contracts`."
    ]
  )

  @doc ~S"""
  Returns a contract address, that may have been set in configuration.

  ## Examples

      iex> Onchain.Configuration.get_contract_address(<<1::160>>)
      <<1::160>>

      iex> Onchain.Configuration.get_contract_address("0x0000000000000000000000000000000000000001")
      <<1::160>>

      iex> Application.put_env(:cartouche, :contracts, [test: "0x0000000000000000000000000000000000000001"])
      iex> Onchain.Configuration.get_contract_address(:test)
      <<1::160>>
  """
  @spec get_contract_address(binary() | atom()) :: address()
  def get_contract_address(address) when is_binary(address), do: Onchain.Hex.decode_hex_input!(address)

  def get_contract_address(contract) when is_atom(contract) do
    :cartouche
    |> Application.get_env(:contracts, [])
    |> Keyword.fetch!(contract)
    |> Onchain.Hex.decode_hex_input!()
  end

  @spec normalize_descripex_module(module() | atom()) :: module() | atom()
  defp normalize_descripex_module(module) when module in @descripex_modules, do: module

  defp normalize_descripex_module(short_or_alias) do
    Map.get(@descripex_aliases, short_or_alias, short_or_alias)
  end

  @spec normalize_descripex_summary(map()) :: map()
  defp normalize_descripex_summary(%{module: module} = summary) do
    case Map.fetch(@descripex_summary_names, module) do
      {:ok, short_name} -> %{summary | short_name: short_name}
      :error -> summary
    end
  end

  defp normalize_descripex_summary(summary), do: summary
end
