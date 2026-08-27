// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

// Test-only wrapper that exposes the public Onchain.Aave.Math.V4 surface as
// external entry points so they can be called via revm with standard ABI
// encoding. Function bodies are inlined from aave/aave-v4 so this file is the
// ground truth for V4 cross-validation.
//
// Source: https://github.com/aave/aave-v4
// Commit: 2524fe4018a42750300e114f2a8c4355df62a878
// Files:  src/libraries/math/WadRayMath.sol     (SHA1 b17a947b9718948f683bfe6c653eb2af2145d89d)
//         src/libraries/math/MathUtils.sol      (SHA1 b094495accdde134725c75e046036adceefd9324)
//         src/libraries/math/PercentageMath.sol (SHA1 51fe6c8d6ef642c7c39bbd9d4b37449816ceca83)
//         src/spoke/libraries/LiquidationLogic.sol (SHA1 2b563f34bc66baa97576e153c43a929423b53174)
// Vendored: 2026-08-22
//
// Deviation from upstream:
//   - calculateLinearInterest is `view` upstream (reads block.timestamp). We
//     expose a 3-arg `calculateLinearInterestAt` that takes `currentTimestamp`
//     explicitly so the test is deterministic. Arithmetic body is identical
//     to MathUtils.calculateLinearInterest with timestamp() substituted.
//   - `rate` / `lastUpdateTimestamp` are uint256 (upstream narrows to uint96 /
//     uint40). Test inputs stay within those ranges, so the narrowing is a no-op.
contract V4MathWrapper {
  uint256 internal constant WAD = 1e18;
  uint256 internal constant RAY = 1e27;
  uint256 internal constant PERCENTAGE_FACTOR = 1e4;
  uint256 internal constant SECONDS_PER_YEAR = 365 days;
  uint64 internal constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

  // --- WadRayMath ----------------------------------------------------------

  function wadMulDown(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      c := div(mul(a, b), WAD)
    }
  }

  function wadMulUp(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      c := mul(a, b)
      c := add(div(c, WAD), gt(mod(c, WAD), 0))
    }
  }

  function wadDivDown(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if or(iszero(b), iszero(iszero(gt(a, div(not(0), WAD))))) {
        revert(0, 0)
      }
      c := div(mul(a, WAD), b)
    }
  }

  function wadDivUp(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if or(iszero(b), iszero(iszero(gt(a, div(not(0), WAD))))) {
        revert(0, 0)
      }
      c := mul(a, WAD)
      c := add(div(c, b), gt(mod(c, b), 0))
    }
  }

  function rayMulDown(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      c := div(mul(a, b), RAY)
    }
  }

  function rayMulUp(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      c := mul(a, b)
      c := add(div(c, RAY), gt(mod(c, RAY), 0))
    }
  }

  function rayDivDown(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if or(iszero(b), iszero(iszero(gt(a, div(not(0), RAY))))) {
        revert(0, 0)
      }
      c := div(mul(a, RAY), b)
    }
  }

  function rayDivUp(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if or(iszero(b), iszero(iszero(gt(a, div(not(0), RAY))))) {
        revert(0, 0)
      }
      c := mul(a, RAY)
      c := add(div(c, b), gt(mod(c, b), 0))
    }
  }

  function toWad(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      b := mul(a, WAD)
      if iszero(eq(div(b, WAD), a)) {
        revert(0, 0)
      }
    }
  }

  function toRay(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      b := mul(a, RAY)
      if iszero(eq(div(b, RAY), a)) {
        revert(0, 0)
      }
    }
  }

  function fromWadDown(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      b := div(a, WAD)
    }
  }

  function fromRayUp(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      b := add(div(a, RAY), gt(mod(a, RAY), 0))
    }
  }

  function bpsToWad(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      let factor := div(WAD, PERCENTAGE_FACTOR)
      b := mul(a, factor)
      if iszero(eq(div(b, factor), a)) {
        revert(0, 0)
      }
    }
  }

  function bpsToRay(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      let factor := div(RAY, PERCENTAGE_FACTOR)
      b := mul(a, factor)
      if iszero(eq(div(b, factor), a)) {
        revert(0, 0)
      }
    }
  }

  function roundRayUp(uint256 a) external pure returns (uint256 b) {
    assembly ("memory-safe") {
      let c := add(div(a, RAY), gt(mod(a, RAY), 0))
      b := mul(c, RAY)
      if iszero(eq(div(b, RAY), c)) {
        revert(0, 0)
      }
    }
  }

  // --- MathUtils -----------------------------------------------------------

  function calculateLinearInterestAt(
    uint256 rate,
    uint256 lastUpdateTimestamp,
    uint256 currentTimestamp
  ) external pure returns (uint256 result) {
    assembly ("memory-safe") {
      if gt(lastUpdateTimestamp, currentTimestamp) {
        revert(0, 0)
      }
      result := sub(currentTimestamp, lastUpdateTimestamp)
      result := add(div(mul(rate, result), SECONDS_PER_YEAR), RAY)
    }
  }

  function min(uint256 a, uint256 b) external pure returns (uint256 result) {
    assembly ("memory-safe") {
      result := xor(b, mul(xor(a, b), lt(a, b)))
    }
  }

  function zeroFloorSub(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      c := mul(sub(a, b), gt(a, b))
    }
  }

  function add(uint256 a, int256 b) external pure returns (uint256) {
    if (b >= 0) return a + uint256(b);
    return a - uint256(-b);
  }

  function divUp(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly ("memory-safe") {
      if iszero(b) {
        revert(0, 0)
      }
      c := add(div(a, b), gt(mod(a, b), 0))
    }
  }

  function mulDivDown(uint256 a, uint256 b, uint256 c) external pure returns (uint256 d) {
    assembly ("memory-safe") {
      if iszero(c) {
        revert(0, 0)
      }
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      d := div(mul(a, b), c)
    }
  }

  function mulDivUp(uint256 a, uint256 b, uint256 c) external pure returns (uint256 d) {
    assembly ("memory-safe") {
      if iszero(c) {
        revert(0, 0)
      }
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      d := mul(a, b)
      d := add(div(d, c), gt(mod(d, c), 0))
    }
  }

  // --- LiquidationLogic.calculateLiquidationBonus --------------------------

  function calculateLiquidationBonus(
    uint256 healthFactorForMaxBonus,
    uint256 liquidationBonusFactor,
    uint256 healthFactor,
    uint256 maxLiquidationBonus
  ) external pure returns (uint256) {
    if (healthFactor <= healthFactorForMaxBonus) {
      return maxLiquidationBonus;
    }

    uint256 minLiquidationBonus = _percentMulDown(
      maxLiquidationBonus - PERCENTAGE_FACTOR,
      liquidationBonusFactor
    ) + PERCENTAGE_FACTOR;

    return
      minLiquidationBonus +
      _mulDivDown(
        maxLiquidationBonus - minLiquidationBonus,
        HEALTH_FACTOR_LIQUIDATION_THRESHOLD - healthFactor,
        HEALTH_FACTOR_LIQUIDATION_THRESHOLD - healthFactorForMaxBonus
      );
  }

  function _percentMulDown(
    uint256 value,
    uint256 percentage
  ) internal pure returns (uint256 result) {
    assembly ("memory-safe") {
      if iszero(or(iszero(percentage), iszero(gt(value, div(not(0), percentage))))) {
        revert(0, 0)
      }
      result := div(mul(value, percentage), PERCENTAGE_FACTOR)
    }
  }

  function _mulDivDown(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 d) {
    assembly ("memory-safe") {
      if iszero(c) {
        revert(0, 0)
      }
      if iszero(or(iszero(b), iszero(gt(a, div(not(0), b))))) {
        revert(0, 0)
      }
      d := div(mul(a, b), c)
    }
  }
}
