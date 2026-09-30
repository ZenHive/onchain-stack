defmodule Onchain.Tempo.Verification.Campaign.Mutant do
  @moduledoc false

  @enforce_keys [:id, :canary?, :surface, :file, :replace, :with, :class]
  defstruct [:id, :canary?, :surface, :file, :replace, :with, :class]

  @type t :: %__MODULE__{
          id: String.t(),
          canary?: boolean(),
          surface: :transaction | :builder | :codec | :native,
          file: String.t(),
          replace: String.t(),
          with: String.t(),
          class: atom()
        }
end

defmodule Onchain.Tempo.Verification.Campaign do
  @moduledoc false

  alias Onchain.Tempo.Codec
  alias Onchain.Tempo.Native
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder
  alias Onchain.Tempo.Verification.Campaign.Mutant
  alias Onchain.Tempo.Verification.Vectors

  @tx_rel "lib/onchain/tempo/transaction.ex"
  @builder_rel "lib/onchain/tempo/transaction/builder.ex"
  @codec_rel "lib/onchain/tempo/codec.ex"
  @native_rel "native/onchain_tempo/src/lib.rs"
  @key_auth_fixture "priv/verification/0x76/tempo_primitives_key_authorization.json"

  @type mutant :: Mutant.t()

  @spec mutants() :: [mutant()]
  def mutants do
    [
      %Mutant{
        id: "canary_field_rlp_skip",
        canary?: true,
        surface: :transaction,
        file: @tx_rel,
        replace: "chain_id: Codec.integer(transaction[\"chainId\"]), calls: calls, fields: fields",
        with: "chain_id: Codec.integer(transaction[\"gas\"]), calls: calls, fields: fields",
        class: :field_index
      },
      %Mutant{
        id: "canary_fee_payer_domain",
        canary?: true,
        surface: :transaction,
        file: @tx_rel,
        replace:
          ~s|transaction = Map.put(fields["transaction"], "feeToken", Codec.hex(fee_token))\n\n    with {:ok, sender_address} <- sender(tx),\n         {:ok, hash} <- Codec.run("fee_hash", %{"transaction" => transaction, "sender" => Codec.hex(sender_address)}),|,
        with:
          ~s|transaction = Map.put(fields["transaction"], "feeToken", Codec.hex(fee_token))\n\n    with {:ok, sender_address} <- sender(tx),\n         {:ok, hash} <- Codec.run("fee_hash", %{"transaction" => fields["transaction"], "sender" => Codec.hex(sender_address)}),|,
        class: :signing_domain
      },
      %Mutant{
        id: "canary_key_authorization_fee_hash",
        canary?: true,
        surface: :codec,
        file: @codec_rel,
        replace:
          "  def run(operation, request) do\n    with {:ok, json} <- Jason.encode(Map.put(request, \"operation\", operation)),",
        with:
          ~s|  def run(operation, request) do\n    request =\n      if operation == "fee_hash" do\n        Map.update!(request, "transaction", fn tx -> Map.put(tx, "keyAuthorization", nil) end)\n      else\n        request\n      end\n\n    with {:ok, json} <- Jason.encode(Map.put(request, "operation", operation)),|,
        class: :key_authorization
      },
      %Mutant{
        id: "type_byte_decode",
        canary?: false,
        surface: :native,
        file: @native_rel,
        replace: "if bytes.first() != Some(&0x76) {",
        with: "if bytes.first() != Some(&0x75) {",
        class: :type_byte
      },
      %Mutant{
        id: "type_byte_placeholder_encode",
        canary?: false,
        surface: :native,
        file: @native_rel,
        replace:
          "if request[\"placeholder\"].as_bool() == Some(true) {\n                signed.encode_for_fee_payer_service(&mut bytes);\n            } else {\n                signed.eip2718_encode(&mut bytes);\n            }",
        with:
          "if request[\"placeholder\"].as_bool() == Some(true) {\n                signed.eip2718_encode(&mut bytes);\n            } else {\n                signed.encode_for_fee_payer_service(&mut bytes);\n            }",
        class: :type_byte
      },
      %Mutant{
        id: "fee_token_cosign_field",
        canary?: false,
        surface: :transaction,
        file: @tx_rel,
        replace: ~s{Map.put(fields["transaction"], "feeToken", Codec.hex(fee_token))},
        with: ~s{Map.put(fields["transaction"], "feePayerSignature", Codec.hex(fee_token))},
        class: :field_index
      },
      %Mutant{
        id: "fee_payer_sig_cosign_field",
        canary?: false,
        surface: :transaction,
        file: @tx_rel,
        replace: "\"yParity\" => Codec.quantity(sig.recid)",
        with: "\"yParity\" => Codec.quantity(sig.r)",
        class: :field_index
      },
      %Mutant{
        id: "swap_nonce_fields",
        canary?: false,
        surface: :builder,
        file: @builder_rel,
        replace: ~s{"nonceKey" => Codec.quantity(nonce_key),\n        "nonce" => Codec.quantity(nonce),},
        with: ~s{"nonceKey" => Codec.quantity(nonce),\n        "nonce" => Codec.quantity(nonce_key),},
        class: :field_order
      },
      %Mutant{
        id: "numeric_placeholder_rlp",
        canary?: false,
        surface: :native,
        file: @native_rel,
        replace: "normalized[offset] = 0x80;",
        with: "normalized[offset] = 0x00;",
        class: :numeric_encoding
      },
      %Mutant{
        id: "signature_v_raw_recid",
        canary?: false,
        surface: :codec,
        file: @codec_rel,
        replace: "hex(<<sig.r::256, sig.s::256, sig.recid + 27>>)",
        with: "hex(<<sig.s::256, sig.r::256, sig.recid + 27>>)",
        class: :signature_recovery
      },
      %Mutant{
        id: "skip_placeholder_adapt",
        canary?: false,
        surface: :native,
        file: @native_rel,
        replace:
          "if placeholder {\n        let offset = normalized.len() - cursor.len();\n        normalized[offset] = 0x80;\n    }",
        with: "if placeholder {\n    }",
        class: :fee_payer_data
      },
      %Mutant{
        id: "sender_wrong_recovery_preimage",
        canary?: false,
        surface: :native,
        file: @native_rel,
        replace: ".recover_address_from_prehash(&tx.signature_hash())",
        with: ".recover_address_from_prehash(&alloy_primitives::B256::ZERO)",
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

  @spec evaluate(mutant()) :: map()
  defp evaluate(%Mutant{surface: surface} = mutant) when surface in [:native, :codec] do
    case with_patched_source(mutant, fn ->
           Map.merge(mutant_meta(mutant), oracle_verdict(mutant, nil))
         end) do
      {:error, {:pattern_missing, _} = reason} ->
        Map.merge(mutant_meta(mutant), %{status: :invalid, evidence: reason})

      {:error, reason} ->
        Map.merge(mutant_meta(mutant), %{status: :killed, evidence: {:compile_error, reason}})

      result when is_map(result) ->
        result
    end
  end

  defp evaluate(mutant) do
    case compile_mutant(mutant) do
      {:ok, compiled} ->
        Map.merge(mutant_meta(mutant), oracle_verdict(mutant, compiled))

      {:error, {:pattern_missing, _} = reason} ->
        Map.merge(mutant_meta(mutant), %{status: :invalid, evidence: reason})

      {:error, reason} ->
        Map.merge(mutant_meta(mutant), %{status: :killed, evidence: {:compile_error, reason}})
    end
  end

  @spec mutant_meta(mutant()) :: map()
  defp mutant_meta(mutant) do
    %{id: mutant.id, canary?: mutant.canary?, class: mutant.class, surface: mutant.surface}
  end

  @spec compile_mutant(mutant()) :: {:ok, module()} | {:error, term()}
  defp compile_mutant(mutant) do
    path = source_path(mutant.file)
    source = File.read!(path)

    if String.contains?(source, mutant.replace) do
      patched = String.replace(source, mutant.replace, mutant.with)
      module = module_name(mutant)
      renamed = rename_defmodule(patched, mutant.surface, module)
      compile_renamed(renamed, path, module)
    else
      {:error, {:pattern_missing, mutant.replace}}
    end
  end

  @spec with_patched_source(mutant(), (-> term())) :: term() | {:error, term()}
  defp with_patched_source(mutant, continue) do
    path = source_path(mutant.file)
    original = File.read!(path)

    if String.contains?(original, mutant.replace) do
      File.write!(path, String.replace(original, mutant.replace, mutant.with, global: false))

      try do
        with :ok <- recompile_native!(), do: continue.()
      after
        File.write!(path, original)
        _ = recompile_native!()
      end
    else
      {:error, {:pattern_missing, mutant.replace}}
    end
  end

  @spec recompile_native!() :: :ok | {:error, term()}
  defp recompile_native! do
    env = [
      {"ONCHAIN_TEMPO_BUILD", "1"},
      {"ONCHAIN_BUILD", "1"},
      {"MIX_ENV", "test"}
    ]

    case System.cmd("mix", ["compile", "--force"],
           cd: package_root(),
           env: env,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        reload_native_nif!()
        :ok

      {output, _} ->
        {:error, String.trim(output)}
    end
  end

  @spec reload_native_nif!() :: :ok
  defp reload_native_nif! do
    modules = [
      Builder,
      Transaction,
      Codec,
      Native
    ]

    for mod <- modules do
      :code.purge(mod)
      :code.delete(mod)
    end

    {:module, _} = Code.ensure_compiled(Native)
    {:module, _} = Code.ensure_compiled(Codec)
    {:module, _} = Code.ensure_compiled(Transaction)
    {:module, _} = Code.ensure_compiled(Builder)
    :ok
  end

  @spec package_root() :: String.t()
  defp package_root do
    __DIR__
    |> Path.join("../../..")
    |> Path.expand()
  end

  @spec source_path(String.t()) :: String.t()
  defp source_path(rel), do: Path.join(package_root(), rel)

  @spec compile_renamed(String.t(), String.t(), module()) :: {:ok, module()} | {:error, term()}
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
    catch
      kind, reason -> {:error, Exception.format_banner(kind, reason)}
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  @spec rename_defmodule(String.t(), :transaction | :builder, module()) :: String.t()
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

  @spec module_name(mutant()) :: module()
  defp module_name(mutant) do
    suffix =
      mutant.id
      |> String.split("_")
      |> Enum.map_join(&String.capitalize/1)

    Module.concat(Onchain.Tempo.Verification.Mutant, suffix)
  end

  @spec purge(module()) :: boolean()
  defp purge(module) do
    :code.purge(module)
    :code.delete(module)
  end

  @spec oracle_verdict(mutant(), module() | nil) :: %{status: atom(), evidence: term()}
  defp oracle_verdict(mutant, compiled) do
    builder = pick_module(compiled, mutant, :builder, Builder)
    txmod = pick_module(compiled, mutant, :transaction, Transaction)

    mismatches =
      []
      |> Kernel.++(builder_mismatches(builder))
      |> Kernel.++(transaction_mismatches(txmod))
      |> Kernel.++(key_authorization_mismatches())

    if mismatches == [] do
      %{status: :survived, evidence: :oracle_still_green}
    else
      %{status: :killed, evidence: mismatches}
    end
  end

  @spec pick_module(module() | nil, mutant(), :builder | :transaction, module()) :: module()
  defp pick_module(compiled, %{surface: :builder}, :builder, _default) when is_atom(compiled), do: compiled
  defp pick_module(compiled, %{surface: :transaction}, :transaction, _default) when is_atom(compiled), do: compiled
  defp pick_module(_, _, _, default), do: default

  @spec builder_mismatches(module()) :: [term()]
  defp builder_mismatches(builder) do
    opts = builder_opts()
    check_self_paid(builder, opts) ++ check_nonce_lanes(builder, opts)
  end

  @spec builder_opts() :: keyword()
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

  @spec check_self_paid(module(), keyword()) :: [term()]
  defp check_self_paid(builder, opts) do
    expected = Vectors.case!("self_paid_transfer")["serialized"]

    case builder.build_signed_transfer(opts) do
      {:ok, hex} -> same_hex(hex, expected, :builder_serialized)
      other -> [{:builder_error, other}]
    end
  end

  @spec check_nonce_lanes(module(), keyword()) :: [term()]
  defp check_nonce_lanes(builder, opts) do
    case builder.build_signed_transfer(Keyword.merge(opts, nonce: 5, nonce_key: 2)) do
      {:ok, hex} -> lanes_from_hex(hex)
      other -> [{:builder_lane_error, other}]
    end
  end

  @spec lanes_from_hex(String.t()) :: [term()]
  defp lanes_from_hex(hex) do
    case Transaction.deserialize(hex) do
      {:ok, tx} -> lanes_from_tx(tx)
      other -> [{:lane_deserialize, other}]
    end
  end

  @spec lanes_from_tx(term()) :: [term()]
  defp lanes_from_tx(tx) do
    nonce_key = Codec.integer(tx.fields["transaction"]["nonceKey"])
    nonce = Codec.integer(tx.fields["transaction"]["nonce"])

    case {nonce_key, nonce} do
      {2, 5} -> []
      pair -> [{:nonce_lanes, pair}]
    end
  end

  @spec transaction_mismatches(module()) :: [term()]
  defp transaction_mismatches(txmod) do
    check_self_paid_identity(txmod) ++ check_fee_payer_cosign(txmod)
  end

  @spec key_authorization_mismatches() :: [term()]
  defp key_authorization_mismatches do
    vector = key_authorization_vector()
    fee_token = Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)

    case Transaction.deserialize(vector["serialized"]) do
      {:ok, tx} ->
        with {:ok, sender} <- txmod_sender(Transaction, tx),
             transaction = Map.put(tx.fields["transaction"], "feeToken", Codec.hex(fee_token)),
             {:ok, hash} <-
               Codec.run("fee_hash", %{"transaction" => transaction, "sender" => Codec.hex(sender)}) do
          if hash == vector["fee_payer_hash"] do
            []
          else
            [{:key_auth_fee_hash, hash, vector["fee_payer_hash"]}]
          end
        else
          other -> [{:key_auth_fee_hash_error, other}]
        end

      other ->
        [{:key_auth_deserialize, other}]
    end
  end

  @spec key_authorization_vector() :: map()
  defp key_authorization_vector do
    :onchain_tempo
    |> Application.app_dir(@key_auth_fixture)
    |> File.read!()
    |> Jason.decode!()
  end

  @spec txmod_sender(module(), term()) :: {:ok, binary()} | {:error, term()}
  defp txmod_sender(txmod, tx), do: txmod.sender(tx)

  @spec check_self_paid_identity(module()) :: [term()]
  defp check_self_paid_identity(txmod) do
    paid = Vectors.case!("self_paid_transfer")

    case txmod.deserialize(paid["serialized"]) do
      {:ok, tx} -> identity_mismatches(txmod, tx, paid)
      other -> [{:deserialize, other}]
    end
  end

  @spec identity_mismatches(module(), term(), map()) :: [term()]
  defp identity_mismatches(txmod, tx, paid) do
    sender_ok = sender_matches?(txmod_sender(txmod, tx), paid["sender"])

    case {tx.chain_id, sender_ok, tx.calls} do
      {42_431, true, [_]} -> []
      {chain, sender, calls} -> [{:deserialize_or_sender, chain, sender, calls}]
    end
  end

  @spec check_fee_payer_cosign(module()) :: [term()]
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

  @spec cosign_mismatches(module(), term(), binary(), binary(), map()) :: [term()]
  defp cosign_mismatches(txmod, tx, fee_key, fee_token, fp) do
    case txmod.cosign_fee_payer(tx, fee_key, fee_token) do
      {:ok, cosigned} -> cosign_result(txmod, cosigned, fp)
      other -> [{:cosign_error, other}]
    end
  end

  @spec cosign_result(module(), term(), map()) :: [term()]
  defp cosign_result(txmod, cosigned, fp) do
    bytes = same_hex(cosigned.raw, fp["cosigned"], :cosign)
    sender_ok = sender_matches?(txmod_sender(txmod, cosigned), fp["sender"])

    case {bytes, sender_ok} do
      {[], true} -> []
      {[], false} -> [{:cosign_sender_recovery, false}]
      {mismatch, _} -> mismatch
    end
  end

  @spec sender_matches?({:ok, binary()} | term(), term()) :: boolean()
  defp sender_matches?({:ok, addr}, expected) do
    "0x" <> Base.encode16(addr, case: :lower) == String.downcase(expected)
  end

  defp sender_matches?(_, _), do: false

  @spec same_hex(String.t(), String.t(), atom()) :: [term()]
  defp same_hex(actual, expected, tag) do
    if String.downcase(actual) == String.downcase(expected) do
      []
    else
      [{tag, expected, actual}]
    end
  end
end
