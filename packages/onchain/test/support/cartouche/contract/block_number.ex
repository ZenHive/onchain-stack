defmodule Cartouche.Contract.BlockNumber do
  @moduledoc false
  use Cartouche.Hex

  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  @doc "Returns the contract name."
  @spec contract_name() :: String.t()
  def contract_name do
    "BlockNumber"
  end

  @doc "Returns the contract ABI entries."
  @spec abi() :: [map()]
  def abi do
    [
      %{
        "inputs" => [],
        "name" => "query",
        "outputs" => [
          %{"internalType" => "uint256", "name" => "blockNumber", "type" => "uint256"}
        ],
        "stateMutability" => "view",
        "type" => "function"
      },
      %{
        "inputs" => [],
        "name" => "queryCool",
        "outputs" => [
          %{
            "components" => [
              %{"internalType" => "string", "name" => "x", "type" => "string"},
              %{"internalType" => "uint256[]", "name" => "ys", "type" => "uint256[]"},
              %{
                "components" => [
                  %{"internalType" => "string", "name" => "cat", "type" => "string"}
                ],
                "internalType" => "struct BlockNumber.Fun",
                "name" => "fun",
                "type" => "tuple"
              }
            ],
            "internalType" => "struct BlockNumber.Cool",
            "name" => "cool",
            "type" => "tuple"
          }
        ],
        "stateMutability" => "pure",
        "type" => "function"
      },
      %{
        "inputs" => [],
        "name" => "queryFour",
        "outputs" => [
          %{"internalType" => "bytes", "name" => "", "type" => "bytes"},
          %{"internalType" => "address", "name" => "", "type" => "address"}
        ],
        "stateMutability" => "pure",
        "type" => "function"
      },
      %{
        "inputs" => [],
        "name" => "queryThree",
        "outputs" => [%{"internalType" => "uint256", "name" => "", "type" => "uint256"}],
        "stateMutability" => "view",
        "type" => "function"
      },
      %{
        "inputs" => [],
        "name" => "queryTwo",
        "outputs" => [
          %{"internalType" => "uint256", "name" => "x", "type" => "uint256"},
          %{"internalType" => "uint256", "name" => "y", "type" => "uint256"}
        ],
        "stateMutability" => "view",
        "type" => "function"
      }
    ]
  end

  @doc "Returns the ABI function selector for `query_selector/query()`."
  @spec query_selector() :: ABI.FunctionSelector.t()
  def query_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "query",
      function_type: :function,
      returns: [%{name: "blockNumber", type: {:uint, 256}}],
      state_mutability: :view,
      types: []
    }
  end

  @doc "Encodes ABI calldata for `encode_query/query()`."
  @spec encode_query() :: binary()
  def encode_query do
    ABI.encode(query_selector(), [])
  end

  @doc "Prepares a transaction for `prepare_query/query()`."
  @spec prepare_query(<<_::160>>, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query(), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query/query()`."
  @spec build_trx_query(<<_::160>>) :: Call.t()
  def build_trx_query(contract) do
    %Call{destination: contract, data: encode_query()}
  end

  @doc "Calls a contract function for `call_query/query()`."
  @spec call_query(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_query(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query(contract), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query/query()`."
  @spec estimate_gas_query(<<_::160>>, Keyword.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query(contract), opts)
  end

  @doc "Executes a contract transaction for `execute_query/query()`."
  @spec execute_query(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def execute_query(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query(), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_call/query()`."
  @spec decode_query_call(binary()) :: []
  def decode_query_call(<<44, 70, 178, 5>> <> calldata) do
    _signature = hex!("0x2c46b205")
    ABI.decode(query_selector(), calldata)
  end

  @doc "Returns the ABI function selector for `query_cool_selector/queryCool()`."
  @spec query_cool_selector() :: ABI.FunctionSelector.t()
  def query_cool_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryCool",
      function_type: :function,
      returns: [
        %{
          name: "cool",
          type:
            {:tuple,
             [
               %{name: "x", type: :string},
               %{name: "ys", type: {:array, {:uint, 256}}},
               %{name: "fun", type: {:tuple, [%{name: "cat", type: :string}]}}
             ]}
        }
      ],
      state_mutability: :pure,
      types: []
    }
  end

  @doc "Encodes ABI calldata for `encode_query_cool/queryCool()`."
  @spec encode_query_cool() :: binary()
  def encode_query_cool do
    ABI.encode(query_cool_selector(), [])
  end

  @doc "Prepares a transaction for `prepare_query_cool/queryCool()`."
  @spec prepare_query_cool(<<_::160>>, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query_cool(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query_cool(), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query_cool/queryCool()`."
  @spec build_trx_query_cool(<<_::160>>) :: Call.t()
  def build_trx_query_cool(contract) do
    %Call{destination: contract, data: encode_query_cool()}
  end

  @doc "Calls a contract function for `call_query_cool/queryCool()`."
  @spec call_query_cool(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_query_cool(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query_cool(contract), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query_cool/queryCool()`."
  @spec estimate_gas_query_cool(<<_::160>>, Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query_cool(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query_cool(contract), opts)
  end

  @doc "Executes a contract transaction for `execute_query_cool/queryCool()`."
  @spec execute_query_cool(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def execute_query_cool(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query_cool(), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_cool_call/queryCool()`."
  @spec decode_query_cool_call(binary()) :: []
  def decode_query_cool_call(<<107, 188, 156, 20>> <> calldata) do
    _signature = hex!("0x6bbc9c14")
    ABI.decode(query_cool_selector(), calldata)
  end

  @doc "Executes deployed bytecode in the local VM for `exec_vm_query_cool/queryCool()`."
  @spec exec_vm_query_cool(Keyword.t()) ::
          {:ok,
           %{x: String.t(), ys: [non_neg_integer()], fun: %{cat: String.t()} | {String.t()}}
           | {String.t(), [non_neg_integer()], %{cat: String.t()} | {String.t()}}}
          | {:revert, String.t(), term()}
  def exec_vm_query_cool(exec_opts \\ []) do
    case Cartouche.VM.exec_call(deployed_bytecode(), encode_query_cool(), exec_opts) do
      {:ok, return_data} ->
        preintern_return_atoms!(query_cool_selector().returns)

        case ABI.decode(%ABI.FunctionSelector{types: query_cool_selector().returns}, return_data, decode_structs: true) do
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

  @doc "Executes deployed bytecode in the local VM and returns raw returndata for `exec_vm_query_cool_raw/queryCool()`."
  @spec exec_vm_query_cool_raw(Keyword.t()) :: {:ok, binary()} | {:revert, binary()}
  def exec_vm_query_cool_raw(exec_opts \\ []) do
    Cartouche.VM.exec_call(deployed_bytecode(), encode_query_cool(), exec_opts)
  end

  @doc "Returns the ABI function selector for `query_four_selector/queryFour()`."
  @spec query_four_selector() :: ABI.FunctionSelector.t()
  def query_four_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryFour",
      function_type: :function,
      returns: [%{name: "", type: :bytes}, %{name: "", type: :address}],
      state_mutability: :pure,
      types: []
    }
  end

  @doc "Encodes ABI calldata for `encode_query_four/queryFour()`."
  @spec encode_query_four() :: binary()
  def encode_query_four do
    ABI.encode(query_four_selector(), [])
  end

  @doc "Prepares a transaction for `prepare_query_four/queryFour()`."
  @spec prepare_query_four(<<_::160>>, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query_four(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query_four(), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query_four/queryFour()`."
  @spec build_trx_query_four(<<_::160>>) :: Call.t()
  def build_trx_query_four(contract) do
    %Call{destination: contract, data: encode_query_four()}
  end

  @doc "Calls a contract function for `call_query_four/queryFour()`."
  @spec call_query_four(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_query_four(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query_four(contract), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query_four/queryFour()`."
  @spec estimate_gas_query_four(<<_::160>>, Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query_four(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query_four(contract), opts)
  end

  @doc "Executes a contract transaction for `execute_query_four/queryFour()`."
  @spec execute_query_four(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def execute_query_four(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query_four(), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_four_call/queryFour()`."
  @spec decode_query_four_call(binary()) :: []
  def decode_query_four_call(<<160, 180, 62, 214>> <> calldata) do
    _signature = hex!("0xa0b43ed6")
    ABI.decode(query_four_selector(), calldata)
  end

  @doc "Executes deployed bytecode in the local VM for `exec_vm_query_four/queryFour()`."
  @spec exec_vm_query_four(Keyword.t()) ::
          {:ok, [binary() | <<_::160>>]} | {:revert, String.t(), term()}
  def exec_vm_query_four(exec_opts \\ []) do
    case Cartouche.VM.exec_call(deployed_bytecode(), encode_query_four(), exec_opts) do
      {:ok, return_data} ->
        preintern_return_atoms!(query_four_selector().returns)

        case ABI.decode(%ABI.FunctionSelector{types: query_four_selector().returns}, return_data, decode_structs: true) do
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

  @doc "Executes deployed bytecode in the local VM and returns raw returndata for `exec_vm_query_four_raw/queryFour()`."
  @spec exec_vm_query_four_raw(Keyword.t()) :: {:ok, binary()} | {:revert, binary()}
  def exec_vm_query_four_raw(exec_opts \\ []) do
    Cartouche.VM.exec_call(deployed_bytecode(), encode_query_four(), exec_opts)
  end

  @doc "Returns the ABI function selector for `query_three_selector/queryThree()`."
  @spec query_three_selector() :: ABI.FunctionSelector.t()
  def query_three_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryThree",
      function_type: :function,
      returns: [%{name: "", type: {:uint, 256}}],
      state_mutability: :view,
      types: []
    }
  end

  @doc "Encodes ABI calldata for `encode_query_three/queryThree()`."
  @spec encode_query_three() :: binary()
  def encode_query_three do
    ABI.encode(query_three_selector(), [])
  end

  @doc "Prepares a transaction for `prepare_query_three/queryThree()`."
  @spec prepare_query_three(<<_::160>>, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query_three(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query_three(), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query_three/queryThree()`."
  @spec build_trx_query_three(<<_::160>>) :: Call.t()
  def build_trx_query_three(contract) do
    %Call{destination: contract, data: encode_query_three()}
  end

  @doc "Calls a contract function for `call_query_three/queryThree()`."
  @spec call_query_three(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_query_three(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query_three(contract), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query_three/queryThree()`."
  @spec estimate_gas_query_three(<<_::160>>, Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query_three(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query_three(contract), opts)
  end

  @doc "Executes a contract transaction for `execute_query_three/queryThree()`."
  @spec execute_query_three(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def execute_query_three(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query_three(), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_three_call/queryThree()`."
  @spec decode_query_three_call(binary()) :: []
  def decode_query_three_call(<<219, 127, 37, 93>> <> calldata) do
    _signature = hex!("0xdb7f255d")
    ABI.decode(query_three_selector(), calldata)
  end

  @doc "Returns the ABI function selector for `query_two_selector/queryTwo()`."
  @spec query_two_selector() :: ABI.FunctionSelector.t()
  def query_two_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryTwo",
      function_type: :function,
      returns: [%{name: "x", type: {:uint, 256}}, %{name: "y", type: {:uint, 256}}],
      state_mutability: :view,
      types: []
    }
  end

  @doc "Encodes ABI calldata for `encode_query_two/queryTwo()`."
  @spec encode_query_two() :: binary()
  def encode_query_two do
    ABI.encode(query_two_selector(), [])
  end

  @doc "Prepares a transaction for `prepare_query_two/queryTwo()`."
  @spec prepare_query_two(<<_::160>>, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query_two(contract, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query_two(), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query_two/queryTwo()`."
  @spec build_trx_query_two(<<_::160>>) :: Call.t()
  def build_trx_query_two(contract) do
    %Call{destination: contract, data: encode_query_two()}
  end

  @doc "Calls a contract function for `call_query_two/queryTwo()`."
  @spec call_query_two(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_query_two(contract, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query_two(contract), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query_two/queryTwo()`."
  @spec estimate_gas_query_two(<<_::160>>, Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query_two(contract, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query_two(contract), opts)
  end

  @doc "Executes a contract transaction for `execute_query_two/queryTwo()`."
  @spec execute_query_two(<<_::160>>, Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def execute_query_two(contract, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query_two(), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_two_call/queryTwo()`."
  @spec decode_query_two_call(binary()) :: []
  def decode_query_two_call(<<53, 0, 122, 122>> <> calldata) do
    _signature = hex!("0x35007a7a")
    ABI.decode(query_two_selector(), calldata)
  end

  @doc "Decodes ABI calldata and dispatches to the matching generated call decoder."
  @spec decode_call(binary()) :: {:ok, String.t() | nil, term()} | :not_found
  def decode_call(<<44, 70, 178, 5>> <> _ = calldata) do
    _signature = hex!("0x2c46b205")
    {:ok, "query", decode_query_call(calldata)}
  end

  def decode_call(<<107, 188, 156, 20>> <> _ = calldata) do
    _signature = hex!("0x6bbc9c14")
    {:ok, "queryCool", decode_query_cool_call(calldata)}
  end

  def decode_call(<<160, 180, 62, 214>> <> _ = calldata) do
    _signature = hex!("0xa0b43ed6")
    {:ok, "queryFour", decode_query_four_call(calldata)}
  end

  def decode_call(<<219, 127, 37, 93>> <> _ = calldata) do
    _signature = hex!("0xdb7f255d")
    {:ok, "queryThree", decode_query_three_call(calldata)}
  end

  def decode_call(<<53, 0, 122, 122>> <> _ = calldata) do
    _signature = hex!("0x35007a7a")
    {:ok, "queryTwo", decode_query_two_call(calldata)}
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
  def decode_error(_) do
    :not_found
  end

  @doc "Returns the contract init bytecode."
  @spec bytecode() :: binary()
  def bytecode do
    hex!(
      "0x608060405234801561001057600080fd5b50610321806100206000396000f3fe608060405234801561001057600080fd5b50600436106100575760003560e01c80632c46b2051461005c57806335007a7a1461006f5780636bbc9c1414610082578063a0b43ed614610097578063db7f255d1461005c575b600080fd5b6040514381526020015b60405180910390f35b6040805143808252602082015201610066565b61008a6100bf565b604051610066919061021c565b604080518082018252600381526201020360e81b6020820152905161006691906001906102ab565b6100c76101a2565b60408051600380825260808201909252600091602082016060803683370190505090506001816000815181106100ff576100ff6102d5565b602002602001018181525050600281600281518110610120576101206102d5565b602002602001018181525050600381600381518110610141576101416102d5565b6020908102919091018101919091526040805160a0810182526002606080830191825261686960f01b608084015290825281840194909452815193840182526004928401928352636d656f7760e01b84830152918352810191909152919050565b604051806060016040528060608152602001606081526020016101d16040518060200160405280606081525090565b905290565b6000815180845260005b818110156101fc576020818501810151868301820152016101e0565b506000602082860101526020601f19601f83011685010191505092915050565b60006020808352835160608285015261023860808501826101d6565b82860151601f1986830381016040880152815180845291850193506000929091908501905b8084101561027d578451825293850193600193909301929085019061025d565b5060408801518782038301606089015251858252935061029f858201856101d6565b98975050505050505050565b6040815260006102be60408301856101d6565b905060018060a01b03831660208301529392505050565b634e487b7160e01b600052603260045260246000fdfea2646970667358221220e8c5d69430acd7260e4e988c876237e9e690c8fb5cf361153ea4369423beea3764736f6c63430008180033"
    )
  end

  @doc "Returns the contract deployed bytecode."
  @spec deployed_bytecode() :: binary()
  def deployed_bytecode do
    hex!(
      "0x608060405234801561001057600080fd5b50600436106100575760003560e01c80632c46b2051461005c57806335007a7a1461006f5780636bbc9c1414610082578063a0b43ed614610097578063db7f255d1461005c575b600080fd5b6040514381526020015b60405180910390f35b6040805143808252602082015201610066565b61008a6100bf565b604051610066919061021c565b604080518082018252600381526201020360e81b6020820152905161006691906001906102ab565b6100c76101a2565b60408051600380825260808201909252600091602082016060803683370190505090506001816000815181106100ff576100ff6102d5565b602002602001018181525050600281600281518110610120576101206102d5565b602002602001018181525050600381600381518110610141576101416102d5565b6020908102919091018101919091526040805160a0810182526002606080830191825261686960f01b608084015290825281840194909452815193840182526004928401928352636d656f7760e01b84830152918352810191909152919050565b604051806060016040528060608152602001606081526020016101d16040518060200160405280606081525090565b905290565b6000815180845260005b818110156101fc576020818501810151868301820152016101e0565b506000602082860101526020601f19601f83011685010191505092915050565b60006020808352835160608285015261023860808501826101d6565b82860151601f1986830381016040880152815180845291850193506000929091908501905b8084101561027d578451825293850193600193909301929085019061025d565b5060408801518782038301606089015251858252935061029f858201856101d6565b98975050505050505050565b6040815260006102be60408301856101d6565b905060018060a01b03831660208301529392505050565b634e487b7160e01b600052603260045260246000fdfea2646970667358221220e8c5d69430acd7260e4e988c876237e9e690c8fb5cf361153ea4369423beea3764736f6c63430008180033"
    )
  end

  (
    @decode_field_atoms [:block_number, :cat, :cool, :fun, :x, :y, :ys]
    @spec preintern_return_atoms!(term()) :: [atom()]
    defp preintern_return_atoms!(_returns) do
      @decode_field_atoms
    end
  )
end
