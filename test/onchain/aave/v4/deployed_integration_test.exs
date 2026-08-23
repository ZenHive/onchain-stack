defmodule Onchain.Aave.V4.DeployedIntegrationTest do
  @moduledoc """
  Independent evidence for the deployed Ethereum Aave V4 wrappers.

  Evidence is pinned to mainnet block `25_800_000` and these deployments:

  - Core Hub: `0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9`
  - Main Spoke: `0x94e7A5dCbE816e498b89aB752661904E2F56c485`
  - Main Spoke Oracle: `0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127`
  - Core WETH Tokenization Spoke: `0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b`
  - Giver/Taker Position Managers: `0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e` /
    `0x6c044c0D3801499bCAbfAd458B70880bc518e9F7`

  At that block, Main Spoke WETH supply and debt equal the Core Hub's
  per-Spoke accounting; the Tokenization Spoke's ERC-4626 totals and previews
  equal its Hub position. On a fork, supplying 10 WETH returns 10 WETH while
  the user view rounds down by one wei, borrowing 1 WETH creates one extra wei
  of debt from share rounding, and Giver repayment clears that debt. Before
  approval, the deployed Taker returns
  `InsufficientBorrowAllowance(0, 1_000_000_000_000_000_000)`.

  The exercised contracts are specified by Aave's `IHub`, `ISpoke`,
  `ITokenizationSpoke`, `GiverPositionManager`, and `TakerPositionManager`
  sources in `https://github.com/aave/aave-v4`.
  """

  use ExUnit.Case, async: false

  alias Cartouche.Transaction
  alias Cartouche.Transaction.V2
  alias Onchain.Aave.V4.Hub
  alias Onchain.Aave.V4.Oracle
  alias Onchain.Aave.V4.PositionManager
  alias Onchain.Aave.V4.Spoke
  alias Onchain.Aave.V4.TokenizationSpoke
  alias Onchain.ABI
  alias Onchain.EVM
  alias Onchain.Hex
  alias Onchain.RPCCase
  alias Onchain.RPCStub
  alias Onchain.Signer

  @moduletag :integration

  @integration_timeout_ms 240_000
  @moduletag timeout: @integration_timeout_ms

  @evidence_block 25_800_000
  @core_hub "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9"
  @main_spoke "0x94e7A5dCbE816e498b89aB752661904E2F56c485"
  @main_oracle "0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127"
  @core_weth_tokenization_spoke "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b"
  @giver "0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e"
  @taker "0x6c044c0D3801499bCAbfAd458B70880bc518e9F7"
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @weth_asset_id 0
  @weth_reserve_id 0
  @weth_decimals 18
  @oracle_decimals 8

  @core_asset_count 17
  @main_reserve_count 14
  @main_weth_added_assets 27_816_667_934_774_842_012_649
  @main_weth_added_shares 27_635_684_347_560_361_070_605
  @main_weth_drawn_debt 208_315_159_723_629_616_941
  @main_weth_premium_debt 0
  @main_weth_price 234_285_133_654
  @tokenized_weth_assets 29_412_573_158_345_796
  @tokenized_weth_shares 29_221_206_132_939_025
  @preview_amount 1_000_000_000_000_000_000
  @preview_add_shares 993_493_699_977_335_337
  @preview_add_assets 1_006_548_909_190_680_416
  @min_underlying_decimals 6
  @max_underlying_decimals 18
  @max_spoke_cap 1_099_511_627_775
  @max_risk_premium_threshold 16_777_215

  @fork_private_key "0x0000000000000000000000000000000000000000000000000000000000000052"
  @fork_user "0x752481f35bB1D44d786c7B4dbe40dB4a4266f96f"
  @supply_amount 10_000_000_000_000_000_000
  @borrow_amount 1_000_000_000_000_000_000
  @repay_amount 2_000_000_000_000_000_000
  @rounding_delta_wei 1
  @fork_weth_balance @supply_amount + @borrow_amount
  @fork_eth_balance_wei 100_000_000_000_000_000_000
  @fork_gas_limit 5_000_000
  @fork_rpc_timeout_ms 30_000
  @weth_balance_slot 3
  @test_tx_hash "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "pinned Hub, Spoke, Oracle, and TokenizationSpoke reads agree on WETH accounting" do
    opts = live_opts!()

    assert {:ok, @core_hub} = Hub.hub_address(:core)
    assert {:ok, @core_weth_tokenization_spoke} = TokenizationSpoke.lookup(:core, :weth)
    assert {:ok, @weth_asset_id} = Hub.get_asset_id(:core, @weth, opts)

    assert {:ok, @weth_reserve_id} =
             Spoke.get_reserve_id(@main_spoke, @core_hub, @weth_asset_id, opts)

    assert {:ok, @core_asset_count} = Hub.get_asset_count(:core, opts)
    assert {:ok, @main_reserve_count} = Spoke.get_reserve_count(@main_spoke, opts)

    assert {:ok, asset} = Hub.get_asset(:core, @weth_asset_id, opts)
    assert asset.underlying == @weth
    assert asset.decimals == @weth_decimals

    assert {:ok, reserve} = Spoke.get_reserve(@main_spoke, @weth_reserve_id, opts)
    assert reserve.underlying == @weth
    assert reserve.hub == @core_hub
    assert reserve.asset_id == @weth_asset_id
    assert reserve.decimals == @weth_decimals
    assert reserve.borrowable

    assert {:ok, @main_weth_added_assets} =
             Hub.get_spoke_added_assets(:core, @weth_asset_id, @main_spoke, opts)

    assert {:ok, @main_weth_added_assets} =
             Spoke.get_reserve_supplied_assets(@main_spoke, @weth_reserve_id, opts)

    assert {:ok, @main_weth_added_shares} =
             Hub.get_spoke_added_shares(:core, @weth_asset_id, @main_spoke, opts)

    assert {:ok, @main_weth_added_shares} =
             Spoke.get_reserve_supplied_shares(@main_spoke, @weth_reserve_id, opts)

    assert {:ok, {@main_weth_drawn_debt, @main_weth_premium_debt}} =
             Hub.get_spoke_owed(:core, @weth_asset_id, @main_spoke, opts)

    assert {:ok, {@main_weth_drawn_debt, @main_weth_premium_debt}} =
             Spoke.get_reserve_debt(@main_spoke, @weth_reserve_id, opts)

    assert {:ok, @main_oracle} = Oracle.oracle_address(@main_spoke, opts)
    assert {:ok, @main_spoke} = Oracle.get_spoke(@main_spoke, opts)
    assert {:ok, @oracle_decimals} = Oracle.decimals(@main_spoke, opts)
    assert {:ok, @main_weth_price} = Oracle.get_reserve_price(@main_spoke, @weth_reserve_id, opts)

    assert {:ok, @weth} = TokenizationSpoke.asset(@core_weth_tokenization_spoke, opts)
    assert {:ok, @core_hub} = TokenizationSpoke.hub(@core_weth_tokenization_spoke, opts)
    assert {:ok, @weth_asset_id} = TokenizationSpoke.asset_id(@core_weth_tokenization_spoke, opts)

    assert {:ok, @tokenized_weth_assets} =
             TokenizationSpoke.total_assets(@core_weth_tokenization_spoke, opts)

    assert {:ok, @tokenized_weth_shares} =
             TokenizationSpoke.total_supply(@core_weth_tokenization_spoke, opts)

    assert {:ok, @tokenized_weth_assets} =
             Hub.get_spoke_added_assets(
               :core,
               @weth_asset_id,
               @core_weth_tokenization_spoke,
               opts
             )

    assert {:ok, @tokenized_weth_shares} =
             Hub.get_spoke_added_shares(
               :core,
               @weth_asset_id,
               @core_weth_tokenization_spoke,
               opts
             )

    assert {:ok, @preview_add_shares} =
             TokenizationSpoke.preview_deposit(
               @core_weth_tokenization_spoke,
               @preview_amount,
               opts
             )

    assert {:ok, @preview_add_shares} =
             Hub.preview_add_by_assets(:core, @weth_asset_id, @preview_amount, opts)

    assert {:ok, @preview_add_assets} =
             TokenizationSpoke.preview_mint(@core_weth_tokenization_spoke, @preview_amount, opts)

    assert {:ok, @preview_add_assets} =
             Hub.preview_add_by_shares(:core, @weth_asset_id, @preview_amount, opts)

    assert {:ok, @min_underlying_decimals} = Hub.min_allowed_underlying_decimals(:core, opts)
    assert {:ok, @max_underlying_decimals} = Hub.max_allowed_underlying_decimals(:core, opts)
    assert {:ok, @max_spoke_cap} = Hub.max_allowed_spoke_cap(:core, opts)
    assert {:ok, @max_risk_premium_threshold} = Hub.max_risk_premium_threshold(:core, opts)
  end

  test "signed PositionManager wrappers enforce Taker allowance and mutate Hub/Spoke accounting on a fork" do
    rpc_url = RPCCase.rpc_url!()
    live_opts = [block: @evidence_block, rpc_url: rpc_url]

    assert Signer.address_from_key!(@fork_private_key) == @fork_user

    assert {:ok, 0} =
             Spoke.get_user_supplied_assets(@main_spoke, @weth_reserve_id, @fork_user, live_opts)

    assert {:ok, 0} =
             Spoke.get_user_total_debt(@main_spoke, @weth_reserve_id, @fork_user, live_opts)

    assert {:ok, 0} =
             PositionManager.borrow_allowance(
               @main_spoke,
               @weth_reserve_id,
               @fork_user,
               @fork_user,
               live_opts
             )

    assert {:ok, base_supplied} =
             Spoke.get_reserve_supplied_assets(@main_spoke, @weth_reserve_id, live_opts)

    assert {:ok, base_added} =
             Hub.get_spoke_added_assets(:core, @weth_asset_id, @main_spoke, live_opts)

    assert {:ok, base_debt} =
             Spoke.get_reserve_total_debt(@main_spoke, @weth_reserve_id, live_opts)

    assert {:ok, base_owed} =
             Hub.get_spoke_total_owed(:core, @weth_asset_id, @main_spoke, live_opts)

    assert base_supplied == base_added
    assert base_debt == base_owed

    [supply_call, approve_borrow_call, borrow_call, repay_call] = signed_position_manager_calls()
    assert_destination(supply_call, @giver)
    assert_destination(approve_borrow_call, @taker)
    assert_destination(borrow_call, @taker)
    assert_destination(repay_call, @giver)

    fork_opts = fork_opts(rpc_url)
    {borrow_to, borrow_data} = borrow_call

    assert {:ok, unauthorized} = EVM.simulate_transaction(borrow_to, borrow_data, fork_opts)
    refute unauthorized.success

    assert {:error, {:insufficient_borrow_allowance, 0, @borrow_amount}} =
             PositionManager.decode_revert(unauthorized.output)

    calls =
      [
        encoded_call(@weth, "approve(address,uint256)", [
          address_bin(@giver),
          @supply_amount + @repay_amount
        ]),
        encoded_call(@main_spoke, "setUserPositionManager(address,bool)", [
          address_bin(@giver),
          true
        ]),
        supply_call,
        encoded_call(@main_spoke, "setUsingAsCollateral(uint256,bool,address)", [
          @weth_reserve_id,
          true,
          address_bin(@fork_user)
        ]),
        encoded_call(@main_spoke, "getUserSuppliedAssets(uint256,address)", [
          @weth_reserve_id,
          address_bin(@fork_user)
        ]),
        encoded_call(@main_spoke, "getReserveSuppliedAssets(uint256)", [@weth_reserve_id]),
        encoded_call(@core_hub, "getSpokeAddedAssets(uint256,address)", [
          @weth_asset_id,
          address_bin(@main_spoke)
        ]),
        encoded_call(@main_spoke, "setUserPositionManager(address,bool)", [
          address_bin(@taker),
          true
        ]),
        approve_borrow_call,
        encoded_call(
          @taker,
          "borrowAllowance(address,uint256,address,address)",
          allowance_args()
        ),
        borrow_call,
        encoded_call(
          @taker,
          "borrowAllowance(address,uint256,address,address)",
          allowance_args()
        ),
        encoded_call(@main_spoke, "getUserTotalDebt(uint256,address)", [
          @weth_reserve_id,
          address_bin(@fork_user)
        ]),
        encoded_call(@main_spoke, "getReserveTotalDebt(uint256)", [@weth_reserve_id]),
        encoded_call(@core_hub, "getSpokeTotalOwed(uint256,address)", [
          @weth_asset_id,
          address_bin(@main_spoke)
        ]),
        repay_call,
        encoded_call(@main_spoke, "getUserTotalDebt(uint256,address)", [
          @weth_reserve_id,
          address_bin(@fork_user)
        ]),
        encoded_call(@main_spoke, "getReserveTotalDebt(uint256)", [@weth_reserve_id]),
        encoded_call(@core_hub, "getSpokeTotalOwed(uint256,address)", [
          @weth_asset_id,
          address_bin(@main_spoke)
        ]),
        encoded_call(@main_spoke, "getUserSuppliedAssets(uint256,address)", [
          @weth_reserve_id,
          address_bin(@fork_user)
        ])
      ]

    assert {:ok, results} = EVM.simulate_batch(calls, fork_opts)

    Enum.with_index(results, fn result, index ->
      assert result.success, "fork call #{index} reverted with #{result.output}"
    end)

    [
      _token_approval,
      _giver_approval,
      supply_result,
      _collateral_enablement,
      supplied_result,
      reserve_supplied_result,
      hub_added_result,
      _taker_approval,
      _borrow_approval,
      allowance_before_result,
      borrow_result,
      allowance_after_result,
      user_debt_result,
      reserve_debt_result,
      hub_owed_result,
      repay_result,
      final_user_debt_result,
      final_reserve_debt_result,
      final_hub_owed_result,
      final_supplied_result
    ] = results

    {supplied_shares, supplied_amount} = decode_pair!(supply_result)
    supplied_assets = decode_uint!(supplied_result)
    reserve_supplied = decode_uint!(reserve_supplied_result)
    hub_added = decode_uint!(hub_added_result)

    assert supplied_shares > 0
    assert supplied_amount == @supply_amount
    assert supplied_assets == supplied_amount - @rounding_delta_wei
    assert reserve_supplied == base_supplied + supplied_amount
    assert hub_added == base_added + supplied_amount
    assert reserve_supplied == hub_added

    assert decode_uint!(allowance_before_result) == @borrow_amount

    {borrowed_shares, borrowed_amount} = decode_pair!(borrow_result)
    user_debt = decode_uint!(user_debt_result)
    reserve_debt = decode_uint!(reserve_debt_result)
    hub_owed = decode_uint!(hub_owed_result)

    assert borrowed_shares > 0
    assert borrowed_amount == @borrow_amount
    assert decode_uint!(allowance_after_result) == 0
    assert user_debt == borrowed_amount + @rounding_delta_wei
    assert reserve_debt == base_debt + user_debt
    assert hub_owed == base_owed + user_debt
    assert reserve_debt == hub_owed

    {repaid_shares, repaid_amount} = decode_pair!(repay_result)
    assert repaid_shares == borrowed_shares
    assert repaid_amount == user_debt
    assert decode_uint!(final_user_debt_result) == 0
    assert decode_uint!(final_reserve_debt_result) == base_debt
    assert decode_uint!(final_hub_owed_result) == base_owed
    assert decode_uint!(final_supplied_result) == supplied_assets
  end

  @spec live_opts!() :: keyword()
  defp live_opts!, do: [block: @evidence_block] ++ RPCCase.rpc_opts!()

  @spec signed_position_manager_calls() :: [{String.t(), String.t()}]
  defp signed_position_manager_calls do
    seen = start_supervised!({Agent, fn -> [] end})
    url = RPCStub.start(RPCStub.send_tx_handler(@test_tx_hash, seen))
    write_opts = RPCStub.write_opts(url, private_key: @fork_private_key)

    actions = [
      &PositionManager.supply(@main_spoke, @weth_reserve_id, @supply_amount, @fork_user, &1),
      &PositionManager.approve_borrow(
        @main_spoke,
        @weth_reserve_id,
        @fork_user,
        @borrow_amount,
        &1
      ),
      &PositionManager.borrow(@main_spoke, @weth_reserve_id, @borrow_amount, @fork_user, &1),
      &PositionManager.repay(@main_spoke, @weth_reserve_id, @repay_amount, @fork_user, &1)
    ]

    actions
    |> Enum.with_index()
    |> Enum.each(fn {action, nonce} ->
      assert {:ok, @test_tx_hash} = action.(Keyword.put(write_opts, :nonce, nonce))
    end)

    seen
    |> Agent.get(&Enum.reverse/1)
    |> Enum.map(&decode_signed_call!/1)
  end

  @spec decode_signed_call!(String.t()) :: {String.t(), String.t()}
  defp decode_signed_call!(raw) do
    assert {:ok, %V2{destination: destination, data: data}} =
             raw
             |> Hex.decode!()
             |> Transaction.decode()

    {Hex.encode(destination), Hex.encode(data)}
  end

  @spec assert_destination({String.t(), String.t()}, String.t()) :: true
  defp assert_destination({destination, _data}, expected) do
    assert String.downcase(destination) == String.downcase(expected)
  end

  @spec fork_opts(String.t()) :: keyword()
  defp fork_opts(rpc_url) do
    balance_slot =
      (<<0::96>> <> address_bin(@fork_user) <> <<@weth_balance_slot::256>>)
      |> Cartouche.Hash.keccak()
      |> Hex.encode()

    [
      rpc_url: rpc_url,
      block: @evidence_block,
      from: @fork_user,
      gas_limit: @fork_gas_limit,
      timeout_ms: @fork_rpc_timeout_ms,
      state_overrides: %{
        @fork_user => %{"balance" => hex_quantity(@fork_eth_balance_wei)},
        @weth => %{
          "storage" => Jason.encode!(%{balance_slot => hex_quantity(@fork_weth_balance)})
        }
      }
    ]
  end

  @spec allowance_args() :: [term()]
  defp allowance_args do
    [address_bin(@main_spoke), @weth_reserve_id, address_bin(@fork_user), address_bin(@fork_user)]
  end

  @spec encoded_call(String.t(), String.t(), [term()]) :: {String.t(), String.t()}
  defp encoded_call(address, signature, args) do
    assert {:ok, data} = ABI.encode_call(signature, args)
    {address, data}
  end

  @spec decode_uint!(EVM.tx_result()) :: non_neg_integer()
  defp decode_uint!(%{output: output}) do
    assert {:ok, [value]} = ABI.decode_types("(uint256)", output)
    value
  end

  @spec decode_pair!(EVM.tx_result()) :: {non_neg_integer(), non_neg_integer()}
  defp decode_pair!(%{output: output}) do
    assert {:ok, [first, second]} = ABI.decode_types("(uint256,uint256)", output)
    {first, second}
  end

  @spec address_bin(String.t()) :: binary()
  defp address_bin(address), do: Hex.decode!(address)

  @spec hex_quantity(non_neg_integer()) :: String.t()
  defp hex_quantity(value), do: "0x" <> Integer.to_string(value, 16)
end
