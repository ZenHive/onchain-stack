defmodule Mix.Tasks.Onchain.Coverage do
  @shortdoc "Run tests and enforce the original library coverage floors"
  @moduledoc "Coverage gates for the three libraries consolidated into onchain."
  use Mix.Task

  @impl true
  @spec run([String.t()]) :: :ok
  def run(args) do
    File.mkdir_p!("cover")
    output = "cover/consolidated.json"

    {_output, status} =
      System.cmd(
        "mix",
        ["test.json", "--cover", "--output", output, "--exclude", "integration", "--exclude", "dev_node"] ++ args,
        env: [{"MIX_ENV", "test"}],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("Coverage test run failed (exit #{status})")
    %{"coverage" => %{"modules" => modules}} = output |> File.read!() |> :json.decode()
    check!(modules)
  end

  # onchain 0.16.0 renamed `ABI.*` to `Onchain.ABI.*` and `Cartouche.*` to
  # `Onchain.*`. The floors still follow the library each module came from, so
  # the former cartouche modules are listed by their new names.
  @former_cartouche Enum.map(
                      [
                        Onchain.Application,
                        Onchain.Block,
                        Onchain.Block.Withdrawal,
                        Onchain.Chain,
                        Onchain.CloudKMS,
                        Onchain.Configuration,
                        Onchain.Contract.Sleuth,
                        Onchain.DebugTrace,
                        Onchain.DebugTrace.StructLog,
                        Onchain.FeeHistory,
                        Onchain.Filter,
                        Onchain.Filter.Log,
                        Onchain.HTTP,
                        Onchain.Hash,
                        Onchain.Hex,
                        Onchain.Hex.InvalidHex,
                        Onchain.Keys,
                        Onchain.Manifest,
                        Onchain.OpenChain,
                        Onchain.OpenChain.API,
                        Onchain.OpenChain.Signatures,
                        Onchain.RPC,
                        Onchain.RPC.Capabilities,
                        Onchain.RPC.Capabilities.DeleteStrategy,
                        Onchain.RPC.Capabilities.Head,
                        Onchain.RPC.Capabilities.Resource,
                        Onchain.RPC.Configuration,
                        Onchain.RPC.Configuration.BlobSchedule,
                        Onchain.RPC.Configuration.Fork,
                        Onchain.RPC.Proof,
                        Onchain.RPC.Proof.StorageProof,
                        Onchain.RPC.SyncStatus,
                        Onchain.RPC.Trace,
                        Onchain.RPC.Trace.Action,
                        Onchain.Receipt,
                        Onchain.Recover,
                        Onchain.RecoveryBit,
                        Onchain.Signature,
                        Onchain.Signer,
                        Onchain.Signer.Backend,
                        Onchain.Signer.CloudKMS,
                        Onchain.Signer.Secp256k1,
                        Onchain.Sleuth,
                        Onchain.TraceCall,
                        Onchain.Transaction,
                        Onchain.Transaction.Call,
                        Onchain.Transaction.Info,
                        Onchain.Transaction.JsonField,
                        Onchain.Transaction.Native,
                        Onchain.Transaction.Signature,
                        Onchain.Transaction.TypedDecode,
                        Onchain.Transaction.V1,
                        Onchain.Transaction.V2,
                        Onchain.Transaction.V3,
                        Onchain.Transaction.V4,
                        Onchain.Transaction.V_2930,
                        Onchain.Typed,
                        Onchain.Typed.Domain,
                        Onchain.Typed.Native,
                        Onchain.Typed.Type,
                        Onchain.Wei
                      ],
                      &inspect/1
                    )

  @doc "Enforce separate library floors and the critical signer floor."
  @spec check!([map()]) :: :ok
  def check!(modules) do
    groups = Enum.group_by(modules, &library(&1["module"]))

    for {name, floor} <- [{"ABI", 95}, {"Cartouche", 85}, {"Onchain", 70}] do
      enforce!(name, Map.get(groups, name, []), floor)
    end

    signers = Enum.filter(modules, &String.starts_with?(&1["module"], "Onchain.Signer"))
    enforce!("Cartouche signers", signers, 95)
    :ok
  end

  defp library("Onchain.ABI"), do: "ABI"
  defp library("Onchain.ABI." <> _), do: "ABI"
  defp library("Mix.Tasks.Onchain.Manifest"), do: "ABI"
  defp library(module) when module in @former_cartouche, do: "Cartouche"
  defp library("Onchain" <> _), do: "Onchain"
  defp library("Mix.Tasks.Onchain." <> _), do: "Onchain"
  defp library(_module), do: :other

  defp enforce!(name, modules, floor) do
    if modules == [], do: Mix.raise("No coverage recorded for #{name}")

    {covered, total} =
      Enum.reduce(modules, {0, 0}, fn mod, {covered, total} ->
        count = mod["covered_lines"]
        {covered + count, total + count + length(mod["uncovered_lines"])}
      end)

    percentage = if total == 0, do: 100.0, else: covered / total * 100
    Mix.shell().info("#{name} coverage: #{Float.round(percentage, 2)}% (minimum #{floor}%)")
    if percentage < floor, do: Mix.raise("#{name} coverage below #{floor}%")
    :ok
  end
end
