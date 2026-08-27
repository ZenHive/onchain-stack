# Planted-mutant corpus for `mix hieroglyph.mutants` (roadmap task 44).
#
# Each entry is a single-site edit to `lib/` that a correct ABI implementation
# must not survive. `find` must occur EXACTLY ONCE in `file`; the runner aborts
# rather than guess when an anchor has drifted, so a refactor that moves a site
# fails loudly instead of silently disarming the mutant.
#
# `expect` is the recorded outcome of the last full run and is what
# `docs/abi-verification-ledger.md` explains:
#
#   :killed   — the task-44 vectors alone must fail on this mutant.
#   :survivor — the task-44 vectors do NOT reach this site; the ledger records
#               the classification and the evidence behind it.
[
  %{
    id: "offset-word-zeroed",
    file: "lib/abi/type_encoder.ex",
    site: "encode_tuple_element/2 — the head slot of a dynamic element",
    mutation: "write a constant 0 instead of the running tail position",
    expect: :killed,
    find: "head <> encode_uint(tail_position, 256),",
    replace: "head <> encode_uint(0, 256),"
  },
  %{
    id: "offset-never-advances",
    file: "lib/abi/type_encoder.ex",
    site: "encode_tuple_element/2 — the tail-position accumulator",
    mutation: "drop `+ byte_size(el)`, so every dynamic element points at the first tail",
    expect: :killed,
    find: "tail_position + byte_size(el)",
    replace: "tail_position"
  },
  %{
    id: "tail-start-off-by-one-word",
    file: "lib/abi/type_encoder.ex",
    site: "encode_type/2 for {:tuple, types} — where the tail begins",
    mutation: "start the tail one 32-byte word too late",
    expect: :killed,
    find: "    tail_start = count(types) * 32",
    replace: "    tail_start = count(types) * 32 + 32"
  },
  %{
    id: "selector-slice-shifted",
    file: "lib/abi.ex",
    site: "method_id/1 — the 4-byte slice of the keccak digest",
    mutation: "take bytes 1..4 of the digest instead of 0..3",
    expect: :killed,
    find: "    <<id::binary-size(4), _::binary>> =",
    replace: "    <<_skip::binary-size(1), id::binary-size(4), _::binary>> ="
  },
  %{
    id: "keccak-digest-reversed",
    file: "lib/abi/math.ex",
    site: "kec/1 — the keccak-256 digest",
    mutation: "return the digest byte-reversed",
    expect: :killed,
    find: "    ExSha3.keccak_256(data)",
    replace: "    data |> ExSha3.keccak_256() |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()"
  },
  %{
    id: "event-signature-annotates-indexed",
    file: "lib/abi/event.ex",
    site: "event_signature/1 — the canonical string that is hashed into topic0",
    mutation: "render the `indexed` keyword into the hashed signature",
    expect: :killed,
    find: "    function_selector\n    |> FunctionSelector.encode()\n    |> Math.kec()",
    replace: "    function_selector\n    |> FunctionSelector.encode(true)\n    |> Math.kec()"
  },
  %{
    id: "indexed-tuple-not-hashed",
    file: "lib/abi/event.ex",
    site: "reference_type?/1 — the tuple clause",
    mutation: "delete the clause, so an indexed tuple is treated as a value type",
    expect: :killed,
    find: "  defp reference_type?({:tuple, _}), do: true\n",
    replace: ""
  },
  %{
    id: "mod-negative-branch",
    file: "lib/abi/math.ex",
    site: "mod/2 — the negative-dividend branch",
    mutation: "return Erlang's `rem/2` (which keeps the sign) instead of a floored modulus",
    expect: :survivor,
    find: "  def mod(x, n) when x < 0, do: rem(rem(x, n) + n, n)",
    replace: "  def mod(x, n) when x < 0, do: rem(x, n)"
  }
]
