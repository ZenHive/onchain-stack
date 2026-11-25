import { bytesToHex } from "@noble/hashes/utils.js";

// Browser bundles commonly capture `self` at module top level.
const root = self;

globalThis.rootIsGlobal = () => root === globalThis && bytesToHex(new Uint8Array([1, 2])) === "0102";
