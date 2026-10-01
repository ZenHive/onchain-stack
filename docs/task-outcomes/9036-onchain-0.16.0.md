# Task 9036 outcome: `ABI.*` / `Cartouche.*` → `Onchain.*`, onchain 0.16.0 prep

## What changed

- Every `ABI.*` module is `Onchain.ABI.*`; every `Cartouche.*` module is
  `Onchain.*`. The full 74-row map is in `packages/onchain/CHANGELOG.md`
  under "Migration".
- Exceptions to the mechanical rule:
  - The `Cartouche` root module is `Onchain.Configuration`; `Onchain` itself
    was already taken.
  - `Cartouche.Trace` is `Onchain.RPC.Trace`, **not** `Onchain.Trace` as the
    9039 map said. onchain_evm already owns `Onchain.Trace` (its `debug_*`
    wrapper), and both modules load together in every evm consumer.
  - `mix hieroglyph.manifest` is `mix onchain.manifest`.
- The 0.15 `Onchain.RPC` defdelegate module was deleted. `Cartouche.RPC`'s
  implementation now *is* `Onchain.RPC`.
- The NIF registers as `Elixir.Onchain.ABI.Native`, and the checksum file is
  `checksum-Elixir.Onchain.ABI.Native.exs`.
- `:cartouche` app-env keys and the `[Cartouche]` log/error prefixes are unchanged.
- The pre-0.16 `.etf` oracle fixtures stay byte-identical.
  `Onchain.Test.LegacyModuleNames` translates their module atoms on replay.
- Gate configs were repointed to the moved paths: `.credo.exs`, `.reach.exs`,
  `.dialyzer_ignore.exs`, both per-library `.doctor-*.exs`, and the
  `onchain.coverage` per-library floors (95/85/95/70).
- Dependents require `onchain ~> 0.16`. Versions in the tree:
  - aave 0.7.0, aerodrome 0.3.0, js 0.5.0.
  - tempo 0.12.0, already pending from task 9033.
  - solana 0.1.0, unpublished.
  - evm stays at 0.7.1 in the tree; see the publish order below.

## Publish order (human, 2FA)

Run each from `packages/<pkg>`, after `bin/publish-prep.sh check <pkg>` is green.

1. **onchain 0.16.0**
   1. `scripts/build-precompiled.sh`
   2. Upload `artifacts/precompiled/v0.16.0/*` to the GitHub release
      `onchain-v0.16.0`.
   3. `mix rustler_precompiled.download Onchain.ABI.Native --all --print`
   4. Commit the checksum.
   5. `ONCHAIN_PUBLISH=1 mix hex.publish`
2. **onchain_evm 0.8.0**
   1. Bump `@version` to 0.8.0 only now; with a checksum file present, the
      bump without uploaded artifacts 404s the build.
   2. Run its `scripts/build-precompiled.sh` and upload to `onchain_evm-v0.8.0`.
   3. `mix rustler_precompiled.download Onchain.EVM --all --print`
   4. `mix rustler_precompiled.download Onchain.Solidity --all --print`
   5. Commit the checksums.
   6. `ONCHAIN_PUBLISH=1 mix hex.publish`
3. **The rest, in any order once onchain is on Hex:**
   - onchain_aave 0.7.0, onchain_aerodrome 0.3.0, onchain_js 0.5.0 and
     onchain_solana 0.1.0: `ONCHAIN_PUBLISH=1 mix hex.publish`.
   - onchain_tempo 0.12.0: first build and upload the `onchain_tempo` NIF
     artifacts to `onchain_tempo-v0.12.0`, then commit
     `checksum-Elixir.Onchain.Tempo.Native.exs`.
4. **mpp** last; it is out of scope here, because it still depends on
   published `cartouche`.
5. **Retire the absorbed packages** (`hex.retire` reason `renamed`):

   ```bash
   mix hex.retire hieroglyph 1.8.1 renamed --message "Merged into onchain 0.16.0 as Onchain.ABI.*"
   mix hex.retire cartouche 0.10.0 renamed --message "Merged into onchain 0.16.0 as Onchain.*"
   ```

   Retire the older versions too if wanted: `mix hex.retire <pkg> <ver> renamed ...`
   for each version listed by `mix hex.info <pkg>`.

Cut the tag `<pkg>-v<ver>` after each confirmed publish.

## Not done here

- External consumers are not migrated (mpp, and `~/.claude/includes/node-portability.md`
  still names `Cartouche.RPC.base_fee/1`).
- Nothing was published or retired.
