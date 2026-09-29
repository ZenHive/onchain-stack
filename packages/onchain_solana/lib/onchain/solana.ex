defmodule Onchain.Solana do
  @moduledoc "Solana RPC, transactions, keys, token programs, and signing."
  use Descripex, namespace: "/solana"

  alias Onchain.Solana.ATA
  alias Onchain.Solana.Keys
  alias Onchain.Solana.PDA
  alias Onchain.Solana.Programs
  alias Onchain.Solana.RPC
  alias Onchain.Solana.Signer
  alias Onchain.Solana.SystemProgram
  alias Onchain.Solana.Token
  alias Onchain.Solana.TokenProgram
  alias Onchain.Solana.Transaction

  @descripex_modules [
    Onchain.Solana,
    Onchain.Solana.Base58,
    Signer,
    Transaction,
    Keys,
    PDA,
    ATA,
    Programs,
    SystemProgram,
    TokenProgram,
    Token,
    RPC
  ]

  @descripex_aliases %{
    solana_signer: Signer,
    solana_transaction: Transaction,
    solana_keys: Keys,
    solana_pda: PDA,
    solana_ata: ATA,
    solana_programs: Programs,
    solana_system_program: SystemProgram,
    solana_token_program: TokenProgram,
    solana_token: Token,
    solana_rpc: RPC
  }
  @descripex_summary_names Map.new(@descripex_aliases, fn {short_name, module} -> {module, short_name} end)

  api(:describe, "Describe Onchain.Solana's registered API surface at progressive levels of detail.",
    params: [
      mod_or_short: [
        kind: :value,
        description: "Full module atom, Descripex short name, or Onchain.Solana alias to drill into."
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

  @doc "Return Level 2 function list for a module by full atom, Descripex short name, or Onchain.Solana alias."
  @spec describe(module() | atom()) :: [map()]
  def describe(mod_or_short),
    do: Descripex.Describe.describe(@descripex_modules, normalize_descripex_module(mod_or_short))

  @doc "Return Level 3 function detail for a module by full atom, Descripex short name, or Onchain.Solana alias."
  @spec describe(module() | atom(), atom()) :: map() | nil
  def describe(mod_or_short, func_name) do
    Descripex.Describe.describe(@descripex_modules, normalize_descripex_module(mod_or_short), func_name)
  end

  @doc false
  @spec __descripex_modules__() :: [module()]
  def __descripex_modules__, do: @descripex_modules

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
