# `:debug_namespace` is excluded alongside `:integration` because the archive
# node deliberately serves no `debug_*` methods (DoS surface). Opt in with
# `mix test --only debug_namespace` against a node that enables them — see
# `test/rpc_debug_namespace_test.exs`.
#
# `:dev_node` is excluded because it needs a key-holding node (Anvil, Hardhat,
# geth --dev) rather than the mainnet archive node the `:integration` lane
# pins. Opt in with `mix test.json --only dev_node`, setting `CARTOUCHE_DEV_NODE_URL`
# or leaving it unset to let the lane boot a local anvil — see
# `test/rpc_dev_node_test.exs`.
ExUnit.start(exclude: [:integration, :debug_namespace, :dev_node])
