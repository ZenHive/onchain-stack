[
  # CloudKMS signers call Goth, which is excluded from the PLT via mix.exs
  # `:plt_ignore_apps`. The `Code.ensure_loaded?/1` guard keeps the optional
  # backend absent when Goth is not present.
  {"lib/cartouche/signer/cloud_kms.ex", :unknown_function},
  {"lib/cartouche/solana/signer/cloud_kms.ex", :unknown_function}
]
