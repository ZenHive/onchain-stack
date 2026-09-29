import Config

config :cartouche, Onchain.Solana.RPC, plug: &Onchain.Solana.Test.Client.call/1
