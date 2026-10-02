defmodule Faucet.Source do
  @moduledoc """
  Behaviour every faucet adapter implements.

  A source knows three things about one asset on one network: how to read a
  balance, how to ask for more, and (optionally) how to tell that a request has
  landed. `Faucet.ensure_min_balance/4` composes them into the top-up loop; the
  loop never knows which concrete source it is driving.

  ## Contract

  All callbacks receive the same `opts` keyword list the caller passed to
  `Faucet`. Adapters document the keys they read and ignore the rest, so one
  keyword list can carry source configuration and loop configuration together.

  `fund/2` additionally receives `:deficit` in `opts` — the amount still
  missing to reach the requested minimum — so a source that can mint an exact
  amount (a testnet ERC-20 faucet contract) does not have to guess.

  ## Confirmation

  `wait_confirmed/3` is optional. When a source does not implement it, the loop
  polls `balance/2` until it rises above the pre-request reading. Sources that
  can do better — poll a transaction receipt, for instance — implement it.
  """

  @typedoc "An opaque reference to one funding request: a tx hash, a signature, an account id."
  @type ref :: term()

  @typedoc "Balance in the source's base unit (wei, lamports, drops, token units)."
  @type amount :: non_neg_integer()

  @doc "Current balance of `address` in the source's base unit."
  @callback balance(address :: String.t(), opts :: keyword()) :: {:ok, amount()} | {:error, term()}

  @doc "Request one round of funding for `address`. Returns the references the provider handed back."
  @callback fund(address :: String.t(), opts :: keyword()) :: {:ok, [ref()]} | {:error, term()}

  @doc "Block until the funding referenced by `refs` is confirmed on-chain, or the deadline passes."
  @callback wait_confirmed(refs :: [ref()], address :: String.t(), opts :: keyword()) :: :ok | {:error, term()}

  @doc ~s{Human-readable base unit, used in error messages (`"wei"`, `"lamports"`, `"drops"`).}
  @callback unit() :: String.t()

  @optional_callbacks wait_confirmed: 3
end
