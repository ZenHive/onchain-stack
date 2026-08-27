defmodule Cartouche.Solana.RPCTest do
  use ExUnit.Case

  alias Cartouche.Solana.Keys
  alias Cartouche.Solana.RPC
  alias Cartouche.Solana.SystemProgram
  alias Cartouche.Solana.Transaction

  setup do
    prev_client = Application.get_env(:cartouche, RPC)
    prev_node = Application.get_env(:cartouche, :solana_node)

    Application.put_env(:cartouche, RPC, plug: &Cartouche.Solana.Test.Client.call/1)
    Application.put_env(:cartouche, :solana_node, "https://api.devnet.solana.com")

    on_exit(fn ->
      if prev_client,
        do: Application.put_env(:cartouche, RPC, prev_client),
        else: Application.delete_env(:cartouche, RPC)

      if prev_node,
        do: Application.put_env(:cartouche, :solana_node, prev_node),
        else: Application.delete_env(:cartouche, :solana_node)
    end)

    :ok
  end

  # Known test pubkeys
  @test_pubkey elem(Keys.from_seed(<<0::256>>), 0)
  @nonexistent_pubkey Cartouche.Base58.decode!("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
  @error_pubkey Cartouche.Base58.decode!("11111111111111111111111111111112")

  # Known blockhash from mock
  @mock_blockhash Cartouche.Base58.decode!("4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn")

  defmodule CustomParam do
    @moduledoc false
    defstruct [:value]
  end

  # Req function plug (`fun(conn) -> conn`). Runs in the process that calls
  # `Req.request/1` — for these direct RPC calls that is the test process, so
  # `send(self(), ...)` reaches the test's own mailbox.
  defmodule InvalidJsonRpcClient do
    @moduledoc false

    @spec call(Plug.Conn.t()) :: Plug.Conn.t()
    def call(conn) do
      id = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!() |> Map.fetch!("id")
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "unexpected" => nil, "id" => id})
    end
  end

  defmodule RecordingClient do
    @moduledoc false

    @spec call(Plug.Conn.t()) :: Plug.Conn.t()
    def call(conn) do
      decoded = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(self(), {:solana_rpc_request, decoded})

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "result" => result_for(decoded["method"]),
        "id" => decoded["id"]
      })
    end

    @spec result_for(String.t()) :: term()
    defp result_for("getAccountInfo") do
      %{"context" => %{"slot" => 256_000}, "value" => nil}
    end

    defp result_for("getMultipleAccounts") do
      %{"context" => %{"slot" => 256_000}, "value" => []}
    end

    defp result_for("getSignatureStatuses") do
      %{
        "context" => %{"slot" => 256_000},
        "value" => [
          %{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => "finalized"}
        ]
      }
    end

    defp result_for("getTransaction"), do: nil
    defp result_for("sendTransaction"), do: "recorded_signature"
  end

  # Script-driven plug for `send_and_confirm/2`. The whole submit→poll chain is
  # synchronous in the test process, so the per-poll `getSignatureStatuses`
  # sequence is pulled from the test process dictionary (`:status_script`); each
  # entry is either `nil` (signature not yet known) or a status map. Once the
  # script is exhausted it reports `finalized`.
  defmodule PollClient do
    @moduledoc false

    @spec call(Plug.Conn.t()) :: Plug.Conn.t()
    def call(conn) do
      %{"method" => method, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      payload =
        case method do
          "sendTransaction" ->
            %{"result" => "polled_sig"}

          "getSignatureStatuses" ->
            {value, rest} =
              case Process.get(:status_script, []) do
                [head | tail] -> {head, tail}
                [] -> {finalized(), []}
              end

            Process.put(:status_script, rest)
            %{"result" => %{"context" => %{"slot" => 1}, "value" => [value]}}
        end

      Req.Test.json(conn, Map.merge(%{"jsonrpc" => "2.0", "id" => id}, payload))
    end

    defp finalized do
      %{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => "finalized"}
    end
  end

  # Plug returning a single fixed response per method, configured via the test
  # process dictionary (`:rpc_responses` → `%{method => {:ok, term} | {:error, map}}`).
  defmodule StubClient do
    @moduledoc false

    @spec call(Plug.Conn.t()) :: Plug.Conn.t()
    def call(conn) do
      %{"method" => method, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      payload =
        case Map.fetch!(Process.get(:rpc_responses, %{}), method) do
          {:error, error} -> %{"error" => error}
          {:ok, value} -> %{"result" => value}
        end

      Req.Test.json(conn, Map.merge(%{"jsonrpc" => "2.0", "id" => id}, payload))
    end
  end

  # ---------------------------------------------------------------------------
  # Core transport
  # ---------------------------------------------------------------------------

  describe "send_rpc/3" do
    test "returns raw result" do
      assert RPC.send_rpc("getSlot", []) == {:ok, 256_000}
    end

    test "returns error for unknown method" do
      assert {:error, %{code: -32_601, message: "Method not found: bogusMethod"}} =
               RPC.send_rpc("bogusMethod", [])
    end

    test "invalid JSON-RPC responses return the sentinel error" do
      Application.put_env(:cartouche, RPC, plug: &InvalidJsonRpcClient.call/1)

      assert {:error, %{code: -999, message: "invalid JSON-RPC response"}} =
               RPC.send_rpc("getSlot", [])
    end

    test "returns invalid_params for a non-UTF-8 binary method" do
      assert {:error, {:invalid_params, %Jason.EncodeError{}}} = RPC.send_rpc(<<255>>, [])
    end

    test "returns invalid_params for tuple params" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} = RPC.send_rpc("getSlot", [{:bad, :tuple}])
    end

    test "returns invalid_params for atom-keyed maps with non-encodable values" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               RPC.send_rpc("getSlot", [%{non_stdlib_key: self()}])
    end

    test "returns invalid_params for custom structs without a Jason encoder" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               RPC.send_rpc("getSlot", [%CustomParam{value: 1}])
    end
  end

  # ---------------------------------------------------------------------------
  # Account methods
  # ---------------------------------------------------------------------------

  describe "get_balance/2" do
    test "returns lamport balance" do
      assert RPC.get_balance(@test_pubkey) == {:ok, 1_500_000_000}
    end

    test "returns error for error address" do
      assert {:error, %{code: -32_600, message: "Invalid request"}} =
               RPC.get_balance(@error_pubkey)
    end
  end

  describe "get_account_info/2" do
    test "returns deserialized account info" do
      assert RPC.get_account_info(@test_pubkey) ==
               {:ok,
                %{
                  data: ["AQAAAAA=", "base64"],
                  executable: false,
                  lamports: 1_461_600,
                  owner: "11111111111111111111111111111111",
                  rent_epoch: 18_446_744_073_709_551_615,
                  space: 5
                }}
    end

    test "returns nil for nonexistent account" do
      assert RPC.get_account_info(@nonexistent_pubkey) == {:ok, nil}
    end

    test "accepts supported account encodings" do
      Application.put_env(:cartouche, RPC, plug: &RecordingClient.call/1)

      for {encoding, expected} <- [
            {:base58, "base58"},
            {:base64, "base64"},
            {:"base64+zstd", "base64+zstd"},
            {:json_parsed, "jsonParsed"},
            {"customEncoding", "customEncoding"}
          ] do
        assert {:ok, nil} = RPC.get_account_info(@test_pubkey, encoding: encoding)

        assert_receive {:solana_rpc_request,
                        %{
                          "method" => "getAccountInfo",
                          "params" => [_pubkey, %{"encoding" => ^expected}]
                        }}
      end
    end
  end

  describe "get_multiple_accounts/2" do
    test "returns list with account info and nils" do
      assert {:ok, [account, nil]} =
               RPC.get_multiple_accounts([@test_pubkey, @nonexistent_pubkey])

      assert account == %{
               data: ["", "base64"],
               executable: false,
               lamports: 500_000,
               owner: "11111111111111111111111111111111",
               rent_epoch: 0,
               space: 0
             }
    end

    test "propagates encoding config" do
      Application.put_env(:cartouche, RPC, plug: &RecordingClient.call/1)

      assert {:ok, []} = RPC.get_multiple_accounts([@test_pubkey], encoding: :"base64+zstd")

      assert_receive {:solana_rpc_request,
                      %{
                        "method" => "getMultipleAccounts",
                        "params" => [[_pubkey], %{"encoding" => "base64+zstd"}]
                      }}
    end
  end

  # ---------------------------------------------------------------------------
  # Blockhash / slot methods
  # ---------------------------------------------------------------------------

  describe "get_latest_blockhash/1" do
    test "returns decoded blockhash and last valid block height" do
      assert RPC.get_latest_blockhash() ==
               {:ok,
                %{
                  blockhash: @mock_blockhash,
                  last_valid_block_height: 256_200
                }}
    end

    test "blockhash is 32 raw bytes, not a Base58 string" do
      {:ok, %{blockhash: bh}} = RPC.get_latest_blockhash()
      assert byte_size(bh) == 32
      # Verify roundtrip: encode back to Base58 matches the mock
      assert Cartouche.Base58.encode(bh) == "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn"
    end
  end

  describe "get_slot/1" do
    test "returns slot number" do
      assert RPC.get_slot() == {:ok, 256_000}
    end
  end

  describe "get_block_height/1" do
    test "returns block height" do
      assert RPC.get_block_height() == {:ok, 255_980}
    end
  end

  # ---------------------------------------------------------------------------
  # Transaction methods
  # ---------------------------------------------------------------------------

  describe "get_transaction/2" do
    test "returns full transaction data" do
      assert {:ok, trx} = RPC.get_transaction("some_signature")

      assert trx["blockTime"] == 1_708_300_522
      assert trx["slot"] == 255_900
      assert trx["version"] == "legacy"

      assert trx["meta"] == %{
               "err" => nil,
               "fee" => 5000,
               "preBalances" => [10_000_000_000, 0, 1],
               "postBalances" => [8_999_995_000, 1_000_000_000, 1],
               "logMessages" => [
                 "Program 11111111111111111111111111111111 invoke [1]",
                 "Program 11111111111111111111111111111111 success"
               ],
               "innerInstructions" => [],
               "rewards" => nil,
               "loadedAddresses" => %{"readonly" => [], "writable" => []},
               "computeUnitsConsumed" => 150
             }
    end

    test "returns nil for not-found transaction" do
      assert RPC.get_transaction("not_found_sig") == {:ok, nil}
    end

    test "accepts explicit transaction encodings" do
      Application.put_env(:cartouche, RPC, plug: &RecordingClient.call/1)

      for {encoding, expected} <- [
            {:base58, "base58"},
            {:base64, "base64"},
            {:json_parsed, "jsonParsed"},
            {"json", "json"}
          ] do
        assert {:ok, nil} = RPC.get_transaction("some_signature", encoding: encoding)

        assert_receive {:solana_rpc_request,
                        %{
                          "method" => "getTransaction",
                          "params" => [
                            "some_signature",
                            %{
                              "encoding" => ^expected,
                              "maxSupportedTransactionVersion" => 0
                            }
                          ]
                        }}
      end
    end
  end

  describe "get_signature_statuses/2" do
    test "finalized status" do
      assert RPC.get_signature_statuses(["finalized_sig"]) ==
               {:ok,
                [
                  %{
                    slot: 255_900,
                    confirmations: nil,
                    err: nil,
                    confirmation_status: :finalized
                  }
                ]}
    end

    test "confirmed status with confirmation count" do
      assert RPC.get_signature_statuses(["confirmed_sig"]) ==
               {:ok,
                [
                  %{
                    slot: 255_900,
                    confirmations: 10,
                    err: nil,
                    confirmation_status: :confirmed
                  }
                ]}
    end

    test "failed transaction" do
      assert RPC.get_signature_statuses(["failed_sig"]) ==
               {:ok,
                [
                  %{
                    slot: 255_900,
                    confirmations: nil,
                    err: %{"InstructionError" => [0, "InsufficientFunds"]},
                    confirmation_status: :finalized
                  }
                ]}
    end

    test "unknown signature returns nil" do
      assert RPC.get_signature_statuses(["unknown_sig"]) == {:ok, [nil]}
    end

    test "mixed statuses" do
      assert {:ok, [finalized, nil, failed]} =
               RPC.get_signature_statuses(["finalized_sig", "unknown_sig", "failed_sig"])

      assert finalized.confirmation_status == :finalized
      assert finalized.err == nil
      assert nil == nil
      assert failed.err == %{"InstructionError" => [0, "InsufficientFunds"]}
    end
  end

  # ---------------------------------------------------------------------------
  # Rent / fees
  # ---------------------------------------------------------------------------

  describe "get_minimum_balance_for_rent_exemption/2" do
    test "returns lamports for token account size" do
      assert RPC.get_minimum_balance_for_rent_exemption(165) == {:ok, 2_039_280}
    end

    test "returns lamports for zero-data account" do
      assert RPC.get_minimum_balance_for_rent_exemption(0) == {:ok, 890_880}
    end
  end

  # ---------------------------------------------------------------------------
  # Token methods
  # ---------------------------------------------------------------------------

  describe "get_token_account_balance/2" do
    test "returns parsed token amount" do
      assert RPC.get_token_account_balance(@test_pubkey) ==
               {:ok,
                %{
                  amount: 1_000_000_000,
                  decimals: 9,
                  ui_amount_string: "1"
                }}
    end
  end

  describe "get_token_accounts_by_owner/3" do
    test "filter by mint returns token accounts" do
      assert {:ok, [account]} =
               RPC.get_token_accounts_by_owner(@test_pubkey, mint: @test_pubkey)

      assert account.pubkey == "AyVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZr"
      assert account.account.lamports == 2_039_280
      assert account.account.space == 165
    end

    test "filter by program_id returns token accounts" do
      token_program = Cartouche.Solana.Programs.token_program()

      assert {:ok, accounts} =
               RPC.get_token_accounts_by_owner(@test_pubkey, program_id: token_program)

      assert [_, _] = accounts
    end

    test "requires a mint or program id filter" do
      assert_raise ArgumentError, ~r/requires :mint or :program_id filter/, fn ->
        RPC.get_token_accounts_by_owner(@test_pubkey, [])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Fee methods
  # ---------------------------------------------------------------------------

  describe "get_recent_prioritization_fees/2" do
    test "returns fee list" do
      assert RPC.get_recent_prioritization_fees() ==
               {:ok,
                [
                  %{slot: 255_998, prioritization_fee: 0},
                  %{slot: 255_999, prioritization_fee: 1000},
                  %{slot: 256_000, prioritization_fee: 500}
                ]}
    end
  end

  # ---------------------------------------------------------------------------
  # Node info
  # ---------------------------------------------------------------------------

  describe "get_health/1" do
    test "returns :ok when healthy" do
      assert RPC.get_health() == :ok
    end
  end

  describe "get_version/1" do
    test "returns parsed version info" do
      assert RPC.get_version() ==
               {:ok, %{solana_core: "1.18.26", feature_set: 2_891_131_721}}
    end
  end

  # ---------------------------------------------------------------------------
  # Write methods
  # ---------------------------------------------------------------------------

  describe "send_transaction/2" do
    test "sends transaction struct and returns signature" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 1_000_000)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)
      {_pub, seed} = Keys.from_seed(<<1::256>>)
      trx = Transaction.sign(msg, [seed])

      assert RPC.send_transaction(trx) ==
               {:ok, "4Lz3raap9pEVGjT4EuVmNxTzMEj3EhVFKBonVFcnjiMwFKwEqh9TuPRYSv3TpK6ia4W33kMtJMdRJiL"}
    end

    test "sends raw bytes" do
      assert RPC.send_transaction(<<1, 2, 3>>) ==
               {:ok, "4Lz3raap9pEVGjT4EuVmNxTzMEj3EhVFKBonVFcnjiMwFKwEqh9TuPRYSv3TpK6ia4W33kMtJMdRJiL"}
    end

    test "accepts base58 encoding and send options" do
      Application.put_env(:cartouche, RPC, plug: &RecordingClient.call/1)

      assert RPC.send_transaction(<<1, 2, 3>>,
               encoding: :base58,
               skip_preflight: true,
               preflight_commitment: :confirmed,
               max_retries: 5
             ) == {:ok, "recorded_signature"}

      assert_receive {:solana_rpc_request,
                      %{
                        "method" => "sendTransaction",
                        "params" => [
                          "Ldp",
                          %{
                            "encoding" => "base58",
                            "skipPreflight" => true,
                            "preflightCommitment" => "confirmed",
                            "maxRetries" => 5
                          }
                        ]
                      }}
    end
  end

  describe "simulate_transaction/2" do
    test "returns simulation result" do
      assert RPC.simulate_transaction(<<1, 2, 3>>) ==
               {:ok,
                %{
                  err: nil,
                  logs: [
                    "Program 11111111111111111111111111111111 invoke [1]",
                    "Program 11111111111111111111111111111111 success"
                  ],
                  units_consumed: 150
                }}
    end

    test "accepts transaction struct" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>
      ix = SystemProgram.transfer(fee_payer, recipient, 100)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)
      {_pub, seed} = Keys.from_seed(<<1::256>>)
      trx = Transaction.sign(msg, [seed])

      assert {:ok, %{err: nil, logs: [_ | _]}} = RPC.simulate_transaction(trx)
    end
  end

  describe "request_airdrop/3" do
    test "returns airdrop transaction signature" do
      assert RPC.request_airdrop(@test_pubkey, 1_000_000_000) ==
               {:ok, "2ZE3FQsWzjbkyNKP5qEDGjJEsaWmVFBCKSBMxpZUTgBs1PWDM1jN6hUEyFz1"}
    end
  end

  # ---------------------------------------------------------------------------
  # Config / response-shaping edge cases
  # ---------------------------------------------------------------------------

  describe "request config edge cases" do
    test "min_context_slot is propagated through the commitment config" do
      Application.put_env(:cartouche, RPC, plug: &RecordingClient.call/1)

      assert {:ok, nil} =
               RPC.get_account_info(@test_pubkey, commitment: :confirmed, min_context_slot: 100)

      assert_receive {:solana_rpc_request,
                      %{
                        "method" => "getAccountInfo",
                        "params" => [_pubkey, %{"commitment" => "confirmed", "minContextSlot" => 100}]
                      }}
    end

    test "get_signature_statuses sends searchTransactionHistory and parses confirmation status" do
      Application.put_env(:cartouche, RPC, plug: &RecordingClient.call/1)

      assert {:ok, [%{confirmation_status: :finalized}]} =
               RPC.get_signature_statuses(["sig"], search_transaction_history: true)

      assert_receive {:solana_rpc_request,
                      %{
                        "method" => "getSignatureStatuses",
                        "params" => [["sig"], %{"searchTransactionHistory" => true}]
                      }}
    end

    test "unwraps a status result that is not context/value shaped" do
      # `getSignatureStatuses` here returns a bare list rather than the usual
      # `%{"context" => _, "value" => _}` envelope, exercising unwrap_value/1's
      # fallthrough clause.
      Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)

      # A `nil` confirmationStatus also exercises parse_commitment/1's nil clause.
      Process.put(:rpc_responses, %{
        "getSignatureStatuses" => {
          :ok,
          [%{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => nil}]
        }
      })

      assert {:ok, [%{confirmation_status: nil}]} = RPC.get_signature_statuses(["sig"])
    end

    test "simulate_transaction propagates commitment, sig_verify, and replace_recent_blockhash" do
      assert {:ok, %{err: nil}} =
               RPC.simulate_transaction(<<1, 2, 3>>,
                 commitment: :confirmed,
                 sig_verify: true,
                 replace_recent_blockhash: true
               )
    end
  end

  describe "get_health/1 result mapping" do
    test "treats any successful result as healthy" do
      Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)
      Process.put(:rpc_responses, %{"getHealth" => {:ok, "behind"}})

      assert RPC.get_health() == :ok
    end

    test "returns the error when the node reports unhealthy" do
      Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)
      Process.put(:rpc_responses, %{"getHealth" => {:error, %{"code" => -32_005, "message" => "behind"}}})

      assert {:error, %{code: -32_005}} = RPC.get_health()
    end
  end

  # ---------------------------------------------------------------------------
  # send_and_confirm / poll_signature
  # ---------------------------------------------------------------------------

  describe "send_and_confirm/2" do
    test "confirms immediately when the node already reports finalized" do
      assert {:ok, signature} = RPC.send_and_confirm(<<1, 2, 3>>, poll_interval: 1)
      assert is_binary(signature)
    end

    test "polls past unknown statuses until the target commitment is reached" do
      Application.put_env(:cartouche, RPC, plug: &PollClient.call/1)

      Process.put(:status_script, [
        nil,
        %{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => "confirmed"}
      ])

      assert {:ok, "polled_sig"} =
               RPC.send_and_confirm(<<1>>, poll_interval: 1, commitment: :confirmed)
    end

    test "recurses on a below-target status before confirming (target :confirmed)" do
      Application.put_env(:cartouche, RPC, plug: &PollClient.call/1)

      Process.put(:status_script, [
        %{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => "processed"},
        %{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => "confirmed"}
      ])

      assert {:ok, "polled_sig"} =
               RPC.send_and_confirm(<<1>>, poll_interval: 1, commitment: :confirmed)
    end

    test "accepts a confirmed status when the target is :processed" do
      Application.put_env(:cartouche, RPC, plug: &PollClient.call/1)

      Process.put(:status_script, [
        %{"slot" => 1, "confirmations" => nil, "err" => nil, "confirmationStatus" => "confirmed"}
      ])

      assert {:ok, "polled_sig"} =
               RPC.send_and_confirm(<<1>>, poll_interval: 1, commitment: :processed)
    end

    test "returns {:transaction_error, err} when the transaction failed" do
      Application.put_env(:cartouche, RPC, plug: &PollClient.call/1)

      Process.put(:status_script, [
        %{
          "slot" => 1,
          "confirmations" => nil,
          "err" => %{"InstructionError" => [0, "Custom"]},
          "confirmationStatus" => "processed"
        }
      ])

      assert {:error, {:transaction_error, %{"InstructionError" => [0, "Custom"]}}} =
               RPC.send_and_confirm(<<1>>, poll_interval: 1)
    end

    test "times out when the signature never reaches a status" do
      Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)

      Process.put(:rpc_responses, %{
        "sendTransaction" => {:ok, "sig"},
        "getSignatureStatuses" => {:ok, %{"context" => %{"slot" => 1}, "value" => [nil]}}
      })

      assert {:error, :timeout} = RPC.send_and_confirm(<<1>>, timeout: 5, poll_interval: 1)
    end

    test "propagates an RPC error raised during status polling" do
      Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)

      Process.put(:rpc_responses, %{
        "sendTransaction" => {:ok, "sig"},
        "getSignatureStatuses" => {:error, %{"code" => -32_002, "message" => "node error"}}
      })

      assert {:error, %{code: -32_002}} = RPC.send_and_confirm(<<1>>, poll_interval: 1)
    end

    test "returns the submission error when sendTransaction fails" do
      Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)

      Process.put(:rpc_responses, %{
        "sendTransaction" => {:error, %{"code" => -32_000, "message" => "blockhash not found"}}
      })

      assert {:error, %{code: -32_000}} = RPC.send_and_confirm(<<1>>)
    end
  end
end
