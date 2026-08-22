//! Local EVM execution for Elixir, backed by [revm].
//!
//! This crate is the native half of `Onchain.EVM`. It forks live chain state
//! from a JSON-RPC endpoint via alloy's `AlloyDB`, executes calls or
//! transactions against that fork in-process, and encodes the result back as
//! Erlang terms. Nothing is broadcast; the fork is discarded when the NIF call
//! returns.
//!
//! # Exposed NIFs
//!
//! | NIF | Purpose |
//! |-----|---------|
//! | `nif_simulate_call` | Read-only `eth_call`-shaped execution -> raw output hex |
//! | `nif_simulate_transaction` | Full transaction -> success flag, gas used, output, logs |
//! | `nif_simulate_batch` | Several calls against one shared fork, sequentially |
//!
//! All three are dirty-IO NIFs: forking issues blocking RPC reads for every
//! account and storage slot the execution touches.
//!
//! # Parameters and errors
//!
//! Parameters arrive as an Erlang map of string keys (see `get_string_param`
//! and friends). Input validation is the Elixir layer's job — `Onchain.EVM.Params`
//! rejects malformed options with tagged atoms before the boundary is crossed,
//! so failures reaching this crate are execution or transport failures, not
//! caller typos.
//!
//! Errors are encoded from `EvmError` into `{:error, {tag, message}}` with
//! tags `:evm_revert`, `:evm_error`, `:fork_error` and `:timeout`. Transport
//! failures are classified by walking the error source chain down to the
//! underlying `reqwest::Error` (see `classify_transport_error`), so a connect
//! refusal is retryable `:fork_error` and a deadline is `:timeout`.
//!
//! # Known limitations
//!
//! The EVM revision (`SpecId`) is not derived from the forked block, so a fork
//! pinned to a historical block still executes under the configured modern
//! revision. See the note at the `Context::mainnet()` call sites.
//!
//! [revm]: https://docs.rs/revm

use rustler::{Encoder, Env, NifResult, Term};
use std::collections::HashMap;
use std::time::Duration;

use alloy_eips::BlockId;
use alloy_primitives::{Address, Bytes, U256};
use alloy_provider::Provider;
use revm::{
    bytecode::Bytecode,
    context::{BlockEnv, TxEnv},
    context_interface::result::{ExecutionResult, Output},
    primitives::TxKind,
    Context, Database, DatabaseRef, ExecuteCommitEvm, ExecuteEvm, MainBuilder, MainContext,
};
use revm_database::{AlloyDB, CacheDB, WrapDatabaseAsync};

// Hard-coded TCP connect ceiling. Per-request total timeout (connect through
// response body completion, per `reqwest::ClientBuilder::timeout`) is
// caller-controlled via the `timeout_ms` NIF param (defaults below).
const DEFAULT_TIMEOUT_MS: u64 = 30_000;
const DEFAULT_CONNECT_TIMEOUT_MS: u64 = 5_000;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        evm_revert,
        evm_error,
        fork_error,
        timeout,

        // Result map keys
        success,
        gas_used,
        output,
        logs,
        address,
        topics,
        data,
    }
}

// --- NIF entry points ---

