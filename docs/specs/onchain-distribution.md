# Native distribution and Rust supply chain

How the in-repo NIF crates are built, shipped and gated, and how in-family
dependencies resolve for development versus publishing. Status is `active`. Each rule's source follows it. DIST-5, DIST-8, DIST-10 and DIST-16 are
release-time checks with no ExUnit test (see each rule); the rest are tagged tests.

DIST-1: The precompiled target set is exactly aarch64/x86_64 Darwin, aarch64/x86_64 GNU/Linux and x86_64 musl at NIF 2.15; `Onchain.Precompiled.targets/0` matches `scripts/build-precompiled.sh`, and no Windows target is declared.
  Source: packages/onchain/lib/onchain/precompiled.ex; task 9031 (five targets).

DIST-2: A checksum mismatch or a missing checksum entry fails the NIF load; neither ever falls back to a source build.
  Source: Onchain.Precompiled moduledoc; task 9043 (acceptance criterion 2).

DIST-3: A Hex-installed package never source-builds because its checksum file is missing; the load fails instead.
  Source: Onchain.Precompiled.force_build?/4; task 9043 (acceptance criterion 2).

DIST-4: With the `.onchain-monorepo-root` marker present and `ONCHAIN_PUBLISH` not `1`, core source-builds its NIF even when checksums are committed and declares Rustler non-optional; onchain_evm's crates keep downloading when their checksums exist.
  Source: task 9043 (1ead589); Onchain.Precompiled; packages/onchain/CLAUDE.md.

DIST-5: A fresh clone with an empty rustler_precompiled cache and no build environment variable compiles at the repo root and in all seven packages.
  Source: task 9043 (acceptance criterion 1; broken since c9c7256).
  Verified by: a fresh-clone compile; no automated test.

DIST-6: Core onchain refuses to compile on a host outside the shipped target set.
  Source: Onchain.Precompiled.opts/1.

DIST-7: `ONCHAIN_BUILD=1` force-builds onchain's crate and `ONCHAIN_EVM_BUILD=1` onchain_evm's crates; neither variable affects the other package.
  Source: Onchain.Precompiled; packages/onchain/CLAUDE.md; task 9043 (acceptance criterion 3).

DIST-8: onchain's published tarball declares rustler optional, ships `checksum-Elixir.Onchain.ABI.Native.exs`, and compiles in a fresh consumer without cargo on PATH.
  Source: task 9031 (acceptance criterion 4); task 9043 (acceptance criterion 2); packages/onchain/CLAUDE.md (publish-time verification).
  Verified by: bin/publish-prep.sh check onchain plus a fresh-consumer compile; no ExUnit test.

DIST-9: `sibling/2,3` resolves an in-family dependency to its path only when the `.onchain-monorepo-root` marker exists and `ONCHAIN_PUBLISH` is not `1`, never by the sibling directory's existence.
  Source: root CLAUDE.md § The sibling/3 mechanism; packages/*/mix.exs `sibling/3`.

DIST-10: Every publish step runs with `ONCHAIN_PUBLISH=1` and aborts when `mix hex.build` output contains "excluded from the package".
  Source: root CLAUDE.md § The publish trap (onchain_aave 0.3.0 incident); bin/publish-prep.sh.
  Verified by: bin/publish-prep.sh (aborts on "excluded from the package"); no ExUnit test.

DIST-11: Every `sibling(:name, "req")` requirement admits that sibling's in-repo `@version`.
  Source: root CLAUDE.md (`mix onchain.bounds`); lib/mix/tasks/onchain.bounds.ex.

DIST-12: The core onchain NIF carries no Tempo, commonware or solar-parse dependency; Tempo encoding ships in onchain_tempo's own crate and Solidity parsing stays in onchain_evm.
  Source: task 9033 (acceptance criterion 4); task 9034 (acceptance criteria 2-3).

DIST-13: Each package's `mix ci` runs `cargo audit` over every crate under its `native/` and fails on a vulnerability; unmaintained and yanked warnings pass, and any ignore is an explicit, commented per-advisory entry.
  Source: task 9044 (acceptance criteria 1-2).

DIST-14: A missing `cargo-audit` binary fails the gate with its install command, and an offline advisory fetch reports itself instead of reading as clean.
  Source: task 9044 (acceptance criterion 4, body).

DIST-15: onchain's `mix ci` runs `cargo test` and `cargo clippy --all-targets -- -D warnings` over `native/onchain_abi` with onchain_evm's lint policy (`unwrap_used` denied, test code exempt).
  Source: task 9044 (acceptance criterion 3).

DIST-16: Every version of a native package (onchain, onchain_evm, onchain_tempo), including a pure-Elixir patch, has its `<pkg>-v<ver>` GitHub release with precompiled artifacts and a committed checksum file before it is published to Hex.
  Source: root CLAUDE.md publish step 10 (0826fbb); onchain 0.16.1 release (checksums e2168e1); task 9055.
  Verified by: the human release step in root CLAUDE.md; no automated test until task 9055.
