
# Cartouche Development Doc

## Generating Cartouche contracts

* `i_console.ex`
  * `mix cartouche.gen --prefix cartouche/contract ./sol/out/IConsole.sol/IConsole.json`
* `sleuth.ex`
  * `mix cartouche.gen --prefix cartouche/contract ./priv/Sleuth.json`
  * (The ABI is vendored at `priv/Sleuth.json`. The original source lives at [compound-finance/sleuth](https://github.com/compound-finance/sleuth).)
* `test/support/{block_number,ierc20,rock}.ex`
  * `mix cartouche.gen --prefix cartouche/contract --out ./test/support/ ./test/abi/*.json`
