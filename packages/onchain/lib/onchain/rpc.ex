defmodule Onchain.RPC do
  @moduledoc """
  Compatibility aliases for `Cartouche.RPC`. This module has no implementation
  of its own.

  Every function here is a `defdelegate`. There is no second implementation.
  The names that remain are `eth_call/2,3`, `eth_call!/2,3`,
  `eth_estimate_gas/1,2`, `eth_estimate_gas!/1,2`, `eth_send_raw_transaction/1,2`,
  `eth_send_raw_transaction!/1,2`, `get_balance/1,2`, `get_balance!/1,2`,
  `block_number/0,1`, `block_number!/0,1`, `get_block_by_number/1,2`,
  `get_block_by_number!/1,2`, `get_block_access_list/1,2`,
  `get_block_access_list!/1,2`, `chain_id/0,1`, `chain_id!/0,1`,
  `get_transaction_receipt/1,2`, `get_transaction_receipt!/1,2`,
  `get_transaction_count/1,2`, `get_transaction_count!/1,2`, `eth_get_code/1,2`,
  `eth_get_code!/1,2`, `call/2,3`, `call!/2,3`, `fee_history/1,2`,
  `fee_history!/1,2`, `blob_base_fee/0,1`, `blob_base_fee!/0,1`, and `batch/1,2`.
  """

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
