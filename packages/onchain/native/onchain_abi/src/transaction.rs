//! Transaction/EIP-712 operations use alloy's codecs; JSON is the RPC-shaped adapter.
use crate::{atoms, binary, bytes, Result};
use alloy_consensus::{
    EthereumTxEnvelope, EthereumTypedTransaction, SignableTransaction, TxEip1559, TxEip2930,
    TxEip4844, TxEip7702, TxLegacy,
};
use alloy_dyn_abi::TypedData;
use alloy_eips::{
    eip2718::{Decodable2718, Encodable2718},
    eip7702::Authorization,
};
use alloy_primitives::{Signature, U256};
use alloy_rlp::Encodable;
use rustler::{Encoder, Env, Term};
use serde_json::Value;
use std::panic::{catch_unwind, AssertUnwindSafe};

type Transaction = EthereumTypedTransaction<TxEip4844>;
type Envelope = EthereumTxEnvelope<TxEip4844>;

fn json(term: Term<'_>) -> Result<Value> {
    let value: Value =
        serde_json::from_slice(bytes(term)?.as_slice()).map_err(|_| "invalid_json")?;
    let mut nodes = 100_000;
    preflight_json(&value, 0, &mut nodes)?;
    Ok(value)
}

fn preflight_json(value: &Value, depth: usize, nodes: &mut usize) -> Result<()> {
    if depth > 64 {
        return Err("depth_limit".into());
    }
    crate::spend(nodes)?;
    match value {
        Value::Array(items) => {
            for item in items {
                preflight_json(item, depth + 1, nodes)?;
            }
        }
        Value::Object(items) => {
            for item in items.values() {
                preflight_json(item, depth + 1, nodes)?;
            }
        }
        _ => (),
    }
    Ok(())
}

fn check_uint(value: &Value, field: &str, width: usize) -> Result<()> {
    let number: U256 = serde_json::from_value(value.clone())
        .map_err(|_| format!("{field} must be in 0..2^{width}-1"))?;
    if number.bit_len() > width {
        return Err(format!("{field} must be in 0..2^{width}-1"));
    }
    Ok(())
}

fn parse_transaction(value: &Value) -> Result<Transaction> {
    for (key, field, width) in [
        ("nonce", "nonce", 64),
        ("gas", "gas_limit", 64),
        ("chainId", "chain_id", 64),
        ("gasPrice", "gas_price", 128),
        ("maxFeePerGas", "max_fee_per_gas", 128),
        ("maxPriorityFeePerGas", "max_priority_fee_per_gas", 128),
        ("maxFeePerBlobGas", "max_fee_per_blob_gas", 128),
        ("value", "value", 256),
    ] {
        if let Some(v) = value.get(key).filter(|v| !v.is_null()) {
            check_uint(v, field, width)?;
        }
    }
    // Parsing the concrete variant avoids serde's opaque untagged-enum errors.
    let error = |_| "invalid transaction fields".to_string();
    match value["type"].as_str() {
        Some("0x0") => serde_json::from_value::<TxLegacy>(value.clone())
            .map(Transaction::Legacy)
            .map_err(error),
        Some("0x1") => serde_json::from_value::<TxEip2930>(value.clone())
            .map(Transaction::Eip2930)
            .map_err(error),
        Some("0x2") => serde_json::from_value::<TxEip1559>(value.clone())
            .map(Transaction::Eip1559)
            .map_err(error),
        Some("0x3") => serde_json::from_value::<TxEip4844>(value.clone())
            .map(Transaction::Eip4844)
            .map_err(error),
        Some("0x4") => serde_json::from_value::<TxEip7702>(value.clone())
            .map(Transaction::Eip7702)
            .map_err(error),
        _ => Err("unknown transaction type".into()),
    }
}

// Bound list traversal before alloy allocates access/authorization lists.
fn preflight_rlp(mut input: &[u8], depth: usize, nodes: &mut usize) -> Result<()> {
    if depth > 64 {
        return Err("depth_limit".into());
    }
    while !input.is_empty() {
        crate::spend(nodes)?;
        let header = alloy_rlp::Header::decode(&mut input).map_err(|e| e.to_string())?;
        if header.payload_length > input.len() {
            return Err("truncated_rlp".into());
        }
        let (payload, rest) = input.split_at(header.payload_length);
        if header.list {
            preflight_rlp(payload, depth + 1, nodes)?;
        }
        input = rest;
    }
    Ok(())
}

