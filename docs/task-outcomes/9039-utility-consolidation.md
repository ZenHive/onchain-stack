# Task 9039 outcome: utility consolidation and 9036 module map

## Consolidation decisions

The survivors are Cartouche.Hex (codec, sigils and sizing), Onchain.Address
(validation plus public-key derivation), Cartouche.HTTP (response normalization
plus both configuration seams), Cartouche.Block (full decoded block plus
fetch/search), Onchain.ERC20 (read/write API plus calldata and simulation helpers),
and ABI (alloy codecs plus hex conveniences). Existing unit/doctest coverage for
both sides now targets the survivors; transfer consumers use ABI.decode_event.
The comma-splitting Onchain.Log implementation is deleted.

The inventory also found Cartouche.Receipt.Log duplicating Cartouche.Filter.Log.
Receipts now use the latter, preserving removed and extra_data fields; receipt
logs may omit removed. Both receipt and filter decoding tests use this survivor.

Candidates retained as distinct responsibilities:

- Onchain.PrivateKey normalizes key input; Cartouche.Keys generates keypairs.
- Onchain.Fees computes recommendations from Cartouche.FeeHistory, an RPC data struct.
- Onchain.Decimal scales arbitrary token amounts; Cartouche.Wei converts named ETH denominations.
- Onchain.Contract.ABI parses JSON ABI for code generation; ABI is the value codec.
- ABI.Event and ABI.AlloyEvents are the public event API and its native adapter;
  ABI.TypeEncoder/TypeDecoder and ABI.Alloy are codec facades and their shared adapter.
- Cartouche.Signature parses/normalizes signature scalars; Transaction.Signature
  attaches signatures to transaction envelopes; RecoveryBit handles parity/EIP-155.
- Cartouche.CloudKMS is the HTTP client; Signer.CloudKMS is the signing backend.
- Cartouche and Onchain are configuration/discovery entry points. Cartouche's
  configuration functions are reserved for Onchain.Configuration; Onchain remains
  the public discovery root. 9036 can fold discovery registration at rename time.

RPC consolidation belongs to **9035**. Its current modules have distinct reserved
names below: the transport-owning Cartouche.RPC becomes Onchain.RPC; the remaining
Onchain.RPC wrappers are reserved as Onchain.RPC.Extensions if still present after
9035. 9035 may eliminate that row by merging the remaining methods before 9036.
This task does not move RPC methods.

Signer consolidation belongs to **the Signer-pair task**; Onchain.Signer is already
absent on this revision and Cartouche.Signer is the survivor. Sleuth consolidation
belongs to **9034**; Onchain.Sleuth is already absent and Cartouche.Sleuth remains,
alongside its distinct generated contract binding Cartouche.Contract.Sleuth.

## Breaking changes for 0.16.0 (release-note payload)

Harness explicitly prohibits CHANGELOG edits. The following is the complete
payload to incorporate into the 0.16.0 changelog when harness records the outcome.

| Removed module | Replacement and migration |
| --- | --- |
| Onchain.Hex | Cartouche.Hex; existing convenience function names are retained alongside the underlying codec API. |
| Cartouche.Address | Onchain.Address; from_public_key/1 is retained. |
| Onchain.HTTP | Cartouche.HTTP; ENS still reads :onchain configuration, other owners read :cartouche. Per-call overrides retain highest priority. |
| Onchain.Block | Cartouche.Block; get_by_number and find_by_timestamp now return full %Cartouche.Block{} values instead of three-field maps. Hashes are 32-byte binaries rather than hex strings. Null RPC blocks remain nil instead of decoding to empty structs; the fetch helper returns :block_not_found. |
| Cartouche.Erc20 | Onchain.ERC20; transfer/3 (the default-options form) is removed; transfer/4 uses the explicit private-key/nonce/chain-id signing API and returns a hex transaction hash rather than raw bytes. For configured-signer execution use exec_trx/3 with CallData.transfer/2. |
| Cartouche.Erc20.Call | Onchain.ERC20.Call; simulation helpers retained. |
| Cartouche.Erc20.CallData | Onchain.ERC20.CallData; binary calldata helpers retained. |
| Onchain.ABI | ABI; hex encode_call, decode_call, decode_error (and bang forms) are now encode_hex_call, decode_hex_call, decode_hex_error to distinguish them from the existing binary APIs. decode_response and decode_types retain their names and shapes. |
| Onchain.Log | ABI.event_signature/1 returns raw topic bytes; ABI.decode_event(signature, data_bytes, topic_bytes, opts) returns {:ok, event_name, string_keyed_args}. Addresses are raw bytes, unnamed parameters use positional string keys, indexed reference values are {:indexed_hash, bytes}. Native error tags replace the old decode_error wrapping; tuple parameters are supported and parameter names are no longer interned as atoms. |
| Cartouche.Receipt.Log | Cartouche.Filter.Log; receipt.logs contains this richer struct, including removed (nil if absent) and extra_data (nil outside filters). |

