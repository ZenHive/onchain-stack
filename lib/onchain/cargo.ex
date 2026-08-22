defmodule Onchain.Cargo do
  @moduledoc """
  `mix ci` gate for both native crates: `cargo test` and `cargo clippy`.

  Absent `cargo` or clippy degrades with a skip message rather than failing
  as if the Rust were bad. Clippy denies `clippy::unwrap_used` via each
  crate's `Cargo.toml`; it does not deny `expect_used`.
  """

  @typep cmd_fun :: (String.t(), [String.t()], keyword() -> {Collectable.t(), integer()})

  @crates ~w(native/onchain_evm native/onchain_solidity)
  @kinds [:test, :clippy]

  @doc "Native crate paths relative to the Mix project root."
  @spec crates() :: [String.t()]
  def crates, do: @crates

  @doc """
  Run `cargo test` or `cargo clippy --all-targets -- -D warnings` on both crates.

  `opts` is for tests: `:find_executable` and `:cmd` replace `System` lookups.
  """
  @spec run(:test | :clippy, keyword()) :: :ok
  def run(kind, opts \\ []) when kind in @kinds do
    find = Keyword.get(opts, :find_executable, &System.find_executable/1)
    cmd = Keyword.get(opts, :cmd, &system_cmd/3)

    case find.("cargo") do
      nil -> skip(kind, "cargo not found on PATH")
      cargo -> run_with_cargo(kind, cargo, cmd)
    end
  end

  @spec run_with_cargo(atom(), String.t(), cmd_fun()) :: :ok
  defp run_with_cargo(:test, cargo, cmd) do
    Enum.each(@crates, &run_crate(&1, cargo, crate_args(:test, &1), "cargo test", cmd))
  end

  defp run_with_cargo(:clippy, cargo, cmd) do
    if clippy_present?(cargo, cmd) do
      Enum.each(@crates, &run_crate(&1, cargo, crate_args(:clippy, &1), "cargo clippy", cmd))
    else
      skip(:clippy, "clippy component not installed")
    end
  end

  @spec clippy_present?(String.t(), cmd_fun()) :: boolean()
  defp clippy_present?(cargo, cmd) do
    {_out, status} = cmd.(cargo, ["clippy", "--version"], into: "", stderr_to_stdout: true)
    status == 0
  end

  @spec crate_args(atom(), String.t()) :: [String.t()]
  defp crate_args(:test, crate), do: ["test", "--manifest-path", manifest(crate)]

  defp crate_args(:clippy, crate) do
    ["clippy", "--manifest-path", manifest(crate), "--all-targets", "--", "-D", "warnings"]
  end

  @spec manifest(String.t()) :: String.t()
  defp manifest(crate), do: Path.join(crate, "Cargo.toml")

  @spec run_crate(String.t(), String.t(), [String.t()], String.t(), cmd_fun()) :: :ok
  defp run_crate(crate, cargo, args, label, cmd) do
    {_out, status} = cmd.(cargo, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("#{label} failed in #{crate} (exit #{status})")
    end

    :ok
  end

  @spec skip(atom(), String.t()) :: :ok
  defp skip(kind, reason) do
    Mix.shell().info("[skip] cargo #{kind}: #{reason}.")
    :ok
  end

  @spec system_cmd(String.t(), [String.t()], keyword()) :: {Collectable.t(), integer()}
  defp system_cmd(_bin, args, opts), do: System.cmd("cargo", args, opts)
end