fn decode(input: &[u8]) -> Result<Vec<u8>> {
    if input
        .first()
        .is_none_or(|b| *b == 0 || (*b > 4 && *b < 0xc0))
    {
        return Err("invalid_envelope".into());
    }
    let body = if input.first().is_some_and(|b| *b < 0x80) {
        &input[1..]
    } else {
        input
    };
    preflight_rlp(body, 0, &mut 100_000)?;
    // Unsigned legacy payloads overload v with chain ID. Re-encoding is essential:
    // alloy's unsigned legacy decoder also consumes (and discards) signed r/s.
    let mut remaining = input;
    if let Ok(tx) = Transaction::decode_unsigned(&mut remaining) {
        if remaining.is_empty() && tx.encoded_for_signing() == input {
            let mut value = serde_json::to_value(&tx).map_err(|e| e.to_string())?;
            if let Transaction::Legacy(tx) = tx {
                // Cartouche's legacy struct has no representation for a six-field
                // unsigned pre-EIP-155 payload (v=0 encodes nine fields).
                if tx.chain_id.is_none() {
                    return Err("invalid_legacy_payload".into());
                }
                value["v"] = serde_json::json!(format!("0x{:x}", tx.chain_id.unwrap_or(0)));
                value["r"] = "0x0".into();
                value["s"] = "0x0".into();
            }
            return serde_json::to_vec(&value).map_err(|e| e.to_string());
        }
    }
    let mut remaining = input;
    let tx = Envelope::decode_2718(&mut remaining).map_err(|e| e.to_string())?;
    if !remaining.is_empty() {
        return Err("trailing_bytes".into());
    }
    let value = serde_json::to_value(&tx).map_err(|e| e.to_string())?;
    if matches!(tx, Envelope::Legacy(_))
        && tx.signature().r().is_zero()
        && tx.signature().s().is_zero()
    {
        check_uint(&value["v"], "chain_id", 64)?;
    }
    serde_json::to_vec(&value).map_err(|e| e.to_string())
}

fn transaction(operation: &str, input: Term<'_>) -> Result<Vec<u8>> {
    if operation == "decode" {
        return decode(bytes(input)?.as_slice());
    }
    let value = json(input)?;
    if operation.starts_with("authorization_") {
        check_uint(&value["nonce"], "authorization_nonce", 64)?;
        check_uint(&value["chainId"], "authorization_chain_id", 256)?;
        let auth: Authorization = serde_json::from_value(value).map_err(|e| e.to_string())?;
        return match operation {
            "authorization_hash" => Ok(auth.signature_hash().to_vec()),
            "authorization_encode" => {
                let mut out = vec![5];
                auth.encode(&mut out);
                Ok(out)
            }
            _ => Err("unknown_operation".into()),
        };
    }
    let tx = parse_transaction(&value)?;
    match operation {
        "signing_hash" => Ok(tx.signature_hash().to_vec()),
        "signing_payload" => Ok(tx.encoded_for_signing()),
        "encode" => {
            if value["r"].is_null() || value["s"].is_null() || value["yParity"].is_null() {
                Ok(tx.encoded_for_signing())
            } else {
                let signature: Signature =
                    serde_json::from_value(value).map_err(|e| e.to_string())?;
                Ok(Envelope::new_unhashed(tx, signature).encoded_2718())
            }
        }
        _ => Err("unknown_operation".into()),
    }
}

// Resolving a DAG can expand shared subtypes exponentially. Bound the expanded
// schema before alloy allocates it; cycles terminate at the same depth limit.
fn check_type(types: &Value, name: &str, depth: usize, nodes: &mut usize) -> Result<()> {
    if depth > 64 || name.len() > 4096 || name.matches('[').count() > 64 {
        return Err("type_depth_limit".into());
    }
    crate::spend(nodes)?;
    let root = name.split('[').next().ok_or("invalid_type")?;
    if let Some(fields) = types[root].as_array() {
        for field in fields {
            check_type(
                types,
                field["type"].as_str().ok_or("invalid_type")?,
                depth + 1,
                nodes,
            )?;
        }
    }
    Ok(())
}

fn typed(operation: &str, input: Term<'_>) -> Result<Vec<u8>> {
    let value = json(input)?;
    let mut nodes = 100_000;
    check_type(
        &value["types"],
        value["primaryType"].as_str().ok_or("primary_type")?,
        0,
        &mut nodes,
    )?;
    let data: TypedData = serde_json::from_value(value).map_err(|e| e.to_string())?;
    match operation {
        "hash" => data
            .eip712_signing_hash()
            .map(|v| v.to_vec())
            .map_err(|e| e.to_string()),
        "hash_struct" => data
            .hash_struct()
            .map(|v| v.to_vec())
            .map_err(|e| e.to_string()),
        "encode_type" => data
            .encode_type()
            .map(|v| v.into_bytes())
            .map_err(|e| e.to_string()),
        "encode_data" => data.encode_data().map_err(|e| e.to_string()),
        "encode" => {
            let mut out = vec![0x19, 0x01];
            out.extend_from_slice(data.domain.separator().as_slice());
            out.extend_from_slice(data.hash_struct().map_err(|e| e.to_string())?.as_slice());
            Ok(out)
        }
        _ => Err("unknown_operation".into()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn consensus<'a>(env: Env<'a>, family: &str, operation: &str, input: Term<'a>) -> Term<'a> {
    let result = catch_unwind(AssertUnwindSafe(|| match family {
        "transaction" => transaction(operation, input),
        "typed" => typed(operation, input),
        _ => Err("unknown_family".into()),
    }));
    match result {
        Ok(Ok(value)) => (atoms::ok(), binary(env, &value)).encode(env),
        Ok(Err(error)) => (atoms::error(), error).encode(env),
        Err(_) => (atoms::error(), "native_panic").encode(env),
    }
}
