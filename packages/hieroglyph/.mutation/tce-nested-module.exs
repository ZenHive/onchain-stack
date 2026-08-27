# Minimal reproduction of the muex TCE unsoundness found by roadmap task 46.
#
# Muex.Tce.compile_binary/2 keeps only the first module the compiler returns
# (`[{module, binary} | _]`). When the file's top-level module contains a
# NESTED defmodule, that first module is the INNER one, so both the original
# and the mutant fingerprint the inner module's bytecode and every mutation
# outside it compares equal -- reported as "equivalent" and dropped from the
# run without ever being executed.
#
# Run: MIX_ENV=test mix run .mutation/tce-nested-module.exs
# Expect: the flat module says false (correct); the nested one says true (bug).
#
# Minimal probe: does Muex.Tce call a behaviour-changing mutant "equivalent"
# when the file's top-level module contains a NESTED defmodule?
flat_orig = ~S"""
defmodule Probe.Flat do
  @word 32
  def word, do: @word
end
"""

flat_mut = ~S"""
defmodule Probe.Flat do
  @word 33
  def word, do: @word
end
"""

nested_orig = ~S"""
defmodule Probe.Nested do
  defmodule Inner do
    @moduledoc false
    defexception [:message]
  end

  @word 32
  def word, do: @word
end
"""

nested_mut = ~S"""
defmodule Probe.Nested do
  defmodule Inner do
    @moduledoc false
    defexception [:message]
  end

  @word 33
  def word, do: @word
end
"""

check = fn label, orig, mut ->
  {:ok, ast} = Code.string_to_quoted(orig)
  verdict = Muex.Tce.equivalent_source?(ast, mut)
  IO.puts("#{label}: TCE says equivalent? #{verdict}   (truth: false -- 32 vs 33 changes word/0)")
end

check.("single top-level module ", flat_orig, flat_mut)
check.("module with nested module", nested_orig, nested_mut)
