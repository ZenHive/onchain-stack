defmodule Onchain.Aave.V4.TokenizationSpokeTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.TokenizationSpoke
  alias Onchain.RPCStub

  @owner "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @assets 1_100
  @shares 1_000
  @total_assets 50_000
  @total_supply 45_000
  @balance 250
  @max_amount 1_000_000
  @asset_id 3
  @spoke_cap 1_099_511_627_775
  @permit_ns 42
  @deposit_hash <<1::256>>
  @mint_hash <<2::256>>
  @withdraw_hash <<3::256>>
  @redeem_hash <<4::256>>
  @permit_hash <<5::256>>
  @domain_hash <<6::256>>

  describe "lookup/3" do
    test "resolves configured Tokenization Spokes across Core, Prime, and Plus" do
      assert TokenizationSpoke.lookup(:core, :weth) == Contracts.v4_tokenization_spoke(:core, :weth)
      assert TokenizationSpoke.lookup(:prime, :gho) == Contracts.v4_tokenization_spoke(:prime, :gho)
      assert TokenizationSpoke.lookup(:plus, :pt_susde) == Contracts.v4_tokenization_spoke(:plus, :pt_susde)
    end

    test "same asset on different Hubs resolves to distinct addresses" do
      {:ok, core_usdc} = TokenizationSpoke.lookup(:core, :usdc)
      {:ok, prime_usdc} = TokenizationSpoke.lookup(:prime, :usdc)
      {:ok, plus_usdc} = TokenizationSpoke.lookup(:plus, :usdc)

      assert [_, _, _] = Enum.uniq([core_usdc, prime_usdc, plus_usdc])
    end

    test "every registered Tokenization Spoke is a valid checksummed address" do
      Enum.each([:core, :prime, :plus], fn hub ->
        Enum.each(tokenization_assets(hub), fn asset ->
          assert {:ok, addr} = TokenizationSpoke.lookup(hub, asset),
                 "expected lookup(#{inspect(hub)}, #{inspect(asset)}) to succeed"

          assert {:ok, _} = Onchain.Address.validate(addr)
          assert addr == Onchain.Address.checksum!(addr)
        end)
      end)
    end

    test "returns unknown_hub for an unconfigured hub atom" do
      assert {:error, {:unknown_hub, :bogus}} = TokenizationSpoke.lookup(:bogus, :weth)
    end

    test "returns unknown_tokenization_spoke for an unconfigured asset" do
      assert {:error, {:unknown_tokenization_spoke, {:core, :bogus}}} =
               TokenizationSpoke.lookup(:core, :bogus)
    end

    test "asset present in one hub but absent in another returns unknown_tokenization_spoke" do
      assert {:ok, _} = TokenizationSpoke.lookup(:core, :aave)

      assert {:error, {:unknown_tokenization_spoke, {:prime, :aave}}} =
               TokenizationSpoke.lookup(:prime, :aave)
    end

    test "returns unsupported_network on a V3-only network" do
      assert {:error, {:unsupported_network, :arbitrum}} =
               TokenizationSpoke.lookup(:core, :weth, network: :arbitrum)
    end
  end

  describe "input validation" do
    test "reads reject an invalid spoke address before RPC" do
      Enum.each(
        [
          &TokenizationSpoke.asset/1,
          &TokenizationSpoke.total_assets/1,
          &TokenizationSpoke.total_supply/1,
          &TokenizationSpoke.hub/1,
          &TokenizationSpoke.asset_id/1,
          &TokenizationSpoke.max_allowed_spoke_cap/1,
          &TokenizationSpoke.permit_nonce_namespace/1,
          &TokenizationSpoke.deposit_typehash/1,
          &TokenizationSpoke.mint_typehash/1,
          &TokenizationSpoke.withdraw_typehash/1,
          &TokenizationSpoke.redeem_typehash/1,
          &TokenizationSpoke.permit_typehash/1,
          &TokenizationSpoke.domain_separator/1
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "amount-taking reads reject an invalid spoke address before RPC" do
      Enum.each(
        [
          &TokenizationSpoke.convert_to_shares(&1, @assets),
          &TokenizationSpoke.convert_to_assets(&1, @shares),
          &TokenizationSpoke.preview_deposit(&1, @assets),
          &TokenizationSpoke.preview_mint(&1, @shares),
          &TokenizationSpoke.preview_withdraw(&1, @assets),
          &TokenizationSpoke.preview_redeem(&1, @shares)
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "account-taking reads reject an invalid owner/receiver before RPC" do
      {:ok, spoke} = TokenizationSpoke.lookup(:core, :weth)

      Enum.each(
        [
          &TokenizationSpoke.balance_of(spoke, &1),
          &TokenizationSpoke.max_deposit(spoke, &1),
          &TokenizationSpoke.max_mint(spoke, &1),
          &TokenizationSpoke.max_withdraw(spoke, &1),
          &TokenizationSpoke.max_redeem(spoke, &1)
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "account-taking reads reject an invalid spoke when the account is valid" do
      assert {:error, {:invalid_address, "bad"}} = TokenizationSpoke.balance_of("bad", @owner)
    end
  end

  describe "ERC-4626 accounting and V4 metadata reads" do
    setup do
      {:ok, spoke} = TokenizationSpoke.lookup(:core, :weth)
      {:ok, usdc} = TokenizationSpoke.lookup(:core, :usdc)
      {:ok, prime} = TokenizationSpoke.lookup(:prime, :weth)
      payloads = calldata_payloads()
      seen = start_supervised!({Agent, fn -> [] end})
      url = RPCStub.start(fn body -> handle_eth_call(body, payloads, seen) end)

      %{spoke: spoke, usdc: usdc, prime: prime, rpc_opts: RPCStub.rpc_opts(url), seen: seen}
    end

    test "ERC-4626 accounting reads decode from a configured Tokenization Spoke", %{
      spoke: spoke,
      rpc_opts: rpc_opts
    } do
      {:ok, weth_underlying} = Onchain.Address.validate("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
      expected_asset = Onchain.Address.checksum!(weth_underlying)

      assert {:ok, ^expected_asset} = TokenizationSpoke.asset(spoke, rpc_opts)
      assert {:ok, @total_assets} = TokenizationSpoke.total_assets(spoke, rpc_opts)
      assert {:ok, @total_supply} = TokenizationSpoke.total_supply(spoke, rpc_opts)
      assert {:ok, @balance} = TokenizationSpoke.balance_of(spoke, @owner, rpc_opts)
      assert {:ok, @shares} = TokenizationSpoke.convert_to_shares(spoke, @assets, rpc_opts)
      assert {:ok, @assets} = TokenizationSpoke.convert_to_assets(spoke, @shares, rpc_opts)
      assert {:ok, @shares} = TokenizationSpoke.preview_deposit(spoke, @assets, rpc_opts)
      assert {:ok, @assets} = TokenizationSpoke.preview_mint(spoke, @shares, rpc_opts)
      assert {:ok, @shares} = TokenizationSpoke.preview_withdraw(spoke, @assets, rpc_opts)
      assert {:ok, @assets} = TokenizationSpoke.preview_redeem(spoke, @shares, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_deposit(spoke, @owner, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_mint(spoke, @owner, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_withdraw(spoke, @owner, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_redeem(spoke, @owner, rpc_opts)
    end

    test "amount reads accept and forward the zero boundary", %{spoke: spoke, rpc_opts: rpc_opts} do
      assert {:ok, 0} = TokenizationSpoke.convert_to_shares(spoke, 0, rpc_opts)
      assert {:ok, 0} = TokenizationSpoke.convert_to_assets(spoke, 0, rpc_opts)
      assert {:ok, 0} = TokenizationSpoke.preview_deposit(spoke, 0, rpc_opts)
      assert {:ok, 0} = TokenizationSpoke.preview_mint(spoke, 0, rpc_opts)
      assert {:ok, 0} = TokenizationSpoke.preview_withdraw(spoke, 0, rpc_opts)
      assert {:ok, 0} = TokenizationSpoke.preview_redeem(spoke, 0, rpc_opts)
    end

    test "V4-specific metadata reads decode from a configured Tokenization Spoke", %{
      spoke: spoke,
      rpc_opts: rpc_opts
    } do
      {:ok, hub_addr} = Contracts.address(:v4_core_hub)

      assert {:ok, ^hub_addr} = TokenizationSpoke.hub(spoke, rpc_opts)
      assert {:ok, @asset_id} = TokenizationSpoke.asset_id(spoke, rpc_opts)
      assert {:ok, @spoke_cap} = TokenizationSpoke.max_allowed_spoke_cap(spoke, rpc_opts)
      assert {:ok, @permit_ns} = TokenizationSpoke.permit_nonce_namespace(spoke, rpc_opts)

      assert {:ok, deposit} = TokenizationSpoke.deposit_typehash(spoke, rpc_opts)
      assert {:ok, mint} = TokenizationSpoke.mint_typehash(spoke, rpc_opts)
      assert {:ok, withdraw} = TokenizationSpoke.withdraw_typehash(spoke, rpc_opts)
      assert {:ok, redeem} = TokenizationSpoke.redeem_typehash(spoke, rpc_opts)
      assert {:ok, permit} = TokenizationSpoke.permit_typehash(spoke, rpc_opts)
      assert {:ok, domain} = TokenizationSpoke.domain_separator(spoke, rpc_opts)

      assert deposit == Onchain.Hex.encode(@deposit_hash)
      assert mint == Onchain.Hex.encode(@mint_hash)
      assert withdraw == Onchain.Hex.encode(@withdraw_hash)
      assert redeem == Onchain.Hex.encode(@redeem_hash)
      assert permit == Onchain.Hex.encode(@permit_hash)
      assert domain == Onchain.Hex.encode(@domain_hash)
    end

    test "lookup address is the eth_call target for configured spokes", %{
      spoke: core_weth,
      usdc: core_usdc,
      prime: prime_weth,
      rpc_opts: rpc_opts,
      seen: seen
    } do
      assert {:ok, _} = TokenizationSpoke.total_assets(core_weth, rpc_opts)
      assert {:ok, _} = TokenizationSpoke.total_assets(core_usdc, rpc_opts)
      assert {:ok, _} = TokenizationSpoke.total_assets(prime_weth, rpc_opts)

      seen_tos =
        seen
        |> Agent.get(& &1)
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()
        |> Enum.sort()

      expected =
        [core_weth, core_usdc, prime_weth]
        |> Enum.map(&String.downcase/1)
        |> Enum.sort()

      assert seen_tos == expected
    end
  end

  defp tokenization_assets(:core),
    do: ~w(aave cbbtc eurc frxusd gho lbtc link rlusd rseth usdc usdg usdt wbtc weeth weth wsteth xaut)a

  defp tokenization_assets(:prime), do: ~w(cbbtc gho usdc usdt wbtc weth wsteth)a
  defp tokenization_assets(:plus), do: ~w(gho pt_susde pt_usde susde usdc usde usdt)a

  defp calldata_payloads do
    {:ok, owner_bin} = Onchain.Address.validate(@owner)
    {:ok, weth_bin} = Onchain.Address.validate("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
    {:ok, hub_bin} = Onchain.Address.validate(Contracts.address!(:v4_core_hub))

    %{
      calldata("asset()", []) => RPCStub.encode("(address)", [{weth_bin}]),
      calldata("totalAssets()", []) => RPCStub.encode("(uint256)", [{@total_assets}]),
      calldata("totalSupply()", []) => RPCStub.encode("(uint256)", [{@total_supply}]),
      calldata("balanceOf(address)", [owner_bin]) => RPCStub.encode("(uint256)", [{@balance}]),
      calldata("convertToShares(uint256)", [@assets]) => RPCStub.encode("(uint256)", [{@shares}]),
      calldata("convertToAssets(uint256)", [@shares]) => RPCStub.encode("(uint256)", [{@assets}]),
      calldata("previewDeposit(uint256)", [@assets]) => RPCStub.encode("(uint256)", [{@shares}]),
      calldata("previewMint(uint256)", [@shares]) => RPCStub.encode("(uint256)", [{@assets}]),
      calldata("previewWithdraw(uint256)", [@assets]) => RPCStub.encode("(uint256)", [{@shares}]),
      calldata("previewRedeem(uint256)", [@shares]) => RPCStub.encode("(uint256)", [{@assets}]),
      calldata("convertToShares(uint256)", [0]) => RPCStub.encode("(uint256)", [{0}]),
      calldata("convertToAssets(uint256)", [0]) => RPCStub.encode("(uint256)", [{0}]),
      calldata("previewDeposit(uint256)", [0]) => RPCStub.encode("(uint256)", [{0}]),
      calldata("previewMint(uint256)", [0]) => RPCStub.encode("(uint256)", [{0}]),
      calldata("previewWithdraw(uint256)", [0]) => RPCStub.encode("(uint256)", [{0}]),
      calldata("previewRedeem(uint256)", [0]) => RPCStub.encode("(uint256)", [{0}]),
      calldata("maxDeposit(address)", [owner_bin]) => RPCStub.encode("(uint256)", [{@max_amount}]),
      calldata("maxMint(address)", [owner_bin]) => RPCStub.encode("(uint256)", [{@max_amount}]),
      calldata("maxWithdraw(address)", [owner_bin]) => RPCStub.encode("(uint256)", [{@max_amount}]),
      calldata("maxRedeem(address)", [owner_bin]) => RPCStub.encode("(uint256)", [{@max_amount}]),
      calldata("hub()", []) => RPCStub.encode("(address)", [{hub_bin}]),
      calldata("assetId()", []) => RPCStub.encode("(uint256)", [{@asset_id}]),
      calldata("MAX_ALLOWED_SPOKE_CAP()", []) => RPCStub.encode("(uint256)", [{@spoke_cap}]),
      calldata("PERMIT_NONCE_NAMESPACE()", []) => RPCStub.encode("(uint256)", [{@permit_ns}]),
      calldata("DEPOSIT_TYPEHASH()", []) => RPCStub.encode("(bytes32)", [{@deposit_hash}]),
      calldata("MINT_TYPEHASH()", []) => RPCStub.encode("(bytes32)", [{@mint_hash}]),
      calldata("WITHDRAW_TYPEHASH()", []) => RPCStub.encode("(bytes32)", [{@withdraw_hash}]),
      calldata("REDEEM_TYPEHASH()", []) => RPCStub.encode("(bytes32)", [{@redeem_hash}]),
      calldata("PERMIT_TYPEHASH()", []) => RPCStub.encode("(bytes32)", [{@permit_hash}]),
      calldata("DOMAIN_SEPARATOR()", []) => RPCStub.encode("(bytes32)", [{@domain_hash}])
    }
  end

  defp calldata(signature, params) do
    {:ok, hex} = Onchain.ABI.encode_call(signature, params)
    String.downcase(hex)
  end

  defp handle_eth_call(%{"method" => "eth_call", "params" => [%{"data" => data, "to" => to} | _]}, payloads, seen) do
    Agent.update(seen, &[to | &1])
    calldata = String.downcase(data)

    Map.get_lazy(payloads, calldata, fn ->
      flunk("stub has no payload for calldata #{data}")
    end)
  end
end
