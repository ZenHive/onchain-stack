defmodule Onchain.ERC7730.DescriptorTest do
  use ExUnit.Case, async: true

  alias Onchain.ERC7730.Descriptor

  @fixtures "test/support/fixtures/erc7730"

  defp load_json(name) do
    @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()
  end

  describe "parse/1 — contract context" do
    test "parses a valid ERC-20 transfer descriptor" do
      assert {:ok, descriptor} = Descriptor.parse(load_json("erc20-transfer.json"))
      assert {:contract, ctx} = descriptor.context
      assert [%{chain_id: 1, address: <<_::160>>}] = ctx.deployments
      assert is_list(ctx.abi)
      assert Map.has_key?(descriptor.display.formats, "transfer(address to, uint256 amount)")
      # raw JSON is retained for $. path resolution
      assert descriptor.raw["metadata"]["token"]["decimals"] == 6
    end

    test "validates and decodes deployment addresses to 20-byte binaries" do
      {:ok, descriptor} = Descriptor.parse(load_json("erc20-transfer.json"))
      {:contract, ctx} = descriptor.context
      assert [%{address: address}] = ctx.deployments
      assert byte_size(address) == 20
    end

    test "captures an addressMatcher when present" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}],
            "addressMatcher" => "https://example.com/matcher"
          }
        },
        "display" => %{"formats" => %{}}
      }

      assert {:ok, %{context: {:contract, ctx}}} = Descriptor.parse(raw)
      assert ctx.address_matcher == "https://example.com/matcher"
    end
  end

  describe "parse/1 — eip712 context" do
    test "parses a valid permit descriptor with domain and schemas" do
      assert {:ok, descriptor} = Descriptor.parse(load_json("eip712-permit.json"))
      assert {:eip712, ctx} = descriptor.context
      assert ctx.domain["name"] == "USD Coin"
      assert is_list(ctx.schemas)
      assert [%{chain_id: 1}] = ctx.deployments
    end

    test "allows an eip712 context with no deployments" do
      raw = %{
        "context" => %{"eip712" => %{"domain" => %{"name" => "X"}}},
        "display" => %{"formats" => %{}}
      }

      assert {:ok, %{context: {:eip712, ctx}}} = Descriptor.parse(raw)
      assert ctx.deployments == []
    end
  end

  describe "parse/1 — structural errors" do
    test "rejects a descriptor with no context" do
      assert {:error, {:missing_context, _}} =
               Descriptor.parse(%{"display" => %{"formats" => %{}}})
    end

    test "rejects an unknown context type" do
      raw = %{"context" => %{"solana" => %{}}, "display" => %{"formats" => %{}}}
      assert {:error, {:invalid_context, _}} = Descriptor.parse(raw)
    end

    test "rejects a contract context with no deployments" do
      raw = %{"context" => %{"contract" => %{}}, "display" => %{"formats" => %{}}}
      assert {:error, {:no_deployments, _}} = Descriptor.parse(raw)
    end

    test "rejects a contract context with an empty deployments list" do
      raw = %{
        "context" => %{"contract" => %{"deployments" => []}},
        "display" => %{"formats" => %{}}
      }

      assert {:error, {:no_deployments, _}} = Descriptor.parse(raw)
    end

    test "rejects an invalid deployment address" do
      raw = %{
        "context" => %{"contract" => %{"deployments" => [%{"chainId" => 1, "address" => "nope"}]}},
        "display" => %{"formats" => %{}}
      }

      assert {:error, {:invalid_address, "nope"}} = Descriptor.parse(raw)
    end

    test "rejects a descriptor with no display section" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        }
      }

      assert {:error, {:missing_display, _}} = Descriptor.parse(raw)
    end

    test "rejects a field with neither path nor value" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        },
        "display" => %{
          "formats" => %{"f()" => %{"fields" => [%{"label" => "x", "format" => "raw"}]}}
        }
      }

      assert {:error, {:invalid_field, {:no_path_or_value, _}}} = Descriptor.parse(raw)
    end

    test "rejects a field with a non-string format" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        },
        "display" => %{
          "formats" => %{"f()" => %{"fields" => [%{"path" => "#.x", "format" => 1}]}}
        }
      }

      assert {:error, {:invalid_field, {:invalid_format, 1}}} = Descriptor.parse(raw)
    end

    test "rejects a non-list excluded value" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        },
        "display" => %{
          "formats" => %{"f()" => %{"excluded" => "#.x", "fields" => [%{"path" => "#.x"}]}}
        }
      }

      assert {:error, {:invalid_field, {:invalid_excluded, "#.x"}}} = Descriptor.parse(raw)
    end

    test "rejects a field with non-map params" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        },
        "display" => %{
          "formats" => %{"f()" => %{"fields" => [%{"path" => "#.x", "params" => "bad"}]}}
        }
      }

      assert {:error, {:invalid_field, {:invalid_params, "bad"}}} = Descriptor.parse(raw)
    end

    test "rejects a non-map input" do
      assert {:error, {:invalid_descriptor, :not_a_map}} = Descriptor.parse("not a map")
    end
  end

  describe "parse/1 — field parsing" do
    test "maps known format strings to atoms and unknown ones to :unknown" do
      {:ok, descriptor} = Descriptor.parse(load_json("eip712-permit.json"))
      fields = descriptor.display.formats |> Map.values() |> hd() |> Map.fetch!(:fields)
      formats = Enum.map(fields, & &1.format)
      assert :address_name in formats
      assert :token_amount in formats
      assert :date in formats
    end

    test "marks visible:never fields as not visible" do
      {:ok, descriptor} = Descriptor.parse(load_json("eip712-permit.json"))
      fields = descriptor.display.formats |> Map.values() |> hd() |> Map.fetch!(:fields)
      owner = Enum.find(fields, &(&1.path == "owner"))
      spender = Enum.find(fields, &(&1.path == "spender"))
      refute owner.visible
      assert spender.visible
    end

    test "honors a legacy format-level excluded array" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        },
        "display" => %{
          "formats" => %{
            "f(uint256 a)" => %{
              "excluded" => ["#.a"],
              "fields" => [%{"path" => "#.a", "label" => "A", "format" => "raw"}]
            }
          }
        }
      }

      {:ok, descriptor} = Descriptor.parse(raw)
      [field] = descriptor.display.formats["f(uint256 a)"].fields
      refute field.visible
    end

    test "defaults a missing format to :raw" do
      raw = %{
        "context" => %{
          "contract" => %{
            "deployments" => [%{"chainId" => 1, "address" => "0x" <> String.duplicate("11", 20)}]
          }
        },
        "display" => %{
          "formats" => %{"f(uint256 a)" => %{"fields" => [%{"path" => "#.a", "label" => "A"}]}}
        }
      }

      {:ok, descriptor} = Descriptor.parse(raw)
      [field] = descriptor.display.formats["f(uint256 a)"].fields
      assert field.format == :raw
    end
  end
end
