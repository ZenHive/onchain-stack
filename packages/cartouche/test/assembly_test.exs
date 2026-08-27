defmodule Cartouche.AssemblyTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Assembly
  alias Cartouche.Assembly.InvalidAssembly
  alias Cartouche.Assembly.InvalidCode
  alias Cartouche.Assembly.InvalidOpcode

  doctest Assembly

  describe "compile/1" do
    test "with jumps" do
      assert [
               {:push, 4, <<1, 2, 3, 4>>},
               {:push, 1, <<0>>},
               :mstore,
               :origin,
               {:jump_ptr, i},
               :jumpi,
               {:push, 1, <<0>>},
               {:push, 1, <<0>>},
               :return,
               {:jump_dest, i},
               {:push, 1, <<4>>},
               {:push, 1, <<28>>},
               :revert
             ] =
               Assembly.compile([
                 {:mstore, 0, 0x01020304},
                 {:if, :origin, {:revert, 28, 4}, {:return, 0, 0}}
               ])
    end

    test "3-operand opcode" do
      assert Assembly.compile({:addmod, 1, 2, 3}) ==
               [{:push, 1, <<3>>}, {:push, 1, <<2>>}, {:push, 1, <<1>>}, :addmod]
    end

    test "4-operand opcode" do
      assert Assembly.compile({:create2, 1, 2, 3, 4}) ==
               [{:push, 1, <<4>>}, {:push, 1, <<3>>}, {:push, 1, <<2>>}, {:push, 1, <<1>>}, :create2]
    end

    test "5-operand opcode" do
      assert Assembly.compile({:log3, 1, 2, 3, 4, 5}) ==
               [
                 {:push, 1, <<5>>},
                 {:push, 1, <<4>>},
                 {:push, 1, <<3>>},
                 {:push, 1, <<2>>},
                 {:push, 1, <<1>>},
                 :log3
               ]
    end

    test "6-operand opcode" do
      assert Assembly.compile({:delegatecall, 1, 2, 3, 4, 5, 6}) ==
               [
                 {:push, 1, <<6>>},
                 {:push, 1, <<5>>},
                 {:push, 1, <<4>>},
                 {:push, 1, <<3>>},
                 {:push, 1, <<2>>},
                 {:push, 1, <<1>>},
                 :delegatecall
               ]
    end

    test "7-operand opcode" do
      assert Assembly.compile({:call, 1, 2, 3, 4, 5, 6, 7}) ==
               [
                 {:push, 1, <<7>>},
                 {:push, 1, <<6>>},
                 {:push, 1, <<5>>},
                 {:push, 1, <<4>>},
                 {:push, 1, <<3>>},
                 {:push, 1, <<2>>},
                 {:push, 1, <<1>>},
                 :call
               ]
    end

    test "1-operand opcode" do
      assert Assembly.compile({:iszero, 5}) == [{:push, 1, <<5>>}, :iszero]
    end

    test "2-operand opcode" do
      assert Assembly.compile({:mstore, 1, 2}) ==
               [{:push, 1, <<2>>}, {:push, 1, <<1>>}, :mstore]
    end

    test "no-operand opcode is returned as-is" do
      assert Assembly.compile(:address) == :address
    end

    test ":self_code_sz is returned as-is" do
      assert Assembly.compile(:self_code_sz) == :self_code_sz
    end

    test "unknown atom raises InvalidAssembly" do
      assert_raise InvalidAssembly, ~r/invalid or unknown assembly/, fn ->
        Assembly.compile(:not_an_opcode)
      end
    end

    test "unknown tuple raises InvalidAssembly" do
      assert_raise InvalidAssembly, ~r/invalid or unknown assembly/, fn ->
        Assembly.compile({:not_an_opcode, 1, 2})
      end
    end

    test "known opcode with wrong operand count raises InvalidAssembly" do
      # :add takes 2 operands, not 1.
      assert_raise InvalidAssembly, ~r/invalid or unknown assembly/, fn ->
        Assembly.compile({:add, 1})
      end
    end
  end

  describe "build/1" do
    test "check origin" do
      assert to_hex(
               Assembly.build([
                 {:mstore, 0, 0x01020304},
                 {:if, :origin, {:revert, 28, 4}, {:return, 0, 0}}
               ])
             ) == "0x630102030460005232620000135760006000f35b6004601cfd"
    end
  end

  describe "constructor/1" do
    test "wraps body so the resulting code ends in the body bytes" do
      body = ~h[0xaabbcc]
      out = Assembly.constructor(body)

      assert binary_part(out, byte_size(out) - byte_size(body), byte_size(body)) == body
    end

    test "produces the documented bytecode for ~h[0xaabbcc]" do
      assert to_hex(Assembly.constructor(~h[0xaabbcc])) ==
               "0x60036200000e60003960036000f3aabbcc"
    end
  end

  describe "transform_jumps via assemble/1" do
    test "raises InvalidOpcode for missing jump destination" do
      assert_raise InvalidOpcode, ~r/could not find jump dest/, fn ->
        Assembly.assemble([{:jump_ptr, :missing}])
      end
    end

    test "resolves :self_code_sz to the total assembled size" do
      # Two opcodes: PUSH3 (4 bytes) + STOP (1 byte) = 5 bytes total.
      assert Assembly.assemble([:self_code_sz, :stop]) == <<0x62, 0, 0, 5, 0x00>>
    end

    test "resolves jump_ptr to the correct pc" do
      out =
        Assembly.assemble([
          {:jump_ptr, :a},
          :stop,
          {:jump_dest, :a},
          :stop
        ])

      # PUSH3 (4 bytes) + STOP (1) = jumpdest at pc 5; then JUMPDEST + STOP.
      assert out == <<0x62, 0, 0, 5, 0x00, 0x5B, 0x00>>
    end
  end

  describe "disassemble_opcode/1" do
    test "every PUSH width 1..32" do
      for n <- 1..32 do
        payload = :binary.copy(<<0xAB>>, n)
        bin = <<0x5F + n>> <> payload
        assert Assembly.disassemble_opcode(bin) == {{:push, n, payload}, <<>>}
      end
    end

    test "every DUP width 1..16" do
      for n <- 1..16 do
        assert Assembly.disassemble_opcode(<<0x7F + n>>) == {{:dup, n}, <<>>}
      end
    end

    test "every SWAP width 1..16" do
      for n <- 1..16 do
        assert Assembly.disassemble_opcode(<<0x8F + n>>) == {{:swap, n}, <<>>}
      end
    end

    test "0xFE consumes all remaining bytes as invalid data" do
      assert Assembly.disassemble_opcode(<<0xFE, 1, 2, 3>>) == {{:invalid, <<1, 2, 3>>}, <<>>}
    end

    test "single-byte known opcode + remaining" do
      assert Assembly.disassemble_opcode(<<0x01, 0xFF>>) == {:add, <<0xFF>>}
    end

    test "truncated PUSH raises InvalidCode" do
      assert_raise InvalidCode, ~r/unsufficient data for push/, fn ->
        Assembly.disassemble_opcode(<<0x60>>)
      end
    end
  end

  describe "opcode_size/1" do
    test "{:push, n, _} is n + 1" do
      assert Assembly.opcode_size({:push, 5, <<1, 2, 3, 4, 5>>}) == 6
      assert Assembly.opcode_size({:push, 0, <<>>}) == 1
    end

    test "{:jump_ptr, _} is 4 (PUSH3 + jump byte slot)" do
      assert Assembly.opcode_size({:jump_ptr, 0}) == 4
    end

    test ":self_code_sz is 4" do
      assert Assembly.opcode_size(:self_code_sz) == 4
    end

    test "{:jump_dest, _} is 1" do
      assert Assembly.opcode_size({:jump_dest, 0}) == 1
    end

    test "{:dup, _} is 1" do
      assert Assembly.opcode_size({:dup, 3}) == 1
    end

    test "{:swap, _} is 1" do
      assert Assembly.opcode_size({:swap, 7}) == 1
    end

    test "{:invalid, data} is 1 + byte_size(data)" do
      assert Assembly.opcode_size({:invalid, <<1, 2, 3>>}) == 4
      assert Assembly.opcode_size({:invalid, <<>>}) == 1
    end

    test "named opcode is 1" do
      assert Assembly.opcode_size(:add) == 1
      assert Assembly.opcode_size(:jumpdest) == 1
    end
  end

  describe "show_opcode/1" do
    @show_opcode_atoms [
      {:stop, "STOP"},
      {:add, "ADD"},
      {:sub, "SUB"},
      {:mul, "MUL"},
      {:div, "DIV"},
      {:sdiv, "SDIV"},
      {:mod, "MOD"},
      {:smod, "SMOD"},
      {:addmod, "ADDMOD"},
      {:mulmod, "MULMOD"},
      {:exp, "EXP"},
      {:signextend, "SIGNEXTEND"},
      {:lt, "LT"},
      {:gt, "GT"},
      {:slt, "SLT"},
      {:sgt, "SGT"},
      {:eq, "EQ"},
      {:iszero, "ISZERO"},
      {:and, "AND"},
      {:or, "OR"},
      {:xor, "XOR"},
      {:not, "NOT"},
      {:byte, "BYTE"},
      {:shl, "SHL"},
      {:shr, "SHR"},
      {:sar, "SAR"},
      {:sha3, "SHA3"},
      {:callvalue, "CALLVALUE"},
      {:calldataload, "CALLDATALOAD"},
      {:calldatasize, "CALLDATASIZE"},
      {:calldatacopy, "CALLDATACOPY"},
      {:codesize, "CODESIZE"},
      {:codecopy, "CODECOPY"},
      {:pop, "POP"},
      {:mload, "MLOAD"},
      {:mstore, "MSTORE"},
      {:mstore8, "MSTORE8"},
      {:jump, "JUMP"},
      {:jumpi, "JUMPI"},
      {:pc, "PC"},
      {:msize, "MSIZE"},
      {:gas, "GAS"},
      {:jumpdest, "JUMPDEST"},
      {:tload, "TLOAD"},
      {:tstore, "TSTORE"},
      {:mcopy, "MCOPY"},
      {:return, "RETURN"},
      {:revert, "REVERT"},
      {:staticcall, "STATICCALL"},
      {:returndatasize, "RETURNDATASIZE"},
      {:returndatacopy, "RETURNDATACOPY"},
      {:address, "ADDRESS"},
      {:balance, "BALANCE"},
      {:origin, "ORIGIN"},
      {:caller, "CALLER"},
      {:gasprice, "GASPRICE"},
      {:extcodesize, "EXTCODESIZE"},
      {:extcodecopy, "EXTCODECOPY"},
      {:extcodehash, "EXTCODEHASH"},
      {:blockhash, "BLOCKHASH"},
      {:coinbase, "COINBASE"},
      {:timestamp, "TIMESTAMP"},
      {:number, "NUMBER"},
      {:prevrandao, "PREVRANDAO"},
      {:gaslimit, "GASLIMIT"},
      {:chainid, "CHAINID"},
      {:selfbalance, "SELFBALANCE"},
      {:basefee, "BASEFEE"},
      {:blobhash, "BLOBHASH"},
      {:blobbasefee, "BLOBBASEFEE"},
      {:sload, "SLOAD"},
      {:sstore, "SSTORE"},
      {:log, "LOG"},
      {:create, "CREATE"},
      {:call, "CALL"},
      {:callcode, "CALLCODE"},
      {:delegatecall, "DELEGATECALL"},
      {:create2, "CREATE2"},
      {:selfdestruct, "SELFDESTRUCT"}
    ]

    test "covers every named atom arm" do
      for {op, expected} <- @show_opcode_atoms do
        assert Assembly.show_opcode(op) == expected,
               "show_opcode(#{inspect(op)}) returned the wrong string"
      end
    end

    test "PUSH tuple includes width and hex payload" do
      assert Assembly.show_opcode({:push, 1, <<0xAB>>}) == "PUSH1 0xab"
      assert Assembly.show_opcode({:push, 5, <<1, 2, 3, 4, 5>>}) == "PUSH5 0x0102030405"
    end

    test "DUP tuple" do
      for n <- 1..16 do
        assert Assembly.show_opcode({:dup, n}) == "DUP#{n}"
      end
    end

    test "SWAP tuple" do
      for n <- 1..16 do
        assert Assembly.show_opcode({:swap, n}) == "SWAP#{n}"
      end
    end

    test "INVALID tuple is opaque" do
      assert Assembly.show_opcode({:invalid, <<>>}) == "INVALID"
      assert Assembly.show_opcode({:invalid, <<1, 2, 3>>}) == "INVALID"
    end
  end

  describe "exception structs" do
    test "InvalidAssembly default message" do
      assert %InvalidAssembly{}.message == "invalid assembly"

      assert_raise InvalidAssembly, "invalid assembly", fn ->
        raise InvalidAssembly
      end
    end

    test "InvalidCode default message" do
      assert %InvalidCode{}.message == "invalid code"

      assert_raise InvalidCode, "invalid code", fn ->
        raise InvalidCode
      end
    end

    test "InvalidOpcode default message" do
      assert %InvalidOpcode{}.message == "invalid opcode"

      assert_raise InvalidOpcode, "invalid opcode", fn ->
        raise InvalidOpcode
      end
    end
  end
end
