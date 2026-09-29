defmodule Cartouche.RPC.DevNodeTest do
  @moduledoc """
  Development-node tests for node-custody JSON-RPC methods.

  Hits a key-holding node (Anvil / Hardhat / geth --dev). Default-excluded;
  opt in with `mix test --only dev_node`. URL override: `CARTOUCHE_DEV_NODE_URL`.
  When that env var is unset, the suite boots a locally installed `anvil` on
  port 18545 and tears it down afterwards.
  """
  use ExUnit.Case, async: false

  alias Cartouche.Test.Live
  alias Cartouche.Transaction
  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  @moduletag :dev_node

  # Anvil account #0 when the suite boots an ephemeral node.
  @anvil_account <<0xF39FD6E51AAD88F6F4CE6AB8827279CFFFB92266::160>>
  # Any address works as an access-list key; WETH9 keeps it recognisable.
  @weth9 <<0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2::160>>

  setup_all do
    Live.assert_dev_node_available!()

    on_exit(fn ->
      Live.stop_ephemeral_anvil()
    end)

    opts = Live.dev_opts()
    {:ok, accounts} = Cartouche.RPC.accounts(opts)
    {:ok, %{opts: opts, accounts: accounts}}
  end

  test "eth_accounts returns the node's configured addresses", %{accounts: accounts} do
    assert accounts != []
    Enum.each(accounts, fn account -> assert byte_size(account) == 20 end)
  end

  test "eth_coinbase returns a 20-byte fee recipient", %{opts: opts} do
    assert {:ok, coinbase} = Cartouche.RPC.coinbase(opts)
    assert byte_size(coinbase) == 20
  end

  test "eth_fillTransaction populates a transaction when the node implements it", %{
    opts: opts,
    accounts: accounts
  } do
    from = hd(accounts)

    call = Call.new(<<0::160>>, <<>>, value: 0)

    case Cartouche.RPC.fill_transaction(call, Keyword.put(opts, :from, from)) do
      {:ok, filled} ->
        encoded = Transaction.encode(filled)
        assert {:ok, decoded} = Transaction.decode(encoded)
        assert decoded.nonce == filled.nonce

      {:error, %{code: -32_601, message: message}} ->
        # Observed on anvil 1.5.1-stable: the method is not implemented.
        assert message =~ "not found"

      {:error, other} ->
        flunk("unexpected eth_fillTransaction error: #{inspect(other)}")
    end
  end

  test "eth_sign returns a 65-byte signature from a managed account", %{opts: opts, accounts: accounts} do
    from = hd(accounts)
    digest = :crypto.hash(:sha256, "cartouche-dev-node-sign")
    assert {:ok, signature} = Cartouche.RPC.sign(from, digest, opts)
    assert byte_size(signature) == 65
  end

  test "eth_sign of an unknown account returns the node's refusal", %{opts: opts} do
    unknown = <<1::160>>
    digest = :crypto.hash(:sha256, "cartouche-dev-node-sign")

    # Observed on anvil for an account the node does not hold: code -32602,
    # message "No Signer available".
    assert {:error, %{code: -32_602, message: message}} = Cartouche.RPC.sign(unknown, digest, opts)
    assert message =~ "No Signer available"
  end

  test "eth_signTransaction recovers the node account that signed it", %{opts: opts, accounts: accounts} do
    from = hd(accounts)
    recipient = Enum.at(accounts, 1, <<0::160>>)
    call = Call.new(recipient, <<>>, value: 0)

    assert {:ok, signed} = Cartouche.RPC.sign_transaction(call, Keyword.put(opts, :from, from))
    signer = recover_signer!(signed, opts)
    assert signer == from
  end

  test "eth_sendTransaction returns a hash whose recovered signer is the node account", %{
    opts: opts,
    accounts: accounts
  } do
    from = hd(accounts)
    recipient = Enum.at(accounts, 1, @anvil_account)
    call = Call.new(recipient, <<>>, value: 1)

    assert {:ok, hash} = Cartouche.RPC.send_transaction(call, Keyword.put(opts, :from, from))
    assert byte_size(hash) == 32

    assert {:ok, params} =
             Cartouche.RPC.send_rpc("eth_getTransactionByHash", [Cartouche.Hex.encode_hex(hash)], opts)

    signed =
      case params["type"] do
        type when type in [nil, "0x0"] -> V1.from_json(params)
        "0x2" -> V2.from_json(params)
        other -> flunk("unexpected sent envelope type: #{inspect(other)}")
      end

    assert recover_signer!(signed, opts) == from
  end

  test "eth_signTransaction preserves a V2 access list and envelope type", %{opts: opts, accounts: accounts} do
    from = hd(accounts)
    recipient = Enum.at(accounts, 1, @anvil_account)
    access_list = [{@weth9, [<<0::256>>, <<1::256>>]}]
    {:ok, chain_id} = Cartouche.RPC.eth_chain_id(opts)
    {:ok, nonce} = Cartouche.RPC.get_nonce(from, opts)

    trx =
      V2.new(
        nonce,
        {1, :gwei},
        {100, :gwei},
        100_000,
        recipient,
        0,
        <<>>,
        access_list,
        nil,
        nil,
        nil,
        chain_id
      )

    assert {:ok, signed} = Cartouche.RPC.sign_transaction(trx, Keyword.put(opts, :from, from))

    # The node signs what it was handed. If `accessList` or `type` never reach
    # it, this comes back as a legacy envelope with the access list dropped —
    # silently signing something other than what the caller built.
    assert %V2{} = signed
    assert signed.access_list == access_list
    assert recover_signer!(signed, opts) == from
  end

  @spec recover_signer!(struct(), Keyword.t()) :: <<_::160>>
  defp recover_signer!(trx, opts) do
    case trx do
      %V1{} = signed ->
        {:ok, chain_id} = Cartouche.RPC.eth_chain_id(opts)
        assert {:ok, signer} = V1.recover_signer(signed, chain_id)
        signer

      %V2{} = signed ->
        assert {:ok, signer} = V2.recover_signer(signed)
        signer

      other ->
        flunk("unexpected signed envelope: #{inspect(other)}")
    end
  end
end
