%Doctor.Config{
  ignore_modules: [
    # Macro DSL module — Doctor can't check @spec on defmacro
    Onchain.BangHelper
  ]
}
