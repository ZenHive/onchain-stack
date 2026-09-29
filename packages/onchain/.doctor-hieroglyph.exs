%Doctor.Config{
  ignore_paths: [~r"^(?!lib/(abi(?:/|\.ex)|mix/tasks/hieroglyph\.)|test/support/)"],
  ignore_modules: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_spec_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
