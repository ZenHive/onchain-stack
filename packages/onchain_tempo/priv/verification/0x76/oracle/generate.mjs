import { writeFileSync } from 'node:fs'
import { Address, Hex, P256, Secp256k1, WebAuthnP256 } from 'ox'
import { AuthorizationTempo, KeyAuthorization, TxEnvelopeTempo } from 'ox/tempo'

// Public deterministic test keys. Never use these for funded accounts.
const privateKey = `0x${'01'.padStart(64, '0')}`
const feeKey = `0x${'02'.padStart(64, '0')}`
const user = Address.fromPublicKey(Secp256k1.getPublicKey({ privateKey: feeKey })).toLowerCase()
const token = '0x20c0000000000000000000000000000000000000'
const publicKey = P256.getPublicKey({ privateKey })
const base = {
  type: 'tempo', chainId: 42431, nonce: 7n, nonceKey: 0n, gas: 500000n,
  maxFeePerGas: 25000000000n, maxPriorityFeePerGas: 1000000000n,
  calls: [{ to: token, value: 0n, data: '0x' }], feePayerSignature: null,
}
function primitive(type, payload, prehash = true) {
  if (type === 'secp256k1') return { type, signature: Secp256k1.sign({ payload, privateKey }) }
  if (type === 'p256') return { type, publicKey, prehash, signature: P256.sign({ payload, privateKey, hash: prehash }) }
  const { metadata, payload: webPayload } = WebAuthnP256.getSignPayload({
    challenge: payload, rpId: 'example.com', origin: 'https://example.com', flag: 5, signCount: 0,
  })
  return { type, publicKey, metadata, signature: P256.sign({ payload: webPayload, privateKey, hash: true }) }
}
function vector(envelope, type, version, prehash = true) {
  const signingHash = TxEnvelopeTempo.getSignPayload(envelope)
  const payload = version === 'v2' ? TxEnvelopeTempo.getSignPayload(envelope, { from: user }) : signingHash
  const inner = primitive(type, payload, prehash)
  const signature = version ? { type: 'keychain', version, userAddress: user, inner } : inner
  const sender = version ? user : (type === 'secp256k1' ? Secp256k1.recoverAddress({ payload, signature: inner.signature }) : Address.fromPublicKey(publicKey)).toLowerCase()
  const signed = { ...envelope, signature }
  const feeEnvelope = { ...signed, feeToken: token }
  const feeHash = TxEnvelopeTempo.getFeePayerSignPayload(feeEnvelope, { sender })
  const feeSignature = Secp256k1.sign({ payload: feeHash, privateKey: feeKey })
  return {
    serialized: TxEnvelopeTempo.serialize(signed), signing_hash: signingHash,
    tx_hash: TxEnvelopeTempo.hash(signed), sender,
    fee_payer_hash: feeHash,
    fee_payer_preimage: TxEnvelopeTempo.serialize({ ...feeEnvelope, signature: undefined }, { format: 'feePayer', sender }),
    cosigned: TxEnvelopeTempo.serialize({ ...feeEnvelope, feePayerSignature: feeSignature }),
    ...(envelope.keyAuthorization ? { key_hash: KeyAuthorization.getSignPayload(envelope.keyAuthorization) } : {}),
  }
}
const cases = {}
for (const type of ['secp256k1', 'p256', 'webAuthn']) cases[type] = vector(base, type)
for (const version of ['v1', 'v2']) {
  for (const inner of ['secp256k1', 'p256', 'webAuthn']) cases[`keychain_${version}_${inner}`] = vector(base, inner, version)
}
for (const type of ['secp256k1', 'p256', 'webAuthn']) {
  const authorization = { chainId: 42431n, type, address: user, expiry: 2000000000,
    limits: [{ token, limit: 123n }], scopes: [], witness: `0x${'11'.repeat(32)}` }
  authorization.signature = primitive(type, KeyAuthorization.getSignPayload(authorization))
  cases[`authorization_${type}`] = vector({ ...base, keyAuthorization: authorization }, type)
}
cases.p256_unhashed = vector(base, 'p256', undefined, false)
const authorization = { chainId: 42431n, address: user, nonce: 9n }
authorization.signature = primitive('p256', AuthorizationTempo.getSignPayload(authorization))
const scoped = { chainId: 42431n, type: 'p256', address: user, account: user, isAdmin: true,
  expiry: 2000000000, limits: [{ token, limit: 123n, period: 3600 }],
  scopes: [{ address: token, selector: '0xa9059cbb', recipients: [user] }, { address: user }],
  witness: `0x${'22'.repeat(32)}` }
scoped.signature = primitive('webAuthn', KeyAuthorization.getSignPayload(scoped))
cases.all_fields = vector({ ...base, nonceKey: 12n, validBefore: 2000000000, validAfter: 100,
  accessList: [{ address: token, storageKeys: [`0x${'33'.repeat(32)}`] }],
  authorizationList: [authorization], keyAuthorization: scoped }, 'p256')
cases.contract_creation = vector({ ...base, calls: [{ value: 1n, data: '0x6000' }] }, 'p256')
writeFileSync(new URL('../all_signatures.json', import.meta.url), JSON.stringify({
  oracle: { package: 'ox', version: '1.8.5', generator: 'oracle/generate.mjs' },
  fee_payer_private_key: feeKey, fee_token: token, cases,
}, null, 2) + '\n')
console.log(`Generated ${Object.keys(cases).length} ox vectors`)
