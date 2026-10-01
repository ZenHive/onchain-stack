# Run from packages/onchain with: MIX_ENV=test mix run scripts/capture-recursive-typed.exs
# Compile the pre-9032 implementation under a separate namespace, before invoking it.
revision = "b1ecb86de3562252547995e3d26050f283983144"
{source, 0} = System.cmd("git", ["show", "#{revision}:packages/onchain/lib/cartouche/typed.ex"])
source |> String.replace("Onchain.Typed", "BeforeAlloyTyped") |> Code.compile_string()

node = fn value, children -> %{"value" => value, "children" => children} end

input = %{
  "domain" => %{"name" => "Recursive tree", "version" => "1", "chainId" => 1},
  "types" => %{
    "Node" => [%{"name" => "value", "type" => "uint256"}, %{"name" => "children", "type" => "Node[]"}]
  },
  "value" => node.(1, [node.(2, []), node.(3, [node.(4, [])])])
}

typed = BeforeAlloyTyped.deserialize(input)
encoded = BeforeAlloyTyped.encode(typed)

fixture = %{
  "source_revision" => revision,
  "input" => input,
  "encode" => Onchain.Hex.to_hex(encoded),
  "hash" => Onchain.Hex.to_hex(Onchain.Hash.keccak(encoded)),
  "hash_struct" => Onchain.Hex.to_hex(BeforeAlloyTyped.hash_struct("Node", typed.value, typed.types)),
  "encode_type" => BeforeAlloyTyped.encode_type("Node", typed.types)
}

File.write!("test/support/fixtures/recursive_typed_before_alloy.json", Jason.encode!(fixture, pretty: true) <> "\n")
IO.puts("Captured pre-9032 digest: #{fixture["hash"]}")
