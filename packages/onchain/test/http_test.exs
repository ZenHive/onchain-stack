defmodule Cartouche.HTTPTest do
  use ExUnit.Case, async: false

  alias Cartouche.HTTP

  describe "normalize_response/1" do
    test "wraps 2xx responses in {:ok, response}" do
      resp = %Req.Response{status: 200, body: "ok", headers: %{}}
      assert HTTP.normalize_response({:ok, resp}) == {:ok, resp}
    end

    test "wraps non-2xx responses in {:error, response}" do
      resp = %Req.Response{status: 500, body: "boom", headers: %{}}
      assert HTTP.normalize_response({:ok, resp}) == {:error, resp}
    end

    test "maps Req.TransportError reasons into an error string" do
      err = %Req.TransportError{reason: :timeout}

      assert {:error, "[Cartouche] HTTP client error: :timeout"} =
               HTTP.normalize_response({:error, err})
    end

    test "maps generic exceptions into an error string via Exception.message/1" do
      err = %RuntimeError{message: "kaboom"}

      assert {:error, "[Cartouche] HTTP client error: kaboom"} =
               HTTP.normalize_response({:error, err})
    end

    test "maps unknown (non-exception) errors into an error string" do
      assert {:error, "[Cartouche] Unknown error: :nope"} =
               HTTP.normalize_response({:error, :nope})
    end
  end

  test "CCIP and RPC keep their application seams and option precedence" do
    for {app, owner} <- [{:onchain, Onchain.ENS}, {:cartouche, Cartouche.RPC}] do
      original_owner = Application.fetch_env(app, owner)
      original_global = Application.fetch_env(app, :req_options)

      on_exit(fn ->
        for {key, value} <- [{owner, original_owner}, {:req_options, original_global}] do
          case value do
            {:ok, config} -> Application.put_env(app, key, config)
            :error -> Application.delete_env(app, key)
          end
        end
      end)

      Application.put_env(app, owner, receive_timeout: 2, plug: :owner)
      Application.put_env(app, :req_options, receive_timeout: 3)

      assert HTTP.req_options(owner, [receive_timeout: 1, retry: false], []) ==
               [retry: false, plug: :owner, receive_timeout: 3]

      assert HTTP.req_options(owner, [], req_options: [receive_timeout: 4])[:receive_timeout] == 4
    end
  end
end
