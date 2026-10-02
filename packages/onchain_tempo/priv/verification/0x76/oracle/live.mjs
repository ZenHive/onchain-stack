import { Address, Hex, P256 } from 'ox'
import { TxEnvelopeTempo } from 'ox/tempo'
const privateKey = P256.randomPrivateKey()
const publicKey = P256.getPublicKey({ privateKey })
const sender = Address.fromPublicKey(publicKey).toLowerCase()
const token = '0x20c0000000000000000000000000000000000000'
const tx = {
  type: 'tempo', chainId: 42431, nonce: 0n, nonceKey: 0n, gas: 2000000n,
  maxFeePerGas: 25000000000n, maxPriorityFeePerGas: 1000000000n, feeToken: token,
  calls: [{ to: token, value: 0n, data: Hex.concat('0xa9059cbb', Hex.padLeft(sender, 32), Hex.fromNumber(1, { size: 32 })) }],
}
tx.signature = { type: 'p256', publicKey, prehash: true,
  signature: P256.sign({ payload: TxEnvelopeTempo.getSignPayload(tx), privateKey, hash: true }) }
console.log(JSON.stringify({ sender, raw: TxEnvelopeTempo.serialize(tx), hash: TxEnvelopeTempo.hash(tx) }))
