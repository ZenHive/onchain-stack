defmodule Onchain.Solana.DescripexValidationTest do
  use ExUnit.Case, async: false

  alias Onchain.Solana.Transaction

  test "registers Solana RPC for Phase 12 discovery" do
    assert Onchain.Solana.RPC in Onchain.Solana.__descripex_modules__()
  end

  test "describe/0 lists registered modules" do
    assert Enum.any?(Onchain.Solana.describe(), &(&1.module == Transaction))
  end

  test "Solana modules resolve through explicit discovery aliases" do
    aliases = %{
      solana_signer: Onchain.Solana.Signer,
      solana_transaction: Transaction,
      solana_keys: Onchain.Solana.Keys,
      solana_pda: Onchain.Solana.PDA,
      solana_ata: Onchain.Solana.ATA,
      solana_programs: Onchain.Solana.Programs,
      solana_system_program: Onchain.Solana.SystemProgram,
      solana_token_program: Onchain.Solana.TokenProgram,
      solana_token: Onchain.Solana.Token
    }

    for {short_name, module} <- aliases do
      assert Onchain.Solana.describe(short_name) == Onchain.Solana.describe(module)
    end
  end

  test "Solana discovery accepts full module atoms" do
    assert Onchain.Solana.describe(Transaction) == Onchain.Solana.describe(:solana_transaction)
  end

  test "Solana sign_partial metadata documents unsigned placeholder signatures" do
    detail = Onchain.Solana.describe(:solana_transaction, :sign_partial)

    assert detail.returns.description =~ "placeholder signatures"
    assert detail.returns.description =~ "empty signer map"
  end

  test "exposes Solana RPC through a stable short alias" do
    assert Enum.any?(Onchain.Solana.describe(:solana_rpc), &match?(%{name: :get_balance}, &1))
  end

  test "exposes Solana RPC function detail through a stable short alias" do
    assert %{
             description: description,
             params: %{pubkey: %{kind: :value}},
             returns: %{type: :ok_error_tuple}
           } = Onchain.Solana.describe(:solana_rpc, :get_balance)

    assert description == "Get the SOL balance for an account."
  end
end
