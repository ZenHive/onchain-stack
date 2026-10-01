defmodule Onchain.Test.LegacyModuleNames do
  @moduledoc """
  Maps module atoms recorded in pre-0.16.0 fixtures to their `Onchain.*` names.

  The `.etf` oracle fixtures were captured before the namespace rename and stay
  byte-identical; replay translates their `ABI.*` and `Cartouche.*` atoms
  (including exception and struct `__struct__` keys) instead of re-capturing.
  """

  @doc "Recursively rewrite legacy module atoms inside `term`."
  @spec translate(term()) :: term()
  def translate(term) when is_atom(term), do: translate_atom(term)
  def translate(term) when is_list(term), do: translate_list(term)
  def translate(term) when is_tuple(term), do: term |> Tuple.to_list() |> Enum.map(&translate/1) |> List.to_tuple()

  def translate(%{} = term) do
    # Structs are not Enumerable; walk the raw map so `__struct__` is renamed too.
    term |> :maps.to_list() |> Enum.map(fn {key, value} -> {translate(key), translate(value)} end) |> :maps.from_list()
  end

  def translate(term), do: term

  # Improper lists (iodata) must keep their tail shape.
  @spec translate_list(list()) :: list()
  defp translate_list([]), do: []
  defp translate_list([head | tail]) when is_list(tail), do: [translate(head) | translate_list(tail)]
  defp translate_list([head | tail]), do: [translate(head) | translate(tail)]

  @spec translate_atom(atom()) :: atom()
  defp translate_atom(atom) do
    case Atom.to_string(atom) do
      # The high-s test double was merged into Onchain.SignerTest.HighSBackend,
      # which accepts the same private-key config.
      "Elixir.Cartouche.Test.HighSSignerBackend" -> Onchain.SignerTest.HighSBackend
      "Elixir.ABI" -> Onchain.ABI
      "Elixir.ABI." <> rest -> Module.concat(Onchain.ABI, rest)
      "Elixir.Cartouche" -> Onchain.Configuration
      "Elixir.Cartouche." <> rest -> Module.concat(Onchain, rest)
      _ -> atom
    end
  end
end
