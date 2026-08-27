const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");

const ethersVersion = "6.17.0";
const viemVersion = "2.55.19";
const toolRoot = process.env.VECTOR_TOOL_ROOT;

if (!toolRoot) {
  throw new Error("VECTOR_TOOL_ROOT must point to the npm prefix containing ethers and viem");
}

const load = createRequire(path.join(toolRoot, "package.json"));
const { Wallet, Transaction, concat, encodeRlp, keccak256: ethersKeccak256 } = load("ethers");
const {
  keccak256: viemKeccak256,
  recoverTransactionAddress,
  serializeTransaction,
} = load("viem");
const { privateKeyToAccount } = load("viem/accounts");

const generationCommand =
  "npm install --prefix /tmp/cartouche-vector-tools ethers@6.17.0 viem@2.55.19 && " +
  "VECTOR_TOOL_ROOT=/tmp/cartouche-vector-tools node test/fixtures/vectors/generate.cjs";
const privateKey = "0x4646464646464646464646464646464646464646464646464646464646464646";
const authorityPrivateKey = "0x1111111111111111111111111111111111111111111111111111111111111111";
const destination = "0x3535353535353535353535353535353535353535";
const authorizationAddress = "0x2222222222222222222222222222222222222222";
const maximalAddress = "0xffffffffffffffffffffffffffffffffffffffff";
const maximalWord = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
const accessList = [{ address: maximalAddress, storageKeys: [maximalWord] }];
const blobVersionedHash = "0x01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

function canonicalFields(name, authorization) {
  const common = {
    chain_id: "1",
    gas_limit: "100000",
    destination,
    data: "0x1234",
    access_list: [{ address: maximalAddress, storage_keys: [maximalWord] }],
  };

  switch (name) {
    case "v1":
      return {
        chain_id: "1",
        nonce: "9",
        gas_price: "20000000000",
        gas_limit: "21000",
        destination,
        amount: "1000000000000000000",
        data: "0x",
      };
    case "v2930":
      return { ...common, nonce: "1", gas_price: "20000000000", amount: "2" };
    case "v2":
      return {
        ...common,
        nonce: "2",
        max_priority_fee_per_gas: "1000000000",
        max_fee_per_gas: "20000000000",
        amount: "3",
      };
    case "v3":
      return {
        ...common,
        nonce: "3",
        max_priority_fee_per_gas: "1000000000",
        max_fee_per_gas: "20000000000",
        amount: "4",
        max_fee_per_blob_gas: "7",
        blob_versioned_hashes: [blobVersionedHash],
      };
    case "v4":
      return {
        ...common,
        nonce: "4",
        max_priority_fee_per_gas: "1000000000",
        max_fee_per_gas: "20000000000",
        amount: "5",
        authorization_list: [authorization],
      };
    default:
      throw new Error(`unknown transaction version: ${name}`);
  }
}

function fixture(source, version, vectors, authority, authorization) {
  return {
    schema_version: 1,
    provenance: {
      source_implementation: source,
      source_url:
        source === "ethers"
          ? "https://github.com/ethers-io/ethers.js"
          : "https://github.com/wevm/viem",
      exact_version: version,
      generation_command: generationCommand,
    },
    signer: "0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F",
    authority,
    authorization,
    vectors,
  };
}

function writeFixture(filename, value) {
  fs.writeFileSync(path.join(__dirname, filename), `${JSON.stringify(value, null, 2)}\n`);
}

