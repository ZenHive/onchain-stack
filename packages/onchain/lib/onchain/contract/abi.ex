defmodule Onchain.Contract.ABI do
  @moduledoc "Parses contract ABI JSON with alloy-json-abi in the core NIF."

  @type parsed_abi :: %{functions: [map()], events: [map()], errors: [map()], constructor: map() | nil}

  @doc "Parses a standard JSON array of ABI entries."
  @spec parse_abi_json(String.t()) :: {:ok, parsed_abi()} | {:error, {:parse_error, String.t()}}
  defdelegate parse_abi_json(json), to: Onchain.ABI.Native

  @doc "Parses ABI JSON, raising on malformed input."
  @spec parse_abi_json!(String.t()) :: parsed_abi()
  def parse_abi_json!(json) do
    case parse_abi_json(json) do
      {:ok, abi} -> abi
      {:error, reason} -> raise "ABI parse failed: #{inspect(reason)}"
    end
  end

  @doc "Reads and parses an ABI JSON file."
  @spec parse_abi_file(String.t()) :: {:ok, parsed_abi()} | {:error, term()}
  def parse_abi_file(path) do
    # Caller-supplied ABI path, same class as other library file readers. Not web input.
    # sobelow_skip ["Traversal.FileModule"]
    case File.read(path) do
      {:ok, json} -> parse_abi_json(json)
      {:error, reason} -> {:error, {:file_error, "#{path}: #{reason}"}}
    end
  end

  @doc "Reads and parses an ABI file, raising on failure."
  @spec parse_abi_file!(String.t()) :: parsed_abi()
  def parse_abi_file!(path) do
    case parse_abi_file(path) do
      {:ok, abi} -> abi
      {:error, reason} -> raise "ABI parse failed: #{inspect(reason)}"
    end
  end
end
