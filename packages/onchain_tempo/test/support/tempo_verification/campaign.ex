defmodule Onchain.Tempo.Verification.Campaign do
  @moduledoc false

  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder
  alias Onchain.Tempo.Verification.Vectors

  @tx_path "lib/onchain/tempo/transaction.ex"
  @builder_path "lib/onchain/tempo/transaction/builder.ex"

  @type mutant :: %{
          id: String.t(),
          canary?: boolean(),
          surface: :transaction | :builder,
          file: String.t(),
          replace: String.t(),
          with: String.t(),
          class: atom()
        }

  @spec mutants() :: [mutant()]
  def mutants do
    [
      %{
        id: "canary_calls_index",
        canary?: true,
        surface: :transaction,
        file: @tx_path,
        replace: "@calls_index 4",
        with: "@calls_index 3",
        class: :field_index
      },
      %{
        id: "canary_fee_payer_domain",
        canary?: true,
        surface: :transaction,
        file: @tx_path,
        replace: "@fee_payer_domain 0x78",
        with: "@fee_payer_domain 0x76",
        class: :signing_domain
      },
      %{
        id: "type_byte_builder",
        canary?: false,
        surface: :builder,
        file: @builder_path,
        replace: "@tempo_tx_type 0x76",
        with: "@tempo_tx_type 0x77",
        class: :type_byte
      },
      %{
        id: "type_byte_deserialize",
        canary?: false,
        surface: :transaction,
        file: @tx_path,
        replace: "@tempo_tx_type 0x76",
        with: "@tempo_tx_type 0x75",
        class: :type_byte
      },
      %{
        id: "fee_token_index",
        canary?: false,
        surface: :transaction,
        file: @tx_path,
        replace: "@fee_token_index 10",
        with: "@fee_token_index 11",
        class: :field_index
      },
      %{
        id: "fee_payer_sig_index",
        canary?: false,
        surface: :transaction,
        file: @tx_path,
        replace: "@fee_payer_sig_index 11",
        with: "@fee_payer_sig_index 10",
        class: :field_index
      },
      %{
        id: "swap_nonce_fields",
        canary?: false,
        surface: :builder,
        file: @builder_path,
        replace: "encode_uint(nonce_key),\n        encode_uint(nonce),",
        with: "encode_uint(nonce),\n        encode_uint(nonce_key),",
        class: :field_order
      },
      %{
        id: "numeric_zero_byte",
        canary?: false,
        surface: :builder,
        file: @builder_path,
        replace: "defp encode_uint(0), do: <<>>",
        with: "defp encode_uint(0), do: <<0>>",
        class: :numeric_encoding
      },
      %{
        id: "signature_v_raw_recid",
        canary?: false,
        surface: :builder,
        file: @builder_path,
        replace: "v = recid + 27",
        with: "v = recid",
        class: :signature_recovery
      },
      %{
        id: "skip_placeholder_reset",
        canary?: false,
        surface: :transaction,
        file: @tx_path,
        replace: "|> List.replace_at(@fee_payer_sig_index, <<0x00>>)",
        with: "|> List.replace_at(@fee_payer_sig_index, <<>>)",
        class: :fee_payer_data
      },
      %{
        id: "recover_ignore_legacy_v",
        canary?: false,
        surface: :transaction,
        file: @tx_path,
        replace: "recid = if v >= 27, do: v - 27, else: v",
        with: "recid = v",
        class: :signature_recovery
      }
    ]
  end

  @spec canary_ids() :: [String.t()]
  def canary_ids, do: Enum.map(Enum.filter(mutants(), & &1.canary?), & &1.id)

  @spec run() :: [map()]
  def run do
    Enum.map(mutants(), &evaluate/1)
  end

  defp evaluate(mutant) do
    case compile_mutant(mutant) do
      {:ok, module} ->
        verdict = oracle_verdict(mutant, module)
        Map.merge(mutant_meta(mutant), verdict)

      {:error, {:pattern_missing, _} = reason} ->
        # The mutant never applied — that is a broken campaign, not a kill.
        Map.merge(mutant_meta(mutant), %{status: :invalid, evidence: reason})

      {:error, reason} ->
        Map.merge(mutant_meta(mutant), %{status: :killed, evidence: {:compile_error, reason}})
    end
  end

  defp mutant_meta(mutant) do
    %{id: mutant.id, canary?: mutant.canary?, class: mutant.class, surface: mutant.surface}
  end

  defp compile_mutant(mutant) do
    source = File.read!(mutant.file)

    if String.contains?(source, mutant.replace) do
      patched = String.replace(source, mutant.replace, mutant.with)
      module = module_name(mutant)
      renamed = rename_defmodule(patched, mutant.surface, module)
      compile_renamed(renamed, mutant.file, module)
    else
      {:error, {:pattern_missing, mutant.replace}}
    end
  end

  defp compile_renamed(renamed, file, module) do
    previous = Code.get_compiler_option(:ignore_module_conflict)

    try do
      Code.put_compiler_option(:ignore_module_conflict, true)
      purge(module)
      compiled = Code.compile_string(renamed, file)

      case List.keyfind(compiled, module, 0) do
        {^module, _} -> {:ok, module}
        nil -> {:error, {:module_missing, Enum.map(compiled, &elem(&1, 0))}}
      end
    rescue
      e -> {:error, Exception.message(e)}
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  defp rename_defmodule(source, :transaction, module) do
    String.replace(source, "defmodule Onchain.Tempo.Transaction do", "defmodule #{inspect(module)} do", global: false)
  end

  defp rename_defmodule(source, :builder, module) do
    String.replace(
      source,
      "defmodule Onchain.Tempo.Transaction.Builder do",
      "defmodule #{inspect(module)} do",
      global: false
    )
  end

  defp module_name(mutant) do
    suffix =
      mutant.id
      |> String.split("_")
      |> Enum.map_join(&String.capitalize/1)

    Module.concat(Onchain.Tempo.Verification.Mutant, suffix)
  end

  defp purge(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp oracle_verdict(mutant, module) do
    builder = if mutant.surface == :builder, do: module, else: Builder
    txmod = if mutant.surface == :transaction, do: module, else: Transaction

    mismatches =
      []
      |> Kernel.++(builder_mismatches(builder))
      |> Kernel.++(transaction_mismatches(txmod))

    if mismatches == [] do
      %{status: :survived, evidence: :oracle_still_green}
    else
      %{status: :killed, evidence: mismatches}
    end
  end

  defp builder_mismatches(builder) do
    opts = builder_opts()
    check_self_paid(builder, opts) ++ check_nonce_lanes(builder, opts)
  end

  defp builder_opts do
    keys = Vectors.keys()

    [
      private_key: keys["sender_private_key"],
      token: "0x20c0000000000000000000000000000000000000",
      recipient: "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
      amount: 1_000_000,
      chain_id: 42_431,
      rpc_url: "http://localhost",
      nonce: 0,
      gas_limit: 500_000,
      fee_token: "0x20c0000000000000000000000000000000000000"
    ]
  end

  defp check_self_paid(builder, opts) do
    expected = Vectors.case!("self_paid_transfer")["serialized"]

    case builder.build_signed_transfer(opts) do
      {:ok, hex} -> same_hex(hex, expected, :builder_serialized)
      other -> [{:builder_error, other}]
    end
  end

  defp check_nonce_lanes(builder, opts) do
    case builder.build_signed_transfer(Keyword.merge(opts, nonce: 5, nonce_key: 2)) do
      {:ok, hex} -> lanes_from_hex(hex)
      other -> [{:builder_lane_error, other}]
    end
  end

  defp lanes_from_hex(hex) do
    case Transaction.deserialize(hex) do
      {:ok, tx} -> lanes_from_tx(tx)
      other -> [{:lane_deserialize, other}]
    end
  end

  defp lanes_from_tx(tx) do
    nonce_key = field_int(Enum.at(tx.fields, 6))
    nonce = field_int(Enum.at(tx.fields, 7))

    case {nonce_key, nonce} do
      {2, 5} -> []
      pair -> [{:nonce_lanes, pair}]
    end
  end

  defp field_int(<<>>), do: 0
  defp field_int(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
  defp field_int(_), do: :not_int

  defp transaction_mismatches(txmod) do
    check_self_paid_identity(txmod) ++ check_fee_payer_cosign(txmod)
  end

  defp check_self_paid_identity(txmod) do
    paid = Vectors.case!("self_paid_transfer")

    case txmod.deserialize(paid["serialized"]) do
      {:ok, tx} -> identity_mismatches(txmod, tx, paid)
      other -> [{:deserialize, other}]
    end
  end

  defp identity_mismatches(txmod, tx, paid) do
    sender_ok = sender_matches?(txmod.sender(tx), paid["sender"])

    case {tx.chain_id, sender_ok, tx.calls} do
      {42_431, true, [_]} -> []
      {chain, sender, calls} -> [{:deserialize_or_sender, chain, sender, calls}]
    end
  end

  defp check_fee_payer_cosign(txmod) do
    fp = Vectors.case!("fee_payer_placeholder")
    keys = Vectors.keys()
    fee_token = Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
    fee_key = Base.decode16!(String.trim_leading(keys["fee_payer_private_key"], "0x"), case: :lower)

    case txmod.deserialize(fp["serialized"]) do
      {:ok, tx} -> cosign_mismatches(txmod, tx, fee_key, fee_token, fp)
      other -> [{:cosign_deserialize, other}]
    end
  end

  defp cosign_mismatches(txmod, tx, fee_key, fee_token, fp) do
    case txmod.cosign_fee_payer(tx, fee_key, fee_token) do
      {:ok, cosigned} -> cosign_result(txmod, cosigned, fp)
      other -> [{:cosign_error, other}]
    end
  end

  defp cosign_result(txmod, cosigned, fp) do
    bytes = same_hex(cosigned.raw, fp["cosigned"], :cosign)
    sender_ok = sender_matches?(txmod.sender(cosigned), fp["sender"])

    case {bytes, sender_ok} do
      {[], true} -> []
      {[], false} -> [{:cosign_sender_recovery, false}]
      {mismatch, _} -> mismatch
    end
  end

  defp sender_matches?({:ok, addr}, expected) do
    "0x" <> Base.encode16(addr, case: :lower) == String.downcase(expected)
  end

  defp sender_matches?(_, _), do: false

  defp same_hex(actual, expected, tag) do
    if String.downcase(actual) == String.downcase(expected) do
      []
    else
      [{tag, expected, actual}]
    end
  end
end
