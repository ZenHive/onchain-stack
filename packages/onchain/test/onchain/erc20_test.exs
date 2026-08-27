defmodule Onchain.ERC20Test do
  # async: false — :dbg tracing sets a process-global tracer, can't run concurrently
  use ExUnit.Case, async: false
  use Onchain.EthCallStub

  alias Onchain.ERC20

  # Valid address for param validation tests (doesn't need to be a real token)
  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @approve_selector <<0x09, 0x5E, 0xA7, 0xB3>>
  @transfer_selector <<0xA9, 0x05, 0x9C, 0xBB>>

  describe "balance_of/3" do
    test "returns error for invalid holder address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               ERC20.balance_of(@valid_address, "not_an_address")
    end

    test "returns error for invalid token address" do
      {:ok, holder_bin} = Onchain.Address.validate(@valid_address)

      assert {:error, {:invalid_address, "bad_token"}} =
               ERC20.balance_of("bad_token", holder_bin)
    end

    test "returns the decoded uint256 balance on success" do
      Onchain.EthCallStub.queue_response("uint256", 1_000_000)

      assert {:ok, 1_000_000} =
               ERC20.balance_of(@valid_address, @valid_address, rpc_url: "http://stub.invalid")
    end
  end

  describe "balance_of!/3" do
    test "raises on invalid holder address" do
      assert_raise RuntimeError, ~r/balance_of failed/, fn ->
        ERC20.balance_of!(@valid_address, "not_an_address")
      end
    end

    test "returns the decoded uint256 balance on success" do
      Onchain.EthCallStub.queue_response("uint256", 1_000_000)

      assert 1_000_000 =
               ERC20.balance_of!(@valid_address, @valid_address, rpc_url: "http://stub.invalid")
    end
  end

  describe "allowance/4" do
    test "returns error for invalid owner address" do
      assert {:error, {:invalid_address, "bad_owner"}} =
               ERC20.allowance(@valid_address, "bad_owner", @valid_address)
    end

    test "returns error for invalid spender address" do
      assert {:error, {:invalid_address, "bad_spender"}} =
               ERC20.allowance(@valid_address, @valid_address, "bad_spender")
    end

    test "returns error for invalid token address" do
      {:ok, addr_bin} = Onchain.Address.validate(@valid_address)

      assert {:error, {:invalid_address, "bad_token"}} =
               ERC20.allowance("bad_token", addr_bin, addr_bin)
    end
  end

  describe "allowance!/4" do
    test "raises on invalid owner address" do
      assert_raise RuntimeError, ~r/allowance failed/, fn ->
        ERC20.allowance!(@valid_address, "bad_owner", @valid_address)
      end
    end
  end

  describe "decimals/2" do
    test "returns error for invalid token address" do
      assert {:error, {:invalid_address, "not_a_token"}} =
               ERC20.decimals("not_a_token")
    end
  end

  describe "decimals!/2" do
    test "raises on invalid token address" do
      assert_raise RuntimeError, ~r/decimals failed/, fn ->
        ERC20.decimals!("not_a_token")
      end
    end
  end

  describe "symbol/2" do
    test "returns error for invalid token address" do
      assert {:error, {:invalid_address, "not_a_token"}} =
               ERC20.symbol("not_a_token")
    end
  end

  describe "symbol!/2" do
    test "raises on invalid token address" do
      assert_raise RuntimeError, ~r/symbol failed/, fn ->
        ERC20.symbol!("not_a_token")
      end
    end

    test "returns the decoded symbol string on success" do
      Onchain.EthCallStub.queue_response("string", "USDC")

      assert "USDC" = ERC20.symbol!(@valid_address, rpc_url: "http://stub.invalid")
    end
  end

  describe "total_supply/2" do
    test "returns error for invalid token address" do
      assert {:error, {:invalid_address, "not_a_token"}} =
               ERC20.total_supply("not_a_token")
    end
  end

  describe "total_supply!/2" do
    test "raises on invalid token address" do
      assert_raise RuntimeError, ~r/total_supply failed/, fn ->
        ERC20.total_supply!("not_a_token")
      end
    end
  end

  describe "approve/4" do
    test "returns error for invalid spender address" do
      assert {:error, {:invalid_address, "bad_spender"}} =
               ERC20.approve(@valid_address, "bad_spender", 1_000_000, [])
    end

    test "returns error for invalid token address (missing opts hits first)" do
      {:ok, addr_bin} = Onchain.Address.validate(@valid_address)

      # Token address validation happens inside Signer.send_transaction (after :private_key check),
      # so with empty opts, :missing_option fires first
      assert {:error, {:missing_option, :private_key}} =
               ERC20.approve("bad_token", addr_bin, 1_000_000, [])
    end
  end

  describe "approve!/4" do
    test "raises on invalid spender address" do
      assert_raise RuntimeError, ~r/approve failed/, fn ->
        ERC20.approve!(@valid_address, "bad_spender", 1_000_000, [])
      end
    end
  end

  describe "transfer/4" do
    test "returns error for invalid recipient address" do
      assert {:error, {:invalid_address, "bad_to"}} =
               ERC20.transfer(@valid_address, "bad_to", 1_000_000, [])
    end

    test "returns error for invalid token address (missing opts hits first)" do
      {:ok, addr_bin} = Onchain.Address.validate(@valid_address)

      # Token address validation happens inside Signer.send_transaction (after :private_key check),
      # so with empty opts, :missing_option fires first
      assert {:error, {:missing_option, :private_key}} =
               ERC20.transfer("bad_token", addr_bin, 1_000_000, [])
    end
  end

  describe "transfer!/4" do
    test "raises on invalid recipient address" do
      assert_raise RuntimeError, ~r/transfer failed/, fn ->
        ERC20.transfer!(@valid_address, "bad_to", 1_000_000, [])
      end
    end
  end

  describe "approve/transfer ABI selector verification" do
    test "wrappers pass distinct ERC-20 selectors to Signer.send_transaction/3" do
      approve_calldata =
        capture_signer_calldata(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   ERC20.approve(@valid_address, @valid_address, 100, [])
        end)

      transfer_calldata =
        capture_signer_calldata(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   ERC20.transfer(@valid_address, @valid_address, 100, [])
        end)

      <<approve_selector::binary-size(4), approve_args::binary>> = approve_calldata
      <<transfer_selector::binary-size(4), transfer_args::binary>> = transfer_calldata

      assert approve_selector == @approve_selector
      assert transfer_selector == @transfer_selector
      refute approve_selector == transfer_selector
      assert approve_args == transfer_args
    end
  end

  @doc false
  # Delegates to TraceCase and destructures to just calldata.
  defp capture_signer_calldata(fun) do
    {_to, calldata, _opts} = Onchain.TraceCase.capture_signer_call(fun)
    calldata
  end
end
