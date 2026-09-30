defmodule OnchainMonorepo.Cargo do
  @moduledoc """
  Development-only Rust tests, lints and advisory audits for native crates.

  Absent `cargo` or clippy degrades with a skip message rather than failing
  as if the Rust were bad. Clippy denies `clippy::unwrap_used` via each
  crate's `Cargo.toml`; it does not deny `expect_used`.
  Missing cargo-audit and failed advisory fetches fail the audit.
  """

  @typep cmd_fun :: (String.t(), [String.t()], keyword() -> {Collectable.t(), integer()})

  @kinds [:test, :clippy, :audit]

  @doc "Native crate paths relative to the Mix project root."
  @spec crates() :: [String.t()]
  def crates do
    "native/**/Cargo.toml"
    |> Path.wildcard()
    |> Enum.reject(&("target" in Path.split(&1)))
    |> Enum.map(&Path.dirname/1)
  end

  @doc """
  Run tests, clippy with warnings denied, or an advisory audit on every native crate.

  `opts` is for tests: `:find_executable` and `:cmd` replace `System` lookups.
  """
  @spec run(:test | :clippy | :audit, keyword()) :: :ok
  def run(kind, opts \\ []) when kind in @kinds do
    find = Keyword.get(opts, :find_executable, &System.find_executable/1)
    cmd = Keyword.get(opts, :cmd, &system_cmd/3)

    case find.("cargo") do
      nil ->
        skip(kind, "cargo not found on PATH")

      cargo ->
        if kind == :audit and is_nil(find.("cargo-audit")) do
          Mix.raise("cargo-audit not found on PATH; install with: cargo install cargo-audit --locked")
        end

        run_with_cargo(kind, cargo, cmd)
    end
  end

  @spec run_with_cargo(atom(), String.t(), cmd_fun()) :: :ok
  defp run_with_cargo(:test, cargo, cmd) do
    Enum.each(crates(), &run_crate(&1, cargo, crate_args(:test, &1), "cargo test", cmd))
  end

  defp run_with_cargo(:clippy, cargo, cmd) do
    if clippy_present?(cargo, cmd) do
      Enum.each(crates(), &run_crate(&1, cargo, crate_args(:clippy, &1), "cargo clippy", cmd))
    else
      skip(:clippy, "clippy component not installed")
    end
  end

  defp run_with_cargo(:audit, cargo, cmd) do
    Enum.each(crates(), fn crate ->
      # Run from the crate so Cargo.lock and any per-advisory .cargo/audit.toml
      # configuration belong to this crate. Keep default warning-only policy.
      {_out, status} =
        cmd.(cargo, ["audit"],
          cd: crate,
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      if status != 0 do
        Mix.raise(
          "cargo audit failed in #{crate} (exit #{status}); see output for vulnerabilities or advisory fetch errors; audit is not clean"
        )
      end
    end)
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
  defp system_cmd(bin, args, opts), do: System.cmd(bin, args, opts)
end
