defmodule Cartouche.Solana.RPC do
  @moduledoc """
  JSON-RPC client for Solana.

  Provides typed functions for Solana RPC methods with automatic
  Base58 encoding of pubkeys, commitment level options, and response
  deserialization.

  ## Configuration

      config :cartouche,
        solana_node: "https://api.mainnet-beta.solana.com"

  ## Examples

      {:ok, balance} = Cartouche.Solana.RPC.get_balance(pubkey)
      {:ok, slot} = Cartouche.Solana.RPC.get_slot()
      {:ok, %{blockhash: bh}} = Cartouche.Solana.RPC.get_latest_blockhash()
  """

  use Descripex, namespace: "/solana/rpc"

  import Cartouche.HTTP, only: [normalize_response: 1]

  alias Cartouche.Solana.Transaction

  require Logger

  @default_timeout Application.compile_env(:cartouche, :solana_timeout, 30_000)

  @typedoc "JSON-RPC error envelope returned by a Solana node or by response validation."
  @type rpc_error :: %{code: integer(), message: String.t()}

  @typedoc "Error returned when JSON encoding rejects the outbound request body."
  @type invalid_params_error :: {:invalid_params, Exception.t()}

  @typedoc "All error shapes returned by `send_rpc/3`."
  @type send_rpc_error :: rpc_error() | invalid_params_error() | Req.Response.t() | Jason.DecodeError.t() | String.t()

  @spec solana_node() :: String.t() | nil
  defp solana_node, do: Application.get_env(:cartouche, :solana_node)

  # ---------------------------------------------------------------------------
  # Core transport
  # ---------------------------------------------------------------------------

  api(:send_rpc, "Send a raw JSON-RPC request to the configured Solana node.",
    params: [
      method: [kind: :value, description: "Solana JSON-RPC method name, such as `getSlot`."],
      params: [kind: :value, description: "JSON-RPC positional params encoded as a list."],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for RPC client configuration."
      ]
    ],
    opts: [
      solana_node: [kind: :value, description: "Override Solana JSON-RPC endpoint URL."],
      timeout: [kind: :value, default: @default_timeout, description: "Request timeout in milliseconds."],
      id: [kind: :value, description: "JSON-RPC request id; defaults to a generated positive integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :term, description: "Decoded JSON-RPC `result` value returned by the node."},
      error: %{
        type: :term,
        description:
          "JSON-RPC error map `%{code: integer, message: string}`, invalid params tuple, HTTP response, decode error, or string reason."
      }
    }
  )

  @doc """
  Send a raw JSON-RPC request to the Solana node.

  Options:
  - `:solana_node` - Override the node URL
  - `:timeout` - Request timeout in ms (default: #{@default_timeout})
  - `:id` - JSON-RPC request ID (default: auto-generated)

  ## Examples

      iex> Cartouche.Solana.RPC.send_rpc("getSlot", [])
      {:ok, 123456789}

      iex> match?({:error, {:invalid_params, %Jason.EncodeError{}}}, Cartouche.Solana.RPC.send_rpc(<<255>>, []))
      true

      iex> match?({:error, {:invalid_params, %Protocol.UndefinedError{}}}, Cartouche.Solana.RPC.send_rpc("getSlot", [self()]))
      true
  """
  @spec send_rpc(binary(), list(), keyword()) :: {:ok, term()} | {:error, send_rpc_error()}
  def send_rpc(method, params, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    url = Keyword.get(opts, :solana_node, solana_node())
    id = Keyword.get_lazy(opts, :id, fn -> System.unique_integer([:positive]) end)

    body = %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }

    headers = [
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ]

    with {:ok, encoded_body} <- encode_body(body) do
      req_result =
        normalize_response(
          Req.request(
            Cartouche.HTTP.req_options(
              __MODULE__,
              [
                method: :post,
                url: url,
                headers: headers,
                body: encoded_body,
                receive_timeout: timeout,
                decode_body: false,
                retry: false
              ],
              opts
            )
          )
        )

      with {:ok, %Req.Response{body: resp_body}} <- req_result do
        decode_response(resp_body, id, method)
      end
    end
  end

  @spec encode_body(map()) :: {:ok, binary()} | {:error, invalid_params_error()}
  defp encode_body(body) do
    {:ok, Jason.encode!(body)}
  rescue
    e in [Jason.EncodeError, Protocol.UndefinedError] ->
      {:error, {:invalid_params, e}}
  end

  @spec decode_response(binary(), integer(), String.t()) ::
          {:ok, term()} | {:error, rpc_error() | Jason.DecodeError.t()}
  defp decode_response(response, id, method) do
    with {:ok, decoded} <- Jason.decode(response) do
      case decoded do
        %{"jsonrpc" => "2.0", "result" => result, "id" => ^id} ->
          {:ok, result}

        %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}, "id" => ^id} ->
          Logger.warning("[Cartouche][Solana][#{method}] RPC error: #{code} #{message}")
          {:error, %{code: code, message: message}}

        _ ->
          {:error, %{code: -999, message: "invalid JSON-RPC response"}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @spec encode_pubkey(<<_::256>>) :: String.t()
  defp encode_pubkey(<<pubkey::binary-32>>), do: Cartouche.Base58.encode(pubkey)

  @spec commitment_config(keyword()) :: map()
  defp commitment_config(opts) do
    config =
      if c = Keyword.get(opts, :commitment),
        do: %{"commitment" => to_string(c)},
        else: %{}

    if s = Keyword.get(opts, :min_context_slot),
      do: Map.put(config, "minContextSlot", s),
      else: config
  end

  @spec account_config(keyword()) :: map()
  defp account_config(opts) do
    encoding =
      if e = Keyword.get(opts, :encoding),
        do: encoding_string(e),
        else: "base64"

    opts
    |> commitment_config()
    |> Map.put("encoding", encoding)
  end

  @spec encoding_string(atom() | binary()) :: String.t()
  defp encoding_string(:base58), do: "base58"
  defp encoding_string(:base64), do: "base64"
  defp encoding_string(:"base64+zstd"), do: "base64+zstd"
  defp encoding_string(:json_parsed), do: "jsonParsed"
  defp encoding_string(s) when is_binary(s), do: s

  @spec unwrap_value(map()) :: term()
  defp unwrap_value(%{"context" => _ctx, "value" => value}), do: value
  defp unwrap_value(other), do: other

  @spec params_with_config(list(), keyword()) :: list()
  defp params_with_config(params, opts) do
    config = commitment_config(opts)
    if config == %{}, do: params, else: params ++ [config]
  end

  # ---------------------------------------------------------------------------
  # Account methods
  # ---------------------------------------------------------------------------

  api(:get_balance, "Get the SOL balance for an account.",
    params: [
      pubkey: [
        kind: :value,
        description: "Raw 32-byte Solana public key binary (`<<_::256>>`); Base58-encoded internally."
      ],
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :non_neg_integer, description: "Amount in lamports (1 SOL = 1_000_000_000 lamports)."},
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the SOL balance (in lamports) for an account.

  ## Options
  - `:commitment` - `:processed`, `:confirmed`, or `:finalized`
  """
  @spec get_balance(<<_::256>>, keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_balance(pubkey, opts \\ []) do
    with {:ok, result} <-
           send_rpc("getBalance", params_with_config([encode_pubkey(pubkey)], opts), opts) do
      {:ok, unwrap_value(result)}
    end
  end

  api(:get_account_info, "Get account info for a Solana account.",
    params: [
      pubkey: [
        kind: :value,
        description: "Raw 32-byte Solana public key binary (`<<_::256>>`); Base58-encoded internally."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for commitment, account encoding, and RPC client configuration."
      ]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."],
      encoding: [
        kind: :value,
        default: :base64,
        description: "Account data encoding: `:base64`, `:base58`, `:\"base64+zstd\"`, `:json_parsed`, or string."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :account_info_or_nil,
        description:
          "`nil` when the account is missing, or a map with keys `:data`, `:executable`, `:lamports`, `:owner`, `:rent_epoch`, and `:space`."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get account info for a pubkey. Returns `nil` if the account doesn't exist.

  ## Options
  - `:commitment` - `:processed`, `:confirmed`, or `:finalized`
  - `:encoding` - `:base64` (default), `:base58`, `:"base64+zstd"`, `:json_parsed`
  """
  @spec get_account_info(<<_::256>>, keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_account_info(pubkey, opts \\ []) do
    config = account_config(opts)

    with {:ok, result} <- send_rpc("getAccountInfo", [encode_pubkey(pubkey), config], opts) do
      {:ok, deserialize_account_info(unwrap_value(result))}
    end
  end

  api(:get_multiple_accounts, "Get account info for multiple Solana accounts.",
    params: [
      pubkeys: [
        kind: :value,
        description: "List of raw 32-byte Solana public key binaries (`<<_::256>>`); Base58-encoded internally, max 100."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for commitment, account encoding, and RPC client configuration."
      ]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."],
      encoding: [
        kind: :value,
        default: :base64,
        description: "Account data encoding: `:base64`, `:base58`, `:\"base64+zstd\"`, `:json_parsed`, or string."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :account_info_list,
        description:
          "List containing `nil` for missing accounts or account maps with keys `:data`, `:executable`, `:lamports`, `:owner`, `:rent_epoch`, and `:space`."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get account info for multiple pubkeys (max 100).

  ## Options
  - `:commitment`, `:encoding` - same as `get_account_info/2`
  """
  @spec get_multiple_accounts([<<_::256>>], keyword()) :: {:ok, [map() | nil]} | {:error, term()}
  def get_multiple_accounts(pubkeys, opts \\ []) do
    config = account_config(opts)
    encoded = Enum.map(pubkeys, &encode_pubkey/1)

    with {:ok, result} <- send_rpc("getMultipleAccounts", [encoded, config], opts) do
      {:ok, Enum.map(unwrap_value(result), &deserialize_account_info/1)}
    end
  end

  @spec deserialize_account_info(nil | map()) :: nil | map()
  defp deserialize_account_info(nil), do: nil

  defp deserialize_account_info(info) when is_map(info) do
    %{
      data: info["data"],
      executable: info["executable"],
      lamports: info["lamports"],
      owner: info["owner"],
      rent_epoch: info["rentEpoch"],
      space: info["space"]
    }
  end

  # ---------------------------------------------------------------------------
  # Blockhash / slot methods
  # ---------------------------------------------------------------------------

  api(:get_latest_blockhash, "Get the latest blockhash and last valid block height.",
    params: [
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :map,
        keys: [:blockhash, :last_valid_block_height],
        description:
          "Map with decoded `:blockhash` bytes from the node's base58 blockhash string and integer `:last_valid_block_height`."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the latest blockhash and its last valid block height.
  """
  @spec get_latest_blockhash(keyword()) ::
          {:ok, %{blockhash: binary(), last_valid_block_height: non_neg_integer()}}
          | {:error, term()}
  def get_latest_blockhash(opts \\ []) do
    with {:ok, result} <- send_rpc("getLatestBlockhash", params_with_config([], opts), opts) do
      value = unwrap_value(result)

      {:ok,
       %{
         blockhash: Cartouche.Base58.decode!(value["blockhash"]),
         last_valid_block_height: value["lastValidBlockHeight"]
       }}
    end
  end

  api(:get_slot, "Get the current slot.",
    params: [
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :non_neg_integer, description: "Current Solana slot as a non-negative integer."},
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the current slot.
  """
  @spec get_slot(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_slot(opts \\ []) do
    send_rpc("getSlot", params_with_config([], opts), opts)
  end

  api(:get_block_height, "Get the current block height.",
    params: [
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :non_neg_integer, description: "Current Solana block height as a non-negative integer."},
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the current block height.
  """
  @spec get_block_height(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_block_height(opts \\ []) do
    send_rpc("getBlockHeight", params_with_config([], opts), opts)
  end

  # ---------------------------------------------------------------------------
  # Transaction methods
  # ---------------------------------------------------------------------------

  api(:get_transaction, "Get a transaction by its base58 transaction signature.",
    params: [
      signature: [
        kind: :value,
        description: "Base58-encoded Solana transaction signature."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for commitment, response encoding, and RPC client configuration."
      ]
    ],
    opts: [
      commitment: [
        kind: :value,
        description:
          "Commitment level atom: `:finalized` or `:confirmed`; `:processed` is not supported by Solana for this method."
      ],
      encoding: [
        kind: :value,
        description:
          "Transaction response encoding override: `:json_parsed`, `:base64`, `:\"base64+zstd\"`, `:base58`, or string."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :transaction_map_or_nil,
        description:
          "`nil` when not found, or the Solana RPC transaction response map including slot, meta, transaction, and block time fields as returned by the node."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get a transaction by its signature.

  Returns `nil` if the transaction is not found.

  ## Options
  - `:commitment` - `:confirmed` or `:finalized` (`:processed` is NOT supported)
  - `:encoding` - `:json` (default), `:json_parsed`, `:base64`, `:base58`
  """
  @spec get_transaction(String.t(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_transaction(signature, opts \\ []) do
    config = commitment_config(opts)
    config = Map.put(config, "maxSupportedTransactionVersion", 0)

    config =
      if e = Keyword.get(opts, :encoding),
        do: Map.put(config, "encoding", encoding_string(e)),
        else: config

    send_rpc("getTransaction", [signature, config], opts)
  end

  api(:get_signature_statuses, "Get status records for base58 transaction signatures.",
    params: [
      signatures: [kind: :value, description: "List of base58-encoded Solana transaction signatures, max 256."],
      opts: [kind: :value, default: [], description: "Keyword options for status lookup and RPC client configuration."]
    ],
    opts: [
      search_transaction_history: [
        kind: :value,
        default: false,
        description: "Boolean flag to search beyond the recent status cache."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :signature_status_list,
        description:
          "List containing `nil` for unknown signatures or maps with keys `:slot`, `:confirmations`, `:err`, and `:confirmation_status` (`:processed`, `:confirmed`, `:finalized`, or `nil`)."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the statuses of transaction signatures (max 256).

  ## Options
  - `:search_transaction_history` - Search beyond recent status cache (default: false)
  """
  @spec get_signature_statuses([String.t()], keyword()) ::
          {:ok, [map() | nil]} | {:error, term()}
  def get_signature_statuses(signatures, opts \\ []) do
    config =
      if Keyword.get(opts, :search_transaction_history, false) do
        %{"searchTransactionHistory" => true}
      else
        %{}
      end

    params = if config == %{}, do: [signatures], else: [signatures, config]

    with {:ok, result} <- send_rpc("getSignatureStatuses", params, opts) do
      statuses =
        result
        |> unwrap_value()
        |> Enum.map(fn
          nil ->
            nil

          s ->
            %{
              slot: s["slot"],
              confirmations: s["confirmations"],
              err: s["err"],
              confirmation_status: parse_commitment(s["confirmationStatus"])
            }
        end)

      {:ok, statuses}
    end
  end

  @spec parse_commitment(nil | String.t()) :: nil | :processed | :confirmed | :finalized
  defp parse_commitment(nil), do: nil
  defp parse_commitment("processed"), do: :processed
  defp parse_commitment("confirmed"), do: :confirmed
  defp parse_commitment("finalized"), do: :finalized

  api(:get_minimum_balance_for_rent_exemption, "Get minimum rent-exempt balance for account data length.",
    params: [
      data_length: [kind: :value, description: "Account data length in bytes as a non-negative integer."],
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :non_neg_integer, description: "Amount in lamports (1 SOL = 1_000_000_000 lamports)."},
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the minimum balance for rent exemption for a given data size.
  """
  @spec get_minimum_balance_for_rent_exemption(non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_minimum_balance_for_rent_exemption(data_length, opts \\ []) do
    send_rpc(
      "getMinimumBalanceForRentExemption",
      params_with_config([data_length], opts),
      opts
    )
  end

  # ---------------------------------------------------------------------------
  # Token methods
  # ---------------------------------------------------------------------------

  api(:get_token_account_balance, "Get the SPL token balance for a token account.",
    params: [
      pubkey: [
        kind: :value,
        description:
          "Raw 32-byte Solana public key binary (`<<_::256>>`) for the SPL token account; Base58-encoded internally."
      ],
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :map,
        keys: [:amount, :decimals, :ui_amount_string],
        description:
          "Map with integer raw token `:amount`, integer `:decimals`, and RPC-provided human-readable `:ui_amount_string`."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the token balance for an SPL Token account.

  Returns the raw integer amount, decimal precision, and `ui_amount_string`
  (a human-readable formatted string provided by the RPC node, e.g. `"1.5"`
  for 1500000 with 6 decimals).
  """
  @spec get_token_account_balance(<<_::256>>, keyword()) ::
          {:ok, %{amount: non_neg_integer(), decimals: non_neg_integer(), ui_amount_string: String.t()}}
          | {:error, term()}
  def get_token_account_balance(pubkey, opts \\ []) do
    with {:ok, result} <-
           send_rpc(
             "getTokenAccountBalance",
             params_with_config([encode_pubkey(pubkey)], opts),
             opts
           ) do
      value = unwrap_value(result)

      {:ok,
       %{
         amount: String.to_integer(value["amount"]),
         decimals: value["decimals"],
         ui_amount_string: value["uiAmountString"]
       }}
    end
  end

  api(:get_token_accounts_by_owner, "Get SPL token accounts owned by a wallet.",
    params: [
      owner: [
        kind: :value,
        description:
          "Raw 32-byte Solana public key binary (`<<_::256>>`) for the owning wallet; Base58-encoded internally."
      ],
      filter: [
        kind: :value,
        description:
          "Keyword list with `:mint` or `:program_id`, each a raw 32-byte Solana public key binary (`<<_::256>>`) that is Base58-encoded internally. If both are provided, `:mint` takes precedence."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for commitment, account encoding, and RPC client configuration."
      ]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."],
      encoding: [
        kind: :value,
        default: :json_parsed,
        description: "Account data encoding; defaults to `:json_parsed` for structured token account data."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :token_account_list,
        description:
          "List of maps with keys `:pubkey` (base58 account address) and `:account` (deserialized account info map)."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    },
    errors: [
      {ArgumentError, "Raised when neither `:mint` nor `:program_id` is present in the filter."}
    ]
  )

  @doc """
  Get all token accounts owned by a wallet.

  Accepts `:mint` (specific token) or `:program_id` (all tokens under a
  program). If both are present, `:mint` takes precedence. Raises
  `ArgumentError` if neither is provided.

  Uses `jsonParsed` encoding by default for structured token account data.

  ## Examples

      get_token_accounts_by_owner(wallet, mint: usdc_mint)
      get_token_accounts_by_owner(wallet, program_id: Programs.token_program())
  """
  @spec get_token_accounts_by_owner(<<_::256>>, keyword(), keyword()) ::
          {:ok, [%{pubkey: String.t(), account: map()}]} | {:error, term()}
  def get_token_accounts_by_owner(owner, filter, opts \\ []) do
    filter_obj =
      cond do
        mint = Keyword.get(filter, :mint) ->
          %{"mint" => encode_pubkey(mint)}

        program_id = Keyword.get(filter, :program_id) ->
          %{"programId" => encode_pubkey(program_id)}

        true ->
          raise ArgumentError, "get_token_accounts_by_owner requires :mint or :program_id filter"
      end

    config = account_config(Keyword.put_new(opts, :encoding, :json_parsed))

    with {:ok, result} <-
           send_rpc("getTokenAccountsByOwner", [encode_pubkey(owner), filter_obj, config], opts) do
      accounts =
        result
        |> unwrap_value()
        |> Enum.map(fn item ->
          %{
            pubkey: item["pubkey"],
            account: deserialize_account_info(item["account"])
          }
        end)

      {:ok, accounts}
    end
  end

  # ---------------------------------------------------------------------------
  # Fee methods
  # ---------------------------------------------------------------------------

  api(:get_recent_prioritization_fees, "Get recent prioritization fees for optional account locks.",
    params: [
      addresses: [
        kind: :value,
        default: [],
        description:
          "List of raw 32-byte Solana public key binaries (`<<_::256>>`) for accounts that transactions lock; Base58-encoded internally."
      ],
      opts: [kind: :value, default: [], description: "Keyword options for RPC client configuration."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :prioritization_fee_list,
        description:
          "List of maps with integer `:slot` and integer `:prioritization_fee` in micro-lamports per compute unit as returned by Solana RPC."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get recent prioritization fees. Pass account addresses to see fees for
  transactions locking those accounts.
  """
  @spec get_recent_prioritization_fees([<<_::256>>], keyword()) ::
          {:ok, [%{slot: non_neg_integer(), prioritization_fee: non_neg_integer()}]}
          | {:error, term()}
  def get_recent_prioritization_fees(addresses \\ [], opts \\ []) do
    encoded = Enum.map(addresses, &encode_pubkey/1)
    params = if encoded == [], do: [], else: [encoded]

    with {:ok, result} <- send_rpc("getRecentPrioritizationFees", params, opts) do
      fees =
        Enum.map(result, fn f ->
          %{slot: f["slot"], prioritization_fee: f["prioritizationFee"]}
        end)

      {:ok, fees}
    end
  end

  # ---------------------------------------------------------------------------
  # Node info methods
  # ---------------------------------------------------------------------------

  api(:get_health, "Check Solana node health.",
    params: [
      opts: [kind: :value, default: [], description: "Keyword options for RPC client configuration."]
    ],
    returns: %{
      type: :ok_or_error,
      ok: %{type: :atom, description: "`:ok` when the node reports healthy."},
      error: %{type: :error_tuple, description: "`{:error, term()}` when unhealthy, unreachable, or decoding fails."}
    }
  )

  @doc """
  Check node health. Returns `:ok` if healthy, `{:error, ...}` if unhealthy.
  """
  @spec get_health(keyword()) :: :ok | {:error, term()}
  def get_health(opts \\ []) do
    case send_rpc("getHealth", [], opts) do
      {:ok, "ok"} -> :ok
      {:ok, _} -> :ok
      error -> error
    end
  end

  api(:get_version, "Get Solana node version information.",
    params: [
      opts: [kind: :value, default: [], description: "Keyword options for RPC client configuration."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :map,
        keys: [:solana_core, :feature_set],
        description: "Map with string `:solana_core` version and integer `:feature_set`."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Get the node version.
  """
  @spec get_version(keyword()) ::
          {:ok, %{solana_core: String.t(), feature_set: non_neg_integer()}}
          | {:error, term()}
  def get_version(opts \\ []) do
    with {:ok, result} <- send_rpc("getVersion", [], opts) do
      {:ok, %{solana_core: result["solana-core"], feature_set: result["feature-set"]}}
    end
  end

  # ---------------------------------------------------------------------------
  # Write methods
  # ---------------------------------------------------------------------------

  api(:send_transaction, "Send a signed Solana transaction to the network.",
    params: [
      transaction: [
        kind: :value,
        description: "Signed `Cartouche.Solana.Transaction` struct or raw serialized transaction bytes."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for transaction submission and RPC client configuration."
      ]
    ],
    opts: [
      encoding: [
        kind: :value,
        default: :base64,
        description: "Wire encoding for serialized transaction bytes: `:base64` or `:base58`."
      ],
      skip_preflight: [kind: :value, default: false, description: "Boolean flag to skip preflight checks."],
      preflight_commitment: [
        kind: :value,
        description: "Preflight commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      max_retries: [kind: :value, description: "Maximum retry count as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :string, description: "Base58-encoded Solana transaction signature."},
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    },
    composes_with: [:send_and_confirm]
  )

  @doc """
  Send a signed transaction to the network.

  Accepts a `Cartouche.Solana.Transaction` struct or raw serialized bytes.

  ## Options
  - `:encoding` - `:base64` (default) or `:base58`
  - `:skip_preflight` - Skip preflight checks (default: false)
  - `:preflight_commitment` - Commitment for preflight simulation
  - `:max_retries` - Max retries before giving up

  Returns the transaction signature (Base58 string).
  """
  @spec send_transaction(binary() | Transaction.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_transaction(transaction, opts \\ [])

  def send_transaction(%Transaction{} = trx, opts) do
    send_transaction(Transaction.serialize(trx), opts)
  end

  def send_transaction(bytes, opts) when is_binary(bytes) do
    encoding = Keyword.get(opts, :encoding, :base64)

    encoded =
      case encoding do
        :base64 -> Base.encode64(bytes)
        :base58 -> Cartouche.Base58.encode(bytes)
      end

    config = %{"encoding" => encoding_string(encoding)}

    config =
      if Keyword.get(opts, :skip_preflight, false),
        do: Map.put(config, "skipPreflight", true),
        else: config

    config =
      if c = Keyword.get(opts, :preflight_commitment),
        do: Map.put(config, "preflightCommitment", to_string(c)),
        else: config

    config =
      if r = Keyword.get(opts, :max_retries), do: Map.put(config, "maxRetries", r), else: config

    send_rpc("sendTransaction", [encoded, config], opts)
  end

  api(:simulate_transaction, "Simulate a signed Solana transaction without submitting it.",
    params: [
      transaction: [
        kind: :value,
        description: "Signed `Cartouche.Solana.Transaction` struct or raw serialized transaction bytes."
      ],
      opts: [kind: :value, default: [], description: "Keyword options for simulation and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      sig_verify: [kind: :value, default: false, description: "Boolean flag to verify signatures during simulation."],
      replace_recent_blockhash: [
        kind: :value,
        default: false,
        description: "Boolean flag allowing the node to replace the transaction's recent blockhash for simulation."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{
        type: :map,
        keys: [:err, :logs, :units_consumed],
        description:
          "Map with simulation `:err`, list of log strings in `:logs`, and integer `:units_consumed` when provided."
      },
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Simulate a transaction without submitting it.

  Returns simulation result including logs, compute units consumed, and errors.
  """
  @spec simulate_transaction(binary() | Transaction.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def simulate_transaction(transaction, opts \\ [])

  def simulate_transaction(%Transaction{} = trx, opts) do
    simulate_transaction(Transaction.serialize(trx), opts)
  end

  def simulate_transaction(bytes, opts) when is_binary(bytes) do
    config = %{"encoding" => "base64"}

    config =
      if c = Keyword.get(opts, :commitment),
        do: Map.put(config, "commitment", to_string(c)),
        else: config

    config =
      if Keyword.get(opts, :sig_verify, false),
        do: Map.put(config, "sigVerify", true),
        else: config

    config =
      if Keyword.get(opts, :replace_recent_blockhash, false),
        do: Map.put(config, "replaceRecentBlockhash", true),
        else: config

    encoded = Base.encode64(bytes)

    with {:ok, result} <- send_rpc("simulateTransaction", [encoded, config], opts) do
      value = unwrap_value(result)
      {:ok, %{err: value["err"], logs: value["logs"], units_consumed: value["unitsConsumed"]}}
    end
  end

  api(:request_airdrop, "Request a devnet/testnet SOL airdrop.",
    params: [
      pubkey: [
        kind: :value,
        description:
          "Raw 32-byte Solana public key binary (`<<_::256>>`) receiving the airdrop; Base58-encoded internally."
      ],
      lamports: [kind: :value, description: "Amount in lamports (1 SOL = 1_000_000_000 lamports)."],
      opts: [kind: :value, default: [], description: "Keyword options for commitment and RPC client configuration."]
    ],
    opts: [
      commitment: [
        kind: :value,
        description: "Commitment level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      min_context_slot: [kind: :value, description: "Minimum context slot as a non-negative integer."]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :string, description: "Base58-encoded Solana transaction signature for the airdrop."},
      error: %{type: :term, description: "RPC transport, node, or decode error."}
    }
  )

  @doc """
  Request an airdrop of SOL (devnet/testnet only).

  Returns the airdrop transaction signature.
  """
  @spec request_airdrop(<<_::256>>, non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def request_airdrop(pubkey, lamports, opts \\ []) do
    send_rpc(
      "requestAirdrop",
      params_with_config([encode_pubkey(pubkey), lamports], opts),
      opts
    )
  end

  # ---------------------------------------------------------------------------
  # High-level helpers
  # ---------------------------------------------------------------------------

  api(:send_and_confirm, "Send a signed transaction and poll until it reaches the target confirmation level.",
    params: [
      transaction: [
        kind: :value,
        description: "Signed `Cartouche.Solana.Transaction` struct or raw serialized transaction bytes."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options for submission, confirmation polling, and RPC client configuration."
      ]
    ],
    opts: [
      commitment: [
        kind: :value,
        default: :confirmed,
        description: "Target confirmation level atom: `:finalized`, `:confirmed`, or `:processed`."
      ],
      timeout: [kind: :value, default: 30_000, description: "Maximum confirmation wait in milliseconds."],
      poll_interval: [kind: :value, default: 500, description: "Polling interval in milliseconds."],
      encoding: [
        kind: :value,
        default: :base64,
        description: "Wire encoding for serialized transaction bytes when submitting: `:base64` or `:base58`."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      ok: %{type: :string, description: "Base58-encoded Solana transaction signature once confirmed."},
      error: %{
        type: :term,
        description: "RPC error, `:timeout`, or `{:transaction_error, err}` from signature status."
      }
    },
    composes_with: [:send_transaction, :get_signature_statuses]
  )

  @doc """
  Send a transaction and poll for confirmation.

  ## Options
  - `:commitment` - Confirmation level to wait for (default: `:confirmed`)
  - `:timeout` - Max time to wait in ms (default: 30_000)
  - `:poll_interval` - Poll interval in ms (default: 500)
  - All options from `send_transaction/2`
  """
  @spec send_and_confirm(Transaction.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_and_confirm(transaction, opts \\ []) do
    target_commitment = Keyword.get(opts, :commitment, :confirmed)
    timeout = Keyword.get(opts, :timeout, 30_000)
    poll_interval = Keyword.get(opts, :poll_interval, 500)

    with {:ok, signature} <- send_transaction(transaction, opts) do
      deadline = System.monotonic_time(:millisecond) + timeout

      poll_signature(signature, target_commitment, poll_interval, deadline, opts)
    end
  end

  @spec poll_signature(String.t(), atom(), pos_integer(), integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp poll_signature(signature, target, interval, deadline, opts) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      check_status(signature, target, interval, deadline, opts)
    end
  end

  @spec check_status(String.t(), atom(), pos_integer(), integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp check_status(signature, target, interval, deadline, opts) do
    case get_signature_statuses([signature], opts) do
      {:ok, [nil]} ->
        retry(signature, target, interval, deadline, opts)

      {:ok, [%{err: err}]} when not is_nil(err) ->
        {:error, {:transaction_error, err}}

      {:ok, [%{confirmation_status: status}]} ->
        if status_satisfies?(status, target),
          do: {:ok, signature},
          else: retry(signature, target, interval, deadline, opts)

      {:ok, _} ->
        retry(signature, target, interval, deadline, opts)

      {:error, _} = err ->
        err
    end
  end

  @spec retry(String.t(), atom(), pos_integer(), integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp retry(signature, target, interval, deadline, opts) do
    Process.sleep(interval)
    poll_signature(signature, target, interval, deadline, opts)
  end

  # Solana confirmation levels are ordered processed < confirmed < finalized;
  # a target is satisfied by an equal-or-stronger observed status. The clauses
  # mirror the original guards exactly: an exact match, `finalized` as terminal
  # for any target, and `confirmed` satisfying a `processed` target.
  @spec status_satisfies?(atom(), atom()) :: boolean()
  defp status_satisfies?(status, status), do: true
  defp status_satisfies?(:finalized, _target), do: true
  defp status_satisfies?(:confirmed, :processed), do: true
  defp status_satisfies?(_status, _target), do: false
end
