defmodule Onchain.ENS.Normalize do
  @moduledoc false

  # ENSIP-15 / UTS-46 name normalization (pragmatic subset).
  #
  # Applied to an ENS name before EIP-137 namehash so that case-variant and
  # Unicode-equivalent spellings collapse to the same node. The ordered steps
  # mirror the ENSIP-15 reference algorithm (ens-normalize.js):
  #
  #   1. split into dot-separated labels, rejecting empty labels
  #   2. map each label: Unicode case-fold (lowercase) + drop ignored code points
  #      (variation selectors FE0E/FE0F, soft hyphen)
  #   3. apply NFC (Unicode Normalization Form C — NOT NFKC) per label
  #   4. validate: reject disallowed code points (C0/C1 controls, zero-width and
  #      format characters, BOM)
  #
  # ## Scope boundary (honest)
  #
  # This implements the deterministic transformations of ENSIP-15 that are
  # exactly defined by the Unicode standard (NFC via OTP `:unicode`, case
  # folding via `String.downcase/1`) plus a curated ignored/disallowed set. It
  # does NOT implement the ENSIP-15 *security* filters — confusable detection,
  # script-group mixing, combining-mark (NSM) limits, fenced-character rules —
  # because those require the generated ENSIP-15 spec data tables (hundreds of
  # KB). A name that survives normalization here is byte-canonical but NOT
  # certified non-confusable. Callers performing security-sensitive resolution
  # should additionally validate against a full ENSIP-15 implementation.
  #
  # Reference: https://docs.ens.domains/ensip/15

  # Code points removed during mapping (ENSIP-15 "ignored" / emoji presentation
  # selectors stripped before hashing).
  @ignored MapSet.new([
             0xFE0F,
             0xFE0E,
             0x00AD
           ])

  # Non-control code points that ENSIP-15 disallows: zero-width spaces/joiners,
  # word joiner, line/paragraph separators, no-break space, and the BOM.
  @disallowed MapSet.new([
                0x00A0,
                0x200B,
                0x200C,
                0x200D,
                0x2028,
                0x2029,
                0x2060,
                0xFEFF
              ])

  @doc false
  @spec normalize(term()) :: {:ok, String.t()} | {:error, {:invalid_name, term()}}
  def normalize(""), do: {:ok, ""}

  def normalize(name) when is_binary(name) do
    case String.trim_trailing(name, ".") do
      "" ->
        # name was non-empty but became empty (e.g. "." or "..") — not the root.
        {:error, {:invalid_name, name}}

      trimmed ->
        trimmed
        |> String.split(".")
        |> normalize_labels(name)
    end
  end

  def normalize(other), do: {:error, {:invalid_name, other}}

  @spec normalize_labels([String.t()], term()) ::
          {:ok, String.t()} | {:error, {:invalid_name, term()}}
  defp normalize_labels(labels, original) do
    labels
    |> Enum.reduce_while({:ok, []}, fn label, {:ok, acc} ->
      case normalize_label(label) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} -> {:halt, {:error, {:invalid_name, original}}}
      end
    end)
    |> case do
      {:ok, normalized_labels} ->
        {:ok, normalized_labels |> Enum.reverse() |> Enum.join(".")}

      error ->
        error
    end
  end

  @spec normalize_label(String.t()) :: {:ok, String.t()} | {:error, atom()}
  defp normalize_label(""), do: {:error, :empty_label}

  defp normalize_label(label) do
    mapped =
      label
      |> String.downcase()
      |> strip_ignored()

    case :unicode.characters_to_nfc_binary(mapped) do
      nfc when is_binary(nfc) ->
        cond do
          nfc == "" -> {:error, :empty_label}
          has_disallowed?(nfc) -> {:error, :disallowed}
          true -> {:ok, nfc}
        end

      _ ->
        {:error, :invalid_encoding}
    end
  end

  @spec strip_ignored(String.t()) :: String.t()
  defp strip_ignored(str) do
    for <<cp::utf8 <- str>>, not MapSet.member?(@ignored, cp), into: "", do: <<cp::utf8>>
  end

  @spec has_disallowed?(String.t()) :: boolean()
  defp has_disallowed?(str) do
    Enum.any?(String.to_charlist(str), &disallowed_cp?/1)
  end

  @spec disallowed_cp?(non_neg_integer()) :: boolean()
  defp disallowed_cp?(cp) when cp < 0x20, do: true
  defp disallowed_cp?(cp) when cp >= 0x7F and cp <= 0x9F, do: true
  defp disallowed_cp?(cp), do: MapSet.member?(@disallowed, cp)
end