#[rustler::nif(schedule = "DirtyIo")]
fn nif_simulate_call<'a>(env: Env<'a>, params: HashMap<String, Term<'a>>) -> NifResult<Term<'a>> {
    match do_simulate_call(&params) {
        Ok(hex_output) => Ok((atoms::ok(), hex_output).encode(env)),
        Err(err) => Ok(encode_error(env, err)),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn nif_simulate_transaction<'a>(
    env: Env<'a>,
    params: HashMap<String, Term<'a>>,
) -> NifResult<Term<'a>> {
    match do_simulate_transaction(&params) {
        Ok(result) => Ok((atoms::ok(), result).encode(env)),
        Err(err) => Ok(encode_error(env, err)),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn nif_simulate_batch<'a>(env: Env<'a>, params: HashMap<String, Term<'a>>) -> NifResult<Term<'a>> {
    match do_simulate_batch(&params) {
        Ok(results) => Ok((atoms::ok(), results).encode(env)),
        Err(err) => Ok(encode_error(env, err)),
    }
}

rustler::init!("Elixir.Onchain.EVM");

// --- Error types ---

#[derive(Debug)]
enum EvmError {
    Revert(String),
    ExecutionError(String),
    ForkError(String),
    Timeout(String),
}

fn encode_error<'a>(env: Env<'a>, err: EvmError) -> Term<'a> {
    match err {
        EvmError::Revert(msg) => (atoms::error(), (atoms::evm_revert(), msg)).encode(env),
        EvmError::ExecutionError(msg) => (atoms::error(), (atoms::evm_error(), msg)).encode(env),
        EvmError::ForkError(msg) => (atoms::error(), (atoms::fork_error(), msg)).encode(env),
        EvmError::Timeout(msg) => (atoms::error(), (atoms::timeout(), msg)).encode(env),
    }
}

// Maps a transport / RPC error from `evm.transact()` to the right EvmError
// variant (Task 49). alloy/revm reformat the underlying `reqwest::Error` in their
// Display impls, so a string match on the top-level message is brittle. Instead we
// walk the `std::error::Error` source chain and recover the original
// `reqwest::Error` — alloy preserves it as a downcastable `#[source]` boxed error
// (`TransportErrorKind::Custom`), reached through revm's `EVMError::Database` and
// alloy's `#[error(transparent)]` `RpcError::Transport`. `is_timeout()` /
// `is_connect()` then classify precisely:
//   - timeout (per-request or connect ceiling) -> `:timeout`
//   - connect failure (refused / DNS / unreachable) -> `:fork_error` (retryable infra)
// Display-string heuristics remain only as a fallback if no `reqwest::Error` is
// found in the chain (e.g. a future alloy version that stops preserving it).
fn classify_transport_error<E: std::error::Error + 'static>(err: E) -> EvmError {
    let msg = error_chain_string(&err);

    let mut source: Option<&(dyn std::error::Error + 'static)> = Some(&err);
    while let Some(e) = source {
        if let Some(re) = e.downcast_ref::<reqwest::Error>() {
            // Order matters: a connect-phase timeout reports both, and we want
            // `:timeout` for it. A pure connection refusal is `is_connect()` only.
            if re.is_timeout() {
                return EvmError::Timeout(msg);
            }
            if re.is_connect() {
                return EvmError::ForkError(msg);
            }
        }
        source = e.source();
    }

    let lower = msg.to_lowercase();
    if lower.contains("operation timed out")
        || lower.contains("deadline")
        || lower.contains("timed out")
    {
        EvmError::Timeout(msg)
    } else if lower.contains("error sending request")
        || lower.contains("connect")
        || lower.contains("dns error")
    {
        EvmError::ForkError(msg)
    } else {
        EvmError::ExecutionError(msg)
    }
}

// Renders an error plus its full source chain into one string. alloy/revm Display
// impls drop the underlying detail (a timeout surfaces only as "database error:
// error sending request for url ..."), so we append each distinct source link to
// keep markers like "operation timed out" in the message returned to Elixir.
fn error_chain_string<E: std::error::Error>(err: &E) -> String {
    let mut out = err.to_string();
    let mut source = err.source();
    while let Some(s) = source {
        let link = s.to_string();
        if !out.contains(&link) {
            out.push_str(": ");
            out.push_str(&link);
        }
        source = s.source();
    }
    out
}

// --- Result types for Erlang encoding ---

#[derive(Debug)]
struct TxResult {
    success: bool,
    gas_used: u64,
    output: String,
    logs: Vec<LogEntry>,
}

#[derive(Debug)]
struct LogEntry {
    address: String,
    topics: Vec<String>,
    data: String,
}

