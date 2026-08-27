import Config

# Per-transport HTTP stubs. Each transport routes its `Req.request/1` through a
# default function plug (`fun(conn)`), so zero-arg doctests and the spawned
# `Cartouche.Filter` GenServer reach the mock with no Req.Test process-ownership
# ceremony (a function plug runs in the caller process). Tests override per
# describe-block via `Application.put_env(:cartouche, <Transport>, plug: ...)` or
# per call via `req_options: [plug: ...]`.
config :cartouche, Cartouche.OpenChain.API, plug: &Cartouche.OpenChainTest.TestClient.call/1
config :cartouche, Cartouche.RPC, plug: &Cartouche.Test.Client.call/1
config :cartouche, Cartouche.Solana.RPC, plug: &Cartouche.Solana.Test.Client.call/1
config :cartouche, :chain_id, :goerli
config :cartouche, :open_chain_base_url, "https://example.com/open-chain"
config :cartouche, :signer, default: {:priv_key, <<1::256>>}
