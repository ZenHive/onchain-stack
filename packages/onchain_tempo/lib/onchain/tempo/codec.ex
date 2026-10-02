defmodule Onchain.Tempo.Codec do
  @moduledoc false

  alias Onchain.Signer.Secp256k1
  alias Onchain.Tempo.Native
  alias Onchain.Tempo.Transaction

  @transaction [
    chain_id: {"chainId", :integer},
    fee_token: {"feeToken", :bytes},
    max_priority_fee_per_gas: {"maxPriorityFeePerGas", :integer},
    max_fee_per_gas: {"maxFeePerGas", :integer},
    gas_limit: {"gas", :integer},
    calls: {"calls", {:list, :call}},
    access_list: {"accessList", {:list, :access}},
    nonce_key: {"nonceKey", :integer},
    nonce: {"nonce", :integer},
    fee_payer_signature: {"feePayerSignature", :secp},
    valid_before: {"validBefore", :integer},
    valid_after: {"validAfter", :integer},
    key_authorization: {"keyAuthorization", :key_authorization},
    tempo_authorization_list: {"aaAuthorizationList", {:list, :authorization}}
  ]
  @schemas %{
    transaction: @transaction,
    call: [to: {"to", :bytes}, value: {"value", :integer}, input: {"input", :bytes}],
    access: [address: {"address", :bytes}, storage_keys: {"storageKeys", {:list, :bytes}}],
    secp: [r: {"r", :integer}, s: {"s", :integer}, y_parity: {"yParity", :integer}],
    p256: [
      r: {"r", :bytes},
      s: {"s", :bytes},
      pub_key_x: {"pubKeyX", :bytes},
      pub_key_y: {"pubKeyY", :bytes},
      pre_hash: {"preHash", :boolean}
    ],
    webauthn: [
      r: {"r", :bytes},
      s: {"s", :bytes},
      pub_key_x: {"pubKeyX", :bytes},
      pub_key_y: {"pubKeyY", :bytes},
      webauthn_data: {"webauthnData", :bytes}
    ],
    key_authorization: [
      chain_id: {"chainId", :integer},
      key_type: {"keyType", :key_type},
      key_id: {"keyId", :bytes},
      expiry: {"expiry", :integer},
      limits: {"limits", {:list, :limit}},
      allowed_calls: {"allowedCalls", {:list, :scope}},
      witness: {"witness", :bytes},
      is_admin: {"isAdmin", :boolean},
      account: {"account", :bytes},
      signature: {"signature", :signature}
    ],
    limit: [token: {"token", :bytes}, limit: {"limit", :integer}, period: {"period", :integer}],
    scope: [target: {"target", :bytes}, selector_rules: {"selectorRules", {:list, :rule}}],
    rule: [selector: {"selector", :bytes}, recipients: {"recipients", {:list, :bytes}}],
    authorization: [
      chain_id: {"chainId", :integer},
      address: {"address", :bytes},
      nonce: {"nonce", :integer},
      signature: {"signature", :signature}
    ]
  }

  @doc false
  @spec request(Transaction.t()) :: map()
  def request(tx) do
    %{
      "transaction" => convert(tx, :transaction, :encode),
      "signature" => convert(tx.signature, :signature, :encode),
      "placeholder" => tx.fee_payer_signature == :placeholder
    }
  end

  @doc false
  @spec decoded(map(), String.t()) :: Transaction.t()
  def decoded(result, raw) do
    attrs = convert(result["transaction"], :transaction, :decode)
    attrs = if result["placeholder"], do: Map.put(attrs, :fee_payer_signature, :placeholder), else: attrs
    struct!(Transaction, Map.merge(attrs, %{signature: convert(result["signature"], :signature, :decode), raw: raw}))
  end

  @doc false
  @spec authorization(Transaction.key_authorization() | nil) :: map() | nil
  def authorization(auth), do: convert(auth, :key_authorization, :encode)

  defp convert(nil, _, _), do: nil
  defp convert(value, :integer, :decode) when is_integer(value), do: value
  defp convert(value, :integer, :decode), do: integer(value)
  defp convert(value, :integer, :encode), do: quantity(value)
  defp convert(value, :bytes, :decode), do: bytes(value)
  defp convert(value, :bytes, :encode), do: hex(value)
  defp convert(value, :boolean, _), do: value
  defp convert(values, {:list, type}, direction), do: Enum.map(values, &convert(&1, type, direction))
  defp convert(:placeholder, :secp, :encode), do: %{"r" => "0x0", "s" => "0x0", "yParity" => "0x0"}
  defp convert("secp256k1", :key_type, :decode), do: :secp256k1
  defp convert("p256", :key_type, :decode), do: :p256
  defp convert("webAuthn", :key_type, :decode), do: :webauthn
  defp convert(:secp256k1, :key_type, :encode), do: "secp256k1"
  defp convert(:p256, :key_type, :encode), do: "p256"
  defp convert(:webauthn, :key_type, :encode), do: "webAuthn"

  defp convert(%{"userAddress" => address, "signature" => signature, "version" => version}, :signature, :decode) do
    {:keychain, if(version == "v1", do: 1, else: 2), bytes(address), convert(signature, :signature, :decode)}
  end

  defp convert(%{"type" => type} = signature, :signature, :decode) do
    tag = convert(type, :key_type, :decode)
    {tag, convert(signature, if(tag == :secp256k1, do: :secp, else: tag), :decode)}
  end

  defp convert({:keychain, version, address, signature}, :signature, :encode) when version in [1, 2] do
    %{"userAddress" => hex(address), "version" => "v#{version}", "signature" => convert(signature, :signature, :encode)}
  end

  defp convert({tag, signature}, :signature, :encode) do
    signature
    |> convert(if(tag == :secp256k1, do: :secp, else: tag), :encode)
    |> Map.put("type", convert(tag, :key_type, :encode))
  end

  defp convert(value, type, direction) do
    Map.new(Map.fetch!(@schemas, type), fn {key, {wire, field_type}} ->
      case direction do
        :decode -> {key, convert(Map.get(value, wire, default(field_type)), field_type, :decode)}
        :encode -> {wire, convert(Map.get(value, key), field_type, :encode)}
      end
    end)
  end

  defp default({:list, _}), do: []
  defp default(_), do: nil

  @doc false
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run(operation, request) do
    with {:ok, json} <- Jason.encode(Map.put(request, "operation", operation)),
         {:ok, result} <- Native.transaction_json(json) do
      Jason.decode(result)
    end
  end

  @doc false
  @spec hex(binary()) :: String.t()
  def hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)

  @doc false
  @spec bytes(String.t()) :: binary()
  def bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  @doc false
  @spec quantity(non_neg_integer()) :: String.t()
  def quantity(n), do: "0x" <> String.downcase(Integer.to_string(n, 16))

  @doc false
  @spec integer(String.t()) :: non_neg_integer()
  def integer("0x" <> hex), do: String.to_integer(hex, 16)

  @doc false
  @spec sign(Transaction.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  def sign(transaction, private_key) do
    request = request(transaction)

    with {:ok, %{"hash" => hash}} <- run("prepare", request),
         {:ok, sig} <- Secp256k1.sign_payload(bytes(hash), private_key) do
      signed = %{transaction | signature: {:secp256k1, %{r: sig.r, s: sig.s, y_parity: sig.recid}}}
      run("serialize", request(signed))
    end
  end
end