impl Encoder for TxResult {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let log_terms: Vec<Term<'a>> = self.logs.iter().map(|l| l.encode(env)).collect();
        // map_put on a fresh map with valid encoded terms cannot fail
        let mut map = rustler::Term::map_new(env);
        map = map
            .map_put(atoms::success().encode(env), self.success.encode(env))
            .expect("map_put with valid terms");
        map = map
            .map_put(atoms::gas_used().encode(env), self.gas_used.encode(env))
            .expect("map_put with valid terms");
        map = map
            .map_put(atoms::output().encode(env), self.output.encode(env))
            .expect("map_put with valid terms");
        map = map
            .map_put(atoms::logs().encode(env), log_terms.encode(env))
            .expect("map_put with valid terms");
        map
    }
}

impl Encoder for LogEntry {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        // map_put on a fresh map with valid encoded terms cannot fail
        let mut map = rustler::Term::map_new(env);
        map = map
            .map_put(atoms::address().encode(env), self.address.encode(env))
            .expect("map_put with valid terms");
        map = map
            .map_put(atoms::topics().encode(env), self.topics.encode(env))
            .expect("map_put with valid terms");
        map = map
            .map_put(atoms::data().encode(env), self.data.encode(env))
            .expect("map_put with valid terms");
        map
    }
}

// --- Parameter extraction helpers ---

fn get_string_param<'a>(params: &HashMap<String, Term<'a>>, key: &str) -> Result<String, EvmError> {
    params
        .get(key)
        .ok_or_else(|| EvmError::ExecutionError(format!("missing param: {}", key)))
        .and_then(|t| {
            t.decode::<String>()
                .map_err(|_| EvmError::ExecutionError(format!("invalid param type: {}", key)))
        })
}

fn get_optional_string_param<'a>(
    params: &HashMap<String, Term<'a>>,
    key: &str,
) -> Result<Option<String>, EvmError> {
    match params.get(key) {
        None => Ok(None),
        Some(t) => t
            .decode::<String>()
            .map(Some)
            .map_err(|_| EvmError::ExecutionError(format!("invalid param type: {}", key))),
    }
}

fn get_optional_u64_param<'a>(
    params: &HashMap<String, Term<'a>>,
    key: &str,
) -> Result<Option<u64>, EvmError> {
    match params.get(key) {
        None => Ok(None),
        Some(t) => t
            .decode::<u64>()
            .map(Some)
            .map_err(|_| EvmError::ExecutionError(format!("invalid param type: {}", key))),
    }
}

// --- Hex conversion helpers ---

fn decode_hex_to_bytes(hex_str: &str) -> Result<Vec<u8>, EvmError> {
    let stripped = hex_str.strip_prefix("0x").unwrap_or(hex_str);
    hex::decode(stripped).map_err(|e| EvmError::ExecutionError(format!("invalid hex: {}", e)))
}

fn decode_hex_to_address(hex_str: &str) -> Result<Address, EvmError> {
    let bytes = decode_hex_to_bytes(hex_str)?;
    if bytes.len() != 20 {
        return Err(EvmError::ExecutionError(format!(
            "address must be 20 bytes, got {}",
            bytes.len()
        )));
    }
    Ok(Address::from_slice(&bytes))
}

