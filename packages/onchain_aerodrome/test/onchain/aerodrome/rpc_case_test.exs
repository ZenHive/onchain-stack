defmodule Onchain.Aerodrome.RPCCaseTest do
  use ExUnit.Case, async: false

  alias Onchain.Aerodrome.RPCCase

  @envs ~w(BASE_RPC_URL BASE_SECONDARY_RPC_URL)
  @primary_fallback "https://mainnet.base.org"
  @secondary_example "https://base-mainnet.g.alchemy.com/v2/YOUR_KEY"

  setup do
    original = Map.new(@envs, &{&1, System.get_env(&1)})
    Enum.each(@envs, &System.delete_env/1)
    on_exit(fn -> System.put_env(original) end)
    :ok
  end

  describe "primary_rpc_url!/0" do
    test "falls back to the public Base endpoint when BASE_RPC_URL is unset or empty" do
      assert RPCCase.primary_rpc_url!() == @primary_fallback
      System.put_env("BASE_RPC_URL", "")
      assert RPCCase.primary_rpc_url!() == @primary_fallback
      System.put_env("BASE_RPC_URL", "   ")
      assert RPCCase.primary_rpc_url!() == @primary_fallback
    end

    test "uses BASE_RPC_URL when set" do
      System.put_env("BASE_RPC_URL", "https://primary.example/base")
      assert RPCCase.primary_rpc_url!() == "https://primary.example/base"
    end
  end

  describe "secondary_rpc_url!/0" do
    test "flunks with the exact env var and export command when unset or empty" do
      for value <- [nil, "", "   "] do
        System.put_env(%{"BASE_SECONDARY_RPC_URL" => value})
        error = assert_raise ExUnit.AssertionError, fn -> RPCCase.secondary_rpc_url!() end
        assert error.message =~ "BASE_SECONDARY_RPC_URL"
        assert error.message =~ ~s(export BASE_SECONDARY_RPC_URL="#{@secondary_example}")
        assert error.message =~ "never a skip"
        refute error.message =~ "skipping"
      end
    end

    test "uses BASE_SECONDARY_RPC_URL when set" do
      System.put_env("BASE_SECONDARY_RPC_URL", "https://alchemy.example/base")
      assert RPCCase.secondary_rpc_url!() == "https://alchemy.example/base"
    end
  end

  describe "run_on_both_endpoints/1" do
    test "runs a zero-arity closure against each endpoint and returns {primary, secondary}" do
      System.put_env("BASE_RPC_URL", "https://primary.example/base")
      System.put_env("BASE_SECONDARY_RPC_URL", "https://secondary.example/base")

      {primary, secondary} = RPCCase.run_on_both_endpoints(fn -> {RPCCase.rpc_url!(), RPCCase.rpc_opts!()} end)

      assert primary == {"https://primary.example/base", [rpc_url: "https://primary.example/base"]}
      assert secondary == {"https://secondary.example/base", [rpc_url: "https://secondary.example/base"]}
      assert RPCCase.rpc_url!() == "https://primary.example/base"
    end

    test "flunks before calling the action when the secondary URL is missing" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          RPCCase.run_on_both_endpoints(fn -> flunk("must not run") end)
        end

      assert error.message =~ "BASE_SECONDARY_RPC_URL"
      assert error.message =~ ~s(export BASE_SECONDARY_RPC_URL="#{@secondary_example}")
    end

    test "flunks when both accessors resolve to the same host, without printing the URL" do
      System.put_env("BASE_RPC_URL", @primary_fallback)
      System.put_env("BASE_SECONDARY_RPC_URL", @primary_fallback)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          RPCCase.run_on_both_endpoints(fn -> flunk("must not run") end)
        end

      assert error.message =~ "BASE_RPC_URL"
      assert error.message =~ "BASE_SECONDARY_RPC_URL"
      assert error.message =~ "same host"
      assert error.message =~ ~s(export BASE_SECONDARY_RPC_URL="#{@secondary_example}")
      refute error.message =~ @primary_fallback
    end

    test "flunks two keys on the same hosted provider as not a second authority" do
      System.put_env("BASE_RPC_URL", "https://base-mainnet.g.alchemy.com/v2/aaa")
      System.put_env("BASE_SECONDARY_RPC_URL", "https://base-mainnet.g.alchemy.com/v2/bbb")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          RPCCase.run_on_both_endpoints(fn -> flunk("must not run") end)
        end

      assert error.message =~ "same host"
      refute error.message =~ "aaa"
      refute error.message =~ "bbb"
    end
  end
end
