defmodule OnchainJs.Script do
  @moduledoc """
  Bundle a JavaScript entry script together with the npm packages it imports
  from `node_modules/`, and load it into an `OnchainJs.Runtime`.

  Packages are installed at **build time** with npm_ex (`mix npm.install` /
  `mix npm.ci`), never at runtime: nothing in this module touches the npm
  registry. Bundling resolves `import` specifiers against an existing
  `node_modules/` directory and concatenates the result with OXC
  (`QuickBEAM.JS.bundle_file/2`, see the QuickBEAM README section
  ["npm packages"](https://hexdocs.pm/quickbeam/readme.html#npm-packages)).

  ## Why not just `Runtime.start_link(script: path)`

  QuickBEAM's `:script` option bundles and evaluates the entry while the
  runtime is still initialising, so there is no point at which
  `OnchainJs.Runtime.apply_browser_stubs/1` can run first. A browser bundle
  that touches `self`/`window` at module top level fails there. `load/3`
  starts from an already running runtime, applies the stubs, then evaluates,
  and it accepts an explicit `:node_modules` directory, which `:script` does
  not.

  ## Where things live

  * **Manifest and lock** — `package.json` and `npm.lock` sit at the root of
    the Mix project that owns the scripts (for this package:
    `packages/onchain_js/`). `mix npm.install <pkg>` adds a dependency;
    `mix npm.ci` reproduces `node_modules/` exactly from `npm.lock` and fails
    if the lock no longer matches the manifest.
  * **`node_modules/`** — next to the manifest, never committed.
  * **Entry scripts** — plain ES modules that `import` from npm and assign the
    functions Elixir will call onto `globalThis`. Without `:node_modules`,
    the directory is found by walking up from the entry script's directory,
    the way Node resolves packages.

  ## What a consuming application must do

  Hex never ships `package.json`, `npm.lock` or `node_modules/`, so a
  consumer supplies its own: declare the npm packages its scripts need in its
  own `package.json` (at its project root), run `mix npm.install` once and
  commit `package.json` plus `npm.lock`, and run `mix npm.ci` in every build
  (CI, Docker image, release build). In a Mix release the source tree is not
  present at runtime, so copy `node_modules/` and the entry scripts into the
  release (for example under `priv/`) and pass `:node_modules` explicitly.

  ## Errors

  Every failure is a tagged tuple that carries the underlying bundler or
  JavaScript error unchanged:

  * `{:error, {:bundle_error, entry, reason}}` — the entry could not be read
    (`{:file_read_error, path, posix}`), an import did not resolve
    (`{:module_not_found, specifier, message}`), a file failed to parse
    (`{:parse_error, path, errors}`), or OXC rejected the bundle.
  * `{:error, {:eval_error, entry, %QuickBEAM.JSError{}}}` — the bundle threw
    while evaluating, e.g. `ReferenceError: self is not defined` for a
    browser global that was not stubbed.
  * `{:error, {:stub_error, reason}}` — applying the browser stubs failed.
  """

  use Descripex, namespace: "/script"

  alias OnchainJs.Runtime

  @type bundle_error ::
          {:bundle_error, String.t(), term()}
  @type load_error ::
          bundle_error()
          | {:eval_error, String.t(), QuickBEAM.JSError.t() | term()}
          | {:stub_error, term()}

  api(:bundle, "Bundle an entry script and the npm packages it imports from node_modules/ into one script.",
    params: [
      entry: [kind: :value, description: "Path to the entry JS/TS file"],
      opts: [
        kind: :value,
        default: [],
        description:
          "`:node_modules` — explicit node_modules/ directory (default: walk up from the entry's directory). " <>
            "Other options are passed to `QuickBEAM.JS.bundle_file/2` (`:minify`, `:define`, ...)."
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, {:bundle_error, String.t(), term()}}",
      description: "The bundled JavaScript source, or the bundler's reason tagged with the entry path"
    },
    errors: [
      bundle_error: "Entry unreadable, import unresolved, parse failure, or OXC bundle failure; reason is unwrapped"
    ],
    composes_with: [:load]
  )

  @doc """
  Bundle `entry` and everything it imports into a single script.

  Pure with respect to the runtime: no JavaScript is evaluated and nothing
  is installed. See the module doc for the error shapes.
  """
  @spec bundle(Path.t(), keyword()) :: {:ok, String.t()} | {:error, bundle_error()}
  def bundle(entry, opts \\ []) when is_binary(entry) and is_list(opts) do
    entry = Path.expand(entry)

    case QuickBEAM.JS.bundle_file(entry, opts) do
      {:ok, js} when is_binary(js) -> {:ok, js}
      {:ok, other} -> {:error, {:bundle_error, entry, {:unexpected_bundle_output, other}}}
      {:error, reason} -> {:error, {:bundle_error, entry, reason}}
    end
  end

  api(:load, "Apply browser stubs, bundle an entry script with its npm imports, and evaluate it in a runtime.",
    params: [
      runtime: [kind: :exchange_data, description: "Runtime handle", source: "OnchainJs.Runtime.start_link/1"],
      entry: [kind: :value, description: "Path to the entry JS/TS file"],
      opts: [
        kind: :value,
        default: [],
        description:
          "`:browser_stubs` (default `true`) — run `Runtime.apply_browser_stubs/1` first; " <>
            "`:timeout` (ms, default 30000) — evaluation timeout; `:node_modules` and bundler options as in `bundle/2`."
      ]
    ],
    returns: %{
      type: ":ok | {:error, load_error()}",
      description: "`:ok` once the bundle has evaluated; the globals it defined are callable with `Runtime.call/3`"
    },
    errors: [
      bundle_error: "See `bundle/2`",
      eval_error: "The bundle threw during evaluation; carries the `QuickBEAM.JSError`",
      stub_error: "Applying the browser stubs failed"
    ],
    composes_with: [:bundle]
  )

  @doc """
  Load `entry` into `runtime`.

  Applies the browser stubs (unless `browser_stubs: false`), bundles `entry`
  with `bundle/2`, and evaluates the result. Afterwards, call the functions
  the script assigned to `globalThis` with `OnchainJs.Runtime.call/3`.
  """
  @spec load(Runtime.runtime(), Path.t(), keyword()) :: :ok | {:error, load_error()}
  def load(runtime, entry, opts \\ []) when is_binary(entry) and is_list(opts) do
    {stubs?, opts} = Keyword.pop(opts, :browser_stubs, true)
    {timeout, opts} = Keyword.pop(opts, :timeout, 30_000)

    with :ok <- maybe_stub(runtime, stubs?),
         {:ok, js} <- bundle(entry, opts) do
      evaluate(runtime, Path.expand(entry), js, timeout)
    end
  end

  defp maybe_stub(_runtime, false), do: :ok

  defp maybe_stub(runtime, true) do
    case Runtime.apply_browser_stubs(runtime) do
      :ok -> :ok
      {:error, reason} -> {:error, {:stub_error, reason}}
    end
  end

  defp evaluate(runtime, entry, js, timeout) do
    case Runtime.eval(runtime, js, timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:eval_error, entry, reason}}
    end
  end
end