fn decode_hex_to_u256(hex_str: &str) -> Result<U256, EvmError> {
    let stripped = hex_str.strip_prefix("0x").unwrap_or(hex_str);
    U256::from_str_radix(stripped, 16)
        .map_err(|e| EvmError::ExecutionError(format!("invalid U256 hex: {}", e)))
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

// --- Fork DB type alias ---

type HttpProvider = alloy_provider::DynProvider<alloy_provider::network::Ethereum>;
type ForkDB = CacheDB<WrapDatabaseAsync<AlloyDB<alloy_provider::network::Ethereum, HttpProvider>>>;

// --- EVM execution core ---

// Resolves block_number (u64) and block_tag (string) params into a BlockId.
// block_number takes precedence if both are present; defaults to latest.
fn resolve_block_id<'a>(params: &HashMap<String, Term<'a>>) -> Result<BlockId, EvmError> {
    let block_number = get_optional_u64_param(params, "block_number")?;
    let block_tag = get_optional_string_param(params, "block_tag")?;

    match (block_number, block_tag) {
        (Some(n), _) => Ok(BlockId::number(n)),
        (None, Some(tag)) => match tag.as_str() {
            "latest" => Ok(BlockId::latest()),
            "finalized" => Ok(BlockId::finalized()),
            "safe" => Ok(BlockId::safe()),
            "pending" => Ok(BlockId::pending()),
            "earliest" => Ok(BlockId::earliest()),
            other => Err(EvmError::ExecutionError(format!(
                "unknown block tag: {}",
                other
            ))),
        },
        (None, None) => Ok(BlockId::latest()),
    }
}

fn build_fork(
    rpc_url: &str,
    block_id: BlockId,
    timeout_ms: u64,
    connect_timeout_ms: u64,
) -> Result<(ForkDB, BlockEnv), EvmError> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| EvmError::ForkError(format!("tokio runtime: {}", e)))?;

    let url: reqwest::Url = rpc_url
        .parse()
        .map_err(|e| EvmError::ForkError(format!("invalid RPC URL: {}", e)))?;

    let reqwest_client = reqwest::Client::builder()
        .timeout(Duration::from_millis(timeout_ms))
        .connect_timeout(Duration::from_millis(connect_timeout_ms))
        .build()
        .map_err(|e| EvmError::ForkError(format!("http client: {}", e)))?;

    let http = alloy_transport_http::Http::with_client(reqwest_client, url);
    let is_local = http.guess_local();
    let rpc_client = alloy_rpc_client::RpcClient::new(http, is_local);
    let provider = alloy_provider::ProviderBuilder::new()
        .connect_client(rpc_client)
        .erased();

    let block = rt
        .block_on(async { provider.get_block(block_id).await })
        .map_err(classify_transport_error)?
        .ok_or_else(|| EvmError::ForkError(format!("block not found: {block_id:?}")))?;
    let header = &block.header.inner;
    let block_env = BlockEnv {
        number: U256::from(header.number),
        beneficiary: header.beneficiary,
        timestamp: U256::from(header.timestamp),
        gas_limit: header.gas_limit,
        basefee: header.base_fee_per_gas.unwrap_or_default(),
        prevrandao: Some(header.mix_hash),
        ..Default::default()
    };

    let fork_block_id = if block_id.is_pending() {
        block_id
    } else {
        BlockId::number(header.number)
    };
    let alloy_db = AlloyDB::new(provider, fork_block_id);
    let wrapped_db = WrapDatabaseAsync::with_runtime(alloy_db, rt);
    let cache_db = CacheDB::new(wrapped_db);

    Ok((cache_db, block_env))
}

fn apply_state_overrides<'a>(
    db: &mut ForkDB,
    params: &HashMap<String, Term<'a>>,
) -> Result<(), EvmError> {
    let overrides_term = match params.get("state_overrides") {
        Some(t) => t,
        None => return Ok(()),
    };

    let overrides: HashMap<String, HashMap<String, String>> = overrides_term
        .decode()
        .map_err(|_| EvmError::ExecutionError("invalid state_overrides format".into()))?;

    for (addr_hex, fields) in &overrides {
        let addr = decode_hex_to_address(addr_hex)?;

        let mut info = db
            .basic(addr)
            .map_err(classify_transport_error)?
            .unwrap_or_default();

        if let Some(balance_hex) = fields.get("balance") {
            info.balance = decode_hex_to_u256(balance_hex)?;
        }
        if let Some(nonce_str) = fields.get("nonce") {
            info.nonce = nonce_str
                .parse::<u64>()
                .map_err(|e| EvmError::ExecutionError(format!("invalid nonce: {}", e)))?;
        }
        if let Some(code_hex) = fields.get("code") {
            let code_bytes = decode_hex_to_bytes(code_hex)?;
            info.code = Some(Bytecode::new_raw(Bytes::from(code_bytes)));
        }

        db.insert_account_info(addr, info);

        if let Some(storage_json) = fields.get("storage") {
            let storage: HashMap<String, String> = serde_json::from_str(storage_json)
                .map_err(|e| EvmError::ExecutionError(format!("invalid storage JSON: {}", e)))?;
            for (slot_hex, val_hex) in &storage {
                let slot = decode_hex_to_u256(slot_hex)?;
                let val = decode_hex_to_u256(val_hex)?;
                db.insert_account_storage(addr, slot, val)
                    .map_err(|e| EvmError::ExecutionError(format!("storage insert: {}", e)))?;
            }
        }
    }

    Ok(())
}

