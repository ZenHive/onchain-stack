defmodule Onchain.AA.UserOperation do
  @moduledoc """
  ERC-4337 UserOperation struct (unpacked representation).

  Holds the fields a consumer reasons about, independent of EntryPoint version.
  Numeric fields (`nonce`, gas limits, fees) are stored as non-negative
  integers; byte-array fields (`sender`, `call_data`, …) as `0x`-prefixed hex
  strings.

  ## Version-specific fields

  The struct carries the union of v0.6 and v0.7 fields. Which ones are used
  depends on the EntryPoint version passed to `Onchain.AA` functions:

  - **v0.6** uses `init_code` and `paymaster_and_data` directly.
  - **v0.7** derives `initCode = factory ++ factory_data` and
    `paymasterAndData = paymaster ++ paymaster_verification_gas_limit (16 bytes)
    ++ paymaster_post_op_gas_limit (16 bytes) ++ paymaster_data` from the
    unpacked `factory*`/`paymaster*` fields when they are set. If `factory` is
    `nil`, `init_code` is used verbatim; if `paymaster` is `nil`,
    `paymaster_and_data` is used verbatim. This lets a v0.7 op be expressed
    either way.

  Build instances with `Onchain.AA.new/1`, which applies defaults and validates.
  """

  @enforce_keys [:sender]
  defstruct sender: nil,
            nonce: 0,
            init_code: "0x",
            call_data: "0x",
            call_gas_limit: 0,
            verification_gas_limit: 0,
            pre_verification_gas: 0,
            max_fee_per_gas: 0,
            max_priority_fee_per_gas: 0,
            paymaster_and_data: "0x",
            signature: "0x",
            factory: nil,
            factory_data: nil,
            paymaster: nil,
            paymaster_verification_gas_limit: nil,
            paymaster_post_op_gas_limit: nil,
            paymaster_data: nil

  @type t :: %__MODULE__{
          sender: String.t(),
          nonce: non_neg_integer(),
          init_code: String.t(),
          call_data: String.t(),
          call_gas_limit: non_neg_integer(),
          verification_gas_limit: non_neg_integer(),
          pre_verification_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          paymaster_and_data: String.t(),
          signature: String.t(),
          factory: String.t() | nil,
          factory_data: String.t() | nil,
          paymaster: String.t() | nil,
          paymaster_verification_gas_limit: non_neg_integer() | nil,
          paymaster_post_op_gas_limit: non_neg_integer() | nil,
          paymaster_data: String.t() | nil
        }
end
