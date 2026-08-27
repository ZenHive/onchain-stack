defmodule Cartouche.Solana.SystemProgram do
  @moduledoc """
  Instructions for the Solana System Program.

  The System Program (address: `11111111111111111111111111111111`, 32 zero bytes)
  handles basic operations like SOL transfers and account creation.
  """

  use Descripex, namespace: "/solana/system_program"

  alias Cartouche.Solana.Programs
  alias Cartouche.Solana.Transaction.AccountMeta
  alias Cartouche.Solana.Transaction.Instruction

  api(:program_id, "Return the Solana System Program public key.",
    returns: %{
      type: :solana_pubkey,
      description: "32-byte System Program public key; base58 string `11111111111111111111111111111111`."
    }
  )

  @doc """
  Returns the System Program pubkey (32 zero bytes).

  Delegates to `Cartouche.Solana.Programs.system_program/0`.
  """
  @spec program_id() :: <<_::256>>
  def program_id, do: Programs.system_program()

  api(:transfer, "Build a Solana System Program SOL transfer instruction.",
    params: [
      from: [
        kind: :value,
        description: "32-byte sender public key; base58 address strings should be decoded before calling."
      ],
      to: [
        kind: :value,
        description: "32-byte recipient public key; base58 address strings should be decoded before calling."
      ],
      lamports: [kind: :value, description: "Amount to transfer, in lamports."]
    ],
    returns: %{
      type: :solana_instruction,
      description: "%Cartouche.Solana.Transaction.Instruction{} for a System Program transfer."
    }
  )

  @doc """
  Build a transfer instruction (SOL transfer).

  System Program instruction index 2.

  ## Examples

      iex> ix = Cartouche.Solana.SystemProgram.transfer(<<1::256>>, <<2::256>>, 1_000_000_000)
      iex> ix.program_id
      <<0::256>>
      iex> byte_size(ix.data)
      12
  """
  @spec transfer(<<_::256>>, <<_::256>>, non_neg_integer()) :: Instruction.t()
  def transfer(<<from::binary-32>>, <<to::binary-32>>, lamports) when is_integer(lamports) and lamports >= 0 do
    %Instruction{
      program_id: Programs.system_program(),
      accounts: [
        %AccountMeta{pubkey: from, is_signer: true, is_writable: true},
        %AccountMeta{pubkey: to, is_signer: false, is_writable: true}
      ],
      data: <<2::little-unsigned-32, lamports::little-unsigned-64>>
    }
  end

  api(:create_account, "Build a Solana System Program create-account instruction.",
    params: [
      from: [
        kind: :value,
        description: "32-byte funding account public key; base58 address strings should be decoded before calling."
      ],
      new_account: [
        kind: :value,
        description: "32-byte new account public key; base58 address strings should be decoded before calling."
      ],
      lamports: [kind: :value, description: "Rent-exempt funding amount, in lamports."],
      space: [kind: :value, description: "Account data allocation size, in bytes."],
      owner: [
        kind: :value,
        description: "32-byte owner program public key; base58 address strings should be decoded before calling."
      ]
    ],
    returns: %{
      type: :solana_instruction,
      description: "%Cartouche.Solana.Transaction.Instruction{} for a System Program create-account operation."
    }
  )

  @doc """
  Build a create_account instruction.

  System Program instruction index 0.

  ## Examples

      iex> ix = Cartouche.Solana.SystemProgram.create_account(<<1::256>>, <<2::256>>, 1_000_000, 165, <<3::256>>)
      iex> ix.program_id
      <<0::256>>
      iex> byte_size(ix.data)
      52
  """
  @spec create_account(<<_::256>>, <<_::256>>, non_neg_integer(), non_neg_integer(), <<_::256>>) ::
          Instruction.t()
  def create_account(<<from::binary-32>>, <<new_account::binary-32>>, lamports, space, <<owner::binary-32>>)
      when is_integer(lamports) and lamports >= 0 and is_integer(space) and space >= 0 do
    %Instruction{
      program_id: Programs.system_program(),
      accounts: [
        %AccountMeta{pubkey: from, is_signer: true, is_writable: true},
        %AccountMeta{pubkey: new_account, is_signer: true, is_writable: true}
      ],
      data: <<0::little-unsigned-32, lamports::little-unsigned-64, space::little-unsigned-64, owner::binary-32>>
    }
  end
end
