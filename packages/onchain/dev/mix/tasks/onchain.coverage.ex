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

  @doc "Enforce separate library floors and the critical signer floor."
  @spec check!([map()]) :: :ok
  def check!(modules) do
    for {name, floor, prefixes} <- [
          {"ABI", 95, ["ABI", "Mix.Tasks.Hieroglyph."]},
          {"Cartouche", 85, ["Cartouche", "Mix.Tasks.Cartouche."]},
          {"Onchain", 70, ["Onchain", "Mix.Tasks.Onchain."]}
        ] do
      selected = Enum.filter(modules, &String.starts_with?(&1["module"], prefixes))
      enforce!(name, selected, floor)
    end

    signers = Enum.filter(modules, &String.starts_with?(&1["module"], "Cartouche.Signer"))
    enforce!("Cartouche signers", signers, 95)
    :ok
  end

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
