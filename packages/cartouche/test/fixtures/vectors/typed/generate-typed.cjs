const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { createRequire } = require("node:module");

if (!process.env.VECTOR_TOOL_ROOT) throw new Error("VECTOR_TOOL_ROOT is required");
const load = createRequire(path.join(process.env.VECTOR_TOOL_ROOT, "package.json"));
const { Wallet, TypedDataEncoder } = load("ethers");
const { hashTypedData, hashStruct } = load("viem");
const { privateKeyToAccount } = load("viem/accounts");
const privateKey = "0x4646464646464646464646464646464646464646464646464646464646464646";
const domain = { name: "Cartouche conformance", version: "1", chainId: 1,
  verifyingContract: "0x3535353535353535353535353535353535353535" };
const types = {
  Order: [ { name: "maker", type: "Person" }, { name: "item", type: "Asset" },
    { name: "people", type: "Person[]" }, { name: "groups", type: "Person[][]" },
    { name: "tag", type: "bytes2" }, { name: "delta", type: "int256" },
    { name: "tick", type: "int24" } ],
  Person: [ { name: "name", type: "string" }, { name: "wallet", type: "address" } ],
  Asset: [ { name: "id", type: "uint256" }, { name: "issuer", type: "Person" } ],
};
const alice = { name: "Alice", wallet: domain.verifyingContract };
const bob = { name: "Bob", wallet: "0x1111111111111111111111111111111111111111" };
const base = { maker: alice, item: { id: 7, issuer: bob }, tag: "0xccdd", delta: -12345, tick: -42 };
const messages = [
  { ...base, people: [alice, bob], groups: [[bob], [], [alice, bob]] },
  { ...base, people: [], groups: [], delta: 0, tick: 8388607 },
];
const generationCommand = "npm install --prefix /tmp/cartouche-vector-tools ethers@6.17.0 viem@2.55.19 && VECTOR_TOOL_ROOT=/tmp/cartouche-vector-tools node test/fixtures/vectors/typed/generate-typed.cjs";

async function main() {
  const wallet = new Wallet(privateKey);
  const account = privateKeyToAccount(privateKey);
  const ethersVectors = [];
  const viemVectors = [];
  for (const message of messages) {
    const input = { domain, types, primaryType: "Order", message };
    const ethersResult = {
      struct_hash: TypedDataEncoder.hashStruct("Order", types, message),
      digest: TypedDataEncoder.hash(domain, types, message),
      signature: await wallet.signTypedData(domain, types, message),
    };
    const viemResult = {
      struct_hash: hashStruct({ data: message, types, primaryType: "Order" }),
      digest: hashTypedData(input),
      signature: await account.signTypedData(input),
    };
    assert.deepEqual(ethersResult, viemResult);
    const common = { ...input, signer: wallet.address.toLowerCase(),
      encode_type: TypedDataEncoder.from(types).encodeType("Order") };
    ethersVectors.push({ ...common, ...ethersResult });
    viemVectors.push({ ...common, ...viemResult });
  }
  for (const [source, version, vectors] of [["ethers", "6.17.0", ethersVectors], ["viem", "2.55.19", viemVectors]]) {
    fs.writeFileSync(path.join(__dirname, `typed-${source}-${version}.json`),
      JSON.stringify({ source, version, generationCommand, privateKey, vectors }, null, 2) + "\n");
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
