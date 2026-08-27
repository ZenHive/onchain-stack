defmodule Onchain.TypeEvasion do
  @moduledoc """
  Test helper for negative tests under Elixir 1.20's compile-time type checker.

  Functions with strict specs (e.g. `binary()`, `integer()`) now produce a
  type warning when called with a literal of the wrong type — even inside an
  `assert_raise` that deliberately exercises the runtime guard. Launder the bad
  value through `untyped/1` to erase its compile-time type and silence the
  warning while keeping the test exercising the real runtime path.
  """

  @doc "Returns `value` typed as `term()`, defeating compile-time type inference."
  @spec untyped(term()) :: term()
  def untyped(value), do: value
end
