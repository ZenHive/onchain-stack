# Transitive deps via onchain are not resolved in the PLT.
# These are false positives — all functions exist at runtime.
[
  # Jason (via onchain)
  ~r/Function Jason\./,
  # Req (via onchain)
  ~r/Function Req\./,
  # Signet (via onchain → signet)
  ~r/Function Signet\./,
  # Onchain modules
  ~r/Function Onchain\./,
  # Descripex (Discoverable macro)
  ~r/Function Descripex\./,
  # TODO(upstream:signet): Signet.Hex spec mismatch causes ABI.encode_call/2 and
  # ABI.decode_response/2 to type as no_return() on success. The wrapper modules
  # below inherit :no_match / :no_return / :no_contracts on every function that
  # touches those helpers. Remove these entries once the upstream Signet.Hex
  # specs are corrected. Same root cause noted in onchain's `abi.ex`.
  {"lib/onchain/aave/pool.ex", :pattern_match},
  {"lib/onchain/aave/pool.ex", :no_return},
  {"lib/onchain/aave/pool.ex", :invalid_contract},
  {"lib/onchain/aave/oracle.ex", :pattern_match},
  {"lib/onchain/aave/oracle.ex", :no_return},
  {"lib/onchain/aave/oracle.ex", :invalid_contract},
  {"lib/onchain/aave/ui_pool_data_provider.ex", :pattern_match},
  {"lib/onchain/aave/ui_pool_data_provider.ex", :no_return},
  {"lib/onchain/aave/ui_pool_data_provider.ex", :invalid_contract},
  {"lib/onchain/aave/faucet.ex", :pattern_match},
  {"lib/onchain/aave/faucet.ex", :no_return},
  {"lib/onchain/aave/faucet.ex", :invalid_contract}
]