Onchain.Transfer and Onchain.Tempo.Transfer keep their public checksummed-address
output while decoding through ABI.decode_event. Existing configuration application
keys are unchanged. No namespace-wide rename or version bump is performed here.

## Full inventory for 9036

Every statically declared module under packages/onchain/lib is listed below,
including nested and conditionally compiled modules. Quoted caller-generated
modules (for example Generator's Multicall template) are not library modules.
Future names are unique across all rows. The one necessary exception to the
literal Onchain.* requirement is the Mix task: Mix requires the Mix.Tasks prefix,
so its future module is Mix.Tasks.Onchain.Manifest (command onchain.manifest).
No runtime namespace rename is implemented in this task.

Inventory: **113 modules, 113 unique target names**.

| Current module | Future module | Source under packages/onchain/lib | Owner |
| --- | --- | --- | --- |
| `ABI` | `Onchain.ABI` | `abi.ex` | 9036 |
| `ABI.Alloy` | `Onchain.ABI.Alloy` | `abi/alloy.ex` | 9036 |
| `ABI.AlloyEvents` | `Onchain.ABI.AlloyEvents` | `abi/alloy_events.ex` | 9036 |
| `ABI.Event` | `Onchain.ABI.Event` | `abi/event.ex` | 9036 |
| `ABI.FunctionSelector` | `Onchain.ABI.FunctionSelector` | `abi/function_selector.ex` | 9036 |
| `ABI.Math` | `Onchain.ABI.Math` | `abi/math.ex` | 9036 |
| `ABI.Native` | `Onchain.ABI.Native` | `abi/native.ex` | 9036 |
| `ABI.Parser` | `Onchain.ABI.Parser` | `abi/parser.ex` | 9036 |
| `ABI.TypeDecoder` | `Onchain.ABI.TypeDecoder` | `abi/type_decoder.ex` | 9036 |
| `ABI.TypeDecoder.StrictViolation` | `Onchain.ABI.TypeDecoder.StrictViolation` | `abi/type_decoder.ex` | 9036 |
| `ABI.TypeEncoder` | `Onchain.ABI.TypeEncoder` | `abi/type_encoder.ex` | 9036 |
| `ABI.Validation` | `Onchain.ABI.Validation` | `abi/validation.ex` | 9036 |
| `Cartouche` | `Onchain.Configuration` | `cartouche.ex` | 9036 |
| `Cartouche.Application` | `Onchain.Application` | `cartouche/application.ex` | 9036 |
| `Cartouche.Block` | `Onchain.Block` | `cartouche/block.ex` | 9036 |
| `Cartouche.Block.Withdrawal` | `Onchain.Block.Withdrawal` | `cartouche/block.ex` | 9036 |
| `Cartouche.Chain` | `Onchain.Chain` | `cartouche/chain.ex` | 9036 |
| `Cartouche.CloudKMS` | `Onchain.CloudKMS` | `cartouche/cloud_kms.ex` | 9036 |
| `Cartouche.Contract.Sleuth` | `Onchain.Contract.Sleuth` | `cartouche/contract/sleuth.ex` | 9034, then 9036 |
| `Cartouche.DebugTrace` | `Onchain.DebugTrace` | `cartouche/debug_trace.ex` | 9036 |
| `Cartouche.DebugTrace.StructLog` | `Onchain.DebugTrace.StructLog` | `cartouche/debug_trace.ex` | 9036 |
| `Cartouche.FeeHistory` | `Onchain.FeeHistory` | `cartouche/fee_history.ex` | 9036 |
| `Cartouche.Filter` | `Onchain.Filter` | `cartouche/filter.ex` | 9036 |
| `Cartouche.Filter.Log` | `Onchain.Filter.Log` | `cartouche/filter/log.ex` | 9036 |
| `Cartouche.Hash` | `Onchain.Hash` | `cartouche/hash.ex` | 9036 |
| `Cartouche.Hex` | `Onchain.Hex` | `cartouche/hex.ex` | 9036 |
| `Cartouche.Hex.InvalidHex` | `Onchain.Hex.InvalidHex` | `cartouche/hex.ex` | 9036 |
| `Cartouche.HTTP` | `Onchain.HTTP` | `cartouche/http.ex` | 9036 |
| `Cartouche.Keys` | `Onchain.Keys` | `cartouche/keys.ex` | 9036 |
| `Cartouche.Manifest` | `Onchain.Manifest` | `cartouche/manifest.ex` | 9036 |
| `Cartouche.OpenChain` | `Onchain.OpenChain` | `cartouche/open_chain.ex` | 9036 |
| `Cartouche.OpenChain.Signatures` | `Onchain.OpenChain.Signatures` | `cartouche/open_chain.ex` | 9036 |
| `Cartouche.OpenChain.API` | `Onchain.OpenChain.API` | `cartouche/open_chain.ex` | 9036 |
| `Cartouche.Receipt` | `Onchain.Receipt` | `cartouche/receipt.ex` | 9036 |
| `Cartouche.Recover` | `Onchain.Recover` | `cartouche/recover.ex` | 9036 |
| `Cartouche.RecoveryBit` | `Onchain.RecoveryBit` | `cartouche/recovery_bit.ex` | 9036 |
| `Cartouche.RPC` | `Onchain.RPC` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Configuration` | `Onchain.RPC.Configuration` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Configuration.BlobSchedule` | `Onchain.RPC.Configuration.BlobSchedule` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Configuration.Fork` | `Onchain.RPC.Configuration.Fork` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Capabilities` | `Onchain.RPC.Capabilities` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Capabilities.Head` | `Onchain.RPC.Capabilities.Head` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Capabilities.DeleteStrategy` | `Onchain.RPC.Capabilities.DeleteStrategy` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.Capabilities.Resource` | `Onchain.RPC.Capabilities.Resource` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.SyncStatus` | `Onchain.RPC.SyncStatus` | `cartouche/rpc.ex` | 9035, then 9036 |
| `Cartouche.RPC.DSL` | `Onchain.RPC.DSL` | `cartouche/rpc/dsl.ex` | 9035, then 9036 |
| `Cartouche.RPC.Proof` | `Onchain.RPC.Proof` | `cartouche/rpc/proof.ex` | 9035, then 9036 |
| `Cartouche.RPC.Proof.StorageProof` | `Onchain.RPC.Proof.StorageProof` | `cartouche/rpc/proof.ex` | 9035, then 9036 |
| `Cartouche.Signature` | `Onchain.Signature` | `cartouche/signature.ex` | 9036 |
| `Cartouche.Signer` | `Onchain.Signer` | `cartouche/signer.ex` | Signer-pair task, then 9036 |
| `Cartouche.Signer.Backend` | `Onchain.Signer.Backend` | `cartouche/signer/backend.ex` | Signer-pair task, then 9036 |
| `Cartouche.Signer.CloudKMS` | `Onchain.Signer.CloudKMS` | `cartouche/signer/cloud_kms.ex` | Signer-pair task, then 9036 |
| `Cartouche.Signer.Secp256k1` | `Onchain.Signer.Secp256k1` | `cartouche/signer/secp256k1.ex` | Signer-pair task, then 9036 |
| `Cartouche.Sleuth` | `Onchain.Sleuth` | `cartouche/sleuth.ex` | 9034, then 9036 |
| `Cartouche.Trace` | `Onchain.Trace` | `cartouche/trace.ex` | 9036 |
| `Cartouche.Trace.Action` | `Onchain.Trace.Action` | `cartouche/trace.ex` | 9036 |
| `Cartouche.TraceCall` | `Onchain.TraceCall` | `cartouche/trace_call.ex` | 9036 |
| `Cartouche.Transaction` | `Onchain.Transaction` | `cartouche/transaction.ex` | 9036 |
| `Cartouche.Transaction.V1` | `Onchain.Transaction.V1` | `cartouche/transaction.ex` | 9036 |
| `Cartouche.Transaction.V2` | `Onchain.Transaction.V2` | `cartouche/transaction.ex` | 9036 |
| `Cartouche.Transaction.JsonField` | `Onchain.Transaction.JsonField` | `cartouche/transaction.ex` | 9036 |
| `Cartouche.Transaction.Call` | `Onchain.Transaction.Call` | `cartouche/transaction/call.ex` | 9036 |
| `Cartouche.Transaction.Info` | `Onchain.Transaction.Info` | `cartouche/transaction/info.ex` | 9036 |
| `Cartouche.Transaction.Native` | `Onchain.Transaction.Native` | `cartouche/transaction/native.ex` | 9036 |
| `Cartouche.Transaction.Signature` | `Onchain.Transaction.Signature` | `cartouche/transaction/signature.ex` | 9036 |
| `Cartouche.Transaction.TypedDecode` | `Onchain.Transaction.TypedDecode` | `cartouche/transaction/typed_decode.ex` | 9036 |
| `Cartouche.Transaction.V3` | `Onchain.Transaction.V3` | `cartouche/transaction/v3.ex` | 9036 |
| `Cartouche.Transaction.V4` | `Onchain.Transaction.V4` | `cartouche/transaction/v4.ex` | 9036 |
| `Cartouche.Transaction.V_2930` | `Onchain.Transaction.V_2930` | `cartouche/transaction/v_2930.ex` | 9036 |
| `Cartouche.Typed` | `Onchain.Typed` | `cartouche/typed.ex` | 9036 |
| `Cartouche.Typed.Type` | `Onchain.Typed.Type` | `cartouche/typed.ex` | 9036 |
| `Cartouche.Typed.Domain` | `Onchain.Typed.Domain` | `cartouche/typed.ex` | 9036 |
| `Cartouche.Typed.Native` | `Onchain.Typed.Native` | `cartouche/typed/native.ex` | 9036 |
| `Cartouche.Wei` | `Onchain.Wei` | `cartouche/wei.ex` | 9036 |
| `Mix.Tasks.Hieroglyph.Manifest` | `Mix.Tasks.Onchain.Manifest` | `mix/tasks/hieroglyph.manifest.ex` | 9036 |
| `Onchain` | `Onchain` | `onchain.ex` | 9036 |
| `Onchain.AA` | `Onchain.AA` | `onchain/aa.ex` | 9036 |
| `Onchain.AA.UserOperation` | `Onchain.AA.UserOperation` | `onchain/aa/user_operation.ex` | 9036 |
| `Onchain.Address` | `Onchain.Address` | `onchain/address.ex` | 9036 |
| `Onchain.Contract` | `Onchain.Contract` | `onchain/contract.ex` | 9036 |
| `Onchain.Contract.ABI` | `Onchain.Contract.ABI` | `onchain/contract/abi.ex` | 9036 |
| `Onchain.Contract.Generator` | `Onchain.Contract.Generator` | `onchain/contract/generator.ex` | 9036 |
| `Onchain.Contract.Generator.ResolvedInput` | `Onchain.Contract.Generator.ResolvedInput` | `onchain/contract/generator.ex` | 9036 |
| `Onchain.Decimal` | `Onchain.Decimal` | `onchain/decimal.ex` | 9036 |
| `Onchain.DEX.Router.Pool` | `Onchain.DEX.Router.Pool` | `onchain/dex/router.ex` | 9036 |
| `Onchain.DEX.Router.Route` | `Onchain.DEX.Router.Route` | `onchain/dex/router.ex` | 9036 |
| `Onchain.DEX.Router` | `Onchain.DEX.Router` | `onchain/dex/router.ex` | 9036 |
| `Onchain.ENS` | `Onchain.ENS` | `onchain/ens.ex` | 9036 |
| `Onchain.ENS.CCIP` | `Onchain.ENS.CCIP` | `onchain/ens/ccip.ex` | 9036 |
| `Onchain.ENS.Normalize` | `Onchain.ENS.Normalize` | `onchain/ens/normalize.ex` | 9036 |
| `Onchain.ERC.Helpers` | `Onchain.ERC.Helpers` | `onchain/erc/helpers.ex` | 9036 |
| `Onchain.ERC1155` | `Onchain.ERC1155` | `onchain/erc1155.ex` | 9036 |
| `Onchain.ERC20` | `Onchain.ERC20` | `onchain/erc20.ex` | 9036 |
| `Onchain.ERC20.CallData` | `Onchain.ERC20.CallData` | `onchain/erc20.ex` | 9036 |
| `Onchain.ERC20.Call` | `Onchain.ERC20.Call` | `onchain/erc20.ex` | 9036 |
| `Onchain.ERC721` | `Onchain.ERC721` | `onchain/erc721.ex` | 9036 |
| `Onchain.ERC7730` | `Onchain.ERC7730` | `onchain/erc7730.ex` | 9036 |
| `Onchain.ERC7730.Binding` | `Onchain.ERC7730.Binding` | `onchain/erc7730/binding.ex` | 9036 |
| `Onchain.ERC7730.Descriptor` | `Onchain.ERC7730.Descriptor` | `onchain/erc7730/descriptor.ex` | 9036 |
| `Onchain.ERC7730.Formatter` | `Onchain.ERC7730.Formatter` | `onchain/erc7730/formatter.ex` | 9036 |
| `Onchain.Fees` | `Onchain.Fees` | `onchain/fees.ex` | 9036 |
| `Onchain.MEV` | `Onchain.MEV` | `onchain/mev.ex` | 9036 |
| `Onchain.Multicall` | `Onchain.Multicall` | `onchain/multicall.ex` | 9036 |
| `Onchain.Precompiled` | `Onchain.Precompiled` | `onchain/precompiled.ex` | 9036 |
| `Onchain.PrivateKey` | `Onchain.PrivateKey` | `onchain/private_key.ex` | 9036 |
| `Onchain.RPC` | `Onchain.RPC.Extensions` | `onchain/rpc.ex` | 9035, then 9036 |
| `Onchain.RPC.Codegen` | `Onchain.RPC.Codegen` | `onchain/rpc/codegen.ex` | 9035, then 9036 |
| `Onchain.RPC.Helpers` | `Onchain.RPC.Helpers` | `onchain/rpc/helpers.ex` | 9035, then 9036 |
| `Onchain.RPC.Specs` | `Onchain.RPC.Specs` | `onchain/rpc/specs.ex` | 9035, then 9036 |
| `Onchain.Subscription` | `Onchain.Subscription` | `onchain/subscription.ex` | 9036 |
| `Onchain.Subscription.Parser` | `Onchain.Subscription.Parser` | `onchain/subscription/parser.ex` | 9036 |
| `Onchain.Transfer` | `Onchain.Transfer` | `onchain/transfer.ex` | 9036 |
| `Onchain.Wallet` | `Onchain.Wallet` | `onchain/wallet.ex` | 9036 |

## Verification and acceptance handoff

- Utility and receipt-log duplicate modules are removed; all packages/*/lib
  references point at the survivors. The remaining Onchain.RPC helper decoders
  are part of RPC consolidation (9035), not an additional utility implementation
  introduced here.
- The former Log tests now exercise ABI's richer result/error contracts, indexed
  reference hashes, strict decode, tuple parameters, topic counts and string-key
  parameter names. Transfer and Tempo tests pin their public address shape and
  rejection/skipping of missing or malformed event data.
- Block tests pin full struct results, binary hashes, timestamp search with
  per-call transport overrides, missing blocks and pending blocks. HTTP tests pin
  application-specific configuration and option precedence. ERC-20 tests cover
  calldata round trips, simulation and configured-signer execution via exec_trx.
- Module inventory was extracted from each source AST (including nested and
  conditional modules, excluding quoted templates): 113 rows and unique targets;
  the final AST inventory matches the table. `git diff --check` passes.
- CHANGELOG acceptance is supplied as the release-note payload above because
  harness prohibits editing CHANGELOG. No roadmap files were edited.

`mix check.dispatch` passes in all seven packages (including unchanged onchain_js
as a dependent check). Each alias was inspected: format checking and compilation
with warnings as errors only. Changed Elixir files were formatted with `mix format`.
All packages fetched their locked dependencies successfully; no mix.lock changed.

Focused test results (commands run from the corresponding package directory):

| Package | Command | Result |
| --- | --- | --- |
| onchain | `mix test test/hex_test.exs test/address_test.exs test/http_test.exs test/block_test.exs test/receipt_test.exs test/abi_test.exs test/erc_20_test.exs test/cartouche/erc20/call_test.exs test/onchain test/signer test/rpc_test.exs test/filter_test.exs test/descripex_validation_test.exs test/manifest_test.exs` | 1,302 passed (205 doctests, 1,097 tests); 190 integration/differential/dev-node cases excluded by the existing project defaults |
| onchain_aave | `mix test test/onchain/aave/v4/position_manager_test.exs test/onchain/aave/v4/tokenization_spoke_test.exs test/onchain/aave/v4/oracle_test.exs` | 62 passed |
| onchain_aerodrome | `mix test test/onchain/aerodrome/bindings test/onchain/aerodrome/fixtures_test.exs` | 42 passed |
| onchain_evm | `mix test test/onchain/solidity_test.exs test/onchain/contract/generator_test.exs` | 121 passed |
| onchain_solana | `mix test test/solana/token_test.exs test/solana/rpc_test.exs test/solana/signer/cloud_kms_test.exs test/signer_boundary_test.exs` | 71 passed |
| onchain_tempo | `mix test test/onchain/tempo/transfer_test.exs test/onchain/tempo/tip20_test.exs` | 20 passed |
| onchain_js | `mix test test/onchain_js_test.exs test/onchain_js/descripex_test.exs` | 14 passed |

Live read verification also passed: 22 tests from
`ETHEREUM_API_URL="$ETHEREUM_ALCHEMY_URL" mix test test/onchain/block_integration_test.exs test/onchain/log_integration_test.exs test/onchain/erc20_integration_test.exs --include integration`.
These were read-only hosted Ethereum checks; no live transaction was submitted.

An additional `mix test test/sleuth_test.exs` consumer regression run passed
54 tests. The migrated receipt-log doctest and discovery/filter checks were also
rerun after restoring the survivor's API documentation:
`mix test test/receipt_test.exs test/descripex_validation_test.exs test/manifest_test.exs test/filter_test.exs`
passed 36 cases (3 doctests, 33 tests; 3 existing integration cases excluded).

The ABI manifest was regenerated with `MIX_ENV=test mix hieroglyph.manifest` and
validated with `MIX_ENV=test mix hieroglyph.manifest --check`.
Full `mix ci`, coverage and analyzers were not run: they remain post-merge QA.
Dependency compilation emitted existing third-party warnings; package dispatch
compilation completed successfully with warnings-as-errors. Initial missing/stale
local dependencies were resolved with `MIX_ENV=test mix deps.get`, without changing
committed locks. Early fixture/return-shape failures were corrected and rerun.
