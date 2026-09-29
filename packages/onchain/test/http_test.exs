defmodule Cartouche.HTTPTest do
  use ExUnit.Case, async: true

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
end
