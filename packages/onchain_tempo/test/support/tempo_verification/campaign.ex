defmodule Onchain.Tempo.Verification.Campaign.Mutant do
  @moduledoc false

  # One planted mutation: which file to patch, the exact literal to swap, and
  # how to classify the result. A bare map with the same seven keys at every
  # call site trips reach's "repeated map shapes" check; it is a contract.

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
  @scratch_dir "_build/tempo_verification_scratch"
  @scratch_crate "onchain_tempo_mutant"
  @tracked_patch_files [@native_rel, @codec_rel]

  @type mutant :: Mutant.t()

  @spec mutants() :: [mutant()]
  def mutants do
    [
      %Mutant{
        id: "canary_field_rlp_skip",
        canary?: true,
        surface: :transaction,
        file: @tx_rel,
        replace: "{:ok, Codec.decoded(result, hex)}",
        with: "{:ok, %{Codec.decoded(result, hex) | chain_id: 0}}",
        class: :field_index
      },
      %Mutant{
        id: "canary_fee_payer_domain",
        canary?: true,
        surface: :transaction,
        file: @tx_rel,
        replace: ~s|Codec.run("fee_hash", Map.put(request, "sender", Codec.hex(sender_address)))|,
        with: ~s|Codec.run("fee_hash", Map.put(Codec.request(tx), "sender", Codec.hex(sender_address)))|,
        class: :signing_domain
      },
      %Mutant{
        id: "canary_key_authorization_fee_hash",
        canary?: true,
        surface: :native,
        file: @native_rel,
        replace: "Ok(json!(tx.fee_payer_signature_hash(sender)))",
        with:
          "let mut tx = tx;\n            tx.key_authorization = None;\n            Ok(json!(tx.fee_payer_signature_hash(sender)))",
        class: :key_authorization
      },
      %Mutant{
        id: "key_authorization_sender_prepare",
        canary?: false,
        surface: :native,
        file: @native_rel,
        replace: "let mut payload = Vec::new();\n            tx.encode_for_signing(&mut payload);",
        with:
          "let mut tx = tx;\n            tx.key_authorization = None;\n            let mut payload = Vec::new();\n            tx.encode_for_signing(&mut payload);",
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
        replace: "signed = %{tx | fee_token: fee_token,",
        with: "signed = %{tx | fee_token: nil,",
        class: :field_index
      },
      %Mutant{
        id: "fee_payer_sig_cosign_field",
        canary?: false,
        surface: :transaction,
        file: @tx_rel,
        replace: "y_parity: sig.recid",
        with: "y_parity: sig.r",
        class: :field_index
      },
      %Mutant{
        id: "swap_nonce_fields",
        canary?: false,
        surface: :builder,
        file: @builder_rel,
        replace: "nonce_key: nonce_key,\n        nonce: nonce,",
        with: "nonce_key: nonce,\n        nonce: nonce_key,",
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
        replace: "%{r: sig.r, s: sig.s, y_parity: sig.recid}",
        with: "%{r: sig.s, s: sig.r, y_parity: sig.recid}",
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
        replace: ".recover_signer(&tx.signature_hash())",
        with: ".recover_signer(&alloy_primitives::B256::ZERO)",
        class: :signature_recovery
      }
    ]
  end

  @spec canary_ids() :: [String.t()]
  def canary_ids, do: Enum.map(Enum.filter(mutants(), & &1.canary?), & &1.id)

  @doc false
  @spec tracked_patch_files() :: [String.t()]
  def tracked_patch_files, do: @tracked_patch_files

  @spec run() :: [map()]
  def run do
    assert_tracked_patch_targets_clean!()
    Enum.map(mutants(), &evaluate/1)
  end

  @spec evaluate(mutant()) :: map()
  defp evaluate(%Mutant{surface: surface} = mutant) when surface in [:native, :codec] do
    case with_patched_source(mutant, fn ->
           Map.merge(mutant_meta(mutant), oracle_verdict(mutant, nil))
         end) do
      {:error, {:pattern_missing, _} = reason} ->
        Map.merge(mutant_meta(mutant), %{status: :invalid, evidence: reason})

      # A source mutant that no longer builds tested nothing; the patterns are
      # chosen to compile, so a build failure breaks the campaign.
      {:error, reason} ->
        Map.merge(mutant_meta(mutant), %{status: :invalid, evidence: {:build_failed, reason}})

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

  # Mutants never touch tracked files, `priv/native`, or the tracked crate's
  # build outputs: a hard kill mid-mutant can leave debris only under
  # `_build/tempo_verification_scratch`. Codec mutants live in memory; native
  # mutants build a renamed copy of the crate (so its cdylib cannot collide
  # with `libonchain_tempo.so` in the shared, warm target dir) and load it into
  # an in-memory `Native` stub. Restoring reloads the on-disk beams.
  @spec with_patched_source(mutant(), (-> term())) :: term() | {:error, term()}
  defp with_patched_source(mutant, continue) do
    source = File.read!(source_path(mutant.file))

    if String.contains?(source, mutant.replace) do
      patched = String.replace(source, mutant.replace, mutant.with, global: false)

      try do
        with :ok <- load_patched(mutant, patched), do: continue.()
      after
        restore_from_disk!(if mutant.surface == :native, do: Native, else: Codec)
      end
    else
      {:error, {:pattern_missing, mutant.replace}}
    end
  end

  @spec load_patched(mutant(), String.t()) :: :ok | {:error, term()}
  defp load_patched(%Mutant{surface: :codec, file: file}, patched) do
    compile_in_memory(Codec, patched, source_path(file))
  end

  defp load_patched(%Mutant{surface: :native} = mutant, patched) do
    with {:ok, so_path} <- build_native_scratch(mutant.id, patched) do
      compile_in_memory(Native, native_stub(so_path), "native_stub")
    end
  end

  @doc false
  @spec assert_tracked_patch_targets_clean!(String.t()) :: :ok
  def assert_tracked_patch_targets_clean!(repo_root \\ monorepo_root()) do
    paths = Enum.map(@tracked_patch_files, &Path.join("packages/onchain_tempo", &1))

    for {args, label} <- [
          {["diff", "--quiet", "--"], "unstaged"},
          {["diff", "--cached", "--quiet", "--"], "staged"}
        ] do
      case System.cmd("git", args ++ paths, cd: repo_root, stderr_to_stdout: true) do
        {"", 0} ->
          :ok

        {output, _} ->
          raise """
          mutation campaign refuses to run: tracked patch target has #{label} changes (#{inspect(paths)}).
          Restore or commit before re-running. git output: #{String.trim(output)}
          """
      end
    end

    :ok
  end

  @spec monorepo_root() :: String.t()
  defp monorepo_root, do: Path.expand("../..", package_root())

  @spec scratch_root() :: String.t()
  defp scratch_root, do: Path.join(package_root(), @scratch_dir)

  # Returns the path (without extension, as `:erlang.load_nif/2` expects) of a
  # per-mutant copy of the built cdylib; a fresh path per mutant sidesteps the
  # dynamic loader handing back an already-open library for a reused name.
  @spec build_native_scratch(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp build_native_scratch(id, patched_rs) do
    crate = Path.join(scratch_root(), "crate")
    tracked = Path.join(package_root(), "native/onchain_tempo")
    target = Path.join(tracked, "target")

    File.rm_rf!(crate)
    File.mkdir_p!(Path.join(crate, "src"))
    File.cp!(Path.join(tracked, "Cargo.lock"), Path.join(crate, "Cargo.lock"))

    manifest = File.read!(Path.join(tracked, "Cargo.toml"))
    renamed = String.replace(manifest, ~s(name = "onchain_tempo"), ~s(name = "#{@scratch_crate}"), global: false)
    # An unrenamed copy would overwrite the tracked crate's cdylib in the shared target dir.
    if renamed == manifest, do: raise("scratch crate rename failed: Cargo.toml has no name = \"onchain_tempo\"")
    File.write!(Path.join(crate, "Cargo.toml"), renamed)

    File.write!(Path.join(crate, "src/lib.rs"), patched_rs)

    case System.cmd("cargo", ["build", "--release", "--quiet"],
           cd: crate,
           env: [{"CARGO_TARGET_DIR", target}],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        nif = Path.join([scratch_root(), "nif", id])
        File.mkdir_p!(Path.dirname(nif))
        # `:erlang.load_nif/2` appends `.so` on every unix, macOS included.
        File.cp!(Path.join(target, "release/lib#{@scratch_crate}.#{dylib_ext()}"), nif <> ".so")
        {:ok, nif}

      {output, _} ->
        {:error, String.trim(output)}
    end
  end

  @spec dylib_ext() :: String.t()
  defp dylib_ext, do: if(match?({:unix, :darwin}, :os.type()), do: "dylib", else: "so")

  @spec native_stub(String.t()) :: String.t()
  defp native_stub(so_path) do
    """
    defmodule Onchain.Tempo.Native do
      @moduledoc false
      @on_load :load_mutant_nif
      def load_mutant_nif, do: :erlang.load_nif(#{inspect(String.to_charlist(so_path))}, 0)
      def transaction_json(_input), do: :erlang.nif_error(:nif_not_loaded)
    end
    """
  end

  @spec compile_in_memory(module(), String.t(), String.t()) :: :ok | {:error, term()}
  defp compile_in_memory(module, source, file) do
    previous = Code.get_compiler_option(:ignore_module_conflict)

    try do
      Code.put_compiler_option(:ignore_module_conflict, true)
      purge(module)

      case Code.compile_string(source, file) do
        [{^module, _}] -> :ok
        compiled -> {:error, {:module_missing, Enum.map(compiled, &elem(&1, 0))}}
      end
    catch
      kind, reason -> {:error, Exception.format_banner(kind, reason)}
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  @spec restore_from_disk!(module()) :: :ok
  defp restore_from_disk!(module) do
    purge(module)
    {:module, ^module} = :code.load_file(module)
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
      # Deliberately `catch`, not `rescue`: this compiles attacker-shaped
      # source, and a mutated module can exit or throw as well as raise — a
      # `rescue` would let those escape and abort the campaign instead of
      # recording the mutant as uncompilable.
      kind, reason -> {:error, Exception.format_banner(kind, reason)}
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  @spec rename_defmodule(String.t(), :transaction | :builder, module()) :: String.t()
  # Codec still builds `%Onchain.Tempo.Transaction{}`, so the renamed mutant must
  # pattern-match that struct rather than its own `__MODULE__` struct.
  defp rename_defmodule(source, :transaction, module) do
    source
    |> String.replace("defmodule Onchain.Tempo.Transaction do", "defmodule #{inspect(module)} do", global: false)
    |> String.replace("%__MODULE__{", "%Onchain.Tempo.Transaction{")
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
  # Purge again after delete so no old version is left holding a NIF library:
  # rustler NIFs refuse the `upgrade` path a lingering old version triggers.
  defp purge(module) do
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
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
    nonce_key = tx.nonce_key
    nonce = tx.nonce

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
        key_auth_signing_mismatches(tx, vector) ++ key_auth_fee_hash_mismatches(tx, vector, fee_token)

      other ->
        [{:key_auth_deserialize, other}]
    end
  end

  @spec key_auth_signing_mismatches(term(), map()) :: [term()]
  defp key_auth_signing_mismatches(tx, vector) do
    expected = vector["signing_hash"]

    case Codec.run("prepare", %{"transaction" => Codec.request(tx)["transaction"]}) do
      {:ok, %{"hash" => ^expected}} -> []
      {:ok, %{"hash" => hash}} -> [{:key_auth_signing_hash, hash, expected}]
      other -> [{:key_auth_signing_hash_error, other}]
    end
  end

  @spec key_auth_fee_hash_mismatches(term(), map(), binary()) :: [term()]
  defp key_auth_fee_hash_mismatches(tx, vector, fee_token) do
    transaction = Map.put(Codec.request(tx)["transaction"], "feeToken", Codec.hex(fee_token))

    with {:ok, sender} <- Transaction.sender(tx),
         {:ok, hash} <- Codec.run("fee_hash", %{"transaction" => transaction, "sender" => Codec.hex(sender)}) do
      if hash == vector["fee_payer_hash"], do: [], else: [{:key_auth_fee_hash, hash, vector["fee_payer_hash"]}]
    else
      other -> [{:key_auth_fee_hash_error, other}]
    end
  end

  @spec key_authorization_vector() :: map()
  defp key_authorization_vector do
    :onchain_tempo
    |> Application.app_dir(@key_auth_fixture)
    |> File.read!()
    |> Jason.decode!()
  end

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
    sender_ok = sender_matches?(txmod.sender(tx), paid["sender"])

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
    sender_ok = sender_matches?(txmod.sender(cosigned), fp["sender"])

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
