defmodule Mix.Tasks.OnchainScrapeErigonMethodsTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Onchain.ScrapeErigonMethods

  @moduletag :tmp_dir

  @go_fixture """
  package jsonrpc

  func (api *TraceAPIImpl) Call(ctx context.Context) {}
  func (api *TraceAPIImpl) ReplayBlockTransactions(ctx context.Context) {}
  func (api *TraceAPIImpl) helper(ctx context.Context) {}
  func (api *OtterscanAPIImpl) GetApiLevel() uint8 { return 8 }
  func (api EthAPIImpl) BlockNumber(ctx context.Context) {}
  """

  test "extract_methods/1 enumerates exported trace and otterscan RPC methods", %{tmp_dir: tmp_dir} do
    source_dir = Path.join(tmp_dir, "jsonrpc")
    File.mkdir_p!(source_dir)
    File.write!(Path.join(source_dir, "apis.go"), @go_fixture)

    assert {:ok, methods} = ScrapeErigonMethods.extract_methods(source_dir)

    assert [
             %{
               "go_method" => "GetApiLevel",
               "method" => "ots_getApiLevel",
               "namespace" => "ots",
               "receiver" => "OtterscanAPIImpl"
             },
             %{
               "go_method" => "Call",
               "method" => "trace_call",
               "namespace" => "trace",
               "receiver" => "TraceAPIImpl"
             },
             %{
               "go_method" => "ReplayBlockTransactions",
               "method" => "trace_replayBlockTransactions",
               "namespace" => "trace",
               "receiver" => "TraceAPIImpl"
             }
           ] = Enum.map(methods, &Map.take(&1, ["go_method", "method", "namespace", "receiver"]))
  end

  test "mix task writes scraped methods JSON", %{tmp_dir: tmp_dir} do
    source_dir = Path.join(tmp_dir, "jsonrpc")
    output_path = Path.join(tmp_dir, "erigon-methods.json")
    File.mkdir_p!(source_dir)
    File.write!(Path.join(source_dir, "apis.go"), @go_fixture)

    Mix.Task.reenable("onchain.scrape_erigon_methods")
    ScrapeErigonMethods.run(["--source", source_dir, "--output", output_path])

    decoded = output_path |> File.read!() |> Jason.decode!()

    assert [
             %{"method" => "ots_getApiLevel"},
             %{"method" => "trace_call"},
             %{"method" => "trace_replayBlockTransactions"}
           ] = Enum.map(decoded, &Map.take(&1, ["method"]))
  end
end
