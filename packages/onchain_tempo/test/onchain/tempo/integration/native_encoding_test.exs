defmodule Onchain.Tempo.Integration.NativeEncodingTest do
  use ExUnit.Case, async: false

  alias Onchain.Hash
  alias Onchain.Signer.Secp256k1
  alias Onchain.Tempo.Codec
  alias Onchain.Tempo.Faucet
  alias Onchain.Tempo.RPC
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  @moduletag :integration
  @moduletag timeout: 120_000
  @token "0x20c0000000000000000000000000000000000000"

  test "Moderato accepts native encodings with and without key authorization and rejects malformed bytes" do
    rpc = Faucet.rpc_url()
    sender = funded_wallet(rpc)
    payer = funded_wallet(rpc)

    opts = [
      private_key: sender.private_key,
      token: @token,
      recipient: sender.address_hex,
      amount: 1,
      chain_id: 42_431,
      rpc_url: rpc,
      gas_limit: 2_000_000
    ]

    assert {:ok, raw} = Builder.build_signed_transfer(opts)
    plain_hash = broadcast(raw, rpc)
    assert plain_hash == Codec.hex(Hash.keccak(Codec.bytes(raw)))

    authorization = %{
      chain_id: 42_431,
      key_type: :secp256k1,
      key_id: payer.address_bin,
      expiry: nil,
      limits: nil,
      allowed_calls: nil,
      witness: nil,
      is_admin: false,
      account: nil,
      signature: nil
    }

    assert {:ok, hash} = Transaction.key_authorization_hash(authorization)
    assert {:ok, signature} = Secp256k1.sign_payload(hash, sender.private_key)

    authorization = %{
      authorization
      | signature: {:secp256k1, %{r: signature.r, s: signature.s, y_parity: signature.recid}}
    }

    assert {:ok, sponsored} = Builder.build_fee_payer_transfer(Keyword.put(opts, :key_authorization, authorization))
    assert {:ok, tx} = Transaction.deserialize(sponsored)
    assert {:ok, cosigned} = Transaction.cosign_fee_payer(tx, payer.private_key, Codec.bytes(@token))
    assert {:ok, recovered} = Transaction.sender(cosigned)
    assert recovered == sender.address_bin
    assert {:ok, recovered_payer} = Codec.run("fee_payer", Map.put(Codec.request(cosigned), "sender", sender.address_hex))
    assert recovered_payer == String.downcase(payer.address_hex)
    key_hash = broadcast(cosigned.raw, rpc)
    assert key_hash == Codec.hex(Hash.keccak(Codec.bytes(cosigned.raw)))
    assert {:error, error} = RPC.broadcast_async("0x76ff", rpc)
    assert error =~ "decode" or error =~ "-32602"

    evidence = %{
      recorded_at: DateTime.to_iso8601(DateTime.utc_now()),
      endpoint: rpc,
      tempo_primitives: "1.11.0",
      chain_id: 42_431,
      without_key_authorization: %{hash: plain_hash, status: 1, raw: raw},
      with_key_authorization: %{
        hash: key_hash,
        status: 1,
        raw: cosigned.raw,
        sender: sender.address_hex,
        fee_payer: payer.address_hex
      },
      live_error: %{raw: "0x76ff", error: error}
    }

    File.write!("priv/verification/0x76/native_live_evidence.json", Jason.encode!(evidence, pretty: true) <> "\n")
  end

  # spec-tags: TEMPO-4, TEMPO-5
  test "Moderato accepts an ox P256 transaction recovered by the native boundary" do
    rpc = Faucet.rpc_url()
    oracle = "priv/verification/0x76/oracle"
    assert System.find_executable("node"), "Install Node.js and run npm ci --prefix #{oracle}"
    {output, status} = System.cmd("node", ["#{oracle}/live.mjs"], stderr_to_stdout: true)
    assert status == 0, "Install oracle dependencies with npm ci --prefix #{oracle}: #{output}"
    vector = Jason.decode!(output)
    assert {:ok, tx} = Transaction.deserialize(vector["raw"])
    assert {:p256, _} = tx.signature
    assert {:ok, recovered} = Transaction.sender(tx)
    assert Codec.hex(recovered) == vector["sender"]
    setup = Faucet.fund_address(vector["sender"], rpc_url: rpc)

    assert {:ok, funding_hashes} = setup,
           "Moderato setup failed: #{inspect(setup)}. Set TEMPO_RPC_URL to a reachable chain 42431 endpoint with tempo_fundAddress, eth_sendRawTransaction and eth_getTransactionReceipt; install Node.js and npm ci --prefix #{oracle}."

    for hash <- funding_hashes, do: assert(%{status: 1} = receipt(hash, rpc, 50))
    hash = broadcast(tx.raw, rpc)
    assert hash == vector["hash"]
    assert {:error, error} = RPC.broadcast_async("0x76ff", rpc)
    assert error =~ "decode" or error =~ "-32602"

    evidence = %{
      recorded_at: DateTime.to_iso8601(DateTime.utc_now()),
      endpoint: rpc,
      oracle: %{package: "ox", version: "1.8.5"},
      tempo_primitives: "1.11.0",
      chain_id: 42_431,
      success: %{signature: "p256", hash: hash, status: 1, raw: tx.raw, recovered_sender: Codec.hex(recovered)},
      live_error: %{raw: "0x76ff", error: error}
    }

    File.write!("priv/verification/0x76/all_signatures_live_evidence.json", Jason.encode!(evidence, pretty: true) <> "\n")
  end

  defp broadcast(raw, rpc) do
    assert {:ok, hash} = RPC.broadcast_async(raw, rpc),
           "Moderato broadcast failed at #{rpc}; TEMPO_RPC_URL must support eth_sendRawTransaction on chain 42431"

    assert %{status: 1} = receipt(hash, rpc, 50)
    hash
  end

  defp receipt(hash, rpc, attempts) do
    case RPC.fetch_receipt(hash, rpc) do
      {:ok, receipt} when is_map(receipt) ->
        receipt

      _result when attempts > 0 ->
        Process.sleep(200)
        receipt(hash, rpc, attempts - 1)

      result ->
        flunk("Moderato receipt unavailable for #{hash} at #{rpc}: #{inspect(result)}")
    end
  end

  defp funded_wallet(rpc) do
    case Faucet.fresh_funded_wallet(rpc_url: rpc) do
      {:ok, wallet} ->
        wallet

      {:error, reason} ->
        flunk(
          "Moderato setup failed at #{rpc}: #{inspect(reason)}. Set TEMPO_RPC_URL to a reachable Moderato (chain 42431) endpoint supporting tempo_fundAddress, eth_call, eth_getTransactionCount and eth_sendRawTransaction and eth_getTransactionReceipt; rerun ONCHAIN_BUILD=1 mix test test/onchain/tempo/integration/native_encoding_test.exs --include integration."
        )
    end
  end
end
