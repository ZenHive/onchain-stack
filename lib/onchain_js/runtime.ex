defmodule OnchainJs.Runtime do
  @moduledoc """
  Thin wrapper over `QuickBEAM` providing supervised JavaScript runtimes for
  `onchain_js`.

  Each runtime is a `GenServer` holding a persistent QuickJS-NG context.
  Functions, modules, and globals survive across `eval/2` and `call/3` calls,
  so the typical pattern is to start a runtime once, load a JS bundle, then
  invoke library functions on demand.

  Defaults to the `:browser` API surface (`fetch`, `crypto`, `WebSocket`,
  `URL`, `TextEncoder`, `document`) since the npm packages this project
  targets — solc-js, Uniswap SDK, DeFiSaver, merkletreejs — ship browser
  bundles and assume those globals exist. Callers may override any option
  by passing them through to `start_link/1`.

  ## Browser-bundle stubs

  Browser bundles routinely reference `self`, `window`, `navigator`, and
  `location`. The `:browser` API surface does NOT define these — they must
  be stubbed before the bundle is loaded. `apply_browser_stubs/1` performs
  the standard QuickBEAM-recommended stub sequence in one call.

  ## Example

      {:ok, rt} = OnchainJs.Runtime.start_link()
      :ok = OnchainJs.Runtime.apply_browser_stubs(rt)
      {:ok, 2} = OnchainJs.Runtime.eval(rt, "1 + 1")
      :ok = OnchainJs.Runtime.stop(rt)

  ## Supervision

  Runtimes are typically spawned dynamically via `OnchainJs.RuntimeSupervisor`:

      {:ok, pid} =
        DynamicSupervisor.start_child(
          OnchainJs.RuntimeSupervisor,
          {OnchainJs.Runtime, []}
        )
  """

  use Descripex, namespace: "/runtime"

  @type runtime :: GenServer.server()
  @type js_result :: {:ok, term()} | {:error, QuickBEAM.JSError.t()}

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__)),
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  api(:start_link, "Start a supervised QuickBEAM runtime with a persistent JavaScript context.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description:
          "QuickBEAM options (`:name`, `:script`, `:handlers`, `:define`, `:memory_limit`, " <>
            "`:max_stack_size`, `:apis`). Defaults `apis: :browser`; a caller-supplied value wins."
      ]
    ],
    returns: %{
      type: "{:ok, pid()} | {:error, term()}",
      description: "Runtime handle to pass as the `runtime` argument of every other function here"
    },
    composes_with: [:eval, :call, :apply_browser_stubs, :stop]
  )

  @doc """
  Start a new supervised QuickBEAM runtime.

  Defaults `apis: :browser`. Callers may override any QuickBEAM option by
  including it in `opts` (the caller's value wins).

  See `QuickBEAM.start/1` for the full list of options (`:name`, `:script`,
  `:handlers`, `:define`, `:memory_limit`, `:max_stack_size`, etc.).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts
    |> Keyword.put_new(:apis, :browser)
    |> QuickBEAM.start()
  end

  api(
    :eval,
    "Evaluate JavaScript source in a runtime. Top-level `await` is supported; promises are awaited before returning.",
    params: [
      runtime: [
        kind: :exchange_data,
        description: "Runtime handle",
        source: "start_link/1"
      ],
      code: [kind: :value, description: "JavaScript source to evaluate"],
      opts: [
        kind: :value,
        default: [],
        description: "`:timeout` (ms) and `:vars` (map of globals injected for the duration of this evaluation only)"
      ]
    ],
    returns: %{
      type: "{:ok, term()} | {:error, QuickBEAM.JSError.t()}",
      description: "The evaluated expression's value, converted to an Elixir term"
    }
  )

  @doc """
  Evaluate JavaScript source in `runtime`.

  Equivalent to `QuickBEAM.eval/2`. Top-level `await` is supported; the
  promise is awaited before returning.
  """
  @spec eval(runtime(), String.t()) :: js_result()
  def eval(runtime, code) when is_binary(code) do
    QuickBEAM.eval(runtime, code)
  end

  @doc """
  Evaluate JavaScript source in `runtime` with options.

  Equivalent to `QuickBEAM.eval/3`. Supports `:timeout` (ms) and `:vars`
  (map of globals injected for the duration of the evaluation).
  """
  @spec eval(runtime(), String.t(), keyword()) :: js_result()
  def eval(runtime, code, opts) when is_binary(code) and is_list(opts) do
    QuickBEAM.eval(runtime, code, opts)
  end

  api(:call, "Call a global JavaScript function by name. Promise-returning functions are awaited automatically.",
    params: [
      runtime: [
        kind: :exchange_data,
        description: "Runtime handle",
        source: "start_link/1"
      ],
      fn_name: [
        kind: :exchange_data,
        description: "Name of a global JS function, defined by a prior `eval/2` or by a loaded bundle",
        source: "eval/2"
      ],
      args: [kind: :value, description: "Positional arguments, converted from Elixir terms to JS values"],
      opts: [kind: :value, default: [], description: "`:timeout` (ms)"]
    ],
    returns: %{
      type: "{:ok, term()} | {:error, QuickBEAM.JSError.t()}",
      description: "The function's return value, converted to an Elixir term"
    }
  )

  @doc """
  Call a global JavaScript function by name.

  Equivalent to `QuickBEAM.call/3`. Promise-returning functions are
  awaited automatically.
  """
  @spec call(runtime(), String.t(), [term()]) :: js_result()
  def call(runtime, fn_name, args) when is_binary(fn_name) and is_list(args) do
    QuickBEAM.call(runtime, fn_name, args)
  end

  @doc """
  Call a global JavaScript function by name with options.

  Equivalent to `QuickBEAM.call/4`. Supports `:timeout` (ms).
  """
  @spec call(runtime(), String.t(), [term()], keyword()) :: js_result()
  def call(runtime, fn_name, args, opts) when is_binary(fn_name) and is_list(args) and is_list(opts) do
    QuickBEAM.call(runtime, fn_name, args, opts)
  end

  api(:stop, "Stop a runtime and free its resources. The JavaScript context and everything defined in it is discarded.",
    params: [
      runtime: [
        kind: :exchange_data,
        description: "Runtime handle",
        source: "start_link/1"
      ]
    ],
    returns: %{type: ":ok", description: "Always `:ok`; the runtime process is no longer alive"}
  )

  @doc """
  Stop `runtime` and free its resources.

  Equivalent to `QuickBEAM.stop/1`. Returns `:ok`.
  """
  @spec stop(runtime()) :: :ok
  def stop(runtime) do
    QuickBEAM.stop(runtime)
  end

  api(
    :apply_browser_stubs,
    "Define the browser globals (`self`, `window`, `navigator`, `location`) that npm browser bundles assume exist. Call before loading a bundle.",
    params: [
      runtime: [
        kind: :exchange_data,
        description: "Runtime handle",
        source: "start_link/1"
      ]
    ],
    returns: %{
      type: ":ok | {:error, term()}",
      description: "`:ok` once `self === globalThis`, `window === globalThis`, `navigator` and `location` are defined"
    },
    composes_with: [:eval]
  )

  @doc """
  Apply the standard browser-global stub sequence to `runtime`.

  Stubs:

  * `globalThis.self = globalThis;`
  * `globalThis.window = globalThis;`
  * `navigator = %{"userAgent" => "OnchainJs"}`
  * `location = %{"protocol" => "https:"}`

  `self` and `window` MUST literally BE `globalThis` (not the string
  `"globalThis"`), so they're set via `eval/2` rather than `set_global/3` —
  the latter would convert the atom value to a string and break libraries
  that perform `self === globalThis` identity checks.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec apply_browser_stubs(runtime()) :: :ok | {:error, term()}
  def apply_browser_stubs(runtime) do
    with {:ok, _} <-
           QuickBEAM.eval(
             runtime,
             "globalThis.self = globalThis; globalThis.window = globalThis;"
           ),
         :ok <-
           QuickBEAM.set_global(runtime, "navigator", %{"userAgent" => "OnchainJs"}),
         :ok <-
           QuickBEAM.set_global(runtime, "location", %{"protocol" => "https:"}) do
      :ok
    else
      {:error, _} = error -> error
    end
  end
end
