defmodule Cartouche.Contract.Sleuth do
  @moduledoc false
  use Cartouche.Hex

  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2

  @doc "Returns the contract name."
  @spec contract_name() :: String.t()
  def contract_name do
    "Sleuth"
  end

  @doc "Returns the contract ABI entries."
  @spec abi() :: [map()]
  def abi do
    [
      %{
        "inputs" => [
          %{"internalType" => "bytes", "name" => "q", "type" => "bytes"},
          %{"internalType" => "bytes", "name" => "c", "type" => "bytes"}
        ],
        "name" => "query",
        "outputs" => [%{"internalType" => "bytes", "name" => "", "type" => "bytes"}],
        "stateMutability" => "nonpayable",
        "type" => "function"
      },
      %{
        "inputs" => [%{"internalType" => "bytes", "name" => "q", "type" => "bytes"}],
        "name" => "query",
        "outputs" => [%{"internalType" => "bytes", "name" => "", "type" => "bytes"}],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ]
  end

  @doc "Returns the ABI function selector for `query_selector/query(bytes,bytes)`."
  @spec query_selector() :: ABI.FunctionSelector.t()
  def query_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "query",
      function_type: :function,
      returns: [%{name: "", type: :bytes}],
      state_mutability: :nonpayable,
      types: [%{name: "q", type: :bytes}, %{name: "c", type: :bytes}]
    }
  end

  @doc "Encodes ABI calldata for `encode_query/query(bytes,bytes)`."
  @spec encode_query(binary(), binary()) :: binary()
  def encode_query(q, c) do
    ABI.encode(query_selector(), [q, c])
  end

  @doc "Prepares a transaction for `prepare_query/query(bytes,bytes)`."
  @spec prepare_query(<<_::160>>, binary(), binary(), Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query(contract, q, c, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query(q, c), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query/query(bytes,bytes)`."
  @spec build_trx_query(<<_::160>>, binary(), binary()) :: Call.t()
  def build_trx_query(contract, q, c) do
    %Call{destination: contract, data: encode_query(q, c)}
  end

  @doc "Calls a contract function for `call_query/query(bytes,bytes)`."
  @spec call_query(<<_::160>>, binary(), binary(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def call_query(contract, q, c, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query(contract, q, c), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query/query(bytes,bytes)`."
  @spec estimate_gas_query(<<_::160>>, binary(), binary(), Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query(contract, q, c, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query(contract, q, c), opts)
  end

  @doc "Executes a contract transaction for `execute_query/query(bytes,bytes)`."
  @spec execute_query(<<_::160>>, binary(), binary(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def execute_query(contract, q, c, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query(q, c), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_call/query(bytes,bytes)`."
  @spec decode_query_call(binary()) :: [binary() | binary()]
  def decode_query_call(<<52, 104, 110, 175>> <> calldata) do
    _signature = hex!("0x34686eaf")
    ABI.decode(query_selector(), calldata)
  end

  @doc "Returns the ABI function selector for `query_ed815d83_selector/query(bytes)`."
  @spec query_ed815d83_selector() :: ABI.FunctionSelector.t()
  def query_ed815d83_selector do
    %{
      __struct__: ABI.FunctionSelector,
      function: "query",
      function_type: :function,
      returns: [%{name: "", type: :bytes}],
      state_mutability: :nonpayable,
      types: [%{name: "q", type: :bytes}]
    }
  end

  @doc "Encodes ABI calldata for `encode_query_ed815d83/query(bytes)`."
  @spec encode_query_ed815d83(binary()) :: binary()
  def encode_query_ed815d83(q) do
    ABI.encode(query_ed815d83_selector(), [q])
  end

  @doc "Prepares a transaction for `prepare_query_ed815d83/query(bytes)`."
  @spec prepare_query_ed815d83(<<_::160>>, binary(), Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_query_ed815d83(contract, q, opts \\ []) do
    Cartouche.RPC.prepare_trx(contract, encode_query_ed815d83(q), opts)
  end

  @doc "Builds an eth_call transaction for `build_trx_query_ed815d83/query(bytes)`."
  @spec build_trx_query_ed815d83(<<_::160>>, binary()) :: Call.t()
  def build_trx_query_ed815d83(contract, q) do
    %Call{destination: contract, data: encode_query_ed815d83(q)}
  end

  @doc "Calls a contract function for `call_query_ed815d83/query(bytes)`."
  @spec call_query_ed815d83(<<_::160>>, binary(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def call_query_ed815d83(contract, q, opts \\ []) do
    Cartouche.RPC.call_trx(build_trx_query_ed815d83(contract, q), opts)
  end

  @doc "Estimates gas for a contract function for `estimate_gas_query_ed815d83/query(bytes)`."
  @spec estimate_gas_query_ed815d83(<<_::160>>, binary(), Keyword.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas_query_ed815d83(contract, q, opts \\ []) do
    Cartouche.RPC.estimate_gas(build_trx_query_ed815d83(contract, q), opts)
  end

  @doc "Executes a contract transaction for `execute_query_ed815d83/query(bytes)`."
  @spec execute_query_ed815d83(<<_::160>>, binary(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def execute_query_ed815d83(contract, q, opts \\ []) do
    Cartouche.RPC.execute_trx(contract, encode_query_ed815d83(q), opts)
  end

  @doc "Decodes ABI calldata for `decode_query_ed815d83_call/query(bytes)`."
  @spec decode_query_ed815d83_call(binary()) :: [binary()]
  def decode_query_ed815d83_call(<<237, 129, 93, 131>> <> calldata) do
    _signature = hex!("0xed815d83")
    ABI.decode(query_ed815d83_selector(), calldata)
  end

  @doc "Decodes ABI calldata and dispatches to the matching generated call decoder."
  @spec decode_call(binary()) :: {:ok, String.t() | nil, term()} | :not_found
  def decode_call(<<52, 104, 110, 175>> <> _ = calldata) do
    _signature = hex!("0x34686eaf")
    {:ok, "query", decode_query_call(calldata)}
  end

  def decode_call(<<237, 129, 93, 131>> <> _ = calldata) do
    _signature = hex!("0xed815d83")
    {:ok, "query", decode_query_ed815d83_call(calldata)}
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
      "0x608060405234801561001057600080fd5b50610372806100206000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c806334686eaf1461003b578063ed815d8314610064575b600080fd5b61004e6100493660046101d0565b610077565b60405161005b91906102ab565b60405180910390f35b61004e6100723660046102fa565b6100c2565b60606100ba84848080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250869250610134915050565b949350505050565b606061012d83838080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250506040805160048152602481019091526020810180516001600160e01b0316632c46b20560e01b17905291506101349050565b9392505050565b606082516020840181816000f0915050825160208401600060c083836000875af1505050503d600060c03e60206080523d60a05260403d01806080f35b60008083601f84011261018357600080fd5b50813567ffffffffffffffff81111561019b57600080fd5b6020830191508360208285010111156101b357600080fd5b9250929050565b634e487b7160e01b600052604160045260246000fd5b6000806000604084860312156101e557600080fd5b833567ffffffffffffffff808211156101fd57600080fd5b61020987838801610171565b9095509350602086013591508082111561022257600080fd5b818601915086601f83011261023657600080fd5b813581811115610248576102486101ba565b604051601f8201601f19908116603f01168101908382118183101715610270576102706101ba565b8160405282815289602084870101111561028957600080fd5b8260208601602083013760006020848301015280955050505050509250925092565b60006020808352835180602085015260005b818110156102d9578581018301518582016040015282016102bd565b506000604082860101526040601f19601f8301168501019250505092915050565b6000806020838503121561030d57600080fd5b823567ffffffffffffffff81111561032457600080fd5b61033085828601610171565b9096909550935050505056fea26469706673582212200f9418a6a5451abfd0a2638ad5d50fa97ed7004227bad65194b24b2f47e2241364736f6c63430008170033"
    )
  end

  @doc "Returns the contract deployed bytecode."
  @spec deployed_bytecode() :: binary()
  def deployed_bytecode do
    hex!(
      "0x608060405234801561001057600080fd5b50600436106100365760003560e01c806334686eaf1461003b578063ed815d8314610064575b600080fd5b61004e6100493660046101d0565b610077565b60405161005b91906102ab565b60405180910390f35b61004e6100723660046102fa565b6100c2565b60606100ba84848080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250869250610134915050565b949350505050565b606061012d83838080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250506040805160048152602481019091526020810180516001600160e01b0316632c46b20560e01b17905291506101349050565b9392505050565b606082516020840181816000f0915050825160208401600060c083836000875af1505050503d600060c03e60206080523d60a05260403d01806080f35b60008083601f84011261018357600080fd5b50813567ffffffffffffffff81111561019b57600080fd5b6020830191508360208285010111156101b357600080fd5b9250929050565b634e487b7160e01b600052604160045260246000fd5b6000806000604084860312156101e557600080fd5b833567ffffffffffffffff808211156101fd57600080fd5b61020987838801610171565b9095509350602086013591508082111561022257600080fd5b818601915086601f83011261023657600080fd5b813581811115610248576102486101ba565b604051601f8201601f19908116603f01168101908382118183101715610270576102706101ba565b8160405282815289602084870101111561028957600080fd5b8260208601602083013760006020848301015280955050505050509250925092565b60006020808352835180602085015260005b818110156102d9578581018301518582016040015282016102bd565b506000604082860101526040601f19601f8301168501019250505092915050565b6000806020838503121561030d57600080fd5b823567ffffffffffffffff81111561032457600080fd5b61033085828601610171565b9096909550935050505056fea26469706673582212200f9418a6a5451abfd0a2638ad5d50fa97ed7004227bad65194b24b2f47e2241364736f6c63430008170033"
    )
  end
end
