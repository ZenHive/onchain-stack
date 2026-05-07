// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

// Test-only wrapper that exposes the 8 Layer-2 functions of Onchain.Aave.Math
// as external entry points so they can be called via revm with standard ABI
// encoding. Function bodies are inlined verbatim from aave-v3-origin so this
// file is the ground truth for cross-validation.
//
// Source: https://github.com/aave-dao/aave-v3-origin
// Commit: 1e3d70c4151a94166ebc59e2eaa4aff6e6ba6978
// Files:  src/contracts/protocol/libraries/math/WadRayMath.sol (SHA1 258be66e2d4e35dfe6bb2302c2bc98ce75457d9f)
//         src/contracts/protocol/libraries/math/MathUtils.sol  (SHA1 0f94a553f10854030f3908d2fe0ebe8168f05ac4)
// Vendored: 2026-04-22
//
// Deviation from upstream:
//   - calculateLinearInterest is `view` upstream (reads block.timestamp). We
//     expose a 3-arg `calculateLinearInterestAt` that takes `currentTimestamp`
//     explicitly so the test is deterministic (does not depend on revm's
//     block.timestamp). Arithmetic body is identical.
//   - `lastUpdateTimestamp` is declared `uint256` (upstream narrows to uint40).
//     Test inputs stay within Unix-timestamp range, so the narrowing is a no-op.
contract WadRayWrapper {
  uint256 internal constant WAD = 1e18;
  uint256 internal constant HALF_WAD = 0.5e18;

  uint256 internal constant RAY = 1e27;
  uint256 internal constant HALF_RAY = 0.5e27;

  uint256 internal constant WAD_RAY_RATIO = 1e9;

  uint256 internal constant SECONDS_PER_YEAR = 365 days;

  // --- WadRayMath ------------------------------------------------------------

  function rayMul(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly {
      if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_RAY), b))))) {
        revert(0, 0)
      }
      c := div(add(mul(a, b), HALF_RAY), RAY)
    }
  }

  function rayDiv(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly {
      if or(iszero(b), iszero(iszero(gt(a, div(sub(not(0), div(b, 2)), RAY))))) {
        revert(0, 0)
      }
      c := div(add(mul(a, RAY), div(b, 2)), b)
    }
  }

  function wadMul(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly {
      if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_WAD), b))))) {
        revert(0, 0)
      }
      c := div(add(mul(a, b), HALF_WAD), WAD)
    }
  }

  function wadDiv(uint256 a, uint256 b) external pure returns (uint256 c) {
    assembly {
      if or(iszero(b), iszero(iszero(gt(a, div(sub(not(0), div(b, 2)), WAD))))) {
        revert(0, 0)
      }
      c := div(add(mul(a, WAD), div(b, 2)), b)
    }
  }

  function rayToWad(uint256 a) external pure returns (uint256 b) {
    assembly {
      b := div(a, WAD_RAY_RATIO)
      let remainder := mod(a, WAD_RAY_RATIO)
      if iszero(lt(remainder, div(WAD_RAY_RATIO, 2))) {
        b := add(b, 1)
      }
    }
  }

  function wadToRay(uint256 a) external pure returns (uint256 b) {
    assembly {
      b := mul(a, WAD_RAY_RATIO)
      if iszero(eq(div(b, WAD_RAY_RATIO), a)) {
        revert(0, 0)
      }
    }
  }

  // --- MathUtils -------------------------------------------------------------

  // 3-arg override of the upstream `view` function so the test is deterministic.
  // Formula body is identical to MathUtils.calculateLinearInterest(rate, last)
  // with block.timestamp substituted by the explicit currentTimestamp arg.
  function calculateLinearInterestAt(
    uint256 rate,
    uint256 lastUpdateTimestamp,
    uint256 currentTimestamp
  ) external pure returns (uint256) {
    uint256 result = rate * (currentTimestamp - lastUpdateTimestamp);
    unchecked {
      result = result / SECONDS_PER_YEAR;
    }
    return RAY + result;
  }

  // Matches upstream's already-pure 3-arg overload.
  function calculateCompoundedInterest(
    uint256 rate,
    uint256 lastUpdateTimestamp,
    uint256 currentTimestamp
  ) external pure returns (uint256) {
    uint256 exp = currentTimestamp - lastUpdateTimestamp;

    if (exp == 0) {
      return RAY;
    }

    unchecked {
      uint256 x = (rate * exp) / SECONDS_PER_YEAR;
      return RAY + x + _rayMul(x, x / 2 + _rayMul(x, x / 6));
    }
  }

  // Internal helper so the compound formula resolves through the same
  // assembly path as WadRayMath.rayMul (keeps bit-exactness explicit).
  function _rayMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    assembly {
      if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_RAY), b))))) {
        revert(0, 0)
      }
      c := div(add(mul(a, b), HALF_RAY), RAY)
    }
  }
}
