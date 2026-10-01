%Doctor.Config{
  # Cartouche.RPC.DSL is gone. The remaining spec-checked macro is
  # Onchain.RPC.Codegen, which this cartouche-only scan does not include.
  ignore_paths: [~r"^(?!lib/(cartouche(?:/|\.ex)|mix/cartouche\.)|test/support/)"],
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
