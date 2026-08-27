defmodule Onchain.ERC7730.Formatter do
  @moduledoc """
  Display-rule engine for ERC-7730 descriptors.

  Applies a single field's `format` rule to the value resolved at its `path`,
  producing a `%{label, value, formatted_value, raw}` map:

  - `raw` — the canonical decoded value (address as a 20-byte binary, numbers as
    integers, booleans, byte strings).
  - `value` — a JSON-friendly normalization of `raw` (address as an EIP-55
    checksummed hex string, bytes as `0x`-hex; numbers/booleans/strings as-is).
  - `formatted_value` — the human-readable string per the field's format rule.

  ## Path resolution

  | Prefix | Root |
  |--------|------|
  | `#.name` (or bare `name`) | decoded message / calldata params |
  | `@.to` / `@.value` / `@.from` | transaction envelope |
  | `$.a.b.c` | the descriptor document (constants, metadata, enums) |

  ## Supported formats (first pass)

  `raw`, `amount` (native currency), `tokenAmount`, `addressName`, `date`,
  `duration`, `unit`, `enum`. `calldata` (embedded calls) and `nftName` (needs an
  on-chain name lookup) are deferred and fall back to `raw` rendering.

  ## Token metadata resolution

  `tokenAmount` needs a token's `decimals`/`symbol`. Resolution order:

  1. `opts[:tokens]` — caller map `%{lowercase_hex => %{decimals:, symbol:}}`.
  2. `metadata.token` in the descriptor (for single-token EIP-712 descriptors).
  3. `opts[:rpc_url]` — live `Onchain.ERC20.decimals/2` + `symbol/2` lookup.
  4. Otherwise the raw integer is shown unscaled.
  """

  use Descripex, namespace: "/erc7730/formatter"

  alias Onchain.Address
  alias Onchain.Decimal, as: OnchainDecimal
  alias Onchain.ERC20
  alias Onchain.ERC7730.Descriptor
  alias Onchain.Hex

  @native_markers [
    "0x0000000000000000000000000000000000000000",
    "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  ]

  @type result :: %{label: String.t() | nil, value: term(), formatted_value: String.t(), raw: term()}

  api(:format_field, "Apply a descriptor field's format rule to its resolved value.",
    params: [
      field: [kind: :value, description: "A parsed display field (see Onchain.ERC7730.Descriptor)"],
      resolution: [
        kind: :value,
        description: "Binding resolution (%{message, types, envelope}) from Onchain.ERC7730.Binding"
      ],
      descriptor: [kind: :value, description: "Parsed %Onchain.ERC7730.Descriptor{} (for $. paths)"],
      opts: [
        kind: :value,
        default: [],
        description: "Resolution opts: :tokens, :rpc_url, :native_symbol, :native_decimals, :names"
      ]
    ],
    returns: %{
      type: "{:ok, %{label, value, formatted_value, raw}} | {:error, {tag, reason}}",
      description: "Rendered field, or {:error, {:unresolved_path, path}} for a missing visible field"
    }
  )

  @spec format_field(Descriptor.field(), map(), Descriptor.t(), keyword()) ::
          {:ok, result()} | {:error, {atom(), term()}}
  def format_field(field, resolution, descriptor, opts \\ [])

  def format_field(%{path: nil, value: literal} = field, _resolution, _descriptor, _opts) do
    {:ok, %{label: field.label, raw: literal, value: literal, formatted_value: to_display(literal)}}
  end

  def format_field(field, resolution, descriptor, opts) do
    case resolve_path(field.path, resolution, descriptor) do
      {nil, _type} ->
        {:error, {:unresolved_path, field.path}}

      {value, type} ->
        raw = coerce(value, type)

        {:ok,
         %{
           label: field.label,
           raw: raw,
           value: normalize(raw, type),
           formatted_value: render(field.format, raw, type, field.params, resolution, descriptor, opts)
         }}
    end
  end

  # --- path resolution ---

  defp resolve_path("$." <> rest, _resolution, descriptor) do
    {get_in_raw(descriptor.raw, String.split(rest, ".")), nil}
  end

  defp resolve_path("@." <> rest, resolution, _descriptor) do
    {Map.get(resolution.envelope, envelope_key(rest)), envelope_type(rest)}
  end

  defp resolve_path("#." <> rest, resolution, _descriptor), do: resolve_message(rest, resolution)
  defp resolve_path(path, resolution, _descriptor) when is_binary(path), do: resolve_message(path, resolution)
  defp resolve_path(_path, _resolution, _descriptor), do: {nil, nil}

  defp resolve_message(path, resolution) do
    [name | rest] = String.split(path, ".")
    value = Map.get(resolution.message, name)
    type = Map.get(resolution.types, name)

    case rest do
      [] -> {value, type}
      keys -> {get_in_raw(value, keys), nil}
    end
  end

  defp envelope_key("to"), do: :to
  defp envelope_key("value"), do: :value
  defp envelope_key("from"), do: :from
  defp envelope_key("data"), do: :data
  defp envelope_key(_other), do: :__unknown__

  defp envelope_type("value"), do: {:uint, 256}
  defp envelope_type(key) when key in ["to", "from"], do: :address
  defp envelope_type(_other), do: nil

  defp get_in_raw(value, []), do: value
  defp get_in_raw(map, [key | rest]) when is_map(map), do: get_in_raw(Map.get(map, key), rest)
  defp get_in_raw(_value, _keys), do: nil

  # --- coercion: any source value -> canonical raw ---

  defp coerce(value, :address), do: to_address_binary(value)
  defp coerce(value, {:uint, _}), do: to_int(value)
  defp coerce(value, {:int, _}), do: to_int(value)
  defp coerce(value, :bool) when is_boolean(value), do: value
  defp coerce(value, {:bytes, _}), do: to_bytes(value)
  defp coerce(value, :bytes), do: to_bytes(value)
  defp coerce(value, _type), do: value

  defp to_address_binary(<<_::160>> = bin), do: bin

  defp to_address_binary(value) when is_binary(value) do
    case Address.validate(value) do
      {:ok, bin} -> bin
      {:error, _} -> value
    end
  end

  defp to_address_binary(value), do: value

  defp to_int(value) when is_integer(value), do: value
  defp to_int("0x" <> _ = hex), do: Hex.to_integer!(hex)

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp to_int(value), do: value

  defp to_bytes(<<_::8, _::binary>> = bin) do
    if String.starts_with?(bin, "0x"), do: Hex.decode!(bin), else: bin
  end

  defp to_bytes(value), do: value

  # --- normalization: canonical raw -> JSON-friendly value ---

  defp normalize(<<_::160>> = address, :address), do: Address.checksum!(address)
  defp normalize(value, {:bytes, _}) when is_binary(value), do: Hex.encode(value)
  defp normalize(value, :bytes) when is_binary(value), do: Hex.encode(value)
  defp normalize(value, _type), do: value

  # --- format rendering ---

  defp render(:amount, raw, _type, _params, _resolution, _descriptor, opts) when is_integer(raw) do
    decimals = Keyword.get(opts, :native_decimals, 18)
    symbol = Keyword.get(opts, :native_symbol, "ETH")
    "#{decimal_string(raw, decimals)} #{symbol}"
  end

  defp render(:token_amount, raw, _type, params, resolution, descriptor, opts) when is_integer(raw) do
    case threshold_message(raw, params) do
      {:ok, message} ->
        message

      :no_threshold ->
        {decimals, symbol} = resolve_token(params, resolution, descriptor, opts)
        format_token_amount(raw, decimals, symbol)
    end
  end

  defp render(:address_name, <<_::160>> = raw, _type, _params, _resolution, _descriptor, opts) do
    checksummed = Address.checksum!(raw)
    names = Keyword.get(opts, :names, %{})
    Map.get(names, String.downcase(checksummed), checksummed)
  end

  defp render(:date, raw, _type, params, _resolution, _descriptor, _opts) when is_integer(raw) do
    case Map.get(params, "encoding", "timestamp") do
      "blockheight" -> "block #{raw}"
      _timestamp -> format_timestamp(raw)
    end
  end

  defp render(:duration, raw, _type, _params, _resolution, _descriptor, _opts) when is_integer(raw) do
    format_duration(raw)
  end

  defp render(:unit, raw, _type, params, _resolution, _descriptor, _opts) when is_integer(raw) do
    decimals = Map.get(params, "decimals", 0)
    base = Map.get(params, "base", "")
    scaled = decimal_string(raw, decimals)
    if base == "%", do: "#{scaled}%", else: String.trim("#{scaled} #{base}")
  end

  defp render(:enum, raw, _type, params, _resolution, descriptor, _opts) do
    with ref when is_binary(ref) <- Map.get(params, "$ref"),
         enum when is_map(enum) <- resolve_enum_ref(ref, descriptor),
         label when not is_nil(label) <- Map.get(enum, to_string(raw)) do
      label
    else
      _ -> to_display(raw)
    end
  end

  defp render(_format, raw, {:bytes, _}, _params, _resolution, _descriptor, _opts) when is_binary(raw),
    do: Hex.encode(raw)

  defp render(_format, raw, :bytes, _params, _resolution, _descriptor, _opts) when is_binary(raw), do: Hex.encode(raw)

  # raw, nft_name, calldata, unknown, and any type mismatch fall through to a
  # plain rendering of the canonical value.
  defp render(_format, raw, _type, _params, _resolution, _descriptor, _opts), do: to_display(raw)

  # --- token amount helpers ---

  defp threshold_message(raw, params) do
    with threshold when not is_nil(threshold) <- Map.get(params, "threshold"),
         message when not is_nil(message) <- Map.get(params, "message"),
         true <- raw >= to_int(threshold) do
      {:ok, message}
    else
      _ -> :no_threshold
    end
  end

  defp format_token_amount(raw, nil, _symbol), do: Integer.to_string(raw)
  defp format_token_amount(raw, decimals, nil), do: decimal_string(raw, decimals)
  defp format_token_amount(raw, decimals, symbol), do: "#{decimal_string(raw, decimals)} #{symbol}"

  defp resolve_token(params, resolution, descriptor, opts) do
    token = resolve_token_address(params, resolution, descriptor)

    cond do
      is_nil(token) -> {nil, nil}
      native_token?(token) -> {Keyword.get(opts, :native_decimals, 18), Keyword.get(opts, :native_symbol, "ETH")}
      true -> lookup_token(token, descriptor, opts)
    end
  end

  defp resolve_token_address(params, resolution, descriptor) do
    cond do
      path = Map.get(params, "tokenPath") -> elem(resolve_path(path, resolution, descriptor), 0)
      token = Map.get(params, "token") -> resolve_ref(token, resolution, descriptor)
      true -> nil
    end
  end

  defp resolve_ref("$." <> _ = ref, resolution, descriptor), do: elem(resolve_path(ref, resolution, descriptor), 0)
  defp resolve_ref("@." <> _ = ref, resolution, descriptor), do: elem(resolve_path(ref, resolution, descriptor), 0)
  defp resolve_ref(literal, _resolution, _descriptor), do: literal

  defp native_token?(token) do
    case Address.normalize(token) do
      {:ok, hex} -> hex in @native_markers
      _ -> false
    end
  end

  defp lookup_token(token, descriptor, opts) do
    with :miss <- from_tokens_opt(token, opts),
         :miss <- from_metadata(token, descriptor),
         :miss <- from_rpc(token, opts) do
      {nil, nil}
    end
  end

  defp from_tokens_opt(token, opts) do
    tokens = Keyword.get(opts, :tokens, %{})

    case Address.normalize(token) do
      {:ok, hex} ->
        case Map.get(tokens, hex) || Map.get(tokens, token) do
          %{} = info -> {Map.get(info, :decimals), Map.get(info, :symbol)}
          _ -> :miss
        end

      _ ->
        :miss
    end
  end

  defp from_metadata(token, %Descriptor{metadata: %{"token" => %{} = metadata_token}}) do
    with metadata_address when not is_nil(metadata_address) <- Map.get(metadata_token, "address"),
         true <- Address.equal?(token, metadata_address),
         decimals when not is_nil(decimals) <- Map.get(metadata_token, "decimals") do
      {decimals, Map.get(metadata_token, "ticker") || Map.get(metadata_token, "name")}
    else
      _ -> :miss
    end
  end

  defp from_metadata(_token, _descriptor), do: :miss

  defp from_rpc(token, opts) do
    case Keyword.get(opts, :rpc_url) do
      nil ->
        :miss

      rpc_url ->
        with {:ok, decimals} <- ERC20.decimals(token, rpc_url: rpc_url),
             {:ok, symbol} <- ERC20.symbol(token, rpc_url: rpc_url) do
          {decimals, symbol}
        else
          _ -> :miss
        end
    end
  end

  # --- generic rendering helpers ---

  defp resolve_enum_ref("$." <> _ = ref, descriptor), do: elem(resolve_path(ref, %{}, descriptor), 0)
  defp resolve_enum_ref(_ref, _descriptor), do: nil

  defp decimal_string(value, 0), do: Integer.to_string(value)

  defp decimal_string(value, decimals) do
    value |> OnchainDecimal.to_decimal(decimals) |> Decimal.to_string(:normal)
  end

  defp format_timestamp(seconds) do
    case DateTime.from_unix(seconds) do
      {:ok, dt} -> DateTime.to_iso8601(dt)
      {:error, _} -> Integer.to_string(seconds)
    end
  end

  defp format_duration(seconds) when seconds >= 0 do
    h = div(seconds, 3600)
    m = seconds |> rem(3600) |> div(60)
    s = rem(seconds, 60)
    "#{h}:#{pad(m)}:#{pad(s)}"
  end

  defp format_duration(seconds), do: Integer.to_string(seconds)

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp to_display(<<_::160>> = address), do: Address.checksum!(address)
  defp to_display(value) when is_binary(value) and byte_size(value) > 20, do: maybe_hex(value)
  defp to_display(value) when is_binary(value), do: value
  defp to_display(value) when is_integer(value), do: Integer.to_string(value)
  defp to_display(value) when is_boolean(value), do: to_string(value)
  defp to_display(value), do: inspect(value)

  defp maybe_hex(value) do
    if String.printable?(value), do: value, else: Hex.encode(value)
  end
end
