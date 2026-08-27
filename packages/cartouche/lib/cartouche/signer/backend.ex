defmodule Cartouche.Signer.Backend do
  @moduledoc """
  Behaviour for key-custody signer backends — *where the key lives and who
  computes the raw signature*.

  This is the **custody axis** only (local key, GCP/AWS/Azure KMS, Vault, MPC).
  It is deliberately decoupled from the **message axis** (Ethereum tx, EIP-712
  typed data, Hyperliquid action hash, Solana tx). Message hashing/serialization
  lives in the *caller* (`Cartouche.Signer` / `Cartouche.Solana.Signer`), never
  in a backend, so one backend set serves every message format.

  ## The pure-payload contract

  `c:sign_payload/2` signs **exactly the bytes it is handed** — it performs no
  hashing of its own:

    * `:secp256k1` backends receive a **32-byte digest** (e.g. the keccak of an
      Ethereum tx, or a pre-computed EIP-712 / Hyperliquid typed-data hash) and
      return a `Curvy.Signature` struct (`r`/`s`, `recid: nil` — recovery is the
      caller's job).
    * `:ed25519` backends receive the **raw message bytes** (Ed25519 hashes
      internally, SHA-512) and return a 64-byte signature.

  Because the backend never hashes, plain Eth-tx signing, EIP-712, Hyperliquid,
  and Solana all reuse the same backend with no per-venue backend change — the
  caller computes the digest/payload and hands it over.

  ## Signature normalization & recovery — caller-side, not here

  Two concerns that vary by *transport*, not by *custody*, stay out of the
  backend so each new secp256k1 backend inherits them for free:

    * **Low-s canonicalization** (EIP-2 malleability). Local Curvy already emits
      low-s; DER-decoded KMS output (AWS/Azure) does not. The caller normalizes
      with `Cartouche.Recover.normalize_low_s/1` after `c:sign_payload/2`
      returns, so the invariant is explicit and backend-agnostic.
    * **Recovery-bit search** (`find_recid`). secp256k1 backends return
      `recid: nil`; the caller brute-forces the recid against the known address
      over the **same digest** the backend signed
      (`Cartouche.Recover.find_recid_from_digest/3`).

  ## `config`

  An opaque, backend-specific term carrying everything the backend needs to
  authenticate and address a key — a raw private-key binary for
  `Cartouche.Signer.Curvy`, a Cloud-KMS key-coordinate tuple for
  `Cartouche.Signer.CloudKMS`, an Ed25519 seed for
  `Cartouche.Solana.Signer.Ed25519`. The runtime carries a backend as a
  `{module, config}` pair.
  """

  @typedoc "Opaque, backend-specific configuration (private key, KMS coordinates, seed, …)."
  @type config :: term()

  @typedoc "`{backend_module, config}` — the runtime carrier for a signer backend."
  @type t :: {module(), config()}

  @doc """
  The elliptic curve this backend signs on.

  Determines how the caller prepares the payload: `:secp256k1` ⇒ hand a 32-byte
  digest; `:ed25519` ⇒ hand the raw message bytes.

  Callers must check this before dispatching: `Cartouche.Signer` requires
  `:secp256k1` and `Cartouche.Solana.Signer` requires `:ed25519`. Use
  `expect_algorithm/3`.
  """
  @callback algorithm(config()) :: :secp256k1 | :ed25519

  @doc """
  The curve-native public key for the backend's key.

  Returns the *public key*, not a chain address — the caller derives the address
  (secp256k1 ⇒ `Cartouche.Address.from_public_key/1`; ed25519 ⇒ the 32-byte key
  *is* the Solana address). Returns the uncompressed SEC1 secp256k1 point (65
  bytes *including* the leading `0x04` prefix, which `Cartouche.Address.from_public_key/1`
  strips) or the 32-byte Ed25519 public key.
  """
  @callback public_key(config()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Sign the exact payload bytes handed in — no internal hashing.

  `:secp256k1` ⇒ `payload` is a 32-byte digest; returns `{:ok, %Curvy.Signature{}}`
  with `recid: nil`. `:ed25519` ⇒ `payload` is the raw message; returns
  `{:ok, <<_::512>>}`.
  """
  @callback sign_payload(payload :: binary(), config()) ::
              {:ok, Curvy.Signature.t() | <<_::512>>} | {:error, term()}

  @doc """
  Reject a backend whose `c:algorithm/1` is not `expected`.

  Returns `:ok` on match, or
  `{:error, {:algorithm_mismatch, expected, got}}` so a crossed-curve
  `{module, config}` fails instead of mis-signing.
  """
  @spec expect_algorithm(module(), config(), :secp256k1 | :ed25519) ::
          :ok | {:error, {:algorithm_mismatch, :secp256k1 | :ed25519, atom()}}
  def expect_algorithm(backend, config, expected) when is_atom(backend) and expected in [:secp256k1, :ed25519] do
    case backend.algorithm(config) do
      ^expected -> :ok
      other -> {:error, {:algorithm_mismatch, expected, other}}
    end
  end
end
