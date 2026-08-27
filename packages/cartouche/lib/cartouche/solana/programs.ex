defmodule Cartouche.Solana.Programs do
  @moduledoc """
  Well-known Solana program IDs and addresses.

  Centralizes program addresses to avoid scattered Base58 decoding
  across modules.
  """

  use Descripex, namespace: "/solana/programs"
  use Cartouche.Base58

  api(:system_program, "Return the Solana System Program id.",
    returns: %{
      type: :solana_program_id,
      description: "32-byte program id for base58 string `11111111111111111111111111111111`."
    }
  )

  @doc "System Program (`11111111111111111111111111111111`)"
  @spec system_program() :: <<_::256>>
  def system_program, do: <<0::256>>

  api(:token_program, "Return the SPL Token Program id.",
    returns: %{
      type: :solana_program_id,
      description: "32-byte program id for base58 string `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`."
    }
  )

  @doc "SPL Token Program (`TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`)"
  @spec token_program() :: <<_::256>>
  def token_program, do: ~B58[TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA]

  api(:token_2022_program, "Return the Token-2022 Program id.",
    returns: %{
      type: :solana_program_id,
      description: "32-byte program id for base58 string `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`."
    }
  )

  @doc "Token-2022 Program (`TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`)"
  @spec token_2022_program() :: <<_::256>>
  def token_2022_program, do: ~B58[TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb]

  api(:ata_program, "Return the Associated Token Account Program id.",
    returns: %{
      type: :solana_program_id,
      description: "32-byte program id for base58 string `ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL`."
    }
  )

  @doc "Associated Token Account Program (`ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL`)"
  @spec ata_program() :: <<_::256>>
  def ata_program, do: ~B58[ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL]

  api(:compute_budget_program, "Return the Compute Budget Program id.",
    returns: %{
      type: :solana_program_id,
      description: "32-byte program id for base58 string `ComputeBudget111111111111111111111111111111`."
    }
  )

  @doc "Compute Budget Program (`ComputeBudget111111111111111111111111111111`)"
  @spec compute_budget_program() :: <<_::256>>
  def compute_budget_program, do: ~B58[ComputeBudget111111111111111111111111111111]

  api(:wrapped_sol_mint, "Return the Wrapped SOL mint address.",
    returns: %{
      type: :solana_mint,
      description: "32-byte mint address for base58 string `So11111111111111111111111111111111111111112`."
    }
  )

  @doc "Wrapped SOL Mint (`So11111111111111111111111111111111111111112`)"
  @spec wrapped_sol_mint() :: <<_::256>>
  def wrapped_sol_mint, do: ~B58[So11111111111111111111111111111111111111112]
end
