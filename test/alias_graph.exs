defmodule AliasGraph do
  @moduledoc false

  @spec read!(String.t()) :: map()
  def read!(source) do
    {_ast, aliases} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(nil, fn
        {:defp, _, [{:aliases, _, _}, [do: aliases]]} = node, _acc ->
          {node, aliases}

        node, acc ->
          {node, acc}
      end)

    Map.new(aliases, fn {name, steps} ->
      {Atom.to_string(name), Enum.map(List.wrap(steps), &Macro.to_string/1)}
    end)
  end

  @spec expand(map(), String.t()) :: [String.t()]
  def expand(aliases, name) do
    Enum.flat_map(Map.fetch!(aliases, name), fn step ->
      case Code.string_to_quoted!(step) do
        command when is_binary(command) ->
          task = command |> String.split() |> hd()

          if task != name and Map.has_key?(aliases, task) do
            expand(aliases, task)
          else
            [step]
          end

        _capture ->
          [step]
      end
    end)
  end
end
