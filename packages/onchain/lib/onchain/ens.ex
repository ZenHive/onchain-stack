defmodule Onchain.ENS do
  @moduledoc """
  ENS (Ethereum Name Service) resolution and namehash computation.

  ## Does

  - Compute EIP-137 namehash for ENS names (`namehash/1`)
  - Normalize names via UTS-46 / ENSIP-15 before hashing (case-fold, NFC, strip trailing dot)
  - Validate name structure (reject empty labels, disallowed code points)
  - Forward resolution: ENS name → ETH address (`resolve/2`)
  - Multi-coin address resolution via `addr(bytes32,uint256)` (`address/3`, ENSIP-9/11)
  - ENSIP-10 wildcard resolution + EIP-3668 CCIP-Read off-chain lookups (`address/3`)
  - Reverse resolution: ETH address → ENS name (`reverse/2`)
  - Text record queries (`text/3`), contenthash, ABI, pubkey retrieval
  - Look up resolver contracts (`resolver/2`)
  - UTS-46 / ENSIP-15 name normalization before namehash (`normalize/1`)
  - DNS wire-format name encoding (`dns_encode/1`, ENSIP-10)
  - Configurable registry address via `:registry` opt

  ## Does Not

  - ENS name registration or management (write operations)
  - Caching — consumers manage their own cache
  - The ENSIP-15 *security* filters (confusable / script-mixing / NSM checks) —
    `normalize/1` applies the deterministic Unicode steps (NFC, case-fold,
    ignored/disallowed code points) but not the data-table-driven confusable
    detection. See the internal Onchain.ENS.Normalize module for the scope boundary.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `namehash/1` | ENS name -> 32-byte EIP-137 node hash (normalized first) |
  | `namehash!/1` | Same, raises on error |
  | `normalize/1` | Apply UTS-46 / ENSIP-15 normalization to a name |
  | `normalize!/1` | Same, raises on error |
  | `dns_encode/1` | ENS name -> DNS wire format (ENSIP-10) |
  | `dns_encode!/1` | Same, raises on error |
  | `evm_coin_type/1` | EVM chain id -> ENSIP-11 coin type |
  | `resolver/2` | ENS name -> resolver contract address |
  | `resolver!/2` | Same, raises on error |
  | `resolve/2` | ENS name -> ETH address (forward resolution) |
  | `resolve!/2` | Same, raises on error |
  | `address/3` | ENS name + coin type -> raw address bytes (multi-coin, wildcard + CCIP) |
  | `address!/3` | Same, raises on error |
  | `reverse/2` | ETH address -> ENS name (reverse resolution) |
  | `reverse!/2` | Same, raises on error |
  | `text/3` | Retrieve a text record (avatar, url, etc.) |
  | `text!/3` | Same, raises on error |
  | `contenthash/2` | Retrieve the contenthash record |
  | `contenthash!/2` | Same, raises on error |
  | `pubkey/2` | Retrieve the ECDSA public key |
  | `pubkey!/2` | Same, raises on error |
  | `abi/3` | Retrieve ABI data (ENSIP-7) |
  | `abi!/3` | Same, raises on error |
  """

  use Descripex, namespace: "/ens"

  import Bitwise, only: [bor: 2]

  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.ENS.CCIP
  alias Onchain.ENS.Normalize
  alias Onchain.Hex
  alias Onchain.RPC

  @ens_registry "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  @addr_reverse_suffix "addr.reverse"
  @zero_address <<0::160>>
  @zero_node <<0::256>>

  # SLIP-44 coin type for Ethereum mainnet (ENSIP-9 default for addr/3).
  @eth_coin_type 60
  # ENSIP-10 "extended resolver" interface id = keccak256("resolve(bytes,bytes)")[0..3].
  @ensip10_interface_id <<0x90, 0x61, 0xB9, 0x23>>
  # ENSIP-11 derives an EVM chain's coin type from its chain id with this bit set.
  @evm_coin_type_flag 0x80000000

  # HTTP plumbing for CCIP-Read gateway requests (mirrors Onchain.RPC.batch/2).
  @default_gateway_timeout_ms 30_000
  @content_type_json {"Content-Type", "application/json"}

  # --- namehash ---

  api(:namehash, "Compute the EIP-137 namehash for an ENS name.",
    params: [
      name: [kind: :value, description: "ENS name, e.g. \"vitalik.eth\""]
    ],
    returns: %{
      type: "{:ok, <<_::256>>} | {:error, term}",
      description: "32-byte keccak256 node hash per EIP-137"
    }
  )

  @spec namehash(String.t()) :: {:ok, binary()} | {:error, {:invalid_name, term()}}
  def namehash(name) when is_binary(name) do
    case Normalize.normalize(name) do
      {:ok, normalized} -> {:ok, compute_namehash(normalized)}
      {:error, _} = error -> error
    end
  end

  # --- namehash! ---

  api(:namehash!, "Compute the EIP-137 namehash. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name, e.g. \"vitalik.eth\""]
    ],
    returns: %{type: "<<_::256>>", description: "32-byte keccak256 node hash"}
  )

  @spec namehash!(String.t()) :: binary()
  def namehash!(name) do
    case namehash(name) do
      {:ok, hash} -> hash
      {:error, reason} -> raise "namehash failed: #{inspect(reason)}"
    end
  end

  # --- normalize ---

  api(:normalize, "Apply UTS-46 / ENSIP-15 normalization to an ENS name.",
    params: [
      name: [kind: :value, description: ~s(ENS name, e.g. "VITALIK.eth" or "café.eth")]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, {:invalid_name, term()}}",
      description:
        "Normalized name (case-folded, NFC, ignored code points stripped). See Onchain.ENS.Normalize for the scope boundary — the ENSIP-15 confusable/script-mixing filters are NOT applied."
    }
  )

  @spec normalize(String.t()) :: {:ok, String.t()} | {:error, {:invalid_name, term()}}
  def normalize(name), do: Normalize.normalize(name)

  # --- normalize! ---

  api(:normalize!, "Apply UTS-46 / ENSIP-15 normalization. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name to normalize"]
    ],
    returns: %{type: "String.t()", description: "Normalized name"}
  )

  @spec normalize!(String.t()) :: String.t()
  def normalize!(name) do
    case Normalize.normalize(name) do
      {:ok, normalized} -> normalized
      {:error, reason} -> raise "normalize failed: #{inspect(reason)}"
    end
  end

  # --- dns_encode ---

  api(:dns_encode, "Encode an ENS name to DNS wire format (ENSIP-10).",
    params: [
      name: [kind: :value, description: "ENS name, e.g. \"foo.eth\""]
    ],
    returns: %{
      type: "{:ok, binary()} | {:error, term()}",
      description:
        ~s|Length-prefixed labels with a null terminator, e.g. "foo.eth" -> <<3, "foo", 3, "eth", 0>>. The name is normalized first.|
    }
  )

  @spec dns_encode(String.t()) :: {:ok, binary()} | {:error, term()}
  def dns_encode(name) do
    with {:ok, normalized} <- Normalize.normalize(name) do
      encode_dns_labels(normalized)
    end
  end

  # --- dns_encode! ---

  api(:dns_encode!, "Encode an ENS name to DNS wire format. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name to encode"]
    ],
    returns: %{type: "binary()", description: "DNS wire-format encoded name"}
  )

  @spec dns_encode!(String.t()) :: binary()
  def dns_encode!(name) do
    case dns_encode(name) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise "dns_encode failed: #{inspect(reason)}"
    end
  end

  # --- evm_coin_type ---

  api(:evm_coin_type, "Derive an ENSIP-11 coin type from an EVM chain id.",
    params: [
      chain_id: [kind: :value, description: "EVM chain id, e.g. 1 (mainnet), 10 (Optimism), 8453 (Base)"]
    ],
    returns: %{
      type: "pos_integer()",
      description:
        "ENSIP-11 coin type = 0x80000000 | chain_id. Pass this to address/3 to resolve an L2 address. Note Ethereum mainnet's canonical coin type is the SLIP-44 value 60, not the ENSIP-11 form."
    }
  )

  @spec evm_coin_type(pos_integer()) :: pos_integer()
  def evm_coin_type(chain_id) when is_integer(chain_id) and chain_id > 0 do
    bor(@evm_coin_type_flag, chain_id)
  end

  # --- resolver ---

  api(:resolver, "Look up the resolver contract address for an ENS name.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "EIP-55 checksummed resolver address"
    }
  )

  @spec resolver(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def resolver(name, opts \\ []) do
    with {:ok, node} <- namehash(name),
         {:ok, resolver_addr} <- get_resolver(node, opts) do
      {:ok, resolver_addr}
    else
      {:error, :no_resolver} -> {:error, {:no_resolver, name}}
      error -> error
    end
  end

  # --- resolver! ---

  api(:resolver!, "Look up the resolver contract address. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "String.t()", description: "EIP-55 checksummed resolver address"}
  )

  @spec resolver!(String.t(), keyword()) :: String.t()
  def resolver!(name, opts \\ []) do
    case resolver(name, opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "resolver lookup failed: #{inspect(reason)}"
    end
  end

  # --- resolve ---

  api(:resolve, "Resolve an ENS name to an ETH address (forward resolution).",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "EIP-55 checksummed ETH address"
    }
  )

  @spec resolve(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def resolve(name, opts \\ []) do
    with_resolver(name, "addr(bytes32)", [], "(address)", opts, fn [addr_bin] ->
      if addr_bin == @zero_address do
        {:error, {:no_address, name}}
      else
        Address.checksum(addr_bin)
      end
    end)
  end

  # --- resolve! ---

  api(:resolve!, "Resolve an ENS name to an ETH address. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "String.t()", description: "EIP-55 checksummed ETH address"}
  )

  @spec resolve!(String.t(), keyword()) :: String.t()
  def resolve!(name, opts \\ []) do
    case resolve(name, opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "resolve failed: #{inspect(reason)}"
    end
  end

  # --- address (multi-coin, ENSIP-9/10/11 + EIP-3668) ---

  api(:address, "Resolve an ENS name to a chain-specific address (ENSIP-9 multi-coin).",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      coin_type: [
        kind: :value,
        default: 60,
        description:
          "SLIP-44 / ENSIP-11 coin type. 60 = Ethereum mainnet (default), 0 = Bitcoin, 2147483658 = Optimism (via evm_coin_type/1)."
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, binary()} | {:error, term()}",
      description:
        "Raw address bytes for the coin type (20 bytes for EVM chains). Resolution walks parent labels for a wildcard resolver (ENSIP-10) and follows EIP-3668 OffchainLookup reverts through the gateway when present."
    }
  )

  @doc """
  Resolve an ENS name to a chain-specific address (ENSIP-9 `addr(bytes32,uint256)`).

  Unlike `resolve/2` (which returns an EIP-55 checksummed string for Ethereum
  mainnet only), this returns the raw address bytes for any SLIP-44 / ENSIP-11
  coin type. Resolution goes through the ENSIP-10 extended-resolver path when the
  resolver supports it (interface `0x9061b923`), which transparently handles
  wildcard subdomains and EIP-3668 CCIP-Read off-chain lookups.
  """
  @spec address(String.t(), non_neg_integer(), keyword()) :: {:ok, binary()} | {:error, term()}
  def address(name, coin_type \\ @eth_coin_type, opts \\ []) when is_integer(coin_type) and coin_type >= 0 do
    resolve_record(name, "addr(bytes32,uint256)", [coin_type], "(bytes)", opts, fn
      [addr_bytes] ->
        if addr_bytes == <<>> do
          {:error, {:no_address, {name, coin_type}}}
        else
          {:ok, addr_bytes}
        end
    end)
  end

  # --- address! ---

  api(:address!, "Resolve an ENS name to a chain-specific address. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      coin_type: [kind: :value, default: 60, description: "SLIP-44 / ENSIP-11 coin type (default 60 = ETH)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "binary()", description: "Raw address bytes for the coin type"}
  )

  @spec address!(String.t(), non_neg_integer(), keyword()) :: binary()
  def address!(name, coin_type \\ @eth_coin_type, opts \\ []) do
    case address(name, coin_type, opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "address resolution failed: #{inspect(reason)}"
    end
  end

  # --- reverse ---

  api(:reverse, "Reverse-resolve an ETH address to an ENS name.",
    params: [
      address: [kind: :value, description: "ETH address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "ENS name (e.g., \"vitalik.eth\")"
    }
  )

  @spec reverse(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def reverse(address, opts \\ []) do
    with {:ok, reverse} <- reverse_name(address),
         {:ok, node} <- namehash(reverse),
         {:ok, resolver_addr} <- get_resolver(node, opts),
         {:ok, [name]} <-
           Contract.call(resolver_addr, "name(bytes32)", [node], "(string)", opts) do
      if name == "" do
        {:error, {:no_reverse, address}}
      else
        {:ok, name}
      end
    else
      {:error, :no_resolver} -> {:error, {:no_resolver, address}}
      error -> error
    end
  end

  # --- reverse! ---

  api(:reverse!, "Reverse-resolve an ETH address to an ENS name. Raises on error.",
    params: [
      address: [kind: :value, description: "ETH address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "String.t()", description: "ENS name (e.g., \"vitalik.eth\")"}
  )

  @spec reverse!(String.t() | binary(), keyword()) :: String.t()
  def reverse!(address, opts \\ []) do
    case reverse(address, opts) do
      {:ok, name} -> name
      {:error, reason} -> raise "reverse failed: #{inspect(reason)}"
    end
  end

  # --- text ---

  api(:text, "Retrieve a text record from an ENS name's resolver.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      key: [kind: :value, description: ~s{Text record key (e.g., "avatar", "url", "com.twitter")}],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Text record value"
    }
  )

  @spec text(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def text(name, key, opts \\ []) do
    with_resolver(name, "text(bytes32,string)", [key], "(string)", opts, fn [value] ->
      if value == "" do
        {:error, {:empty_record, {name, key}}}
      else
        {:ok, value}
      end
    end)
  end

  # --- text! ---

  api(:text!, "Retrieve a text record. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      key: [kind: :value, description: ~s{Text record key (e.g., "avatar", "url", "com.twitter")}],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "String.t()", description: "Text record value"}
  )

  @spec text!(String.t(), String.t(), keyword()) :: String.t()
  def text!(name, key, opts \\ []) do
    case text(name, key, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "text lookup failed: #{inspect(reason)}"
    end
  end

  # --- contenthash ---

  api(:contenthash, "Retrieve the contenthash record from an ENS name's resolver.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, binary()} | {:error, term()}",
      description: "Raw contenthash bytes (ENSIP-7 encoded)"
    }
  )

  @spec contenthash(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def contenthash(name, opts \\ []) do
    with_resolver(name, "contenthash(bytes32)", [], "(bytes)", opts, fn [hash] ->
      if hash == <<>> do
        {:error, {:empty_record, {name, "contenthash"}}}
      else
        {:ok, hash}
      end
    end)
  end

  # --- contenthash! ---

  api(:contenthash!, "Retrieve the contenthash record. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "binary()", description: "Raw contenthash bytes"}
  )

  @spec contenthash!(String.t(), keyword()) :: binary()
  def contenthash!(name, opts \\ []) do
    case contenthash(name, opts) do
      {:ok, hash} -> hash
      {:error, reason} -> raise "contenthash lookup failed: #{inspect(reason)}"
    end
  end

  # --- pubkey ---

  api(:pubkey, "Retrieve the ECDSA public key from an ENS name's resolver.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, {binary(), binary()}} | {:error, term()}",
      description: "Tuple of {x, y} 32-byte coordinates"
    }
  )

  @spec pubkey(String.t(), keyword()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def pubkey(name, opts \\ []) do
    with_resolver(name, "pubkey(bytes32)", [], "(bytes32,bytes32)", opts, fn [x, y] ->
      zero = <<0::256>>

      if x == zero and y == zero do
        {:error, {:empty_record, {name, "pubkey"}}}
      else
        {:ok, {x, y}}
      end
    end)
  end

  # --- pubkey! ---

  api(:pubkey!, "Retrieve the ECDSA public key. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "{binary(), binary()}", description: "Tuple of {x, y} 32-byte coordinates"}
  )

  @spec pubkey!(String.t(), keyword()) :: {binary(), binary()}
  def pubkey!(name, opts \\ []) do
    case pubkey(name, opts) do
      {:ok, coords} -> coords
      {:error, reason} -> raise "pubkey lookup failed: #{inspect(reason)}"
    end
  end

  # --- abi ---

  api(:abi, "Retrieve ABI data from an ENS name's resolver (ENSIP-7).",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      content_types: [
        kind: :value,
        description: "Bitmask of content types: 1=JSON, 2=zlib, 4=CBOR, 8=URI"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{
      type: "{:ok, {non_neg_integer(), binary()}} | {:error, term()}",
      description: "Tuple of {content_type, abi_data}"
    }
  )

  @spec abi(String.t(), non_neg_integer(), keyword()) ::
          {:ok, {non_neg_integer(), binary()}} | {:error, term()}
  def abi(name, content_types, opts \\ []) do
    with_resolver(name, "ABI(bytes32,uint256)", [content_types], "(uint256,bytes)", opts, fn
      [ct, data] ->
        if ct == 0 do
          {:error, {:empty_record, {name, "abi"}}}
        else
          {:ok, {ct, data}}
        end
    end)
  end

  # --- abi! ---

  api(:abi!, "Retrieve ABI data. Raises on error.",
    params: [
      name: [kind: :value, description: "ENS name (e.g., \"vitalik.eth\")"],
      content_types: [
        kind: :value,
        description: "Bitmask of content types: 1=JSON, 2=zlib, 4=CBOR, 8=URI"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :registry"]
    ],
    returns: %{type: "{non_neg_integer(), binary()}", description: "Tuple of {content_type, abi_data}"}
  )

  @spec abi!(String.t(), non_neg_integer(), keyword()) :: {non_neg_integer(), binary()}
  def abi!(name, content_types, opts \\ []) do
    case abi(name, content_types, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "abi lookup failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  # Shared resolver lookup: namehash → get_resolver → Contract.call, then apply result_fn.
  # Centralizes the error mapping for :no_resolver across all resolver-based functions.
  @spec with_resolver(String.t(), String.t(), list(), String.t(), keyword(), function()) ::
          {:ok, term()} | {:error, term()}
  defp with_resolver(name, sig, extra_args, return_type, opts, result_fn) do
    with {:ok, node} <- namehash(name),
         {:ok, resolver_addr} <- get_resolver(node, opts),
         {:ok, result} <-
           Contract.call(resolver_addr, sig, [node | extra_args], return_type, opts) do
      result_fn.(result)
    else
      {:error, :no_resolver} -> {:error, {:no_resolver, name}}
      error -> error
    end
  end

  @doc false
  # Builds the reverse resolution name from an address.
  # "0xd8dA..." → "d8da6bf2...6cc2.addr.reverse" (40 lowercase hex chars, no 0x prefix)
  @spec reverse_name(String.t() | binary()) :: {:ok, String.t()} | {:error, term()}
  defp reverse_name(address) do
    with {:ok, addr_bin} <- Address.validate(address) do
      hex = addr_bin |> Hex.encode() |> String.trim_leading("0x")
      {:ok, "#{hex}.#{@addr_reverse_suffix}"}
    end
  end

  @doc false
  # Queries the ENS Registry for the resolver address of a name.
  @spec get_resolver(binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp get_resolver(namehash_bin, opts) do
    registry = Keyword.get(opts, :registry, @ens_registry)

    with {:ok, [resolver_bin]} <-
           Contract.call(registry, "resolver(bytes32)", [namehash_bin], "(address)", opts) do
      if resolver_bin == @zero_address do
        {:error, :no_resolver}
      else
        Address.checksum(resolver_bin)
      end
    end
  end

  # --- Resolution engine (ENSIP-9/10 + EIP-3668) ---

  # Resolves a record by (1) normalizing + namehashing, (2) walking parent labels
  # for a resolver (ENSIP-10 wildcard discovery), (3) using the extended
  # resolve(bytes,bytes) path with CCIP-Read when the resolver supports interface
  # 0x9061b923, else the legacy direct call. `on_result` interprets the decoded
  # return values list.
  @spec resolve_record(String.t(), String.t(), list(), String.t(), keyword(), (list() ->
                                                                                 {:ok, term()}
                                                                                 | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  defp resolve_record(name, inner_sig, extra_args, return_type, opts, on_result) do
    with {:ok, normalized} <- Normalize.normalize(name),
         node = compute_namehash(normalized),
         {:ok, resolver_addr} <- find_resolver(normalized, opts) do
      if extended_resolver?(resolver_addr, opts) do
        resolve_extended(resolver_addr, normalized, node, inner_sig, extra_args, return_type, opts, on_result)
      else
        resolve_legacy(resolver_addr, node, inner_sig, extra_args, return_type, opts, on_result)
      end
    else
      {:error, :no_resolver} -> {:error, {:no_resolver, name}}
      error -> error
    end
  end

  # ENSIP-10 wildcard discovery: try the full name, then strip the leftmost label
  # and retry, until a resolver is registered or the name is exhausted.
  @doc false
  @spec wildcard_suffix_names(String.t()) :: [String.t()]
  def wildcard_suffix_names(name) when is_binary(name) do
    name
    |> String.split(".")
    |> suffix_names_from_labels()
  end

  @spec suffix_names_from_labels([String.t()]) :: [String.t()]
  defp suffix_names_from_labels([]), do: []

  defp suffix_names_from_labels(labels) do
    [Enum.join(labels, ".") | suffix_names_from_labels(tl(labels))]
  end

  @spec find_resolver(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp find_resolver(name, opts) do
    name
    |> wildcard_suffix_names()
    |> do_find_resolver_by_name(opts)
  end

  @spec do_find_resolver_by_name([String.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  defp do_find_resolver_by_name([], _opts), do: {:error, :no_resolver}

  defp do_find_resolver_by_name([candidate | rest], opts) do
    node = compute_namehash(candidate)

    case get_resolver(node, opts) do
      {:ok, resolver_addr} -> {:ok, resolver_addr}
      {:error, :no_resolver} -> do_find_resolver_by_name(rest, opts)
      error -> error
    end
  end

  # Returns true when the resolver implements ENSIP-10 (interface 0x9061b923).
  @spec extended_resolver?(String.t(), keyword()) :: boolean()
  defp extended_resolver?(resolver_addr, opts) do
    match?(
      {:ok, [true]},
      Contract.call(resolver_addr, "supportsInterface(bytes4)", [@ensip10_interface_id], "(bool)", opts)
    )
  end

  # ENSIP-10 extended path: resolve(dnsEncode(name), innerCall) with CCIP-Read.
  # The outer call returns the ABI-encoded inner result as `bytes`.
  @spec resolve_extended(String.t(), String.t(), binary(), String.t(), list(), String.t(), keyword(), (list() ->
                                                                                                         {:ok, term()}
                                                                                                         | {:error,
                                                                                                            term()})) ::
          {:ok, term()} | {:error, term()}
  defp resolve_extended(resolver_addr, normalized, node, inner_sig, extra_args, return_type, opts, on_result) do
    with {:ok, dns} <- encode_dns_labels(normalized),
         {:ok, inner_call} <- ABI.encode_call(inner_sig, [node | extra_args]),
         {:ok, inner_bytes} <- Hex.decode(inner_call),
         {:ok, outer_call} <- ABI.encode_call("resolve(bytes,bytes)", [dns, inner_bytes]),
         {:ok, outer_hex} <- ccip_eth_call(resolver_addr, outer_call, opts),
         {:ok, [inner_result]} <- ABI.decode_response("(bytes)", outer_hex),
         {:ok, decoded} <- ABI.decode_response(return_type, Hex.encode(inner_result)) do
      on_result.(decoded)
    end
  end

  # Legacy path for resolvers that predate ENSIP-10 (exact-match only).
  @spec resolve_legacy(String.t(), binary(), String.t(), list(), String.t(), keyword(), (list() ->
                                                                                           {:ok, term()}
                                                                                           | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  defp resolve_legacy(resolver_addr, node, inner_sig, extra_args, return_type, opts, on_result) do
    case Contract.call(resolver_addr, inner_sig, [node | extra_args], return_type, opts) do
      {:ok, decoded} -> on_result.(decoded)
      error -> error
    end
  end

  # Wires real eth_call + gateway closures into the CCIP round-trip. The eth_call
  # closure surfaces execution-revert bytes as {:revert, bytes} so the loop can
  # detect an OffchainLookup.
  @spec ccip_eth_call(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp ccip_eth_call(resolver_addr, data_hex, opts) do
    call_fun = fn target, calldata ->
      case RPC.eth_call(target, calldata, opts) do
        {:ok, hex} -> {:ok, hex}
        {:error, {:rpc_error, %{revert: revert}}} when is_binary(revert) -> {:revert, revert}
        {:error, _reason} = error -> error
      end
    end

    gateway_fun = fn lookup -> gateway_fetch(lookup, opts) end

    CCIP.fetch(call_fun, gateway_fun, resolver_addr, data_hex)
  end

  # Fetches the first responsive CCIP-Read gateway from the OffchainLookup urls,
  # returning the decoded `data` response bytes.
  @spec gateway_fetch(CCIP.lookup(), keyword()) :: {:ok, binary()} | {:error, term()}
  defp gateway_fetch(%{urls: urls} = lookup, opts) do
    try_gateways(urls, lookup, opts)
  end

  @spec try_gateways([String.t()], CCIP.lookup(), keyword()) :: {:ok, binary()} | {:error, term()}
  defp try_gateways([], _lookup, _opts), do: {:error, :ccip_no_gateway}

  defp try_gateways([url | rest], lookup, opts) do
    {method, full_url, body} = CCIP.build_gateway_request(lookup, url)

    case gateway_http(method, full_url, body, opts) do
      {:ok, data_hex} ->
        case Hex.decode(data_hex) do
          {:ok, bytes} -> {:ok, bytes}
          {:error, _reason} -> try_gateways(rest, lookup, opts)
        end

      {:error, _reason} ->
        try_gateways(rest, lookup, opts)
    end
  end

  # Req transport (mirrors Onchain.RPC.batch/2). normalize_response/1 already maps
  # 2xx -> {:ok, resp} and non-2xx -> {:error, resp}; retry: false keeps a single
  # gateway attempt so try_gateways/3 controls fallback across the URL list.
  @spec gateway_http(:get | :post, String.t(), binary() | nil, keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp gateway_http(method, url, body, opts) do
    headers = if method == :post, do: [@content_type_json], else: []
    timeout = Keyword.get(opts, :timeout, @default_gateway_timeout_ms)

    base = [
      method: method,
      url: url,
      headers: headers,
      body: body,
      receive_timeout: timeout,
      decode_body: false,
      retry: false
    ]

    __MODULE__
    |> Onchain.HTTP.req_options(base, opts)
    |> Req.request()
    |> Cartouche.HTTP.normalize_response()
    |> case do
      {:ok, %Req.Response{body: resp_body}} ->
        parse_gateway_body(resp_body)

      {:error, %Req.Response{status: status}} ->
        {:error, {:gateway_status, status}}

      {:error, other} ->
        {:error, {:gateway_error, inspect(other)}}
    end
  end

  @spec parse_gateway_body(binary()) :: {:ok, String.t()} | {:error, term()}
  defp parse_gateway_body(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => data}} when is_binary(data) -> {:ok, data}
      {:ok, other} -> {:error, {:gateway_body, other}}
      {:error, reason} -> {:error, {:gateway_body, inspect(reason)}}
    end
  end

  # ENSIP-10 DNS wire format: each label prefixed by its byte length, terminated
  # by a zero octet. The root name ("") encodes as a single null byte.
  @spec encode_dns_labels(String.t()) :: {:ok, binary()} | {:error, term()}
  defp encode_dns_labels(""), do: {:ok, <<0>>}

  defp encode_dns_labels(name) do
    name
    |> String.split(".")
    |> Enum.reduce_while({:ok, <<>>}, fn label, {:ok, acc} ->
      size = byte_size(label)

      if size > 255 do
        {:halt, {:error, {:label_too_long, label}}}
      else
        # DNS names are ≤127 short labels (RFC 1035) — O(n²) here is bounded and tiny.
        # reach:disable-next-line string_building
        {:cont, {:ok, acc <> <<size>> <> label}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded <> <<0>>}
      error -> error
    end
  end

  # EIP-137 namehash: fold right over dot-separated labels with keccak256
  defp compute_namehash(""), do: @zero_node

  defp compute_namehash(name) do
    name
    |> String.split(".")
    |> Enum.reverse()
    |> Enum.reduce(@zero_node, fn label, node ->
      label_hash = Cartouche.Hash.keccak(label)
      # Not string accumulation: node and label_hash are both fixed 32-byte keccak digests.
      # reach:disable-next-line string_building
      Cartouche.Hash.keccak(node <> label_hash)
    end)
  end
end
