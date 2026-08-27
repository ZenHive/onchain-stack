defmodule Cartouche.DebugTrace do
  @moduledoc ~S"""
  Represents an Ethereum transaction debug trace, which contains information
  about the call graph of an executed transaction. Note: this is different
  from `trace_call` and instead has deep struct logs for execution.

  See `Cartouche.RPC.debug_trace_call` for getting traces from
  an Ethereum JSON-RPC host.

  See also:
    * QuickNode docs: https://www.quicknode.com/docs/ethereum/debug_traceCall
  """

  use Descripex, namespace: "/ethereum/debug_trace"
  use Cartouche.Hex

  defmodule StructLog do
    @moduledoc """
    One execution step inside a `Cartouche.DebugTrace` — the EVM opcode,
    program counter, call depth, remaining gas, gas cost of this step, and
    the stack snapshot at that point.
    """
    use Descripex, namespace: "/ethereum/debug_trace/struct_log"

    @type t() :: %__MODULE__{
            depth: integer(),
            gas: integer(),
            gas_cost: integer(),
            op: atom(),
            pc: integer(),
            stack: [binary()]
          }

    defstruct [
      :depth,
      :gas,
      :gas_cost,
      :op,
      :pc,
      :stack
    ]

    # Closed whitelist of EVM opcode strings that real nodes emit in
    # `eth_debug_traceCall` struct-logs. Atoms are interned at compile time when
    # the AST is built; runtime lookup uses `Map.fetch/2` so RPC input cannot grow
    # the BEAM atom table.
    #
    # Aliases for opcode 0x20 (`KECCAK256`):
    #   KECCAK256 — current Geth and most modern clients
    #   SHA3      — pre-1.8 Geth and some non-Geth nodes (Erigon/Nethermind history)
    #
    # Aliases for opcode 0x44 (the post-Merge randomness slot):
    #   DIFFICULTY  — current go-ethereum mnemonic. The rename to PREVRANDAO is
    #                 still an open TODO in go-ethereum master (`opCodeToString`
    #                 in `core/vm/opcodes.go`), so live struct-logs from any
    #                 current Geth node carry "DIFFICULTY", not "PREVRANDAO".
    #   PREVRANDAO  — forward-compat for clients (or a future Geth) that emit the
    #                 post-Merge name; Erigon/Reth historically used it.
    # Atom literals (`~w(...)a`) so the compiler interns every opcode atom at
    # build time — no `String.to_atom/1` on the list, and runtime lookup
    # (`Map.fetch/2` keyed by the wire string) can never grow the atom table.
    @single_opcodes ~w(
      STOP ADD MUL SUB DIV SDIV MOD SMOD ADDMOD MULMOD EXP SIGNEXTEND
      LT GT SLT SGT EQ ISZERO AND OR XOR NOT BYTE SHL SHR SAR CLZ
      KECCAK256 SHA3
      ADDRESS BALANCE ORIGIN CALLER CALLVALUE CALLDATALOAD CALLDATASIZE CALLDATACOPY
      CODESIZE CODECOPY GASPRICE EXTCODESIZE EXTCODECOPY RETURNDATASIZE RETURNDATACOPY
      EXTCODEHASH BLOCKHASH COINBASE TIMESTAMP NUMBER DIFFICULTY PREVRANDAO GASLIMIT CHAINID
      SELFBALANCE BASEFEE BLOBHASH BLOBBASEFEE
      POP MLOAD MSTORE MSTORE8 SLOAD SSTORE JUMP JUMPI PC MSIZE GAS JUMPDEST
      TLOAD TSTORE MCOPY PUSH0
      CREATE CALL CALLCODE RETURN DELEGATECALL CREATE2 STATICCALL REVERT INVALID SELFDESTRUCT
    )a

    @ranged_opcodes ~w(
      PUSH1 PUSH2 PUSH3 PUSH4 PUSH5 PUSH6 PUSH7 PUSH8 PUSH9 PUSH10 PUSH11 PUSH12
      PUSH13 PUSH14 PUSH15 PUSH16 PUSH17 PUSH18 PUSH19 PUSH20 PUSH21 PUSH22 PUSH23
      PUSH24 PUSH25 PUSH26 PUSH27 PUSH28 PUSH29 PUSH30 PUSH31 PUSH32
      DUP1 DUP2 DUP3 DUP4 DUP5 DUP6 DUP7 DUP8 DUP9 DUP10 DUP11 DUP12 DUP13 DUP14 DUP15 DUP16
      SWAP1 SWAP2 SWAP3 SWAP4 SWAP5 SWAP6 SWAP7 SWAP8 SWAP9 SWAP10 SWAP11 SWAP12
      SWAP13 SWAP14 SWAP15 SWAP16
      LOG0 LOG1 LOG2 LOG3 LOG4
    )a

    @opcode_to_atom Map.new(@single_opcodes ++ @ranged_opcodes, &{Atom.to_string(&1), &1})

    api(:deserialize, "Decode a JSON-RPC debug trace struct-log object.",
      params: [
        params: [
          kind: :exchange_data,
          source: "Cartouche.RPC.debug_trace_call/2",
          description: "Map with `depth`, `gas`, `gasCost`, `op`, `pc`, and `stack` fields from a `structLogs` entry."
        ]
      ],
      returns: %{
        type: :debug_trace_struct_log,
        description:
          "%Cartouche.DebugTrace.StructLog{} with integer depth/gas metadata, a whitelisted opcode atom, and decoded stack words."
      }
    )

    @doc ~S"""
    Deserializes a trace's struct-log into a struct.

    Raises `ArgumentError` for unknown opcode strings or non-binary `op` —
    the whitelist covers Cancun-era opcodes, Osaka's `CLZ` (EIP-7939),
    plus the legacy Geth `SHA3` alias;
    future-fork additions surface as raises rather than silent atom-table growth.

    ## Examples

        iex> %{
        ...>   "depth" => 1,
        ...>   "gas" => 599978565,
        ...>   "gasCost" => 3,
        ...>   "op" => "PUSH1",
        ...>   "pc" => 2,
        ...>   "stack" => ["0x80"]
        ...> }
        ...> |> Cartouche.DebugTrace.StructLog.deserialize()
        %Cartouche.DebugTrace.StructLog{
          depth: 1,
          gas: 599978565,
          gas_cost: 3,
          op: :PUSH1,
          pc: 2,
          stack: [~h[0x80]]
        }
    """
    @spec deserialize(map()) :: t() | no_return()
    def deserialize(params) do
      %__MODULE__{
        depth: params["depth"],
        gas: params["gas"],
        gas_cost: params["gasCost"],
        op: decode_op(params["op"]),
        pc: params["pc"],
        stack: Enum.map(params["stack"], &Cartouche.Hex.decode_hex!/1)
      }
    end

    @spec decode_op(term()) :: atom() | no_return()
    defp decode_op(op) when is_binary(op) do
      case Map.fetch(@opcode_to_atom, op) do
        {:ok, atom} -> atom
        :error -> raise ArgumentError, "unknown EVM opcode: #{inspect(op)}"
      end
    end

    defp decode_op(op) do
      raise ArgumentError, "expected binary opcode string, got: #{inspect(op)}"
    end

    api(:serialize, "Encode a debug trace struct-log struct back to a JSON map.",
      params: [
        struct_log: [
          kind: :value,
          description: "%Cartouche.DebugTrace.StructLog{} to serialize."
        ]
      ],
      returns: %{
        type: :map,
        description: "JSON-ready map with `depth`, `gas`, `gasCost`, `op`, `pc`, and hex-encoded `stack` fields."
      }
    )

    @doc ~S"""
    Serializes a trace's struct-log into a json map.

    ## Examples

        iex> %Cartouche.DebugTrace.StructLog{
        ...>   depth: 1,
        ...>   gas: 599978565,
        ...>   gas_cost: 3,
        ...>   op: :PUSH1,
        ...>   pc: 2,
        ...>   stack: [~h[0x80]]
        ...> }
        ...> |> Cartouche.DebugTrace.StructLog.serialize()
        %{
          depth: 1,
          gas: 599978565,
          gasCost: 3,
          op: "PUSH1",
          pc: 2,
          stack: ["0x80"]
        }

    """
    @spec serialize(t()) :: map()
    def serialize(struct_log) do
      %{
        depth: struct_log.depth,
        gas: struct_log.gas,
        gasCost: struct_log.gas_cost,
        op: to_string(struct_log.op),
        pc: struct_log.pc,
        stack: Enum.map(struct_log.stack, &Cartouche.Hex.to_hex/1)
      }
    end
  end

  @type t() :: %__MODULE__{
          failed: boolean(),
          gas: integer(),
          return_value: binary(),
          struct_logs: [StructLog.t()]
        }

  defstruct [
    :failed,
    :gas,
    :return_value,
    :struct_logs
  ]

  api(:deserialize, "Decode a `debug_traceCall` result into a debug trace struct.",
    params: [
      params: [
        kind: :exchange_data,
        source: "Cartouche.RPC.debug_trace_call/2",
        description: "Map with `failed`, `gas`, `returnValue`, and `structLogs` from `debug_traceCall`."
      ]
    ],
    returns: %{
      type: :debug_trace,
      description:
        "%Cartouche.DebugTrace{} with decoded return value bytes and nested %Cartouche.DebugTrace.StructLog{} entries."
    }
  )

  @doc ~S"""
  Deserializes a trace result from `debug_traceCall`.

  ## Examples

      iex> %{
      ...>   "failed" => false,
      ...>   "gas" => 24034,
      ...>   "returnValue" => "0000000000000000000000000000000000000000000000000858898f93629000",
      ...>   "structLogs" => [
      ...>     %{
      ...>       "depth" => 1,
      ...>       "gas" => 599978568,
      ...>       "gasCost" => 3,
      ...>       "op" => "PUSH1",
      ...>       "pc" => 0,
      ...>       "stack" => []
      ...>     },
      ...>     %{
      ...>       "depth" => 1,
      ...>       "gas" => 599978565,
      ...>       "gasCost" => 3,
      ...>       "op" => "PUSH1",
      ...>       "pc" => 2,
      ...>       "stack" => ["0x80"]
      ...>     },
      ...>     %{
      ...>       "depth" => 1,
      ...>       "gas" => 599978562,
      ...>       "gasCost" => 12,
      ...>       "op" => "MSTORE",
      ...>       "pc" => 4,
      ...>       "stack" => ["0x80", "0x40"]
      ...>     }
      ...>   ]
      ...> }
      ...> |> Cartouche.DebugTrace.deserialize()
      %Cartouche.DebugTrace{
        failed: false,
        gas: 24034,
        return_value: ~h[0x0000000000000000000000000000000000000000000000000858898f93629000],
        struct_logs: [
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978568,
            gas_cost: 3,
            op: :PUSH1,
            pc: 0,
            stack: []
          },
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978565,
            gas_cost: 3,
            op: :PUSH1,
            pc: 2,
            stack: [~h[0x80]]
          },
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978562,
            gas_cost: 12,
            op: :MSTORE,
            pc: 4,
            stack: [~h[0x80], ~h[0x40]]
          }
        ]
      }
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(params) do
    %__MODULE__{
      failed: params["failed"],
      gas: params["gas"],
      return_value: Cartouche.Hex.decode_hex!(params["returnValue"]),
      struct_logs: Enum.map(params["structLogs"], &StructLog.deserialize/1)
    }
  end

  api(:serialize, "Encode a debug trace struct back to a JSON map.",
    params: [
      debug_trace: [
        kind: :value,
        description: "%Cartouche.DebugTrace{} to serialize."
      ]
    ],
    returns: %{
      type: :map,
      description:
        "JSON-ready map with `failed`, `gas`, hex returnValue without a 0x prefix, and serialized `structLogs`."
    }
  )

  @doc ~S"""
  Serializes a trace result back to a json map.

  ## Examples

      iex> %Cartouche.DebugTrace{
      ...>   failed: false,
      ...>   gas: 24034,
      ...>   return_value: ~h[0x0000000000000000000000000000000000000000000000000858898f93629000],
      ...>   struct_logs: [
      ...>     %Cartouche.DebugTrace.StructLog{
      ...>       depth: 1,
      ...>       gas: 599978568,
      ...>       gas_cost: 3,
      ...>       op: :PUSH1,
      ...>       pc: 0,
      ...>       stack: []
      ...>     },
      ...>     %Cartouche.DebugTrace.StructLog{
      ...>       depth: 1,
      ...>       gas: 599978565,
      ...>       gas_cost: 3,
      ...>       op: :PUSH1,
      ...>       pc: 2,
      ...>       stack: [~h[0x80]]
      ...>     },
      ...>     %Cartouche.DebugTrace.StructLog{
      ...>       depth: 1,
      ...>       gas: 599978562,
      ...>       gas_cost: 12,
      ...>       op: :MSTORE,
      ...>       pc: 4,
      ...>       stack: [~h[0x80], ~h[0x40]]
      ...>     }
      ...>   ]
      ...> }
      ...> |> Cartouche.DebugTrace.serialize()
      %{
        failed: false,
        gas: 24034,
        returnValue: "0000000000000000000000000000000000000000000000000858898f93629000",
        structLogs: [
          %{
            depth: 1,
            gas: 599978568,
            gasCost: 3,
            op: "PUSH1",
            pc: 0,
            stack: []
          },
          %{
            depth: 1,
            gas: 599978565,
            gasCost: 3,
            op: "PUSH1",
            pc: 2,
            stack: ["0x80"]
          },
          %{
            depth: 1,
            gas: 599978562,
            gasCost: 12,
            op: "MSTORE",
            pc: 4,
            stack: ["0x80", "0x40"]
          }
        ]
      }
  """
  @spec serialize(t()) :: map()
  def serialize(debug_trace) do
    %{
      failed: debug_trace.failed,
      gas: debug_trace.gas,
      returnValue: String.replace_prefix(to_hex(debug_trace.return_value), "0x", ""),
      structLogs: Enum.map(debug_trace.struct_logs, &StructLog.serialize/1)
    }
  end
end
