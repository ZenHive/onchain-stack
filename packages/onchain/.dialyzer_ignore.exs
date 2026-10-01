[
  # CloudKMS signers call Goth, which is excluded from the PLT via mix.exs
  # `:plt_ignore_apps`. The `Code.ensure_loaded?/1` guard keeps the optional
  # backend absent when Goth is not present.
  {"lib/onchain/signer/cloud_kms.ex", :unknown_function},
  # ex_secp256k1 0.8.0 specs create_public_key/1 as `{:ok, binary()} | atom()`,
  # but its NIF returns `{:error, :invalid_private_key | :wrong_private_key_size}`
  # (observed 2026-10-01), so these invalid-key clauses do run. Remove both
  # entries once a release carries ayrat555/ex_secp256k1#35.
  {"lib/onchain/signer.ex", :pattern_match, 817},
  {"lib/onchain/aa.ex", :pattern_match, 622}
]
