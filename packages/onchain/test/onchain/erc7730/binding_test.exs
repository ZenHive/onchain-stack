defmodule Onchain.ERC7730.BindingTest do
  use ExUnit.Case, async: true

  alias Onchain.ABI
  alias Onchain.ERC7730
  alias Onchain.ERC7730.Binding
  alias Onchain.Hex

  @fixtures "test/support/fixtures/erc7730"
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @router "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
  @recipient "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

  defp load(name), do: @fixtures |> Path.join(name) |> ERC7730.load() |> elem(1)

  defp transfer_calldata(to \\ @recipient, amount \\ 1_500_000) do
    ABI.encode_call!("transfer(address,uint256)", [Hex.decode!(to), amount])
  end

  describe "resolve/3 — calldata" do
    setup do: %{descriptor: load("erc20-transfer.json")}

    test "matches deployment + selector and decodes named message fields", %{descriptor: d} do
      assert {:ok, resolution} = Binding.resolve(d, {:calldata, @usdc, 1, transfer_calldata()})
      assert resolution.message["amount"] == 1_500_000
      assert resolution.message["to"] == Hex.decode!(@recipient)
      assert resolution.types["to"] == :address
      assert resolution.types["amount"] == {:uint, 256}
      assert resolution.envelope.to == @usdc
    end

    test "errors when no deployment matches the chain id", %{descriptor: d} do
      assert {:error, {:no_deployment_match, {137, @usdc}}} =
               Binding.resolve(d, {:calldata, @usdc, 137, transfer_calldata()})
    end

    test "errors when no deployment matches the address", %{descriptor: d} do
      other = "0x" <> String.duplicate("ab", 20)

      assert {:error, {:no_deployment_match, {1, ^other}}} =
               Binding.resolve(d, {:calldata, other, 1, transfer_calldata()})
    end

    test "errors when the selector matches no format", %{descriptor: d} do
      unknown = ABI.encode_call!("approve(address,uint256)", [Hex.decode!(@recipient), 1])

      assert {:error, {:no_format_match, _selector}} =
               Binding.resolve(d, {:calldata, @usdc, 1, unknown})
    end

    test "errors on calldata shorter than a 4-byte selector", %{descriptor: d} do
      assert {:error, {:decode_error, :calldata_too_short}} =
               Binding.resolve(d, {:calldata, @usdc, 1, "0x1234"})
    end

    test "passes envelope value/from overrides through", %{descriptor: d} do
      assert {:ok, resolution} =
               Binding.resolve(d, {:calldata, @usdc, 1, transfer_calldata()},
                 value: 42,
                 from: @recipient
               )

      assert resolution.envelope.value == 42
      assert resolution.envelope.from == @recipient
    end
  end

  describe "resolve/3 — eip712" do
    setup do: %{descriptor: load("eip712-permit.json")}

    defp permit_payload(overrides \\ %{}) do
      Map.merge(
        %{
          "domain" => %{
            "name" => "USD Coin",
            "version" => "2",
            "chainId" => 1,
            "verifyingContract" => @usdc
          },
          "primaryType" => "Permit",
          "message" => %{
            "owner" => @recipient,
            "spender" => @router,
            "value" => 1_000_000,
            "nonce" => 0,
            "deadline" => 1_900_000_000
          }
        },
        overrides
      )
    end

    test "matches domain + primaryType and exposes message fields", %{descriptor: d} do
      assert {:ok, resolution} = Binding.resolve(d, {:eip712, permit_payload()})
      assert resolution.message["spender"] == @router
      assert resolution.message["value"] == 1_000_000
      assert resolution.types["deadline"] == {:uint, 256}
      assert resolution.envelope.to == @usdc
    end

    test "errors when the domain name mismatches the descriptor", %{descriptor: d} do
      payload =
        permit_payload(%{"domain" => %{"name" => "Wrong", "version" => "2", "chainId" => 1}})

      assert {:error, {:domain_mismatch, "name"}} = Binding.resolve(d, {:eip712, payload})
    end

    test "errors when a constrained domain field is missing", %{descriptor: d} do
      payload = permit_payload(%{"domain" => %{"version" => "2", "chainId" => 1}})
      assert {:error, {:domain_mismatch, "name"}} = Binding.resolve(d, {:eip712, payload})
    end

    test "errors when the primaryType has no matching format", %{descriptor: d} do
      payload = permit_payload(%{"primaryType" => "Unknown"})
      assert {:error, {:no_format_match, "Unknown"}} = Binding.resolve(d, {:eip712, payload})
    end

    test "matches a bare primaryType format key and derives types from the payload" do
      raw = %{
        "context" => %{"eip712" => %{"domain" => %{"name" => "USD Coin"}}},
        "display" => %{"formats" => %{"Permit" => %{"fields" => [%{"path" => "value"}]}}}
      }

      assert {:ok, descriptor} = ERC7730.load(raw)

      payload =
        permit_payload(%{
          "types" => %{
            "Permit" => [
              %{"name" => "owner", "type" => "address"},
              %{"name" => "value", "type" => "uint256"}
            ]
          }
        })

      assert {:ok, resolution} = Binding.resolve(descriptor, {:eip712, payload})
      assert resolution.signature == nil
      assert resolution.types["owner"] == :address
      assert resolution.types["value"] == {:uint, 256}
    end

    test "matches an encodeType format key by primaryType" do
      raw = %{
        "context" => %{"eip712" => %{"domain" => %{"name" => "Mail App"}}},
        "display" => %{
          "formats" => %{
            "Mail(address from,Person to)Person(address wallet)" => %{
              "fields" => [%{"path" => "from"}]
            }
          }
        }
      }

      assert {:ok, descriptor} = ERC7730.load(raw)

      payload = %{
        "domain" => %{"name" => "Mail App"},
        "primaryType" => "Mail",
        "types" => %{
          "Mail" => [
            %{"name" => "from", "type" => "address"},
            %{"name" => "to", "type" => "Person"}
          ],
          "Person" => [%{"name" => "wallet", "type" => "address"}]
        },
        "message" => %{"from" => @recipient, "to" => %{"wallet" => @router}}
      }

      assert {:ok, resolution} = Binding.resolve(descriptor, {:eip712, payload})
      assert resolution.message["from"] == @recipient
      assert resolution.types["from"] == :address
    end

    test "accepts atom-keyed payloads", %{descriptor: d} do
      payload = %{
        domain: %{name: "USD Coin", version: "2", chainId: 1, verifyingContract: @usdc},
        primaryType: "Permit",
        message: %{owner: @recipient, spender: @router, value: 5, nonce: 0, deadline: 1}
      }

      assert {:ok, resolution} = Binding.resolve(d, {:eip712, payload})
      assert resolution.message["spender"] == @router
    end
  end

  describe "resolve/3 — descriptor hardening" do
    test "errors when two format keys share the same calldata selector" do
      raw = %{
        "context" => %{
          "contract" => %{"deployments" => [%{"chainId" => 1, "address" => @usdc}]}
        },
        "display" => %{
          "formats" => %{
            "f(uint256 a)" => %{"fields" => [%{"path" => "a"}]},
            "f(uint256 b)" => %{"fields" => [%{"path" => "b"}]}
          }
        }
      }

      assert {:ok, descriptor} = ERC7730.load(raw)
      calldata = ABI.encode_call!("f(uint256)", [1])

      assert {:error, {:invalid_descriptor, {:duplicate_format_selector, _selector}}} =
               Binding.resolve(descriptor, {:calldata, @usdc, 1, calldata})
    end
  end

  describe "resolve/3 — user_op" do
    test "unwraps callData and binds as calldata" do
      d = load("erc20-transfer.json")
      user_op = %{"sender" => @recipient, "callData" => transfer_calldata()}
      assert {:ok, resolution} = Binding.resolve(d, {:user_op, @usdc, 1, user_op})
      assert resolution.message["amount"] == 1_500_000
    end

    test "errors when the user_op has no callData" do
      d = load("erc20-transfer.json")

      assert {:error, {:missing_calldata, _}} =
               Binding.resolve(d, {:user_op, @usdc, 1, %{"sender" => @recipient}})
    end
  end

  describe "resolve/3 — context mismatch" do
    test "rejects an eip712 request against a contract descriptor" do
      d = load("erc20-transfer.json")
      assert {:error, {:context_mismatch, _}} = Binding.resolve(d, {:eip712, %{}})
    end

    test "rejects a calldata request against an eip712 descriptor" do
      d = load("eip712-permit.json")

      assert {:error, {:context_mismatch, _}} =
               Binding.resolve(d, {:calldata, @usdc, 1, transfer_calldata()})
    end

    test "rejects an unrecognized request shape" do
      d = load("erc20-transfer.json")
      assert {:error, {:invalid_request, _}} = Binding.resolve(d, {:bogus, 1})
    end
  end
end
