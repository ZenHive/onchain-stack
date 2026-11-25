import { keccak_256 } from "@noble/hashes/sha3.js";

globalThis.broken = (x) => {
  return keccak_256(x
};
