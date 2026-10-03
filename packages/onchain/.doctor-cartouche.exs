%Doctor.Config{
  # Onchain.RPC.DSL is gone. The remaining spec-checked macro is
  # Onchain.RPC.Codegen, which this cartouche-only scan does not include.
  # Former cartouche sources, moved under lib/onchain/ in 0.16.0.
  ignore_paths: [
    ~r"^(?!lib/onchain/(application\.ex|block\.ex|chain\.ex|cloud_kms\.ex|configuration\.ex|contract/sleuth\.ex|debug_trace\.ex|fee_history\.ex|filter(?:/|\.ex)|hash\.ex|hex\.ex|http\.ex|keys\.ex|manifest\.ex|open_chain\.ex|receipt\.ex|recover\.ex|recovery_bit\.ex|rpc\.ex|rpc/proof\.ex|rpc/simulate\.ex|rpc/trace\.ex|signature\.ex|signer(?:/|\.ex)|sleuth\.ex|trace_call\.ex|transaction(?:/|\.ex)|typed(?:/|\.ex)|wei\.ex)|test/support/)"
  ],
  ignore_modules: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
