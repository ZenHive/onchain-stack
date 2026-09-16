defmodule Onchain.Aerodrome.CalldataFixture do
  @moduledoc "Independent cast calldata references and Sugar-backed eth_call impersonation."

  import ExUnit.Assertions

  alias Onchain.ABI
  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.Contracts
  alias Onchain.Aerodrome.RPCCase
  alias Onchain.Hex
  alias Onchain.RPC
  alias Onchain.RPC.Helpers

  @doc "Encodes reference calldata with Foundry cast; arguments use cast's CLI syntax (including arrays and tuples)."
  @spec reference!(String.t(), [String.t()]) :: String.t()
  def reference!(signature, args) do
    cast =
      System.find_executable("cast") ||
        flunk("""
        Foundry cast is required on PATH; never a skip. Install with:
          curl -L https://getfoundry.sh/install | bash
          source ~/.bashrc  # or source ~/.zshrc
          foundryup
        """)

    case System.cmd(cast, ["calldata", signature | args], stderr_to_stdout: true) do
      {output, 0} ->
        reference = String.trim(output)
        assert Regex.match?(~r/\A0x(?:[0-9a-fA-F]{2}){4,}\z/, reference), "cast returned invalid calldata: #{output}"
        reference

      {output, status} ->
        flunk("cast calldata failed (exit #{status}): #{output}")
    end
  end

  @doc "Asserts byte equality against cast's reference, never against our encoder's output."
  @spec assert_calldata(String.t(), String.t(), [String.t()]) :: true
  def assert_calldata(actual, signature, args) do
    reference = reference!(signature, args)
    assert Hex.decode!(actual) == Hex.decode!(reference)
  end

  @doc """
  Simulates calldata with `from` discovered by a live VeSugar.byId read of `owner_id`.

  This stateless call proves only the simulated return bytes or the node's
  specific revert, not persisted state. Use a pinned Onchain.EVM fork for
  stateful evidence; never broadcast a real transaction from this helper.
  No private key is used.

  Returns raw response bytes or the unchanged RPC error (including revert data).
  Uses the current RPCCase endpoint unless overridden by `:rpc_url`. Pass a
  block tag or number in `:block` to pin both the Sugar read and impersonation;
  historical blocks require an archive-capable endpoint. No state overrides are sent.
  """
  @spec eth_call_as_sugar_owner(String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def eth_call_as_sugar_owner(to, calldata, owner_id, opts \\ []) do
    opts = Keyword.merge(RPCCase.rpc_opts!(), opts)

    with {:ok, block} <- Helpers.normalize_block(Keyword.get(opts, :block, "latest")),
         {:ok, from} <- sugar_owner(owner_id, Keyword.put(opts, :block, block)) do
      # eth_call/3 omits `from`; core's raw batch API preserves the call object.
      params = [%{"to" => to, "data" => calldata, "from" => from}, block]

      with {:ok, [result]} <- RPC.batch([{"eth_call", params}], opts), do: {:ok, result}
    end
  end

  @spec sugar_owner(non_neg_integer(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp sugar_owner(id, opts) do
    with {:ok, signature} <- Abi.signature("ve_sugar.json", "byId"),
         {:ok, return_type} <- Abi.return_type("ve_sugar.json", "byId"),
         {:ok, data} <- ABI.encode_call(signature, [id]),
         {:ok, response} <- RPC.eth_call(Contracts.address!(:ve_sugar), data, opts),
         {:ok, [nft]} <- ABI.decode_response(return_type, response) do
      owner_from_nft(nft, id)
    end
  end

  # Positional: VeNFT.id then VeNFT.account. Trailing field count is not load-bearing.
  @spec owner_from_nft(term(), non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  defp owner_from_nft(nft, id) when is_tuple(nft) and tuple_size(nft) >= 2 and elem(nft, 0) == id do
    case elem(nft, 1) do
      <<owner::binary-size(20)>> when owner != <<0::160>> -> {:ok, Hex.encode(owner)}
      _missing -> {:error, {:sugar_owner_not_found, id}}
    end
  end

  defp owner_from_nft(_nft, id), do: {:error, {:sugar_owner_not_found, id}}
end
