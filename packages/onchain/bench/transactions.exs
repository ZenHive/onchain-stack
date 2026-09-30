alias Cartouche.Transaction
alias Cartouche.Transaction.Native
alias Cartouche.Transaction.V2
alias Cartouche.Transaction.V4

# ONCHAIN_BUILD=1 MIX_ENV=test mix run --no-start bench/transactions.exs before|after
# Benchee is a development dependency; load its compiled dev artifacts for this offline run.
for app <- ~w(benchee deep_merge statistex), do: Code.prepend_path("_build/dev/lib/#{app}/ebin")
Application.ensure_all_started(:crypto)
fixtures = Jason.decode!(File.read!("test/fixtures/vectors/ethers-6.17.0.json"))

transactions =
  Map.new(fixtures["vectors"], fn {name, vector} ->
    {:ok, tx} = Transaction.decode(Cartouche.Hex.decode_hex!(vector["unsigned_serialized"]))
    {name, tx}
  end)

raw = Cartouche.Hex.decode_hex!(fixtures["vectors"]["v2"]["serialized"])

permit =
  Cartouche.Typed.deserialize(%{
    "domain" => %{
      "name" => "Token",
      "version" => "1",
      "chainId" => 1,
      "verifyingContract" => "0x3535353535353535353535353535353535353535"
    },
    "types" => %{
      "Permit" => [
        %{"name" => "owner", "type" => "address"},
        %{"name" => "spender", "type" => "address"},
        %{"name" => "value", "type" => "uint256"},
        %{"name" => "nonce", "type" => "uint256"},
        %{"name" => "deadline", "type" => "uint256"}
      ]
    },
    "value" => %{
      "owner" => "0x3535353535353535353535353535353535353535",
      "spender" => "0x4646464646464646464646464646464646464646",
      "value" => 1_000_000,
      "nonce" => 1,
      "deadline" => 2_000_000_000
    }
  })

[phase] = System.argv()
if phase not in ["before", "after"], do: raise("expected before or after")

if phase == "before" and Code.ensure_loaded?(Native),
  do: raise("the baseline must run against the pre-alloy revision")

hash = fn tx ->
  if phase == "before",
    do: tx |> Transaction.encode() |> Cartouche.Hash.keccak(),
    else: Native.signing_hash(tx)
end

suite =
  Benchee.run(
    %{
      "EIP-1559 encode + signing hash" => fn -> {V2.encode(transactions["v2"]), hash.(transactions["v2"])} end,
      "EIP-7702 encode + signing hash" => fn -> {V4.encode(transactions["v4"]), hash.(transactions["v4"])} end,
      "raw-tx decode" => fn -> Transaction.decode(raw) end,
      "EIP-712 permit hash" => fn ->
        if phase == "before",
          do: permit |> Cartouche.Typed.encode() |> Cartouche.Hash.keccak(),
          else: Cartouche.Typed.Native.signing_hash(permit)
      end
    },
    time: 3,
    warmup: 1,
    memory_time: 1,
    print: [fast_warning: false]
  )

results =
  Map.new(suite.scenarios, fn s ->
    {s.name,
     %{
       median_ips: 1_000_000_000 / s.run_time_data.statistics.median,
       beam_memory_bytes: s.memory_usage_data.statistics.median
     }}
  end)

File.write!(
  "bench/transactions-#{phase}.json",
  Jason.encode!(
    %{revision: "git" |> System.cmd(["rev-parse", "HEAD"]) |> elem(0) |> String.trim(), phase: phase, results: results},
    pretty: true
  )
)
