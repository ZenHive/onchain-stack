use rustler::{Encoder, Env, NifResult, Term};
use std::collections::HashMap;
use std::time::Duration;

use alloy_eips::BlockId;
use alloy_primitives::{Address, Bytes, U256};
use revm::{
    db::{AlloyDB, CacheDB},
    primitives::{Bytecode, ExecutionResult, Output, TxKind},
    Evm,
};

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

type HttpTransport = alloy_transport_http::Http<reqwest::Client>;
type HttpProvider = alloy_provider::RootProvider<HttpTransport, alloy_provider::network::Ethereum>;
type ForkDB = CacheDB<AlloyDB<HttpTransport, alloy_provider::network::Ethereum, HttpProvider>>;

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
            other => Err(EvmError::ExecutionError(format!("unknown block tag: {}", other))),
        },
        (None, None) => Ok(BlockId::latest()),
    }
}

fn build_fork_db(
    rpc_url: &str,
    block_id: BlockId,
    timeout_ms: u64,
    connect_timeout_ms: u64,
) -> Result<ForkDB, EvmError> {
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
    let provider = alloy_provider::ProviderBuilder::new().on_client(rpc_client);

    let alloy_db = AlloyDB::with_runtime(provider, block_id, rt);
    let cache_db = CacheDB::new(alloy_db);

    Ok(cache_db)
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
            .accounts
            .get(&addr)
            .map(|a| a.info.clone())
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
            let storage: HashMap<String, String> =
                serde_json::from_str(storage_json).map_err(|e| {
                    EvmError::ExecutionError(format!("invalid storage JSON: {}", e))
                })?;
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

fn configure_tx(tx: &mut revm::primitives::TxEnv, cp: &CallParams, data: Bytes) {
    tx.caller = cp.from;
    tx.transact_to = TxKind::Call(cp.to);
    tx.data = data;
    tx.value = cp.value;
    if let Some(gl) = cp.gas_limit {
        tx.gas_limit = gl;
    }
}

// --- ExecutionResult → TxResult ---

fn extract_tx_result(result: ExecutionResult) -> Result<TxResult, EvmError> {
    match result {
        ExecutionResult::Success {
            gas_used,
            logs,
            output,
            ..
        } => {
            let out_bytes = match output {
                Output::Call(b) => b,
                Output::Create(b, _) => b,
            };
            let log_entries = logs
                .iter()
                .map(|l| LogEntry {
                    address: bytes_to_hex(l.address.as_ref()),
                    topics: l.topics().iter().map(|t| bytes_to_hex(t.as_ref())).collect(),
                    data: bytes_to_hex(l.data.data.as_ref()),
                })
                .collect();
            Ok(TxResult {
                success: true,
                gas_used,
                output: bytes_to_hex(&out_bytes),
                logs: log_entries,
            })
        }
        ExecutionResult::Revert { gas_used, output } => Ok(TxResult {
            success: false,
            gas_used,
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

    let mut db = build_fork_db(&rpc_url, block_id, timeout_ms, DEFAULT_CONNECT_TIMEOUT_MS)?;
    apply_state_overrides(&mut db, params)?;

    let data_bytes = Bytes::from(cp.data.clone());
    let mut evm = Evm::builder()
        .with_db(&mut db)
        .modify_tx_env(|tx| configure_tx(tx, &cp, data_bytes))
        .build();

    let result = evm.transact().map_err(classify_transport_error)?;

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

fn do_simulate_transaction<'a>(
    params: &HashMap<String, Term<'a>>,
) -> Result<TxResult, EvmError> {
    let rpc_url = get_string_param(params, "rpc_url")?;
    let block_id = resolve_block_id(params)?;
    let timeout_ms = get_optional_u64_param(params, "timeout_ms")?.unwrap_or(DEFAULT_TIMEOUT_MS);
    let cp = extract_call_params(params)?;

    let mut db = build_fork_db(&rpc_url, block_id, timeout_ms, DEFAULT_CONNECT_TIMEOUT_MS)?;
    apply_state_overrides(&mut db, params)?;

    let data_bytes = Bytes::from(cp.data.clone());
    let mut evm = Evm::builder()
        .with_db(&mut db)
        .modify_tx_env(|tx| configure_tx(tx, &cp, data_bytes))
        .build();

    let result = evm.transact().map_err(classify_transport_error)?;

    extract_tx_result(result.result)
}

// --- simulate_batch ---

fn do_simulate_batch<'a>(
    params: &HashMap<String, Term<'a>>,
) -> Result<Vec<TxResult>, EvmError> {
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

    let calls: Vec<(String, String)> = calls_term
        .decode()
        .map_err(|_| {
            EvmError::ExecutionError("calls must be list of {address, data} tuples".into())
        })?;

    let mut db = build_fork_db(&rpc_url, block_id, timeout_ms, DEFAULT_CONNECT_TIMEOUT_MS)?;
    apply_state_overrides(&mut db, params)?;

    let mut results = Vec::with_capacity(calls.len());

    for (to_hex, data_hex) in &calls {
        let to = decode_hex_to_address(to_hex)?;
        let data = decode_hex_to_bytes(data_hex)?;

        let cp = CallParams {
            to,
            data: data.clone(),
            from,
            value: U256::ZERO,
            gas_limit,
        };

        let data_bytes = Bytes::from(data);
        let mut evm = Evm::builder()
            .with_db(&mut db)
            .modify_tx_env(|tx| configure_tx(tx, &cp, data_bytes))
            .build();

        let result = evm.transact_commit().map_err(classify_transport_error)?;

        // transact_commit returns ExecutionResult directly (not ResultAndState)
        results.push(extract_tx_result(result)?);
    }

    Ok(results)
}
