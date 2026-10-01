defmodule Onchain.RPC do
  @moduledoc "Compatibility aliases for `Cartouche.RPC`; scheduled for removal in the namespace migration."

  @spec eth_call(term(), term(), keyword()) :: term()
  defdelegate eth_call(address, data, opts \\ []), to: Cartouche.RPC
  @spec eth_call!(term(), term(), keyword()) :: term()
  defdelegate eth_call!(address, data, opts \\ []), to: Cartouche.RPC
  @spec eth_estimate_gas(term(), keyword()) :: term()
  defdelegate eth_estimate_gas(tx_params, opts \\ []), to: Cartouche.RPC
  @spec eth_estimate_gas!(term(), keyword()) :: term()
  defdelegate eth_estimate_gas!(tx_params, opts \\ []), to: Cartouche.RPC
  @spec eth_send_raw_transaction(term(), keyword()) :: term()
  defdelegate eth_send_raw_transaction(data, opts \\ []), to: Cartouche.RPC
  @spec eth_send_raw_transaction!(term(), keyword()) :: term()
  defdelegate eth_send_raw_transaction!(data, opts \\ []), to: Cartouche.RPC
  @spec get_balance(term(), keyword()) :: term()
  defdelegate get_balance(address, opts \\ []), to: Cartouche.RPC
  @spec get_balance!(term(), keyword()) :: term()
  defdelegate get_balance!(address, opts \\ []), to: Cartouche.RPC
  @spec block_number(keyword()) :: term()
  defdelegate block_number(opts \\ []), to: Cartouche.RPC
  @spec block_number!(keyword()) :: term()
  defdelegate block_number!(opts \\ []), to: Cartouche.RPC
  @spec get_block_by_number(term(), keyword()) :: term()
  defdelegate get_block_by_number(block, opts \\ []), to: Cartouche.RPC
  @spec get_block_by_number!(term(), keyword()) :: term()
  defdelegate get_block_by_number!(block, opts \\ []), to: Cartouche.RPC
  @spec get_block_access_list(term(), keyword()) :: term()
  defdelegate get_block_access_list(block, opts \\ []), to: Cartouche.RPC
  @spec get_block_access_list!(term(), keyword()) :: term()
  defdelegate get_block_access_list!(block, opts \\ []), to: Cartouche.RPC
  @spec chain_id(keyword()) :: term()
  defdelegate chain_id(opts \\ []), to: Cartouche.RPC
  @spec chain_id!(keyword()) :: term()
  defdelegate chain_id!(opts \\ []), to: Cartouche.RPC
  @spec get_transaction_receipt(term(), keyword()) :: term()
  defdelegate get_transaction_receipt(hash, opts \\ []), to: Cartouche.RPC
  @spec get_transaction_receipt!(term(), keyword()) :: term()
  defdelegate get_transaction_receipt!(hash, opts \\ []), to: Cartouche.RPC
  @spec get_transaction_count(term(), keyword()) :: term()
  defdelegate get_transaction_count(address, opts \\ []), to: Cartouche.RPC
  @spec get_transaction_count!(term(), keyword()) :: term()
  defdelegate get_transaction_count!(address, opts \\ []), to: Cartouche.RPC
  @spec eth_get_code(term(), keyword()) :: term()
  defdelegate eth_get_code(address, opts \\ []), to: Cartouche.RPC
  @spec eth_get_code!(term(), keyword()) :: term()
  defdelegate eth_get_code!(address, opts \\ []), to: Cartouche.RPC
  @spec call(term(), term(), keyword()) :: term()
  defdelegate call(method, params, opts \\ []), to: Cartouche.RPC
  @spec call!(term(), term(), keyword()) :: term()
  defdelegate call!(method, params, opts \\ []), to: Cartouche.RPC
  @spec fee_history(term(), keyword()) :: term()
  defdelegate fee_history(count, opts \\ []), to: Cartouche.RPC
  @spec fee_history!(term(), keyword()) :: term()
  defdelegate fee_history!(count, opts \\ []), to: Cartouche.RPC
  @spec blob_base_fee(keyword()) :: term()
  defdelegate blob_base_fee(opts \\ []), to: Cartouche.RPC
  @spec blob_base_fee!(keyword()) :: term()
  defdelegate blob_base_fee!(opts \\ []), to: Cartouche.RPC
  @spec batch(list(), keyword()) :: {:ok, list()} | {:error, term()}
  defdelegate batch(requests, opts \\ []), to: Cartouche.RPC
end