// --- Common param extraction ---

#[derive(Debug)]
struct CallParams {
    to: Address,
    data: Vec<u8>,
    from: Address,
    value: U256,
    gas_limit: Option<u64>,
}

fn extract_call_params<'a>(params: &HashMap<String, Term<'a>>) -> Result<CallParams, EvmError> {
    let to_hex = get_string_param(params, "to")?;
    let data_hex = get_string_param(params, "data")?;
    let from_hex = get_optional_string_param(params, "from")?;
    let value_hex = get_optional_string_param(params, "value")?;
    let gas_limit = get_optional_u64_param(params, "gas_limit")?;

    Ok(CallParams {
        to: decode_hex_to_address(&to_hex)?,
        data: decode_hex_to_bytes(&data_hex)?,
        from: match &from_hex {
            Some(h) => decode_hex_to_address(h)?,
            None => Address::ZERO,
        },
        value: match &value_hex {
            Some(h) => decode_hex_to_u256(h)?,
            None => U256::ZERO,
        },
        gas_limit,
    })
}

fn build_tx(cp: &CallParams, data: Bytes) -> Result<TxEnv, EvmError> {
    build_tx_with_nonce(cp, data, None)
}

fn build_tx_with_nonce(
    cp: &CallParams,
    data: Bytes,
    nonce: Option<u64>,
) -> Result<TxEnv, EvmError> {
    let mut tx = TxEnv::builder()
        .caller(cp.from)
        .kind(TxKind::Call(cp.to))
        .data(data)
        .value(cp.value);

    if let Some(gl) = cp.gas_limit {
        tx = tx.gas_limit(gl);
    }
    if let Some(nonce) = nonce {
        tx = tx.nonce(nonce);
    }

    tx.build()
        .map_err(|e| EvmError::ExecutionError(format!("invalid tx: {}", e)))
}

fn current_nonce(db: &ForkDB, address: Address) -> Result<u64, EvmError> {
    db.basic_ref(address)
        .map_err(classify_transport_error)
        .map(|account| account.map(|info| info.nonce).unwrap_or_default())
}

// --- ExecutionResult → TxResult ---

fn extract_tx_result(result: ExecutionResult) -> Result<TxResult, EvmError> {
    match result {
        ExecutionResult::Success {
            gas, logs, output, ..
        } => {
            let out_bytes = match output {
                Output::Call(b) => b,
                Output::Create(b, _) => b,
            };
            let log_entries = logs
                .iter()
                .map(|l| LogEntry {
                    address: bytes_to_hex(l.address.as_ref()),
                    topics: l
                        .topics()
                        .iter()
                        .map(|t| bytes_to_hex(t.as_ref()))
                        .collect(),
                    data: bytes_to_hex(l.data.data.as_ref()),
                })
                .collect();
            Ok(TxResult {
                success: true,
                gas_used: gas.tx_gas_used(),
                output: bytes_to_hex(&out_bytes),
                logs: log_entries,
            })
        }
        ExecutionResult::Revert { gas, output, .. } => Ok(TxResult {
            success: false,
            gas_used: gas.tx_gas_used(),
            output: bytes_to_hex(&output),
            logs: vec![],
        }),
        ExecutionResult::Halt { reason, .. } => {
            Err(EvmError::ExecutionError(format!("halt: {:?}", reason)))
        }
    }
}

