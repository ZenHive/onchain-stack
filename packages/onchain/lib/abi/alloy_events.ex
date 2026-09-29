defmodule ABI.AlloyEvents do
  @moduledoc false
  alias ABI.Alloy
  alias ABI.FunctionSelector
  alias ABI.Native
  alias ABI.TypeDecoder
  alias ABI.Validation

  @spec decode(binary(), [binary()], FunctionSelector.t(), keyword()) :: term()
  def decode(data, topics, selector, opts) do
    schema = schema(selector, opts)

    with {:ok, input} <- prepare(data, topics, schema, opts) do
      result =
        if schema.small? do
          Native.abi_small(:event, schema.resource, input)
        else
          Native.abi(:event, schema.resource, input)
        end

      finish(result, schema, opts)
    end
  rescue
    e in TypeDecoder.StrictViolation -> {:error, {:strict_violation, e.detail}}
  end

  @spec decode_batch([{binary(), [binary()]}], FunctionSelector.t(), keyword()) :: [term()]
  def decode_batch(logs, selector, opts) do
    schema = schema(selector, opts)

    logs
    |> Enum.chunk_every(10_000)
    |> Enum.flat_map(fn chunk ->
      prepared =
        Enum.map(chunk, fn {data, topics} ->
          try do
            prepare(data, topics, schema, opts)
          rescue
            e in TypeDecoder.StrictViolation -> {:error, {:strict_violation, e.detail}}
          end
        end)

      inputs = for {:ok, input} <- prepared, do: input
      {:ok, results} = Native.abi(:events, schema.resource, inputs)

      {decoded, []} =
        Enum.map_reduce(prepared, results, fn
          {:ok, _}, [result | rest] -> {finish(result, schema, opts), rest}
          error, rest -> {error, rest}
        end)

      decoded
    end)
  end

  defp schema(selector, opts) do
    check =
      Keyword.get(opts, :check_event_signature, true) and
        not (selector.function_type == :event and selector.returns == :anonymous)

    key = {selector, check}
    cache = :persistent_term.get(__MODULE__, %{})

    case Map.fetch(cache, key) do
      {:ok, schema} ->
        schema

      :error ->
        types = Enum.with_index(selector.types, &Map.put_new(&1, :name, Integer.to_string(&2)))
        {indexed, body} = Enum.split_with(types, &Map.get(&1, :indexed, false))
        signature = if check, do: ABI.Event.event_signature(selector), else: <<>>
        indexed = if check, do: [%{type: {:bytes, 32}, name: "__abi__topic"} | indexed], else: indexed
        wire_indexed = Enum.map(indexed, fn p -> if reference?(p.type), do: %{p | type: {:bytes, 32}}, else: p end)
        wire_body = Enum.map(body, &Map.delete(&1, :name))
        # Alloy.schema handles binary strings and zero-width aggregate compatibility.
        types = [%{type: {:tuple, wire_indexed}}, %{type: {:tuple, wire_body}}]
        resource = Alloy.schema(types, signature)

        small? =
          static_nodes({:tuple, types}) <= 32 and
            byte_size(FunctionSelector.encode(%FunctionSelector{types: types})) <= 256

        schema = %{
          resource: resource,
          small?: small?,
          indexed: indexed,
          body: body,
          wire_indexed: wire_indexed,
          wire_body: wire_body,
          signature: signature,
          name: selector.function
        }

        if map_size(cache) < 1024, do: :persistent_term.put(__MODULE__, Map.put(cache, key, schema))
        schema
    end
  end

  defp prepare(data, topics, schema, opts) do
    if length(topics) == length(schema.indexed) do
      Enum.zip_with(schema.wire_indexed, topics, fn type, topic -> Validation.chunks(topic, [type], opts) end)

      if schema.signature != <<>> and hd(topics) != schema.signature do
        {:error, {:event_signature_mismatch, %{expected: schema.signature, got: hd(topics)}}}
      else
        prepare_body(data, topics, schema, opts)
      end
    else
      {:error, {:topics_length_mismatch, %{got: length(topics), expected: length(schema.indexed)}}}
    end
  end

  defp prepare_body(data, topics, schema, opts) do
    [body] = Validation.chunks(data, [%{type: {:tuple, schema.wire_body}}], opts)
    {:ok, {topics, body}}
  rescue
    e in [MatchError, CaseClauseError, RuntimeError] -> {:error, {:malformed_data, Exception.message(e)}}
  end

  defp finish({:ok, {topics, body}}, schema, opts) do
    indexed =
      Enum.zip_with(schema.indexed, topics, fn p, value ->
        {p.name, if(reference?(p.type), do: {:indexed_hash, value}, else: value)}
      end)

    body = Enum.zip_with(schema.body, Tuple.to_list(body), fn p, value -> {p.name, Alloy.render(p.type, value, opts)} end)
    indexed = if schema.signature == <<>>, do: indexed, else: tl(indexed)
    {:ok, schema.name, Map.new(indexed ++ body)}
  end

  defp finish({:error, reason}, _, _), do: {:error, {:malformed_data, reason}}

  # Conservative mirror of the native normal-scheduler schema budget.
  defp static_nodes({:tuple, types}), do: 1 + Enum.sum_by(types, &static_nodes(&1.type))
  defp static_nodes({:array, _}), do: 33
  defp static_nodes({:array, _, _}), do: 33
  defp static_nodes(type) when type in [:string, :bytes], do: 33
  defp static_nodes(_), do: 1

  defp reference?(t) when t in [:string, :bytes], do: true
  defp reference?({:tuple, _}), do: true
  defp reference?({:array, _}), do: true
  defp reference?({:array, _, _}), do: true
  defp reference?(_), do: false
end
