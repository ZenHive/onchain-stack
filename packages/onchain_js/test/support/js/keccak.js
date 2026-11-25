import { keccak_256 } from "@noble/hashes/sha3.js";
import { bytesToHex, utf8ToBytes } from "@noble/hashes/utils.js";

globalThis.keccak256Hex = (text) => bytesToHex(keccak_256(utf8ToBytes(text)));
