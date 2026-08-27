defmodule Cartouche.Solana.ATA do
  @moduledoc """
  Associated Token Account (ATA) utilities for Solana.

  An ATA is the canonical token account for a (wallet, mint) pair. It is
  a PDA derived with seeds `[wallet, token_program_id, mint]` under the
  Associated Token Account Program.

  ## Examples

      iex> {pub, _} = Cartouche.Solana.Keys.from_seed(<<1::256>>)
      iex> mint = Cartouche.Solana.Programs.wrapped_sol_mint()
      iex> {ata, bump} = Cartouche.Solana.ATA.find_address(pub, mint)
      iex> byte_size(ata) == 32 and bump >= 0 and bump <= 255
      true
  """

  use Descripex, namespace: "/solana/ata"

  alias Cartouche.Solana.PDA
  alias Cartouche.Solana.Programs
  alias Cartouche.Solana.Transaction.AccountMeta
  alias Cartouche.Solana.Transaction.Instruction

  api(:find_address, "Derive the associated token account PDA for a wallet and mint.",
    params: [
      wallet: [
        kind: :value,
        description: "32-byte wallet public key; base58 address strings should be decoded before calling."
      ],
      mint: [
        kind: :value,
        description: "32-byte mint public key; base58 mint address strings should be decoded before calling."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options, including `:token_program` to override the SPL Token Program pubkey."
      ]
    ],
    returns: %{
      type: :associated_token_account_address,
      description: "`{ata_address, bump_seed}` with the 32-byte ATA PDA and its bump seed."
    },
    composes_with: [:create, :create_idempotent]
  )

  @doc """
  Derive the associated token account address for a wallet + mint.

  Pure computation (no RPC call). Returns `{ata_address, bump_seed}`.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
    Pass `Programs.token_2022_program()` for Token-2022 mints.
  """
  @spec find_address(<<_::256>>, <<_::256>>, keyword()) :: {<<_::256>>, non_neg_integer()}
  def find_address(<<wallet::binary-32>>, <<mint::binary-32>>, opts \\ []) do
    token_program = Keyword.get(opts, :token_program, Programs.token_program())

    PDA.find_program_address!(
      [wallet, token_program, mint],
      Programs.ata_program()
    )
  end

  api(:create, "Build an Associated Token Account create instruction that fails if the ATA already exists.",
    params: [
      payer: [
        kind: :value,
        description: "32-byte payer public key; this account signs and funds ATA creation."
      ],
      wallet: [
        kind: :value,
        description: "32-byte owner wallet public key for the associated token account."
      ],
      mint: [
        kind: :value,
        description: "32-byte token mint public key."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options, including `:token_program` to override the SPL Token Program pubkey."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "%Cartouche.Solana.Transaction.Instruction{} targeting the Associated Token Account Program."
    },
    composes_with: [:find_address]
  )

  @doc """
  Build an instruction to create an ATA. Fails if it already exists.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec create(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def create(<<payer::binary-32>>, <<wallet::binary-32>>, <<mint::binary-32>>, opts \\ []) do
    build_create_instruction(payer, wallet, mint, <<0>>, opts)
  end

  api(:create_idempotent, "Build an idempotent Associated Token Account create instruction.",
    params: [
      payer: [
        kind: :value,
        description: "32-byte payer public key; this account signs and funds ATA creation."
      ],
      wallet: [
        kind: :value,
        description: "32-byte owner wallet public key for the associated token account."
      ],
      mint: [
        kind: :value,
        description: "32-byte token mint public key."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options, including `:token_program` to override the SPL Token Program pubkey."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "%Cartouche.Solana.Transaction.Instruction{} targeting the Associated Token Account Program."
    },
    composes_with: [:find_address]
  )

  @doc """
  Build an instruction to create an ATA, succeeding even if it already exists.

  This is the preferred variant for most use cases - it is a no-op if the
  ATA already exists.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec create_idempotent(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def create_idempotent(<<payer::binary-32>>, <<wallet::binary-32>>, <<mint::binary-32>>, opts \\ []) do
    build_create_instruction(payer, wallet, mint, <<1>>, opts)
  end

  # data is the ATA program instruction index:
  #   <<0>> = Create (fails if ATA already exists)
  #   <<1>> = CreateIdempotent (no-op if ATA already exists)
  @spec build_create_instruction(<<_::256>>, <<_::256>>, <<_::256>>, binary(), keyword()) :: Instruction.t()
  defp build_create_instruction(payer, wallet, mint, data, opts) do
    token_program = Keyword.get(opts, :token_program, Programs.token_program())
    {ata, _bump} = find_address(wallet, mint, opts)

    %Instruction{
      program_id: Programs.ata_program(),
      accounts: [
        %AccountMeta{pubkey: payer, is_signer: true, is_writable: true},
        %AccountMeta{pubkey: ata, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: wallet, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: mint, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: Programs.system_program(), is_signer: false, is_writable: false},
        %AccountMeta{pubkey: token_program, is_signer: false, is_writable: false}
      ],
      data: data
    }
  end
end