async function generateEthers() {
  const wallet = new Wallet(privateKey);
  const authority = new Wallet(authorityPrivateKey);
  const authorizationCore = ["0x01", authorizationAddress, "0x07"];
  const authorizationSignature = authority.signingKey.sign(
    ethersKeccak256(concat(["0x05", encodeRlp(authorizationCore)])),
  );
  const authorization = {
    chainId: 1n,
    address: authorizationAddress,
    nonce: 7n,
    signature: authorizationSignature,
  };
  const canonicalAuthorization = {
    chain_id: "1",
    address: authorizationAddress,
    nonce: "7",
    y_parity: authorizationSignature.yParity,
    r: authorizationSignature.r,
    s: authorizationSignature.s,
  };
  const definitions = transactionDefinitions(authorization, "ethers");
  const vectors = {};

  for (const [name, fields] of definitions) {
    const transaction = Transaction.from(fields);
    const unsignedSerialized = transaction.unsignedSerialized;
    transaction.signature = wallet.signingKey.sign(transaction.unsignedHash);
    vectors[name] = {
      fields: canonicalFields(name, canonicalAuthorization),
      unsigned_serialized: unsignedSerialized,
      unsigned_hash: transaction.unsignedHash,
      serialized: transaction.serialized,
      hash: transaction.hash,
      from: transaction.from,
    };
  }

  return fixture("ethers", ethersVersion, vectors, authority.address, canonicalAuthorization);
}

async function generateViem() {
  const account = privateKeyToAccount(privateKey);
  const authority = privateKeyToAccount(authorityPrivateKey);
  const authorization = await authority.signAuthorization({
    chainId: 1,
    nonce: 7,
    contractAddress: authorizationAddress,
  });
  const canonicalAuthorization = {
    chain_id: authorization.chainId.toString(),
    address: authorization.address,
    nonce: authorization.nonce.toString(),
    y_parity: authorization.yParity,
    r: authorization.r,
    s: authorization.s,
  };
  const definitions = transactionDefinitions(authorization, "viem");
  const vectors = {};

  for (const [name, transaction] of definitions) {
    const unsignedSerialized = serializeTransaction(transaction);
    const serialized = await account.signTransaction(transaction);
    vectors[name] = {
      fields: canonicalFields(name, canonicalAuthorization),
      unsigned_serialized: unsignedSerialized,
      unsigned_hash: viemKeccak256(unsignedSerialized),
      serialized,
      hash: viemKeccak256(serialized),
      from: await recoverTransactionAddress({ serializedTransaction: serialized }),
    };
  }

  return fixture("viem", viemVersion, vectors, authority.address, canonicalAuthorization);
}

function transactionDefinitions(authorization, implementation) {
  const type = (ethersType, viemType) => (implementation === "ethers" ? ethersType : viemType);
  const gasField = implementation === "ethers" ? "gasLimit" : "gas";
  const common = {
    chainId: 1,
    to: destination,
    data: "0x1234",
    accessList,
    [gasField]: 100000n,
  };

  return [
    [
      "v1",
      {
        type: type(0, "legacy"),
        chainId: 1,
        nonce: 9,
        gasPrice: 20000000000n,
        [gasField]: 21000n,
        to: destination,
        value: 1000000000000000000n,
        data: "0x",
      },
    ],
    [
      "v2930",
      { ...common, type: type(1, "eip2930"), nonce: 1, gasPrice: 20000000000n, value: 2n },
    ],
    [
      "v2",
      {
        ...common,
        type: type(2, "eip1559"),
        nonce: 2,
        maxPriorityFeePerGas: 1000000000n,
        maxFeePerGas: 20000000000n,
        value: 3n,
      },
    ],
    [
      "v3",
      {
        ...common,
        type: type(3, "eip4844"),
        nonce: 3,
        maxPriorityFeePerGas: 1000000000n,
        maxFeePerGas: 20000000000n,
        maxFeePerBlobGas: 7n,
        value: 4n,
        blobVersionedHashes: [blobVersionedHash],
        ...(implementation === "viem" ? { sidecars: false } : {}),
      },
    ],
    [
      "v4",
      {
        ...common,
        type: type(4, "eip7702"),
        nonce: 4,
        maxPriorityFeePerGas: 1000000000n,
        maxFeePerGas: 20000000000n,
        value: 5n,
        authorizationList: [authorization],
      },
    ],
  ];
}

Promise.all([generateEthers(), generateViem()]).then(([ethersFixture, viemFixture]) => {
  writeFixture("ethers-6.17.0.json", ethersFixture);
  writeFixture("viem-2.55.19.json", viemFixture);
});
