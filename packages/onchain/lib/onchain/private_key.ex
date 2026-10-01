defmodule Onchain.PrivateKey do
  @moduledoc false

  # Shared private-key normalization for `Onchain.AA` (ERC-4337 UserOperation
  # signing) and `Onchain.Signer` (raw transaction signing) — both accept the
  # same private-key input shapes (32-byte binary, or "0x"-optional 64-char hex
  # string) and must reject malformed ones identically before handing off to
  # signing. Extracted to satisfy `mix ex_dna --max-clones 0`.

  alias Onchain.Hex

  @doc false
  @spec decode(term()) :: {:ok, binary()} | {:error, {:invalid_private_key, term()}}
  def decode(bin) when is_binary(bin) and byte_size(bin) == 32, do: {:ok, bin}

  def decode(hex) when is_binary(hex) do
    case Hex.decode(hex) do
      {:ok, bin} when byte_size(bin) == 32 -> {:ok, bin}
      _ -> {:error, {:invalid_private_key, hex}}
    end
  end

  def decode(other), do: {:error, {:invalid_private_key, other}}
end