// --- simulate_call ---

fn do_simulate_call<'a>(params: &HashMap<String, Term<'a>>) -> Result<String, EvmError> {
    let rpc_url = get_string_param(params, "rpc_url")?;
    let block_id = resolve_block_id(params)?;
    let timeout_ms = get_optional_u64_param(params, "timeout_ms")?.unwrap_or(DEFAULT_TIMEOUT_MS);
    let cp = extract_call_params(params)?;

    let (mut db, block_env) =
        build_fork(&rpc_url, block_id, timeout_ms, DEFAULT_CONNECT_TIMEOUT_MS)?;
    apply_state_overrides(&mut db, params)?;

    let tx = build_tx(&cp, Bytes::from(cp.data.clone()))?;
    // KNOWN LIMITATION (applies to every Context::mainnet() site below too):
    // revm 42 defaults to the latest hardfork spec, so a fork pinned to a
    // historical block executes under newer EVM rules than were active then. We do
    // not derive SpecId from the forked block because these NIFs fork an arbitrary
    // RPC URL (any L1/L2), and a mainnet block→hardfork table would assign the
    // wrong spec to non-mainnet chains — worse than the latest-spec default. A
    // correct fix needs a chain-aware fork schedule keyed on chain id; deferred.
    let mut evm = Context::mainnet()
        .with_block(block_env)
        .with_db(&mut db)
        .modify_cfg_chained(|cfg| {
            cfg.disable_nonce_check = true;
            cfg.disable_base_fee = true;
        })
        .build_mainnet();

    let result = evm.transact(tx).map_err(classify_transport_error)?;

    match result.result {
        ExecutionResult::Success { output, .. } => {
            let out_bytes = match output {
                Output::Call(b) => b,
                Output::Create(b, _) => b,
            };
            Ok(bytes_to_hex(&out_bytes))
        }
        ExecutionResult::Revert { output, .. } => Err(EvmError::Revert(bytes_to_hex(&output))),
        ExecutionResult::Halt { reason, .. } => {
            Err(EvmError::ExecutionError(format!("halt: {:?}", reason)))
        }
    }
}

// --- simulate_transaction ---

fn do_simulate_transaction<'a>(params: &HashMap<String, Term<'a>>) -> Result<TxResult, EvmError> {
    let rpc_url = get_string_param(params, "rpc_url")?;
    let block_id = resolve_block_id(params)?;
    let timeout_ms = get_optional_u64_param(params, "timeout_ms")?.unwrap_or(DEFAULT_TIMEOUT_MS);
    let cp = extract_call_params(params)?;

    let (mut db, block_env) =
        build_fork(&rpc_url, block_id, timeout_ms, DEFAULT_CONNECT_TIMEOUT_MS)?;
    apply_state_overrides(&mut db, params)?;

    let tx = build_tx(&cp, Bytes::from(cp.data.clone()))?;
    let mut evm = Context::mainnet()
        .with_block(block_env)
        .with_db(&mut db)
        .modify_cfg_chained(|cfg| {
            cfg.disable_nonce_check = true;
            cfg.disable_base_fee = true;
        })
        .build_mainnet();

    let result = evm.transact(tx).map_err(classify_transport_error)?;

    extract_tx_result(result.result)
}

// --- simulate_batch ---

