defmodule Cartouche.Signer.CloudKMSTest do
  use ExUnit.Case, async: false

  alias Cartouche.Signer.CloudKMS

  doctest CloudKMS

  @credential_ref {:goth_credential, __MODULE__}
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  setup do
    previous_config = Application.get_env(:cartouche, CloudKMS, [])
    Application.put_env(:cartouche, CloudKMS, Keyword.put(previous_config, :req_options, plug: &kms_plug/1))
    on_exit(fn -> Application.put_env(:cartouche, CloudKMS, previous_config) end)

    :ok
  end

  setup do
    # :meck patches Goth globally, so this test module cannot run async.
    :meck.new(Goth, [:passthrough, :no_link])
    :meck.expect(Goth, :fetch!, fn @credential_ref -> %{token: "stubbed-token", type: "Bearer", expires: 0} end)

    on_exit(fn -> :meck.unload(Goth) end)

    {:ok, credential: @credential_ref}
  end

  defp kms_plug(conn) do
    assert Plug.Conn.get_req_header(conn, "authorization") in [["Bearer token"], ["Bearer stubbed-token"]]

    case conn do
      %{
        method: "GET",
        request_path:
          "/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version/publicKey"
      } ->
        # https://cloud.google.com/kms/docs/reference/rest/v1/projects.locations.keyRings.cryptoKeys.cryptoKeyVersions/getPublicKey
        # projects/treasury-stage/locations/global/keyRings/
        # treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1
        Req.Test.json(conn, %{
          pem:
            "-----BEGIN PUBLIC KEY-----\nMFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEI3tE5EGI0XQZMPwFEiYs4cvq3YHiNSDT\n3/ehihlwUqKAYJajnrlRGhSYdqC+bGekcjnQZxyLlw1xXf/pr+yj3g==\n-----END PUBLIC KEY-----\n",
          algorithm: "EC_SIGN_SECP256K1_SHA256",
          pemCrc32c: "1065940272",
          name:
            "projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1",
          protectionLevel: "HSM"
        })

      %{
        method: "GET",
        request_path:
          "/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/wrong-algo/cryptoKeyVersions/version/publicKey"
      } ->
        Req.Test.json(conn, %{
          pem: "-----BEGIN PUBLIC KEY-----\nIRRELEVANT\n-----END PUBLIC KEY-----\n",
          algorithm: "RSA_SIGN_PSS_2048_SHA256",
          pemCrc32c: "0",
          name: "projects/project/locations/location/keyRings/keychain/cryptoKeys/wrong-algo/cryptoKeyVersions/version",
          protectionLevel: "SOFTWARE"
        })

      %{
        method: "POST",
        request_path:
          "/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version:asymmetricSign"
      } ->
        # https://cloud.google.com/kms/docs/reference/rest/v1/projects.locations.keyRings.cryptoKeys.cryptoKeyVersions/asymmetricSign
        # projects/treasury-stage/locations/global/keyRings/
        # treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1
        # {"digest": {"sha256":"nCL/XyHwuBsRPmP3222pT+3vEbIRm0CIuJZk+5o8tlg="}}
        body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
        assert %{"digest" => %{"sha256" => "nCL/XyHwuBsRPmP3222pT+3vEbIRm0CIuJZk+5o8tlg="}} = body

        Req.Test.json(conn, %{
          signature: "MEQCIGSKMaVlv78Uhc8D+6c9qacz7ISU4rXvH/zhgtaWy++9AiAU2LxgbNAmeYt5KgcgkzchwFsaRZtHTHdruwf5mY8IYQ==",
          signatureCrc32c: "3329027021",
          name:
            "projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1",
          protectionLevel: "HSM"
        })
    end
  end

  describe "get_address/6" do
    test "returns address through the token path" do
      {:ok, address} = CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")

      assert Cartouche.Hex.to_hex(address) == "0xdda641b2a76a4a7c3617815bb13281dd207b74d5"
    end

    test "fetches Goth token and returns address through the credential path", %{credential: credential} do
      {:ok, address} = CloudKMS.get_address(credential, "project", "location", "keychain", "key", "version")

      assert Cartouche.Hex.to_hex(address) == "0xdda641b2a76a4a7c3617815bb13281dd207b74d5"
      assert :meck.num_calls(Goth, :fetch!, [credential]) == 1
    end
  end

  describe "sign/7" do
    test "returns signature through the token path" do
      {:ok, sig} = CloudKMS.sign("test", "token", "project", "location", "keychain", "key", "version")

      assert {:ok, recid} =
               Cartouche.Recover.find_recid(
                 "test",
                 sig,
                 Cartouche.Hex.decode_address!("0xDDA641B2A76A4A7c3617815BB13281DD207b74d5")
               )

      assert "0xDDa641B2A76a4A7c3617815bb13281DD207b74d5" =
               "test"
               |> Cartouche.Recover.recover_eth(%{sig | recid: recid})
               |> Cartouche.Hex.to_address()
    end

    test "fetches Goth token and returns signature through the credential path", %{credential: credential} do
      {:ok, sig} = CloudKMS.sign("test", credential, "project", "location", "keychain", "key", "version")

      assert {:ok, recid} =
               Cartouche.Recover.find_recid(
                 "test",
                 sig,
                 Cartouche.Hex.decode_address!("0xDDA641B2A76A4A7c3617815BB13281DD207b74d5")
               )

      assert "0xDDa641B2A76a4A7c3617815bb13281DD207b74d5" =
               "test"
               |> Cartouche.Recover.recover_eth(%{sig | recid: recid})
               |> Cartouche.Hex.to_address()

      assert :meck.num_calls(Goth, :fetch!, [credential]) == 1
    end

    test "canonicalizes a high-s KMS signature so returned s is at most n/2" do
      Application.put_env(:cartouche, CloudKMS, req_options: [plug: &high_s_sign_plug/1])

      {:ok, sig} = CloudKMS.sign("test", "token", "project", "location", "keychain", "key", "version")

      assert sig.s <= div(@secp256k1_n, 2)
    end
  end

  describe "get_address/6 algorithm validation" do
    test "rejects non-secp256k1 algorithms with descriptive error" do
      assert {:error, "Invalid algorithm: RSA_SIGN_PSS_2048_SHA256"} =
               CloudKMS.get_address("token", "project", "location", "keychain", "wrong-algo", "version")
    end
  end

  describe "HTTP error handling" do
    test "returns non-2xx Req responses" do
      Application.put_env(:cartouche, CloudKMS, req_options: [plug: &unauthorized_plug/1])

      assert {:error, %Req.Response{status: 401, body: %{"error" => %{"message" => "unauthorized"}}}} =
               CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")
    end

    test "returns transport error messages" do
      Application.put_env(:cartouche, CloudKMS, req_options: [plug: &transport_error_plug/1])

      assert {:error, message} =
               CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")

      assert message =~ "closed"
    end
  end

  describe "algorithm/1" do
    test "reports secp256k1" do
      assert CloudKMS.algorithm({"token", "project", "location", "keychain", "key", "version"}) ==
               :secp256k1
    end
  end

  describe "sign_payload/2 contract" do
    test "rejects a short and an over-long payload" do
      config = {"token", "project", "location", "keychain", "key", "version"}

      assert_raise FunctionClauseError, fn -> CloudKMS.sign_payload(<<0::248>>, config) end
      assert_raise FunctionClauseError, fn -> CloudKMS.sign_payload(<<0::264>>, config) end
    end

    test "returns an error tuple for malformed DER instead of wrapping parse failure" do
      Application.put_env(:cartouche, CloudKMS, req_options: [plug: &malformed_der_sign_plug/1])

      digest = Cartouche.Hash.keccak("test")

      assert {:error, :invalid_signature} =
               CloudKMS.sign_payload(
                 digest,
                 {"token", "project", "location", "keychain", "key", "version"}
               )
    end
  end

  defp malformed_der_sign_plug(conn) do
    Req.Test.json(conn, %{
      signature: Base.encode64("not-a-der-signature"),
      signatureCrc32c: "0",
      name: "projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version",
      protectionLevel: "HSM"
    })
  end

  defp high_s_sign_plug(conn) do
    der = Curvy.Signature.to_der(%Curvy.Signature{crv: :secp256k1, r: 123, s: @secp256k1_n - 1})

    Req.Test.json(conn, %{
      signature: Base.encode64(der),
      signatureCrc32c: "0",
      name: "projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version",
      protectionLevel: "HSM"
    })
  end

  defp unauthorized_plug(conn) do
    conn
    |> Plug.Conn.put_status(:unauthorized)
    |> Req.Test.json(%{"error" => %{"message" => "unauthorized"}})
  end

  defp transport_error_plug(conn), do: Req.Test.transport_error(conn, :closed)
end
