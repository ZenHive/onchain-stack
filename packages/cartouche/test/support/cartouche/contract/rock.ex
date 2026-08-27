defmodule Cartouche.Contract.Rock do
  @moduledoc false
  use Cartouche.Hex

  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  @doc "Returns the contract name."
  @spec contract_name() :: String.t()
  def contract_name do
    "Rock"
  end

  @doc "Returns the contract ABI entries."
  @spec abi() :: [map()]
  def abi do
    [
      %{
        "inputs" => [%{"internalType" => "uint256", "name" => "c", "type" => "uint256"}],
        "name" => "Stumble",
        "type" => "error"
      },
      %{
        "inputs" => [%{"internalType" => "uint256", "name" => "beats", "type" => "uint256"}],
        "name" => "jam",
        "outputs" => [
          %{
            "components" => [
              %{"internalType" => "uint256", "name" => "beats", "type" => "uint256"},
              %{"internalType" => "string", "name" => "song", "type" => "string"}
            ],
            "internalType" => "struct Rock.Fun",
            "name" => "f",
            "type" => "tuple"
          }
        ],
        "stateMutability" => "pure",
        "type" => "function"
      },
      %{
        "inputs" => [],
        "name" => "stumble",
        "outputs" => [%{"internalType" => "uint256", "name" => "", "type" => "uint256"}],
        "stateMutability" => "pure",
        "type" => "function"
      }
    ]
  end

  @doc "Returns the ABI function selector for `stumble_selector/Stumble(uint256)`."
  @spec stumble_selector() :: ABI.FunctionSelector.t()
  def stumble_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "Stumble",
      function_type: :error,
      returns: nil,
      state_mutability: nil,
      types: [%{name: "c", type: {:uint, 256}}]
    }
  end

  @doc "Encodes ABI calldata for `encode_stumble/Stumble(uint256)`."
  @spec encode_stumble(non_neg_integer()) :: binary()
  def encode_stumble(c) do
    ABI.encode(stumble_selector(), [c])
  end

  @doc "Decodes ABI revert data for `decode_stumble_error/Stumble(uint256)`."
  @spec decode_stumble_error(binary()) :: [non_neg_integer()]
  def decode_stumble_error(<<211, 49, 186, 152>> <> error) do
    _signature = hex!("0xd331ba98")
    ABI.decode(stumble_selector(), error)
  end

  @doc "Returns the ABI function selector for `jam_selector/jam(uint256)`."
  @spec jam_selector() :: ABI.FunctionSelector.t()
  def jam_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "jam",
      function_type: :function,
      returns: [
        %{
          name: "f",
          type: {:tuple, [%{name: "beats", type: {:uint, 256}}, %{name: "song", type: :string}]}
        }
      ],
      state_mutability: :pure,
      types: [%{name: "beats", type: {:uint, 256}}]
    }
  end

  @doc "Encodes ABI calldata for `encode_jam/jam(uint256)`."
  @spec encode_jam(non_neg_integer()) :: binary()
  def encode_jam(beats) do
    ABI.encode(jam_selector(), [beats])
  end

  @doc "Prepares a transaction for `prepare_jam/jam(uint256)`."
  @spec prepare_jam(<<_::160>>, non_neg_integer(), Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_jam(beats), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_jam/jam(uint256)`."
  @spec build_trx_jam(<<_::160>>, non_neg_integer()) :: Call.t()
  def build_trx_jam(contract, beats) do
    %Call{destination: contract, data: encode_jam(beats)}
  end

  @doc "Calls a contract function for `call_jam/jam(uint256)`."
  @spec call_jam(<<_::160>>, non_neg_integer(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_jam(contract, beats), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_jam/jam(uint256)`."
  @spec estimate_gas_jam(<<_::160>>, non_neg_integer(), Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_jam(contract, beats), opts)
  end

  @doc "Executes a contract transaction for `execute_jam/jam(uint256)`."
  @spec execute_jam(<<_::160>>, non_neg_integer(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def execute_jam(contract, beats, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_jam(beats), opts)
  end

  @doc "Decodes ABI calldata for `decode_jam_call/jam(uint256)`."
  @spec decode_jam_call(binary()) :: [non_neg_integer()]
  def decode_jam_call(<<191, 104, 23, 16>> <> calldata) do
    _signature = hex!("0xbf681710")
    ABI.decode(jam_selector(), calldata)
  end

  @doc "Executes deployed bytecode in the local VM for `exec_vm_jam/jam(uint256)`."
  @spec exec_vm_jam(non_neg_integer(), Keyword.t()) ::
          {:ok, %{beats: non_neg_integer(), song: String.t()} | {non_neg_integer(), String.t()}}
          | {:revert, String.t(), term()}
  def exec_vm_jam(beats, exec_opts \\ []) do
    case Cartouche.VM.exec_call(deployed_bytecode(), encode_jam(beats), exec_opts) do
      {:ok, return_data} ->
        preintern_return_atoms!(jam_selector().returns)

        case ABI.decode(%ABI.FunctionSelector{types: jam_selector().returns}, return_data, decode_structs: true) do
          m when is_map(m) -> {:ok, m}
          [decoded] -> {:ok, decoded}
          els -> {:ok, els}
        end

      {:revert, revert_data} ->
        case apply(__MODULE__, :decode_error, [revert_data]) do
          {:ok, error, data} -> {:revert, error, data}
          :not_found -> {:revert, "Unknown", revert_data}
        end
    end
  end

  @doc "Executes deployed bytecode in the local VM and returns raw returndata for `exec_vm_jam_raw/jam(uint256)`."
  @spec exec_vm_jam_raw(non_neg_integer(), Keyword.t()) :: {:ok, binary()} | {:revert, binary()}
  def exec_vm_jam_raw(beats, exec_opts \\ []) do
    Cartouche.VM.exec_call(deployed_bytecode(), encode_jam(beats), exec_opts)
  end

  @doc "Returns the ABI function selector for `stumble_144e59d6_selector/stumble()`."
  @spec stumble_144e59d6_selector() :: ABI.FunctionSelector.t()
  def stumble_144e59d6_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "stumble",
      function_type: :function,
      returns: [%{name: "", type: {:uint, 256}}],
      state_mutability: :pure,
      types: []
    }
  end

  @doc "Encodes ABI calldata for `encode_stumble_144e59d6/stumble()`."
  @spec encode_stumble_144e59d6() :: binary()
  def encode_stumble_144e59d6 do
    ABI.encode(stumble_144e59d6_selector(), [])
  end

  @doc "Prepares a transaction for `prepare_stumble_144e59d6/stumble()`."
  @spec prepare_stumble_144e59d6(<<_::160>>, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_stumble_144e59d6(), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_stumble_144e59d6/stumble()`."
  @spec build_trx_stumble_144e59d6(<<_::160>>) :: Call.t()
  def build_trx_stumble_144e59d6(contract) do
    %Call{destination: contract, data: encode_stumble_144e59d6()}
  end

  @doc "Calls a contract function for `call_stumble_144e59d6/stumble()`."
  @spec call_stumble_144e59d6(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_stumble_144e59d6(contract), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_stumble_144e59d6/stumble()`."
  @spec estimate_gas_stumble_144e59d6(<<_::160>>, Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_stumble_144e59d6(contract), opts)
  end

  @doc "Executes a contract transaction for `execute_stumble_144e59d6/stumble()`."
  @spec execute_stumble_144e59d6(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def execute_stumble_144e59d6(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_stumble_144e59d6(), opts)
  end

  @doc "Decodes ABI calldata for `decode_stumble_144e59d6_call/stumble()`."
  @spec decode_stumble_144e59d6_call(binary()) :: []
  def decode_stumble_144e59d6_call(<<20, 78, 89, 214>> <> calldata) do
    _signature = hex!("0x144e59d6")
    ABI.decode(stumble_144e59d6_selector(), calldata)
  end

  @doc "Executes deployed bytecode in the local VM for `exec_vm_stumble_144e59d6/stumble()`."
  @spec exec_vm_stumble_144e59d6(Keyword.t()) ::
          {:ok, non_neg_integer()} | {:revert, String.t(), term()}
  def exec_vm_stumble_144e59d6(exec_opts \\ []) do
    case Cartouche.VM.exec_call(deployed_bytecode(), encode_stumble_144e59d6(), exec_opts) do
      {:ok, return_data} ->
        preintern_return_atoms!(stumble_144e59d6_selector().returns)

        case ABI.decode(
               %ABI.FunctionSelector{types: stumble_144e59d6_selector().returns},
               return_data,
               decode_structs: true
             ) do
          m when is_map(m) -> {:ok, m}
          [decoded] -> {:ok, decoded}
          els -> {:ok, els}
        end

      {:revert, revert_data} ->
        case apply(__MODULE__, :decode_error, [revert_data]) do
          {:ok, error, data} -> {:revert, error, data}
          :not_found -> {:revert, "Unknown", revert_data}
        end
    end
  end

  @doc "Executes deployed bytecode in the local VM and returns raw returndata for `exec_vm_stumble_144e59d6_raw/stumble()`."
  @spec exec_vm_stumble_144e59d6_raw(Keyword.t()) :: {:ok, binary()} | {:revert, binary()}
  def exec_vm_stumble_144e59d6_raw(exec_opts \\ []) do
    Cartouche.VM.exec_call(deployed_bytecode(), encode_stumble_144e59d6(), exec_opts)
  end

  @doc "Decodes ABI calldata and dispatches to the matching generated call decoder."
  @spec decode_call(binary()) :: {:ok, String.t() | nil, term()} | :not_found
  def decode_call(<<191, 104, 23, 16>> <> _ = calldata) do
    _signature = hex!("0xbf681710")
    {:ok, "jam", decode_jam_call(calldata)}
  end

  def decode_call(<<20, 78, 89, 214>> <> _ = calldata) do
    _signature = hex!("0x144e59d6")
    {:ok, "stumble", decode_stumble_144e59d6_call(calldata)}
  end

  def decode_call(_) do
    :not_found
  end

  @doc "Decodes ABI event topics and data with the matching generated event decoder."
  @spec decode_event([binary()], binary()) ::
          {:ok, String.t() | nil, map()} | {:error, term()} | :not_found
  def decode_event(_, _) do
    :not_found
  end

  @doc "Decodes ABI revert data and dispatches to the matching generated error decoder."
  @spec decode_error(binary()) :: {:ok, String.t() | nil, term()} | :not_found
  def decode_error(<<211, 49, 186, 152>> <> _ = error) do
    _signature = hex!("0xd331ba98")
    {:ok, "Stumble", decode_stumble_error(error)}
  end

  def decode_error(_) do
    :not_found
  end

  @doc "Returns the contract init bytecode."
  @spec bytecode() :: binary()
  def bytecode do
    hex!(
      "608060405234801561000f575f80fd5b506103458061001d5f395ff3fe608060405234801561000f575f80fd5b5060043610610034575f3560e01c8063144e59d614610038578063bf68171014610056575b5f80fd5b610040610086565b60405161004d919061014f565b60405180910390f35b610070600480360381019061006b9190610196565b6100c5565b60405161007d9190610294565b60405180910390f35b5f60376040517fd331ba980000000000000000000000000000000000000000000000000000000081526004016100bc91906102f6565b60405180910390fd5b6100cd61011e565b60405180604001604052808381526020016040518060400160405280600f81526020017f42616e64206f6e207468652052756e00000000000000000000000000000000008152508152509050919050565b60405180604001604052805f8152602001606081525090565b5f819050919050565b61014981610137565b82525050565b5f6020820190506101625f830184610140565b92915050565b5f80fd5b61017581610137565b811461017f575f80fd5b50565b5f813590506101908161016c565b92915050565b5f602082840312156101ab576101aa610168565b5b5f6101b884828501610182565b91505092915050565b6101ca81610137565b82525050565b5f81519050919050565b5f82825260208201905092915050565b5f5b838110156102075780820151818401526020810190506101ec565b5f8484015250505050565b5f601f19601f8301169050919050565b5f61022c826101d0565b61023681856101da565b93506102468185602086016101ea565b61024f81610212565b840191505092915050565b5f604083015f83015161026f5f8601826101c1565b50602083015184820360208601526102878282610222565b9150508091505092915050565b5f6020820190508181035f8301526102ac818461025a565b905092915050565b5f819050919050565b5f819050919050565b5f6102e06102db6102d6846102b4565b6102bd565b610137565b9050919050565b6102f0816102c6565b82525050565b5f6020820190506103095f8301846102e7565b9291505056fea26469706673582212202c77c48aba2ef6154e6648ed7c485abc0d9fe67fb484d56a7e986a6ee7c7734764736f6c63430008170033"
    )
  end

  @doc "Returns the contract deployed bytecode."
  @spec deployed_bytecode() :: binary()
  def deployed_bytecode do
    hex!(
      "608060405234801561000f575f80fd5b5060043610610034575f3560e01c8063144e59d614610038578063bf68171014610056575b5f80fd5b610040610086565b60405161004d919061014f565b60405180910390f35b610070600480360381019061006b9190610196565b6100c5565b60405161007d9190610294565b60405180910390f35b5f60376040517fd331ba980000000000000000000000000000000000000000000000000000000081526004016100bc91906102f6565b60405180910390fd5b6100cd61011e565b60405180604001604052808381526020016040518060400160405280600f81526020017f42616e64206f6e207468652052756e00000000000000000000000000000000008152508152509050919050565b60405180604001604052805f8152602001606081525090565b5f819050919050565b61014981610137565b82525050565b5f6020820190506101625f830184610140565b92915050565b5f80fd5b61017581610137565b811461017f575f80fd5b50565b5f813590506101908161016c565b92915050565b5f602082840312156101ab576101aa610168565b5b5f6101b884828501610182565b91505092915050565b6101ca81610137565b82525050565b5f81519050919050565b5f82825260208201905092915050565b5f5b838110156102075780820151818401526020810190506101ec565b5f8484015250505050565b5f601f19601f8301169050919050565b5f61022c826101d0565b61023681856101da565b93506102468185602086016101ea565b61024f81610212565b840191505092915050565b5f604083015f83015161026f5f8601826101c1565b50602083015184820360208601526102878282610222565b9150508091505092915050565b5f6020820190508181035f8301526102ac818461025a565b905092915050565b5f819050919050565b5f819050919050565b5f6102e06102db6102d6846102b4565b6102bd565b610137565b9050919050565b6102f0816102c6565b82525050565b5f6020820190506103095f8301846102e7565b9291505056fea26469706673582212202c77c48aba2ef6154e6648ed7c485abc0d9fe67fb484d56a7e986a6ee7c7734764736f6c63430008170033"
    )
  end

  (
    @decode_field_atoms [:beats, :f, :song]
    @spec preintern_return_atoms!(term()) :: [atom()]
    defp preintern_return_atoms!(_returns) do
      @decode_field_atoms
    end
  )
end
