%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/"], excluded: [~r"/_build/", ~r"/deps/"]},
      strict: true,
      color: true,
      # ExSlop: AI-slop antipatterns. ExDNA.Credo: clone diagnostics inline.
      plugins: [{ExSlop, []}],
      checks: [
        {ExDNA.Credo, []},
        {Credo.Check.Refactor.Nesting, max_nesting: 3, files: %{included: ["test/"]}},
        {Credo.Check.Refactor.Nesting, max_nesting: 2, files: %{included: ["lib/"]}}
      ]
    }
  ]
}
