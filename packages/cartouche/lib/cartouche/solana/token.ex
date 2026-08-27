defmodule Cartouche.Solana.Token do
  @moduledoc """
  High-level token operations for Solana: balance queries, transfers,
  and ATA management.

  Combines RPC calls with PDA derivation and instruction building.
  Analogous to `Cartouche.Erc20` on the Ethereum side.

  ## Examples

      # Get USDC balance for a wallet
      {:ok, balance} = Cartouche.Solana.Token.get_balance(wallet, usdc_mint)

      # Get all token balances
      {:ok, balances} = Cartouche.Solana.Token.get_all_balances(wallet)

      # Build transfer instructions (includes ATA creation if needed)
      instructions = Cartouche.Solana.Token.transfer_instructions(
        from_wallet, to_wallet, mint, 1_000_000, 6
      )
  """

  use Descripex, namespace: "/solana/token"

  alias Cartouche.Solana.ATA
  alias Cartouche.Solana.Programs
  alias Cartouche.Solana.RPC
  alias Cartouche.Solana.TokenProgram

  api(:get_balance, "Get the balance of a specific token mint for a Solana wallet.",
    params: [
      wallet: [
        kind: :value,
        description: "32-byte owner wallet public key; base58 address strings should be decoded before calling."
      ],
      mint: [
        kind: :value,
        description: "32-byte token mint public key; base58 mint address strings should be decoded before calling."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "RPC options forwarded to `Cartouche.Solana.RPC.get_token_accounts_by_owner/3`."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %{amount: raw_amount, decimals: decimals, mint: base58_mint}}` or `{:error, reason}` from the RPC call."
    },
    composes_with: [:get_all_balances]
  )

  @doc """
  Get the balance of a specific token for a wallet.

  Uses `getTokenAccountsByOwner` with a mint filter and `jsonParsed` encoding.
  Sums across all token accounts for the mint (usually just the ATA, but
  handles edge cases with multiple accounts).

  Returns the raw integer amount, decimals, and mint address.
  """
  @spec get_balance(<<_::256>>, <<_::256>>, keyword()) ::
          {:ok,
           %{
             amount: non_neg_integer(),
             decimals: non_neg_integer(),
             mint: String.t()
           }}
          | {:error, term()}
  def get_balance(wallet, mint, opts \\ []) do
    mint_b58 = Cartouche.Base58.encode(mint)

    with {:ok, accounts} <-
           RPC.get_token_accounts_by_owner(wallet, [mint: mint], opts) do
      summarize_balance(accounts, mint_b58)
    end
  end

  @spec summarize_balance([map()], String.t()) ::
          {:ok, %{amount: non_neg_integer(), decimals: non_neg_integer(), mint: String.t()}}
  defp summarize_balance([], mint_b58), do: {:ok, %{amount: 0, decimals: 0, mint: mint_b58}}

  defp summarize_balance(accounts, mint_b58) do
    {total, decimals} = Enum.reduce(accounts, {0, 0}, &accumulate_token_amount/2)
    {:ok, %{amount: total, decimals: decimals, mint: mint_b58}}
  end

  @spec accumulate_token_amount(map(), {non_neg_integer(), non_neg_integer()}) ::
          {non_neg_integer(), non_neg_integer()}
  defp accumulate_token_amount(acct, {sum, _dec}) do
    token_amount = get_in(acct, [:account, :data, "parsed", "info", "tokenAmount"])
    amount = String.to_integer(token_amount["amount"])
    {sum + amount, token_amount["decimals"]}
  end

  api(:get_all_balances, "Get all SPL Token and optionally Token-2022 balances for a Solana wallet.",
    params: [
      wallet: [
        kind: :value,
        description: "32-byte owner wallet public key; base58 address strings should be decoded before calling."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "RPC options forwarded to `Cartouche.Solana.RPC.get_token_accounts_by_owner/3`; set `:include_token_2022` to `false` to skip Token-2022."
      ]
    ],
    opts: [
      include_token_2022: [
        kind: :value,
        default: true,
        description: "Whether to query Token-2022 accounts in addition to the SPL Token Program."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, balances}` where each balance includes base58 mint and token-account strings, raw integer amount, and decimals; or `{:error, reason}` from RPC."
    },
    composes_with: [:get_balance]
  )

  @doc """
  Get all token balances for a wallet.

  Queries both SPL Token Program and Token-2022 by default.

  ## Options
  - `:include_token_2022` - also query Token-2022 (default: true)
  """
  @spec get_all_balances(<<_::256>>, keyword()) ::
          {:ok,
           [
             %{
               mint: String.t(),
               amount: non_neg_integer(),
               decimals: non_neg_integer(),
               token_account: String.t()
             }
           ]}
          | {:error, term()}
  def get_all_balances(wallet, opts \\ []) do
    include_2022 = Keyword.get(opts, :include_token_2022, true)

    with {:ok, token_accounts} <-
           RPC.get_token_accounts_by_owner(
             wallet,
             [program_id: Programs.token_program()],
             opts
           ) do
      balances = parse_token_accounts(token_accounts)
      maybe_include_token_2022(balances, include_2022, wallet, opts)
    end
  end

  @spec maybe_include_token_2022([map()], boolean(), <<_::256>>, keyword()) ::
          {:ok, [map()]} | {:error, term()}
  defp maybe_include_token_2022(balances, false, _wallet, _opts), do: {:ok, balances}

  defp maybe_include_token_2022(balances, true, wallet, opts) do
    with {:ok, t22_accounts} <-
           RPC.get_token_accounts_by_owner(
             wallet,
             [program_id: Programs.token_2022_program()],
             opts
           ) do
      {:ok, balances ++ parse_token_accounts(t22_accounts)}
    end
  end

  api(:transfer_instructions, "Build token transfer instructions between Solana wallets.",
    params: [
      from_wallet: [
        kind: :value,
        description:
          "32-byte sender wallet public key and transfer authority; base58 address strings should be decoded before calling."
      ],
      to_wallet: [
        kind: :value,
        description: "32-byte recipient wallet public key; base58 address strings should be decoded before calling."
      ],
      mint: [
        kind: :value,
        description: "32-byte token mint public key; base58 mint address strings should be decoded before calling."
      ],
      amount: [
        kind: :value,
        description: "Raw token amount in the mint's smallest unit."
      ],
      decimals: [
        kind: :value,
        description: "Mint decimal count used by the checked transfer instruction."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Instruction options, including optional `:token_program` override."
      ]
    ],
    opts: [
      token_program: [
        kind: :value,
        description: "Optional 32-byte SPL Token or Token-2022 program id override."
      ]
    ],
    returns: %{
      type: :solana_instructions,
      description:
        "List of `%Cartouche.Solana.Transaction.Instruction{}` values: idempotent destination ATA creation plus checked token transfer."
    }
  )

  @doc """
  Build instructions for a token transfer between wallets.

  Handles ATA derivation for both source and destination. Includes an
  idempotent ATA creation for the destination (no-op if it already exists).
  Uses `transfer_checked` for safety.

  Returns a list of instructions suitable for `Transaction.build_message/3`.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec transfer_instructions(
          <<_::256>>,
          <<_::256>>,
          <<_::256>>,
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) :: [Cartouche.Solana.Transaction.Instruction.t()]
  def transfer_instructions(from_wallet, to_wallet, mint, amount, decimals, opts \\ []) do
    {from_ata, _} = ATA.find_address(from_wallet, mint, opts)
    {to_ata, _} = ATA.find_address(to_wallet, mint, opts)

    create_ix = ATA.create_idempotent(from_wallet, to_wallet, mint, opts)

    transfer_ix =
      TokenProgram.transfer_checked(from_ata, mint, to_ata, from_wallet, amount, decimals, opts)

    [create_ix, transfer_ix]
  end

  @spec parse_token_accounts([map()]) :: [
          %{
            mint: String.t(),
            amount: non_neg_integer(),
            decimals: non_neg_integer(),
            token_account: String.t()
          }
        ]
  defp parse_token_accounts(accounts) do
    Enum.map(accounts, fn acct ->
      info = get_in(acct, [:account, :data, "parsed", "info"])
      token_amount = info["tokenAmount"]

      %{
        mint: info["mint"],
        amount: String.to_integer(token_amount["amount"]),
        decimals: token_amount["decimals"],
        token_account: acct.pubkey
      }
    end)
  end
end
