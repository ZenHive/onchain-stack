defmodule Onchain.ERC7730Test do
  use ExUnit.Case, async: true

  alias Onchain.ABI
  alias Onchain.ERC7730
  alias Onchain.ERC7730.Descriptor
  alias Onchain.Hex

  @fixtures "test/support/fixtures/erc7730"
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @router "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
  @recipient "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
  @usdc_tokens %{"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" => %{decimals: 6, symbol: "USDC"}}

  defp fixture(name), do: Path.join(@fixtures, name)

  describe "load/1" do
    test "loads a descriptor from a file path" do
      assert {:ok, %Descriptor{}} = ERC7730.load(fixture("erc20-transfer.json"))
    end

    test "loads a descriptor from a JSON string" do
      json = File.read!(fixture("erc20-transfer.json"))
      assert {:ok, %Descriptor{}} = ERC7730.load(json)
    end

    test "loads a descriptor from an already-decoded map" do
      raw = "erc20-transfer.json" |> fixture() |> File.read!() |> Jason.decode!()
      assert {:ok, %Descriptor{}} = ERC7730.load(raw)
    end

    test "returns {:invalid_json, _} for malformed JSON" do
      assert {:error, {:invalid_json, _}} = ERC7730.load("{not json")
    end

    test "returns {:file_error, :enoent} for a missing file path" do
      assert {:error, {:file_error, :enoent}} = ERC7730.load("test/support/fixtures/erc7730/nope.json")
    end

    test "propagates a structural validation error" do
      assert {:error, {:missing_context, _}} = ERC7730.load(~s({"display": {"formats": {}}}))
    end
  end

  describe "format/3 — ERC-20 transfer" do
    setup do
      {:ok, descriptor} = ERC7730.load(fixture("erc20-transfer.json"))
      calldata = ABI.encode_call!("transfer(address,uint256)", [Hex.decode!(@recipient), 1_500_000])
      %{descriptor: descriptor, calldata: calldata}
    end

    test "renders recipient + token amount", %{descriptor: d, calldata: calldata} do
      assert {:ok, fields} = ERC7730.format(d, {:calldata, @usdc, 1, calldata}, tokens: @usdc_tokens)

      assert [
               %{label: "To", formatted_value: @recipient},
               %{label: "Amount", formatted_value: "1.5 USDC", raw: 1_500_000}
             ] = fields
    end

    test "surfaces a binding error", %{descriptor: d, calldata: calldata} do
      assert {:error, {:no_deployment_match, _}} = ERC7730.format(d, {:calldata, @usdc, 999, calldata})
    end
  end

  describe "format/3 — EIP-712 permit" do
    test "renders spender, max amount, and deadline; hides owner/nonce" do
      {:ok, descriptor} = ERC7730.load(fixture("eip712-permit.json"))

      payload = %{
        "domain" => %{"name" => "USD Coin", "version" => "2", "chainId" => 1, "verifyingContract" => @usdc},
        "primaryType" => "Permit",
        "message" => %{
          "owner" => @recipient,
          "spender" => @router,
          "value" => 1_000_000,
          "nonce" => 7,
          "deadline" => 1_900_000_000
        }
      }

      assert {:ok, fields} = ERC7730.format(descriptor, {:eip712, payload}, tokens: @usdc_tokens)
      labels = Enum.map(fields, & &1.label)
      assert labels == ["Spender", "Max spending amount", "Valid until"]
      assert Enum.at(fields, 1).formatted_value == "1 USDC"
      assert Enum.at(fields, 2).formatted_value == "2030-03-17T17:46:40Z"
    end
  end

  describe "format/3 — Uniswap V3 router" do
    test "renders a sweepToken call with tokenPath resolution" do
      {:ok, descriptor} = ERC7730.load(fixture("uniswap-v3-router.json"))

      calldata =
        ABI.encode_call!("sweepToken(address,uint256,address)", [
          Hex.decode!(@usdc),
          2_000_000,
          Hex.decode!(@recipient)
        ])

      assert {:ok, fields} = ERC7730.format(descriptor, {:calldata, @router, 1, calldata}, tokens: @usdc_tokens)
      assert [%{label: "Token"}, %{label: "Minimum amount", formatted_value: "2 USDC"}, %{label: "Recipient"}] = fields
    end

    test "renders an unwrapWETH9 call with a native amount" do
      {:ok, descriptor} = ERC7730.load(fixture("uniswap-v3-router.json"))

      calldata =
        ABI.encode_call!("unwrapWETH9(uint256,address)", [500_000_000_000_000_000, Hex.decode!(@recipient)])

      assert {:ok, fields} = ERC7730.format(descriptor, {:calldata, @router, 1, calldata})
      assert [%{label: "Minimum received", formatted_value: "0.5 ETH"}, %{label: "Recipient"}] = fields
    end
  end

  describe "format!/3" do
    test "returns the field list directly" do
      {:ok, descriptor} = ERC7730.load(fixture("erc20-transfer.json"))
      calldata = ABI.encode_call!("transfer(address,uint256)", [Hex.decode!(@recipient), 1_000_000])

      assert [%{label: "To"}, %{label: "Amount"}] =
               ERC7730.format!(descriptor, {:calldata, @usdc, 1, calldata}, tokens: @usdc_tokens)
    end

    test "raises on a binding error" do
      {:ok, descriptor} = ERC7730.load(fixture("erc20-transfer.json"))
      calldata = ABI.encode_call!("transfer(address,uint256)", [Hex.decode!(@recipient), 1])

      assert_raise RuntimeError, ~r/no_deployment_match/, fn ->
        ERC7730.format!(descriptor, {:calldata, @usdc, 42, calldata})
      end
    end
  end
end
