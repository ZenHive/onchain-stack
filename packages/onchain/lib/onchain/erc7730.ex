defmodule Onchain.ERC7730 do
  @moduledoc """
  [ERC-7730](https://eips.ethereum.org/EIPS/eip-7730) clear-signing descriptors:
  load a descriptor, bind it to a signing request, and render human-readable
  display fields.

  ERC-7730 standardizes a JSON descriptor that binds calldata, EIP-712 typed
  messages, and ERC-4337 UserOperations to display rules, so a wallet can show
  *what a transaction does* instead of opaque hex. This module is the entry
  point over three internal pieces:

  - `Onchain.ERC7730.Descriptor` — parse + structurally validate the JSON.
  - `Onchain.ERC7730.Binding` — resolve which display format applies and decode
    the bound data (chain id + address + selector, or EIP-712 domain + type).
  - `Onchain.ERC7730.Formatter` — apply per-field format rules.

  ## Usage

      {:ok, descriptor} = Onchain.ERC7730.load(json_string)

      {:ok, fields} =
        Onchain.ERC7730.format(
          descriptor,
          {:calldata, token_address, 1, calldata_hex},
          tokens: %{"0x...usdc" => %{decimals: 6, symbol: "USDC"}}
        )

      # fields => [%{label: "To", value: "0x...", formatted_value: "0x...", raw: <<...>>}, ...]

  ## Scope (Task 74, first pass)

  - **In:** caller-provided descriptors; contract/calldata, EIP-712, and
    UserOp binding; the common formatters (`raw`, `amount`, `tokenAmount`,
    `addressName`, `date`, `duration`, `unit`, `enum`).
  - **Out:** fetching curated descriptors from the Ledger registry / IPFS / CDN;
    `includes` / external `$ref` resolution; on-chain proxy/`addressMatcher`
    resolution; `calldata` (embedded sub-call) and `nftName` formatters (they
    fall back to raw rendering).

  Token `decimals`/`symbol` for `tokenAmount` resolve from `opts[:tokens]`, the
  descriptor's `metadata.token`, or a live `opts[:rpc_url]` lookup — see
  `Onchain.ERC7730.Formatter`.
  """

  use Descripex, namespace: "/erc7730"

  alias Onchain.ERC7730.Binding
  alias Onchain.ERC7730.Descriptor
  alias Onchain.ERC7730.Formatter

  @max_path_bytes 4096

  api(:load, "Load and validate an ERC-7730 descriptor from a JSON string, file path, or decoded map.",
    params: [
      source: [
        kind: :exchange_data,
        description: "A JSON string, a filesystem path to a .json descriptor, or an already-decoded JSON map"
      ]
    ],
    returns: %{
      type: "{:ok, Descriptor.t()} | {:error, {tag, reason}}",
      description:
        "Parsed descriptor, or an error: {:invalid_json, _}, {:file_error, posix}, or a structural tag from Descriptor.parse/1"
    }
  )

  @spec load(String.t() | map()) :: {:ok, Descriptor.t()} | {:error, {atom(), term()}}
  def load(source) when is_map(source), do: Descriptor.parse(source)

  def load(source) when is_binary(source) do
    with {:ok, json} <- read_source(source),
         {:ok, raw} <- decode_json(json) do
      Descriptor.parse(raw)
    end
  end

  api(:format, "Bind a descriptor to a signing request and render its display fields.",
    params: [
      descriptor: [kind: :value, description: "Parsed %Onchain.ERC7730.Descriptor{} from load/1"],
      request: [
        kind: :exchange_data,
        description:
          "{:calldata, address, chain_id, hex_data} | {:eip712, payload} | {:user_op, address, chain_id, user_op}"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Rendering opts: :tokens, :rpc_url, :native_symbol, :native_decimals, :names, :value, :from"
      ]
    ],
    returns: %{
      type: "{:ok, [%{label, value, formatted_value, raw}]} | {:error, {tag, reason}}",
      description: "Ordered list of rendered visible fields, or a binding/format error tuple"
    }
  )

  @spec format(Descriptor.t(), Binding.request(), keyword()) ::
          {:ok, [Formatter.result()]} | {:error, {atom(), term()}}
  def format(%Descriptor{} = descriptor, request, opts \\ []) do
    with {:ok, resolution} <- Binding.resolve(descriptor, request, opts) do
      render_fields(resolution, descriptor, opts)
    end
  end

  api(:format!, "Bind a descriptor to a signing request and render its display fields. Raises on error.",
    params: [
      descriptor: [kind: :value, description: "Parsed %Onchain.ERC7730.Descriptor{} from load/1"],
      request: [
        kind: :exchange_data,
        description: "Same request shapes as format/2"
      ],
      opts: [kind: :value, default: [], description: "Same rendering opts as format/2"]
    ],
    returns: %{
      type: "[%{label, value, formatted_value, raw}]",
      description: "Ordered list of rendered visible fields"
    }
  )

  @spec format!(Descriptor.t(), Binding.request(), keyword()) :: [Formatter.result()]
  def format!(%Descriptor{} = descriptor, request, opts \\ []) do
    case format(descriptor, request, opts) do
      {:ok, fields} -> fields
      {:error, reason} -> raise "ERC7730.format failed: #{inspect(reason)}"
    end
  end

  # --- private ---

  defp render_fields(resolution, descriptor, opts) do
    resolution.format.fields
    |> Enum.filter(& &1.visible)
    |> Enum.reduce_while({:ok, []}, fn field, {:ok, acc} ->
      case Formatter.format_field(field, resolution, descriptor, opts) do
        {:ok, rendered} -> {:cont, {:ok, [rendered | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      {:error, _} = error -> error
    end
  end

  defp read_source(source) do
    trimmed = String.trim_leading(source)

    cond do
      String.starts_with?(trimmed, "{") -> {:ok, source}
      byte_size(source) < @max_path_bytes and path_like?(source) -> read_file(source)
      true -> {:ok, source}
    end
  end

  # A single-line input that is either an existing file or carries a .json
  # suffix is treated as a path — so a typo'd path surfaces as {:file_error,
  # :enoent} rather than a confusing JSON-parse error.
  defp path_like?(source) do
    not String.contains?(source, "\n") and
      (File.regular?(source) or String.ends_with?(source, ".json"))
  end

  # Reading a caller-supplied descriptor path is the documented purpose of load/1.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, posix} -> {:error, {:file_error, posix}}
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, raw} -> {:ok, raw}
      {:error, error} -> {:error, {:invalid_json, Exception.message(error)}}
    end
  end
end
