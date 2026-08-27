// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Sleuth probe: reads token.balanceOf(who) and returns the raw bytes
// as if the constructor had deployed them. Paired with an `eth_call`
// that has no `to` and this contract's creation bytecode as `data`,
// the result is vitalik's live USDC balance.
//
// Compile:
//   solc --optimize --bin test/fixtures/sleuth_balance_query.sol \
//     | awk '/^[0-9a-f]+$/' > test/fixtures/sleuth_balance_query.bin
contract SleuthBalanceQuery {
    constructor(address token, address who) {
        (bool ok, bytes memory ret) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", who)
        );
        require(ok, "staticcall failed");
        assembly {
            return(add(ret, 0x20), mload(ret))
        }
    }
}
