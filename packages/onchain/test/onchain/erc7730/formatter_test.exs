defmodule Onchain.ERC7730.FormatterTest do
  use ExUnit.Case, async: true

  alias Onchain.ERC7730.Descriptor
  alias Onchain.ERC7730.Formatter
  alias Onchain.Hex

  @recipient "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
  @recipient_bin Hex.decode!("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @dai "0x6B175474E89094C44Da98b954EedeAC495271d0F"

  defp field(attrs) do
    Map.merge(%{path: nil, value: nil, label: nil, format: :raw, params: %{}, visible: true}, Map.new(attrs))
  end

  defp resolution(message, types, envelope \\ %{to: nil, value: 0, from: nil}) do
    %{message: message, types: types, envelope: envelope, format: nil, signature: nil}
  end

  defp descriptor(raw \\ %{}, metadata \\ %{}) do
    %Descriptor{
      context: {:contract, %{deployments: [], abi: nil, address_matcher: nil}},
      display: %{formats: %{}},
      metadata: metadata,
      raw: raw
    }
  end

  defp render(field, resolution, opts \\ [], descriptor \\ descriptor()) do
    assert {:ok, result} = Formatter.format_field(field, resolution, descriptor, opts)
    result
  end

  describe "raw format" do
    test "renders an address as an EIP-55 checksummed hex string" do
      result = render(field(path: "#.to", format: :raw), resolution(%{"to" => @recipient_bin}, %{"to" => :address}))
      assert result.raw == @recipient_bin
      assert result.value == @recipient
      assert result.formatted_value == @recipient
    end

    test "renders an integer" do
      result = render(field(path: "#.n", format: :raw), resolution(%{"n" => 42}, %{"n" => {:uint, 256}}))
      assert result.value == 42
      assert result.formatted_value == "42"
    end

    test "renders a boolean" do
      result = render(field(path: "#.flag", format: :raw), resolution(%{"flag" => true}, %{"flag" => :bool}))
      assert result.formatted_value == "true"
    end

    test "renders fixed-size bytes as 0x hex" do
      result = render(field(path: "#.b", format: :raw), resolution(%{"b" => <<1, 2, 3>>}, %{"b" => {:bytes, 3}}))
      assert result.value == "0x010203"
      assert result.formatted_value == "0x010203"
    end

    test "renders dynamic bytes as 0x hex" do
      result = render(field(path: "#.b", format: :raw), resolution(%{"b" => <<0xDE, 0xAD>>}, %{"b" => :bytes}))
      assert result.value == "0xdead"
      assert result.formatted_value == "0xdead"
    end
  end

  describe "amount format (native currency)" do
    test "scales by 18 decimals with the ETH symbol by default" do
      result =
        render(
          field(path: "@.value", format: :amount),
          resolution(%{}, %{}, %{to: nil, value: 1_500_000_000_000_000_000, from: nil})
        )

      assert result.formatted_value == "1.5 ETH"
    end

    test "honors native_symbol and native_decimals opts" do
      result =
        render(
          field(path: "@.value", format: :amount),
          resolution(%{}, %{}, %{to: nil, value: 2_000_000, from: nil}),
          native_decimals: 6,
          native_symbol: "MATIC"
        )

      assert result.formatted_value == "2 MATIC"
    end
  end

  describe "tokenAmount format" do
    test "uses decimals + symbol from the :tokens opt" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"token" => @usdc}),
          resolution(%{"amount" => 1_500_000}, %{"amount" => {:uint, 256}}),
          tokens: %{String.downcase(@usdc) => %{decimals: 6, symbol: "USDC"}}
        )

      assert result.formatted_value == "1.5 USDC"
    end

    test "resolves the token address via tokenPath" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"tokenPath" => "#.token"}),
          resolution(%{"amount" => 2_000_000, "token" => @usdc}, %{"amount" => {:uint, 256}, "token" => :address}),
          tokens: %{String.downcase(@usdc) => %{decimals: 6, symbol: "USDC"}}
        )

      assert result.formatted_value == "2 USDC"
    end

    test "shows the threshold message when the amount meets the threshold" do
      params = %{"token" => @usdc, "threshold" => "0x" <> String.duplicate("ff", 32), "message" => "Unlimited"}

      result =
        render(
          field(path: "#.amount", format: :token_amount, params: params),
          resolution(%{"amount" => Integer.pow(2, 256) - 1}, %{"amount" => {:uint, 256}})
        )

      assert result.formatted_value == "Unlimited"
    end

    test "falls back to the raw integer when decimals cannot be resolved" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"token" => @usdc}),
          resolution(%{"amount" => 12_345}, %{"amount" => {:uint, 256}})
        )

      assert result.formatted_value == "12345"
    end

    test "resolves a $. token reference against descriptor constants and metadata.token" do
      raw = %{"metadata" => %{"constants" => %{"tok" => @usdc}}}
      metadata = %{"token" => %{"address" => @usdc, "decimals" => 6, "ticker" => "USDC"}}

      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"token" => "$.metadata.constants.tok"}),
          resolution(%{"amount" => 3_000_000}, %{"amount" => {:uint, 256}}),
          [],
          descriptor(raw, metadata)
        )

      assert result.formatted_value == "3 USDC"
    end

    test "does not use descriptor metadata when tokenPath resolves to a different token" do
      metadata = %{"token" => %{"address" => @usdc, "decimals" => 6, "ticker" => "USDC"}}

      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"tokenPath" => "#.token"}),
          resolution(%{"amount" => 1_000_000, "token" => @dai}, %{"amount" => {:uint, 256}, "token" => :address}),
          [],
          descriptor(%{}, metadata)
        )

      assert result.formatted_value == "1000000"
    end
  end

  describe "addressName format" do
    test "renders a checksummed address when no name is known" do
      result =
        render(field(path: "#.to", format: :address_name), resolution(%{"to" => @recipient_bin}, %{"to" => :address}))

      assert result.formatted_value == @recipient
    end

    test "uses a trusted name from the :names opt" do
      result =
        render(
          field(path: "#.to", format: :address_name),
          resolution(%{"to" => @recipient_bin}, %{"to" => :address}),
          names: %{String.downcase(@recipient) => "vitalik.eth"}
        )

      assert result.formatted_value == "vitalik.eth"
    end
  end

  describe "date format" do
    test "renders a unix timestamp as RFC3339" do
      result =
        render(
          field(path: "#.deadline", format: :date, params: %{"encoding" => "timestamp"}),
          resolution(%{"deadline" => 1_900_000_000}, %{"deadline" => {:uint, 256}})
        )

      assert result.formatted_value == "2030-03-17T17:46:40Z"
    end

    test "renders a blockheight encoding distinctly" do
      result =
        render(
          field(path: "#.block", format: :date, params: %{"encoding" => "blockheight"}),
          resolution(%{"block" => 21_000_000}, %{"block" => {:uint, 256}})
        )

      assert result.formatted_value == "block 21000000"
    end
  end

  describe "duration format" do
    test "renders seconds as H:MM:SS" do
      result = render(field(path: "#.d", format: :duration), resolution(%{"d" => 3_661}, %{"d" => {:uint, 256}}))
      assert result.formatted_value == "1:01:01"
    end
  end

  describe "unit format" do
    test "scales by decimals and appends the base unit" do
      result =
        render(
          field(path: "#.gwei", format: :unit, params: %{"base" => "gwei", "decimals" => 9}),
          resolution(%{"gwei" => 1_500_000_000}, %{"gwei" => {:uint, 256}})
        )

      assert result.formatted_value == "1.5 gwei"
    end

    test "renders a percentage base without a space" do
      result =
        render(
          field(path: "#.bps", format: :unit, params: %{"base" => "%", "decimals" => 2}),
          resolution(%{"bps" => 250}, %{"bps" => {:uint, 256}})
        )

      assert result.formatted_value == "2.5%"
    end
  end

  describe "enum format" do
    test "resolves a value to a label via a $ref enum" do
      raw = %{"metadata" => %{"enums" => %{"side" => %{"0" => "Buy", "1" => "Sell"}}}}

      result =
        render(
          field(path: "#.side", format: :enum, params: %{"$ref" => "$.metadata.enums.side"}),
          resolution(%{"side" => 1}, %{"side" => {:uint, 8}}),
          [],
          descriptor(raw)
        )

      assert result.formatted_value == "Sell"
    end

    test "falls back to the raw value when the enum has no matching key" do
      raw = %{"metadata" => %{"enums" => %{"side" => %{"0" => "Buy"}}}}

      result =
        render(
          field(path: "#.side", format: :enum, params: %{"$ref" => "$.metadata.enums.side"}),
          resolution(%{"side" => 9}, %{"side" => {:uint, 8}}),
          [],
          descriptor(raw)
        )

      assert result.formatted_value == "9"
    end
  end

  describe "coercion across sources" do
    test "coerces EIP-712 string values (hex address, decimal uint) to canonical raw" do
      result =
        render(
          field(path: "value", format: :raw),
          resolution(%{"value" => "1000000"}, %{"value" => {:uint, 256}})
        )

      assert result.raw == 1_000_000

      addr =
        render(
          field(path: "owner", format: :raw),
          resolution(%{"owner" => @recipient}, %{"owner" => :address})
        )

      assert addr.raw == @recipient_bin
      assert addr.value == @recipient
    end
  end

  describe "envelope and nested paths" do
    test "resolves @.from and @.to as addresses" do
      env = %{to: nil, value: 0, from: @recipient}
      result = render(field(path: "@.from", format: :address_name), resolution(%{}, %{}, env))
      assert result.formatted_value == @recipient
    end

    test "resolves a nested message path into a decoded sub-map" do
      result =
        render(
          field(path: "#.order.amount", format: :raw),
          resolution(%{"order" => %{"amount" => 5}}, %{"order" => :tuple})
        )

      assert result.formatted_value == "5"
    end

    test "renders a long non-address binary as hex" do
      sig = :binary.copy(<<0xFF>>, 32)
      result = render(field(path: "#.r", format: :raw), resolution(%{"r" => sig}, %{"r" => nil}))
      assert result.formatted_value == Hex.encode(sig)
    end
  end

  describe "tokenAmount fallbacks" do
    test "treats the zero address as the native currency" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"token" => "0x" <> String.duplicate("00", 20)}),
          resolution(%{"amount" => 1_000_000_000_000_000_000}, %{"amount" => {:uint, 256}})
        )

      assert result.formatted_value == "1 ETH"
    end

    test "omits the symbol when only decimals are known" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"token" => @usdc}),
          resolution(%{"amount" => 2_500_000}, %{"amount" => {:uint, 256}}),
          tokens: %{String.downcase(@usdc) => %{decimals: 6}}
        )

      assert result.formatted_value == "2.5"
    end

    test "renders the raw integer when no token param is given" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{}),
          resolution(%{"amount" => 88}, %{"amount" => {:uint, 256}})
        )

      assert result.formatted_value == "88"
    end

    test "renders the raw integer when the token path resolves to nothing" do
      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"tokenPath" => "#.missing"}),
          resolution(%{"amount" => 99}, %{"amount" => {:uint, 256}})
        )

      assert result.formatted_value == "99"
    end

    test "resolves a token from an @. envelope reference" do
      env = %{to: @usdc, value: 0, from: nil}

      result =
        render(
          field(path: "#.amount", format: :token_amount, params: %{"token" => "@.to"}),
          resolution(%{"amount" => 3_000_000}, %{"amount" => {:uint, 256}}, env),
          tokens: %{String.downcase(@usdc) => %{decimals: 6, symbol: "USDC"}}
        )

      assert result.formatted_value == "3 USDC"
    end
  end

  describe "numeric edge cases" do
    test "renders a zero-decimal unit without scaling" do
      result =
        render(
          field(path: "#.n", format: :unit, params: %{"base" => "wei", "decimals" => 0}),
          resolution(%{"n" => 7}, %{"n" => {:uint, 256}})
        )

      assert result.formatted_value == "7 wei"
    end

    test "falls back to the raw integer for an out-of-range timestamp" do
      result =
        render(
          field(path: "#.d", format: :date, params: %{"encoding" => "timestamp"}),
          resolution(%{"d" => 999_999_999_999_999_999}, %{"d" => {:uint, 256}})
        )

      assert result.formatted_value == "999999999999999999"
    end

    test "renders a negative duration verbatim" do
      result = render(field(path: "#.d", format: :duration), resolution(%{"d" => -5}, %{"d" => {:int, 256}}))
      assert result.formatted_value == "-5"
    end
  end

  describe "literals and missing paths" do
    test "renders a literal value field" do
      result = render(field(value: "Swap on Uniswap", label: "Action"), resolution(%{}, %{}))
      assert result.raw == "Swap on Uniswap"
      assert result.formatted_value == "Swap on Uniswap"
    end

    test "renders a long printable literal verbatim" do
      long = String.duplicate("ab", 20)
      result = render(field(value: long), resolution(%{}, %{}))
      assert result.formatted_value == long
    end

    test "inspects a non-scalar literal value" do
      result = render(field(value: [1, 2]), resolution(%{}, %{}))
      assert result.formatted_value == "[1, 2]"
    end

    test "errors when a visible field path resolves to nothing" do
      assert {:error, {:unresolved_path, "#.missing"}} =
               Formatter.format_field(field(path: "#.missing", format: :raw), resolution(%{}, %{}), descriptor())
    end

    test "unknown formats fall back to a plain rendering" do
      result = render(field(path: "#.x", format: :unknown), resolution(%{"x" => 7}, %{"x" => {:uint, 256}}))
      assert result.formatted_value == "7"
    end
  end
end