fn do_simulate_batch<'a>(params: &HashMap<String, Term<'a>>) -> Result<Vec<TxResult>, EvmError> {
    let rpc_url = get_string_param(params, "rpc_url")?;
    let block_id = resolve_block_id(params)?;
    let timeout_ms = get_optional_u64_param(params, "timeout_ms")?.unwrap_or(DEFAULT_TIMEOUT_MS);
    let from_hex = get_optional_string_param(params, "from")?;
    let gas_limit = get_optional_u64_param(params, "gas_limit")?;

    let from = match &from_hex {
        Some(h) => decode_hex_to_address(h)?,
        None => Address::ZERO,
    };

    let calls_term = params
        .get("calls")
        .ok_or_else(|| EvmError::ExecutionError("missing param: calls".into()))?;

    let calls: Vec<(String, String)> = calls_term.decode().map_err(|_| {
        EvmError::ExecutionError("calls must be list of {address, data} tuples".into())
    })?;

    // An empty batch is a no-op — return before opening the fork DB so we issue
    // no RPC. The `current_nonce` read below otherwise hits the node (and can
    // error/time out) just to compute an unused base nonce for zero calls.
    if calls.is_empty() {
        return Ok(Vec::new());
    }

    let (mut db, block_env) =
        build_fork(&rpc_url, block_id, timeout_ms, DEFAULT_CONNECT_TIMEOUT_MS)?;
    apply_state_overrides(&mut db, params)?;
    let base_nonce = current_nonce(&db, from)?;

    let mut results = Vec::with_capacity(calls.len());

    for (index, (to_hex, data_hex)) in calls.iter().enumerate() {
        let to = decode_hex_to_address(to_hex)?;
        let data = decode_hex_to_bytes(data_hex)?;
        let nonce_offset = u64::try_from(index)
            .map_err(|e| EvmError::ExecutionError(format!("batch index overflow: {}", e)))?;
        let nonce = base_nonce
            .checked_add(nonce_offset)
            .ok_or_else(|| EvmError::ExecutionError("batch nonce overflow".into()))?;

        let cp = CallParams {
            to,
            data: data.clone(),
            from,
            value: U256::ZERO,
            gas_limit,
        };

        let tx = build_tx_with_nonce(&cp, Bytes::from(data), Some(nonce))?;
        let mut evm = Context::mainnet()
            .with_block(block_env.clone())
            .with_db(&mut db)
            .modify_cfg_chained(|cfg| cfg.disable_base_fee = true)
            .build_mainnet();

        let result = evm.transact_commit(tx).map_err(classify_transport_error)?;

        // transact_commit returns ExecutionResult directly (not ResultAndState)
        results.push(extract_tx_result(result)?);
    }

    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_FROM_BYTE: u8 = 0x11;
    const TEST_TO_BYTE: u8 = 0x22;
    const TEST_GAS_LIMIT: u64 = 42_000;
    const TEST_NONCE: u64 = 3;
    const TEST_VALUE: u64 = 7;

    #[test]
    fn build_tx_preserves_call_params() {
        let from = Address::repeat_byte(TEST_FROM_BYTE);
        let to = Address::repeat_byte(TEST_TO_BYTE);
        let data = Bytes::from(vec![0xde, 0xad, 0xbe, 0xef]);
        let params = CallParams {
            to,
            data: data.to_vec(),
            from,
            value: U256::from(TEST_VALUE),
            gas_limit: Some(TEST_GAS_LIMIT),
        };

        let tx = build_tx(&params, data.clone()).expect("valid tx");

        assert_eq!(tx.caller, from);
        assert_eq!(tx.kind, TxKind::Call(to));
        assert_eq!(tx.data, data);
        assert_eq!(tx.value, U256::from(TEST_VALUE));
        assert_eq!(tx.gas_limit, TEST_GAS_LIMIT);
        assert_eq!(tx.nonce, 0);
    }

    #[test]
    fn build_tx_preserves_explicit_nonce() {
        let params = CallParams {
            to: Address::repeat_byte(TEST_TO_BYTE),
            data: Vec::new(),
            from: Address::repeat_byte(TEST_FROM_BYTE),
            value: U256::ZERO,
            gas_limit: None,
        };

        let tx = build_tx_with_nonce(&params, Bytes::new(), Some(TEST_NONCE)).expect("valid tx");

        assert_eq!(tx.nonce, TEST_NONCE);
    }
}
