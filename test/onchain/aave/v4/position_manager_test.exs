defmodule Onchain.Aave.V4.PositionManagerTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.PositionManager
  alias Onchain.Address
  alias Onchain.RPCStub
  alias Onchain.Signer

  @spoke "0x94e7A5dCbE816e498b89aB752661904E2F56c485"
  @owner "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @spender "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"
  @reserve_id 4
  @amount 1_000_000
  @allowance 10
  @required 99

  @signer_key "0x" <> String.duplicate("11", 32)
  @giver :v4_giver_position_manager
  @taker :v4_taker_position_manager

  @supply_selector <<0xFD, 0xF3, 0xCA, 0x71>>
  @repay_selector <<0x11, 0x5F, 0x67, 0xA9>>
  @borrow_selector <<0x22, 0x7E, 0x1D, 0xF4>>
  @withdraw_selector <<0x0A, 0x25, 0x0C, 0x6D>>
  @approve_borrow_selector <<0x3C, 0x4A, 0xF0, 0x4F>>
  @approve_withdraw_selector <<0xFF, 0xF5, 0x9F, 0x09>>
  @renounce_borrow_selector <<0x5A, 0x4B, 0x72, 0xBC>>
  @renounce_withdraw_selector <<0xEA, 0xB0, 0x73, 0xE3>>

  describe "input validation" do
    test "on-behalf-of writes reject an invalid spoke before RPC" do
      Enum.each(on_behalf_of_writes(), fn fun ->
        assert {:error, {:invalid_address, "bad"}} = fun.("bad", @reserve_id, @amount, @owner, [])
      end)
    end

    test "on-behalf-of writes reject an invalid owner before RPC" do
      Enum.each(on_behalf_of_writes(), fn fun ->
        assert {:error, {:invalid_address, "bad_obo"}} = fun.(@spoke, @reserve_id, @amount, "bad_obo", [])
      end)
    end

    test "amount-taking writes reject a negative or non-integer amount before RPC" do
      Enum.each(amount_writes(), fn fun ->
        assert {:error, {:invalid_amount, -1}} = fun.(@spoke, @reserve_id, -1, @owner, [])
        assert {:error, {:invalid_amount, 1.5}} = fun.(@spoke, @reserve_id, 1.5, @owner, [])
        assert {:error, {:invalid_amount, "100"}} = fun.(@spoke, @reserve_id, "100", @owner, [])
      end)
    end

    test "writes reject a negative or non-integer reserve id before RPC" do
      assert {:error, {:invalid_reserve_id, -1}} =
               PositionManager.supply(@spoke, -1, @amount, @owner, [])

      assert {:error, {:invalid_reserve_id, 1.0}} =
               PositionManager.borrow(@spoke, 1.0, @amount, @owner, [])
    end

    test "approve writes reject invalid spoke, spender, and amount" do
      Enum.each(
        [
          &PositionManager.approve_borrow/5,
          &PositionManager.approve_withdraw/5
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad", @reserve_id, @spender, @amount, [])
          assert {:error, {:invalid_address, "bad_spender"}} = fun.(@spoke, @reserve_id, "bad_spender", @amount, [])
          assert {:error, {:invalid_amount, -1}} = fun.(@spoke, @reserve_id, @spender, -1, [])
          assert {:error, {:invalid_amount, 0.5}} = fun.(@spoke, @reserve_id, @spender, 0.5, [])
        end
      )
    end

    test "renounce writes reject invalid spoke and owner" do
      Enum.each(
        [
          &PositionManager.renounce_borrow_allowance/4,
          &PositionManager.renounce_withdraw_allowance/4
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad", @reserve_id, @owner, [])
          assert {:error, {:invalid_address, "bad_owner"}} = fun.(@spoke, @reserve_id, "bad_owner", [])
        end
      )
    end

    test "allowance views reject invalid spoke, owner, and spender" do
      Enum.each(
        [
          &PositionManager.borrow_allowance/5,
          &PositionManager.withdraw_allowance/5
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad", @reserve_id, @owner, @spender, [])
          assert {:error, {:invalid_address, "bad_owner"}} = fun.(@spoke, @reserve_id, "bad_owner", @spender, [])
          assert {:error, {:invalid_address, "bad_spender"}} = fun.(@spoke, @reserve_id, @owner, "bad_spender", [])
        end
      )
    end

    test "allowance views accept omitted opts" do
      assert {:error, {:invalid_address, "bad"}} =
               PositionManager.borrow_allowance("bad", @reserve_id, @owner, @spender)

      assert {:error, {:invalid_address, "bad"}} =
               PositionManager.withdraw_allowance("bad", @reserve_id, @owner, @spender)
    end

    test "writes fail on an unsupported network before RPC" do
      assert {:error, {:unsupported_network, :solana}} =
               PositionManager.supply(@spoke, @reserve_id, @amount, @owner, network: :solana)
    end

    test "writes fail on a V3-only network before RPC" do
      assert {:error, {:unknown_contract, :v4_giver_position_manager}} =
               PositionManager.supply(@spoke, @reserve_id, @amount, @owner, network: :arbitrum)
    end
  end

  describe "Giver and Taker calldata" do
    test "supply encodes supplyOnBehalfOf against the Giver" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.supply(@spoke, @reserve_id, @amount, @owner, [])
        end)

      assert to == Contracts.address!(@giver)
      assert_on_behalf_of_calldata(calldata, @supply_selector, @spoke, @reserve_id, @amount, @owner)
    end

    test "repay encodes repayOnBehalfOf against the Giver" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.repay(@spoke, @reserve_id, @amount, @owner, [])
        end)

      assert to == Contracts.address!(@giver)
      assert_on_behalf_of_calldata(calldata, @repay_selector, @spoke, @reserve_id, @amount, @owner)
    end

    test "borrow encodes borrowOnBehalfOf against the Taker" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.borrow(@spoke, @reserve_id, @amount, @owner, [])
        end)

      assert to == Contracts.address!(@taker)
      assert_on_behalf_of_calldata(calldata, @borrow_selector, @spoke, @reserve_id, @amount, @owner)
    end

    test "withdraw encodes withdrawOnBehalfOf against the Taker" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.withdraw(@spoke, @reserve_id, @amount, @owner, [])
        end)

      assert to == Contracts.address!(@taker)
      assert_on_behalf_of_calldata(calldata, @withdraw_selector, @spoke, @reserve_id, @amount, @owner)
    end

    test "approveBorrow and approveWithdraw encode spender and amount against the Taker" do
      {borrow_to, borrow_data} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.approve_borrow(@spoke, @reserve_id, @spender, @amount, [])
        end)

      {withdraw_to, withdraw_data} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.approve_withdraw(@spoke, @reserve_id, @spender, 0, [])
        end)

      assert borrow_to == Contracts.address!(@taker)
      assert withdraw_to == borrow_to
      assert_approve_calldata(borrow_data, @approve_borrow_selector, @spoke, @reserve_id, @spender, @amount)
      assert_approve_calldata(withdraw_data, @approve_withdraw_selector, @spoke, @reserve_id, @spender, 0)
    end

    test "renounceBorrowAllowance and renounceWithdrawAllowance encode the owner against the Taker" do
      {borrow_to, borrow_data} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.renounce_borrow_allowance(@spoke, @reserve_id, @owner, [])
        end)

      {withdraw_to, withdraw_data} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   PositionManager.renounce_withdraw_allowance(@spoke, @reserve_id, @owner, [])
        end)

      assert borrow_to == Contracts.address!(@taker)
      assert withdraw_to == borrow_to
      assert_renounce_calldata(borrow_data, @renounce_borrow_selector, @spoke, @reserve_id, @owner)
      assert_renounce_calldata(withdraw_data, @renounce_withdraw_selector, @spoke, @reserve_id, @owner)
    end

    test "on-behalf-of selectors are distinct" do
      selectors =
        Enum.map(on_behalf_of_writes(), fn fun ->
          {_to, calldata} = capture_signer_args(fn -> fun.(@spoke, @reserve_id, @amount, @owner, []) end)
          <<selector::binary-size(4), _rest::binary>> = calldata
          selector
        end)

      assert length(Enum.uniq(selectors)) == 4
    end
  end

  describe "owner is never inferred from the signer" do
    test "supply signed with one key encodes a different on_behalf_of" do
      signer = Signer.address_from_key!(@signer_key)
      refute String.downcase(signer) == String.downcase(@owner)

      {_to, calldata, opts} =
        Onchain.TraceCase.capture_signer_call(fn ->
          assert {:error, {:missing_option, :chain_id}} =
                   PositionManager.supply(@spoke, @reserve_id, @amount, @owner, private_key: @signer_key)
        end)

      assert opts[:private_key] == @signer_key

      <<_selector::binary-size(4), _spoke::binary-size(32), _rid::binary-size(32), _amt::binary-size(32),
        obo_arg::binary-size(32)>> = calldata

      {:ok, owner_bin} = Address.validate(@owner)
      {:ok, signer_bin} = Address.validate(signer)
      encoded_owner = :binary.decode_unsigned(obo_arg)
      assert encoded_owner == :binary.decode_unsigned(pad_left(owner_bin))
      refute encoded_owner == :binary.decode_unsigned(pad_left(signer_bin))
    end
  end

  describe "decode_revert/1" do
    test "decodes InsufficientBorrowAllowance from its custom-error selector" do
      {:ok, revert} = Onchain.ABI.encode_call("InsufficientBorrowAllowance(uint256,uint256)", [@allowance, @required])

      assert {:error, {:insufficient_borrow_allowance, @allowance, @required}} =
               PositionManager.decode_revert(revert)
    end

    test "decodes InsufficientWithdrawAllowance from its custom-error selector" do
      {:ok, revert} =
        Onchain.ABI.encode_call("InsufficientWithdrawAllowance(uint256,uint256)", [@allowance, @required])

      assert {:error, {:insufficient_withdraw_allowance, @allowance, @required}} =
               PositionManager.decode_revert(revert)
    end

    test "decodes raw revert bytes the same as 0x hex" do
      {:ok, hex} = Onchain.ABI.encode_call("InsufficientBorrowAllowance(uint256,uint256)", [1, 2])
      {:ok, raw} = Onchain.Hex.decode(hex)

      assert PositionManager.decode_revert(raw) == PositionManager.decode_revert(hex)
    end

    test "returns unknown_revert when the selector does not match" do
      bogus = "0x" <> String.duplicate("aa", 4) <> String.duplicate("00", 64)
      assert {:error, {:unknown_revert, {:decode_error, :no_match}}} = PositionManager.decode_revert(bogus)
    end
  end

  describe "Taker write reverts" do
    test "borrow surfaces InsufficientBorrowAllowance from gas estimation" do
      {:ok, revert} =
        Onchain.ABI.encode_call("InsufficientBorrowAllowance(uint256,uint256)", [@allowance, @required])

      url = start_rpc_stub(fn _body -> {:rpc_error, revert_error(revert)} end)

      assert {:error, {:insufficient_borrow_allowance, @allowance, @required}} =
               PositionManager.borrow(@spoke, @reserve_id, @amount, @owner, signer_opts(url))
    end

    test "withdraw surfaces InsufficientWithdrawAllowance from gas estimation" do
      {:ok, revert} =
        Onchain.ABI.encode_call("InsufficientWithdrawAllowance(uint256,uint256)", [@allowance, @required])

      url = start_rpc_stub(fn _body -> {:rpc_error, revert_error(revert)} end)

      assert {:error, {:insufficient_withdraw_allowance, @allowance, @required}} =
               PositionManager.withdraw(@spoke, @reserve_id, @amount, @owner, signer_opts(url))
    end
  end

  describe "Taker allowance views" do
    setup do
      payloads = allowance_payloads()
      url = start_rpc_stub(fn body -> handle_rpc(body, payloads) end)
      %{rpc_opts: RPCStub.rpc_opts(url)}
    end

    test "borrowAllowance and withdrawAllowance decode the uint256 return", %{rpc_opts: rpc_opts} do
      assert {:ok, 42} = PositionManager.borrow_allowance(@spoke, @reserve_id, @owner, @spender, rpc_opts)
      assert {:ok, 7} = PositionManager.withdraw_allowance(@spoke, @reserve_id, @owner, @spender, rpc_opts)
    end

    test "borrowAllowance surfaces InsufficientBorrowAllowance as a tagged tuple", %{rpc_opts: rpc_opts} do
      assert {:error, {:insufficient_borrow_allowance, @allowance, @required}} =
               PositionManager.borrow_allowance(@spoke, 1, @owner, @spender, rpc_opts)
    end

    test "withdrawAllowance surfaces InsufficientWithdrawAllowance as a tagged tuple", %{rpc_opts: rpc_opts} do
      assert {:error, {:insufficient_withdraw_allowance, @allowance, @required}} =
               PositionManager.withdraw_allowance(@spoke, 1, @owner, @spender, rpc_opts)
    end

    test "unrelated revert data stays an rpc_error", %{rpc_opts: rpc_opts} do
      assert {:error, {:rpc_error, %{code: 3, data: data}}} =
               PositionManager.borrow_allowance(@spoke, 2, @owner, @spender, rpc_opts)

      assert is_binary(data)
    end
  end

  defp on_behalf_of_writes do
    [
      &PositionManager.supply/5,
      &PositionManager.repay/5,
      &PositionManager.borrow/5,
      &PositionManager.withdraw/5
    ]
  end

  defp amount_writes do
    on_behalf_of_writes()
  end

  defp capture_signer_args(fun) do
    {to, calldata, _opts} = Onchain.TraceCase.capture_signer_call(fun)
    {to, calldata}
  end

  defp assert_on_behalf_of_calldata(calldata, selector, spoke, reserve_id, amount, owner) do
    <<got_selector::binary-size(4), spoke_arg::binary-size(32), rid_arg::binary-size(32), amt_arg::binary-size(32),
      obo_arg::binary-size(32)>> = calldata

    assert got_selector == selector
    {:ok, spoke_bin} = Address.validate(spoke)
    {:ok, owner_bin} = Address.validate(owner)
    assert :binary.decode_unsigned(spoke_arg) == :binary.decode_unsigned(pad_left(spoke_bin))
    assert :binary.decode_unsigned(rid_arg) == reserve_id
    assert :binary.decode_unsigned(amt_arg) == amount
    assert :binary.decode_unsigned(obo_arg) == :binary.decode_unsigned(pad_left(owner_bin))
  end

  defp assert_approve_calldata(calldata, selector, spoke, reserve_id, spender, amount) do
    <<got_selector::binary-size(4), spoke_arg::binary-size(32), rid_arg::binary-size(32), spender_arg::binary-size(32),
      amt_arg::binary-size(32)>> = calldata

    assert got_selector == selector
    {:ok, spoke_bin} = Address.validate(spoke)
    {:ok, spender_bin} = Address.validate(spender)
    assert :binary.decode_unsigned(spoke_arg) == :binary.decode_unsigned(pad_left(spoke_bin))
    assert :binary.decode_unsigned(rid_arg) == reserve_id
    assert :binary.decode_unsigned(spender_arg) == :binary.decode_unsigned(pad_left(spender_bin))
    assert :binary.decode_unsigned(amt_arg) == amount
  end

  defp assert_renounce_calldata(calldata, selector, spoke, reserve_id, owner) do
    <<got_selector::binary-size(4), spoke_arg::binary-size(32), rid_arg::binary-size(32), owner_arg::binary-size(32)>> =
      calldata

    assert got_selector == selector
    {:ok, spoke_bin} = Address.validate(spoke)
    {:ok, owner_bin} = Address.validate(owner)
    assert :binary.decode_unsigned(spoke_arg) == :binary.decode_unsigned(pad_left(spoke_bin))
    assert :binary.decode_unsigned(rid_arg) == reserve_id
    assert :binary.decode_unsigned(owner_arg) == :binary.decode_unsigned(pad_left(owner_bin))
  end

  defp pad_left(bin) when byte_size(bin) <= 32 do
    padding_size = 32 - byte_size(bin)
    <<0::size(padding_size * 8), bin::binary>>
  end

  defp allowance_payloads do
    {:ok, spoke_bin} = Address.validate(@spoke)
    {:ok, owner_bin} = Address.validate(@owner)
    {:ok, spender_bin} = Address.validate(@spender)
    {:ok, borrow_err} = Onchain.ABI.encode_call("InsufficientBorrowAllowance(uint256,uint256)", [@allowance, @required])

    {:ok, withdraw_err} =
      Onchain.ABI.encode_call("InsufficientWithdrawAllowance(uint256,uint256)", [@allowance, @required])

    unknown = "0x" <> String.duplicate("aa", 4) <> String.duplicate("00", 64)

    %{
      calldata("borrowAllowance(address,uint256,address,address)", [spoke_bin, @reserve_id, owner_bin, spender_bin]) =>
        {:result, encode_uint(42)},
      calldata("withdrawAllowance(address,uint256,address,address)", [spoke_bin, @reserve_id, owner_bin, spender_bin]) =>
        {:result, encode_uint(7)},
      calldata("borrowAllowance(address,uint256,address,address)", [spoke_bin, 1, owner_bin, spender_bin]) =>
        {:rpc_error, revert_error(borrow_err)},
      calldata("withdrawAllowance(address,uint256,address,address)", [spoke_bin, 1, owner_bin, spender_bin]) =>
        {:rpc_error, revert_error(withdraw_err)},
      calldata("borrowAllowance(address,uint256,address,address)", [spoke_bin, 2, owner_bin, spender_bin]) =>
        {:rpc_error, revert_error(unknown)}
    }
  end

  defp calldata(signature, params) do
    {:ok, hex} = Onchain.ABI.encode_call(signature, params)
    String.downcase(hex)
  end

  defp encode_uint(value) do
    "0x" <> Base.encode16(<<value::256>>, case: :lower)
  end

  defp revert_error(data) do
    %{"code" => 3, "message" => "execution reverted", "data" => data}
  end

  defp handle_rpc(%{"method" => "eth_call", "params" => [%{"data" => data} | _]}, payloads) do
    Map.get_lazy(payloads, String.downcase(data), fn ->
      flunk("stub has no payload for calldata #{data}")
    end)
  end

  defp signer_opts(url) do
    [private_key: @signer_key, nonce: 0, chain_id: 1] ++ RPCStub.rpc_opts(url)
  end

  # `allowance_payloads/0` and the ad hoc revert handlers in "Taker write
  # reverts" speak the local {:result, _} / {:rpc_error, _} envelope tags
  # rather than RPCStub's {:error, _}-or-raw-result contract — adapt at the
  # boundary so the canned payloads and test bodies stay untouched.
  defp start_rpc_stub(handler) do
    RPCStub.start(fn body ->
      case handler.(body) do
        {:rpc_error, error} -> {:error, error}
        {:result, result} -> result
      end
    end)
  end
end
