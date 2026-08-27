defmodule Cartouche.Solana.TokenProgram do
  @moduledoc """
  Instruction builders for the SPL Token Program.

  Works with both SPL Token and Token-2022 via the `:token_program` option.
  SPL Token uses a 1-byte instruction index (unlike System Program's 4-byte u32).

  ## Examples

      iex> ix = Cartouche.Solana.TokenProgram.transfer(<<1::256>>, <<2::256>>, <<3::256>>, 1_000_000)
      iex> ix.data
      <<3, 64, 66, 15, 0, 0, 0, 0, 0>>
  """

  use Descripex, namespace: "/solana/token_program"

  alias Cartouche.Solana.Programs
  alias Cartouche.Solana.Transaction.AccountMeta
  alias Cartouche.Solana.Transaction.Instruction

  api(:transfer, "Build an SPL token transfer instruction.",
    params: [
      source: [
        kind: :value,
        description: "32-byte source token account public key; base58 address strings must be decoded before calling."
      ],
      destination: [
        kind: :value,
        description:
          "32-byte destination token account public key; base58 address strings must be decoded before calling."
      ],
      authority: [
        kind: :value,
        description: "32-byte transfer authority public key; base58 address strings must be decoded before calling."
      ],
      amount: [kind: :value, description: "Raw token amount in the mint's base units."],
      opts: [
        kind: :value,
        default: [],
        description: "Options; `:token_program` may override the SPL Token Program public key."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "`%Cartouche.Solana.Transaction.Instruction{}` for SPL Token instruction index 3."
    }
  )

  @doc """
  Transfer tokens from source to destination.

  The authority must sign the transaction.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec transfer(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), keyword()) ::
          Instruction.t()
  def transfer(<<source::binary-32>>, <<destination::binary-32>>, <<authority::binary-32>>, amount, opts \\ [])
      when is_integer(amount) and amount >= 0 do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: source, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: destination, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<3, amount::little-unsigned-64>>
    }
  end

  api(:transfer_checked, "Build an SPL token transfer instruction with mint and decimal verification.",
    params: [
      source: [
        kind: :value,
        description: "32-byte source token account public key; base58 address strings must be decoded before calling."
      ],
      mint: [kind: :value, description: "32-byte mint public key; base58 address strings must be decoded before calling."],
      destination: [
        kind: :value,
        description:
          "32-byte destination token account public key; base58 address strings must be decoded before calling."
      ],
      authority: [
        kind: :value,
        description: "32-byte transfer authority public key; base58 address strings must be decoded before calling."
      ],
      amount: [kind: :value, description: "Raw token amount in the mint's base units."],
      decimals: [kind: :value, description: "Mint decimal count used by the token program to verify the transfer amount."],
      opts: [
        kind: :value,
        default: [],
        description: "Options; `:token_program` may override the SPL Token Program public key."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "`%Cartouche.Solana.Transaction.Instruction{}` for SPL Token instruction index 12."
    }
  )

  @doc """
  Transfer tokens with decimal verification (preferred over `transfer/5`).

  Requires passing the mint, preventing accidental wrong-decimal transfers.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec transfer_checked(
          <<_::256>>,
          <<_::256>>,
          <<_::256>>,
          <<_::256>>,
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) :: Instruction.t()
  def transfer_checked(
        <<source::binary-32>>,
        <<mint::binary-32>>,
        <<destination::binary-32>>,
        <<authority::binary-32>>,
        amount,
        decimals,
        opts \\ []
      )
      when is_integer(amount) and amount >= 0 and is_integer(decimals) and decimals >= 0 do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: source, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: mint, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: destination, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<12, amount::little-unsigned-64, decimals::unsigned-8>>
    }
  end

  api(:approve, "Build an SPL token approve instruction for a delegate allowance.",
    params: [
      source: [
        kind: :value,
        description: "32-byte source token account public key; base58 address strings must be decoded before calling."
      ],
      delegate: [
        kind: :value,
        description: "32-byte delegate public key; base58 address strings must be decoded before calling."
      ],
      authority: [
        kind: :value,
        description: "32-byte source authority public key; base58 address strings must be decoded before calling."
      ],
      amount: [kind: :value, description: "Raw token allowance in the mint's base units."],
      opts: [
        kind: :value,
        default: [],
        description: "Options; `:token_program` may override the SPL Token Program public key."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "`%Cartouche.Solana.Transaction.Instruction{}` for SPL Token instruction index 4."
    }
  )

  @doc """
  Approve a delegate to transfer up to `amount` tokens from source.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec approve(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), keyword()) ::
          Instruction.t()
  def approve(<<source::binary-32>>, <<delegate::binary-32>>, <<authority::binary-32>>, amount, opts \\ [])
      when is_integer(amount) and amount >= 0 do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: source, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: delegate, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<4, amount::little-unsigned-64>>
    }
  end

  api(:close_account, "Build an SPL token close-account instruction.",
    params: [
      account: [
        kind: :value,
        description: "32-byte token account public key to close; base58 address strings must be decoded before calling."
      ],
      destination: [
        kind: :value,
        description:
          "32-byte destination public key receiving remaining SOL rent; base58 address strings must be decoded before calling."
      ],
      authority: [
        kind: :value,
        description: "32-byte close authority public key; base58 address strings must be decoded before calling."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options; `:token_program` may override the SPL Token Program public key."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "`%Cartouche.Solana.Transaction.Instruction{}` for SPL Token instruction index 9."
    }
  )

  @doc """
  Close a token account, transferring remaining SOL rent to destination.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec close_account(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def close_account(<<account::binary-32>>, <<destination::binary-32>>, <<authority::binary-32>>, opts \\ []) do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: account, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: destination, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<9>>
    }
  end

  api(:sync_native, "Build an SPL token sync-native instruction for wrapped SOL accounts.",
    params: [
      account: [
        kind: :value,
        description:
          "32-byte wrapped SOL token account public key; base58 address strings must be decoded before calling."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options; `:token_program` may override the SPL Token Program public key."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "`%Cartouche.Solana.Transaction.Instruction{}` for SPL Token instruction index 17."
    }
  )

  @doc """
  Sync the native SOL balance of a wrapped SOL token account.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec sync_native(<<_::256>>, keyword()) :: Instruction.t()
  def sync_native(<<account::binary-32>>, opts \\ []) do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: account, is_signer: false, is_writable: true}
      ],
      data: <<17>>
    }
  end

  @spec token_program(keyword()) :: <<_::256>>
  defp token_program(opts), do: Keyword.get(opts, :token_program, Programs.token_program())
end
