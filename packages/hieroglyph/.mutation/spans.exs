# Emits, as JSON, the line spans of code that carries DOCUMENTATION rather than
# behaviour, so survivor triage can separate the two without eyeballing 1000+
# entries:
#
#   * `api(...)` — Descripex metadata blocks. Their strings and atoms are
#     agent-facing prose rendered into api_manifest.json.
#   * `@moduledoc` / `@doc` / `@typedoc` — documentation attributes.
#
# Spans come from the AST, not a paren scan: descripex descriptions are prose
# and contain unbalanced parentheses and quotes that defeat text matching.
#
# Run: elixir .mutation/spans.exs > .mutation/results/spans.json
files = Path.wildcard("lib/abi.ex") ++ Path.wildcard("lib/abi/*.ex")

max_line = fn ast ->
  {_, acc} =
    Macro.prewalk(ast, [], fn
      {_, meta, _} = node, acc when is_list(meta) -> {node, [Keyword.get(meta, :line, 0) | acc]}
      node, acc -> {node, acc}
    end)

  Enum.max([0 | acc])
end

spans =
  Map.new(files, fn file ->
    ast = file |> File.read!() |> Code.string_to_quoted!(columns: true)

    {_, found} =
      Macro.prewalk(ast, [], fn
        {:api, meta, args} = node, acc when is_list(args) ->
          {node, [%{kind: "api", line: meta[:line], last: max_line.(args)} | acc]}

        {:@, meta, [{attr, _, _} = inner]} = node, acc
        when attr in [:moduledoc, :doc, :typedoc] ->
          span = %{kind: "doc", line: meta[:line], last: max_line.([inner])}
          {node, [span | acc]}

        # `raise ...` / `raise(...)`. A mutation anywhere inside one only
        # changes the text of an error, never the encoded bytes -- but the
        # interpolated bounds inside that text ARE the diagnostic contract, so
        # the class is dispositioned as a whole rather than dismissed.
        {:raise, meta, args} = node, acc when is_list(args) ->
          {node, [%{kind: "raise", line: meta[:line], last: max_line.(args)} | acc]}

        node, acc ->
          {node, acc}
      end)

    {file, Enum.sort_by(found, & &1.line)}
  end)

IO.puts(Jason.encode!(spans))
