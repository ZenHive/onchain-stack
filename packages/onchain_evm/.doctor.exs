%Doctor.Config{
  ignore_modules: [
    # Macro DSL modules — Doctor can't check @spec on defmacro or distinguish quoted
    # generated functions from functions defined on the generator itself.
    Onchain.BangHelper,
    Onchain.Contract.Generator
  ]
}
