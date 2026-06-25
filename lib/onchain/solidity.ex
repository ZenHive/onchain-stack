defmodule Onchain.Solidity do
  @moduledoc """
  Solidity ABI parser powered by Alloy and solang-parser via Rustler NIF.

  Supports three input modes:

  - **ABI JSON** — standard `solc` output. Parses function signatures, selectors,
    parameter types, events, and errors. Use `parse_abi_json/1`.
  - **Solidity source** — raw source strings. Recovers structs, enums, NatSpec,
    and constants that ABI JSON discards. Use `parse_sol/1`.
  - **Resolved Solidity files** — root `.sol` files with relative imports and
    Foundry-style remappings. Use `resolve_sol_file/2` or `parse_sol_file/2`.

  ## Output Structure

  Both parsers return maps with `:functions`, `:events`, `:errors`, `:constructor`.
  The Solidity parser additionally returns `:structs`, `:enums`, and `:constants`,
  and attaches `:natspec` to each function entry.

  ### Parameter Maps

  All parameter maps use `:ty` (not `:type`) for the Solidity type string. Nested
  struct/tuple parameters include `:components` with recursive `param()` maps.

  ### Selectors & Topics

  Selectors and topic hashes are `0x`-prefixed hex strings (e.g. `"0x70a08231"`),
  consistent with the `Onchain.Hex` convention used throughout the codebase.

  The `:return_type` field on each function produces tuple-type strings compatible
  with `Onchain.ABI.decode_response/2` (e.g. `"(uint256,uint256,bool)"`).

  ## Error Format

  | Source | Error Shape |
  |--------|-------------|
  | Invalid JSON / malformed ABI | `{:error, {:parse_error, reason}}` |
  | Invalid Solidity source | `{:error, {:parse_error, reason}}` |
  | File not found / unreadable | `{:error, {:file_error, reason}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `parse_abi_json/1` | Parse ABI JSON string → structured map |
  | `parse_abi_json!/1` | Same, raises on error |
  | `parse_abi_file/1` | Read file + parse ABI JSON |
  | `parse_abi_file!/1` | Same, raises on error |
  | `parse_sol/1` | Parse Solidity source string → enriched map |
  | `parse_sol!/1` | Same, raises on error |
  | `resolve_sol_file/2` | Resolve a root `.sol` file, its imports, and remappings |
  | `resolve_sol_file!/2` | Same, raises on error |
  | `parse_sol_file/2` | Resolve imports/remappings, then parse the root contract |
  | `parse_sol_file!/2` | Same, raises on error |
  """

  use Descripex, namespace: "/solidity"
  use Rustler, otp_app: :onchain_evm, crate: "onchain_solidity"

  import Onchain.BangHelper, only: [defbang: 2]

  alias Onchain.Solidity.Resolver

  # --- Types ---

  @typedoc "ABI parameter with Solidity type and optional nested components."
  @type param :: %{name: String.t(), ty: String.t(), components: [param()]}

  @typedoc "Event parameter — like `param()` but includes `:indexed` flag."
  @type event_param :: %{
          name: String.t(),
          ty: String.t(),
          indexed: boolean(),
          components: [param()]
        }

  @typedoc "Parsed ABI function entry."
  @type function_info :: %{
          name: String.t(),
          signature: String.t(),
          selector: String.t(),
          return_type: String.t(),
          state_mutability: String.t(),
          inputs: [param()],
          outputs: [param()]
        }

  @typedoc "Parsed function entry with NatSpec (from .sol source)."
  @type function_info_with_natspec :: %{
          name: String.t(),
          signature: String.t(),
          selector: String.t(),
          return_type: String.t(),
          state_mutability: String.t(),
          inputs: [param()],
          outputs: [param()],
          natspec: natspec() | nil
        }

  @typedoc "Parsed ABI event entry."
  @type event_info :: %{
          name: String.t(),
          signature: String.t(),
          topic: String.t(),
          anonymous: boolean(),
          inputs: [event_param()]
        }

  @typedoc "Parsed ABI error entry."
  @type error_info :: %{
          name: String.t(),
          signature: String.t(),
          selector: String.t(),
          inputs: [param()]
        }

  @typedoc "Parsed ABI constructor entry, or `nil` if not present."
  @type constructor_info :: %{inputs: [param()], state_mutability: String.t()} | nil

  @typedoc "Complete parsed ABI with functions, events, errors, and constructor."
  @type parsed_abi :: %{
          functions: [function_info()],
          events: [event_info()],
          errors: [error_info()],
          constructor: constructor_info()
        }

  @typedoc "Struct definition from Solidity source."
  @type struct_info :: %{name: String.t(), fields: [%{name: String.t(), ty: String.t()}]}

  @typedoc "Enum definition from Solidity source."
  @type enum_info :: %{name: String.t(), variants: [String.t()]}

  @typedoc "Constant definition from Solidity source."
  @type constant_info :: %{name: String.t(), ty: String.t(), value: String.t()}

  @typedoc "NatSpec documentation for a function."
  @type natspec :: %{
          notice: String.t(),
          params: %{String.t() => String.t()},
          returns: %{String.t() => String.t()}
        }

  @typedoc "Complete parsed Solidity source with structs, enums, constants, and NatSpec."
  @type parsed_sol :: %{
          functions: [function_info_with_natspec()],
          events: [event_info()],
          errors: [error_info()],
          constructor: constructor_info(),
          structs: [struct_info()],
          enums: [enum_info()],
          constants: [constant_info()]
        }

  @typedoc "Foundry-style remapping string such as `\"@aave/core-v3/=lib/aave-v3-core/\"`."
  @type remapping_string :: String.t()

  @typedoc "Options for resolved Solidity file parsing."
  @type parse_sol_file_opts :: [remappings: [remapping_string()], root_contract: String.t()]

  @typedoc "Resolved Solidity file graph and merged source."
  @type resolved_sol_file :: %{
          source: String.t(),
          files: [String.t()],
          root_contract: String.t()
        }

  # --- parse_abi_json ---

  api(:parse_abi_json, "Parse a Solidity ABI JSON string into structured Elixir data.",
    params: [
      json: [
        kind: :value,
        description: "ABI JSON string (standard solc output format — array of ABI items)"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_abi()} | {:error, {:parse_error, String.t()}}",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_json(String.t()) :: {:ok, parsed_abi()} | {:error, {:parse_error, String.t()}}
  def parse_abi_json(_json), do: :erlang.nif_error(:nif_not_loaded)

  # --- parse_abi_json! ---

  api(:parse_abi_json!, "Parse a Solidity ABI JSON string. Raises on error.",
    params: [
      json: [
        kind: :value,
        description: "ABI JSON string (standard solc output format — array of ABI items)"
      ]
    ],
    returns: %{
      type: "parsed_abi()",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_json!(String.t()) :: parsed_abi()
  # defbang expands to the same case/raise pattern, see Onchain.BangHelper
  defbang(parse_abi_json!(json),
    errors: [parse_error: "ABI parse failed"],
    fallback: "ABI parse failed"
  )

  # --- parse_abi_file ---

  api(:parse_abi_file, "Read a file and parse its contents as Solidity ABI JSON.",
    params: [
      path: [
        kind: :value,
        description: "Path to an ABI JSON file (e.g. \"priv/abis/erc20.json\")"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_abi()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_file(String.t()) ::
          {:ok, parsed_abi()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  def parse_abi_file(path) do
    case File.read(path) do
      {:ok, contents} -> parse_abi_json(contents)
      {:error, reason} -> {:error, {:file_error, "#{path}: #{reason}"}}
    end
  end

  # --- parse_abi_file! ---

  api(:parse_abi_file!, "Read a file and parse its contents as Solidity ABI JSON. Raises on error.",
    params: [
      path: [
        kind: :value,
        description: "Path to an ABI JSON file (e.g. \"priv/abis/erc20.json\")"
      ]
    ],
    returns: %{
      type: "parsed_abi()",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_file!(String.t()) :: parsed_abi()
  # defbang expands to the same case/raise pattern, see Onchain.BangHelper
  defbang(parse_abi_file!(path),
    errors: [parse_error: "ABI parse failed", file_error: "ABI file error"],
    fallback: "ABI error"
  )

  # --- parse_sol ---

  api(
    :parse_sol,
    "Parse a Solidity source string into structured Elixir data with structs, enums, and NatSpec.",
    params: [
      source: [
        kind: :value,
        description: "Solidity source code string (e.g. an interface definition)"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_sol()} | {:error, {:parse_error, String.t()}}",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol(String.t()) :: {:ok, parsed_sol()} | {:error, {:parse_error, String.t()}}
  def parse_sol(_source), do: :erlang.nif_error(:nif_not_loaded)

  # --- parse_sol! ---

  api(:parse_sol!, "Parse a Solidity source string. Raises on error.",
    params: [
      source: [
        kind: :value,
        description: "Solidity source code string (e.g. an interface definition)"
      ]
    ],
    returns: %{
      type: "parsed_sol()",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol!(String.t()) :: parsed_sol()
  # defbang expands to the same case/raise pattern, see Onchain.BangHelper
  defbang(parse_sol!(source),
    errors: [parse_error: "Solidity parse failed"],
    fallback: "Solidity parse failed"
  )

  # --- resolve_sol_file ---

  api(:resolve_sol_file, "Resolve a root Solidity file, its imports, and remappings.",
    params: [
      path: [
        kind: :value,
        description: "Path to the root .sol file"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "{:ok, resolved_sol_file()} | {:error, {:file_error, String.t()} | {:parse_error, String.t()}}",
      description: "Merged source, resolved file list, and selected root contract"
    }
  )

  @spec resolve_sol_file(String.t(), parse_sol_file_opts()) ::
          {:ok, resolved_sol_file()} | {:error, {:file_error, String.t()} | {:parse_error, String.t()}}
  def resolve_sol_file(path, opts \\ []), do: Resolver.resolve_sol_file(path, opts)

  # --- resolve_sol_file! ---

  api(:resolve_sol_file!, "Resolve a root Solidity file. Raises on error.",
    params: [
      path: [
        kind: :value,
        description: "Path to the root .sol file"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "resolved_sol_file()",
      description: "Merged source, resolved file list, and selected root contract"
    }
  )

  @spec resolve_sol_file!(String.t(), parse_sol_file_opts()) :: resolved_sol_file()
  # defbang expands to the same case/raise pattern, see Onchain.BangHelper
  defbang(resolve_sol_file!(path, opts \\ []),
    errors: [parse_error: "Solidity parse failed", file_error: "Solidity file error"],
    fallback: "Solidity error"
  )

  # --- parse_sol_file ---

  api(:parse_sol_file, "Resolve a Solidity file graph and parse the selected root contract.",
    params: [
      path: [
        kind: :value,
        description: "Path to a root .sol file (e.g. \"priv/contracts/IPool.sol\")"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_sol()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol_file(String.t(), parse_sol_file_opts()) ::
          {:ok, parsed_sol()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  def parse_sol_file(path, opts \\ []), do: Resolver.parse_sol_file(path, opts)

  # --- parse_sol_file! ---

  api(:parse_sol_file!, "Resolve a Solidity file graph and parse it. Raises on error.",
    params: [
      path: [
        kind: :value,
        description: "Path to a root .sol file (e.g. \"priv/contracts/IPool.sol\")"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "parsed_sol()",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol_file!(String.t(), parse_sol_file_opts()) :: parsed_sol()
  # defbang expands to the same case/raise pattern, see Onchain.BangHelper
  defbang(parse_sol_file!(path, opts \\ []),
    errors: [parse_error: "Solidity parse failed", file_error: "Solidity file error"],
    fallback: "Solidity error"
  )

  @doc false
  @spec __parse_sol_root__(String.t(), String.t()) ::
          {:ok, parsed_sol()} | {:error, {:parse_error, String.t()}}
  def __parse_sol_root__(_source, _root_contract), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec __extract_sol_imports__(String.t()) ::
          {:ok, [String.t()]} | {:error, {:parse_error, String.t()}}
  def __extract_sol_imports__(_source), do: :erlang.nif_error(:nif_not_loaded)
end
