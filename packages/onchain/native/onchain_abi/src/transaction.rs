//! Transaction/EIP-712 operations use alloy's codecs; JSON is the RPC-shaped adapter.
use crate::{atoms, binary, bytes, Result};
use alloy_consensus::{
    EthereumTxEnvelope, EthereumTypedTransaction, SignableTransaction, TxEip1559, TxEip2930,
    TxEip4844, TxEip7702, TxLegacy,
};
use alloy_dyn_abi::{DynSolValue, TypeDef, TypedData};
use alloy_eips::{
    eip2718::{Decodable2718, Encodable2718},
    eip7702::Authorization,
};
use alloy_primitives::{keccak256, Signature, B256, U256};
use alloy_rlp::Encodable;
use alloy_sol_type_parser::TypeSpecifier;
use rustler::{Encoder, Env, Term};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
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

// Resolving a DAG can expand shared subtypes exponentially. Bound expansion,
// but stop at back-edges: recursive schemas are converted along finite values.
fn check_type<'a>(
    types: &'a Value,
    name: &'a str,
    path: &mut Vec<&'a str>,
    nodes: &mut usize,
) -> Result<bool> {
    if path.len() > 64 || name.len() > 4096 || name.matches('[').count() > 64 {
        return Err("type_depth_limit".into());
    }
    crate::spend(nodes)?;
    let root = name.split('[').next().ok_or("invalid_type")?;
    if path.contains(&root) {
        return Ok(true);
    }
    let mut recursive = false;
    if let Some(fields) = types[root].as_array() {
        path.push(root);
        for field in fields {
            recursive |= check_type(
                types,
                field["type"].as_str().ok_or("invalid_type")?,
                path,
                nodes,
            )?;
        }
        path.pop();
    }
    Ok(recursive)
}

// Alloy 1.6.1's resolve() builds a DynSolType, which cannot represent cycles.
// DynSolValue can represent the finite value tree; keep primitive coercion
// in alloy while bounding conversion of recursive structs and arrays.
fn coerce_recursive(
    data: &TypedData,
    types: &Value,
    name: &str,
    value: &Value,
    depth: usize,
    nodes: &mut usize,
) -> Result<DynSolValue> {
    if depth > 64 {
        return Err("depth_limit".into());
    }
    crate::spend(nodes)?;
    let spec = TypeSpecifier::parse_eip712(name).map_err(|e| e.to_string())?;
    if let Some(size) = spec.sizes.last() {
        let values = value.as_array().ok_or("expected_array")?;
        if size.is_some_and(|size| size.get() != values.len()) {
            return Err("array_length_mismatch".into());
        }
        let (inner, _) = name.rsplit_once('[').ok_or("invalid_type")?;
        let values = values
            .iter()
            .map(|value| coerce_recursive(data, types, inner, value, depth + 1, nodes))
            .collect::<Result<Vec<_>>>()?;
        return Ok(if size.is_some() {
            DynSolValue::FixedArray(values)
        } else {
            DynSolValue::Array(values)
        });
    }
    if let Some(fields) = types[name].as_array() {
        let object = value.as_object().ok_or("expected_struct")?;
        let mut tuple = Vec::new();
        let mut prop_names = Vec::new();
        for field in fields {
            let property = field["name"].as_str().ok_or("invalid_field")?;
            tuple.push(coerce_recursive(
                data,
                types,
                field["type"].as_str().ok_or("invalid_type")?,
                object.get(property).ok_or("missing_field")?,
                depth + 1,
                nodes,
            )?);
            prop_names.push(property.to_owned());
        }
        return Ok(DynSolValue::CustomStruct {
            name: name.to_owned(),
            prop_names,
            tuple,
        });
    }
    data.resolver
        .resolve(name)
        .and_then(|ty| ty.coerce_json(value))
        .map_err(|e| e.to_string())
}

// Alloy's encode_type permits self-edges but rejects mutual cycles. Collect
// each reachable definition once, then use alloy's individual type formatter.
fn recursive_encode_type(data: &TypedData, types: &Value, name: &str) -> Result<String> {
    let mut pending = vec![name];
    let mut definitions = BTreeMap::new();
    let mut seen = BTreeSet::new();
    while let Some(name) = pending.pop() {
        if !seen.insert(name) {
            continue;
        }
        if let Some(fields) = types[name].as_array() {
            for field in fields {
                let ty = field["type"].as_str().ok_or("invalid_type")?;
                pending.push(ty.split('[').next().ok_or("invalid_type")?);
            }
            let props = serde_json::from_value(types[name].clone()).map_err(|e| e.to_string())?;
            let definition = TypeDef::new(name, props).map_err(|e| e.to_string())?;
            definitions.insert(name, definition.eip712_encode_type());
        } else {
            data.resolver.resolve(name).map_err(|e| e.to_string())?;
        }
    }
    let mut encoded = definitions.remove(name).ok_or("expected_struct")?;
    for definition in definitions.values() {
        encoded.push_str(definition);
    }
    Ok(encoded)
}

fn recursive_encode_data(
    data: &TypedData,
    types: &Value,
    values: &[DynSolValue],
    hashes: &mut BTreeMap<String, B256>,
) -> Result<Vec<u8>> {
    let mut encoded = Vec::new();
    for value in values {
        encoded.extend_from_slice(recursive_data_word(data, types, value, hashes)?.as_slice());
    }
    Ok(encoded)
}

fn recursive_data_word(
    data: &TypedData,
    types: &Value,
    value: &DynSolValue,
    hashes: &mut BTreeMap<String, B256>,
) -> Result<B256> {
    match value {
        DynSolValue::CustomStruct { name, tuple, .. } => {
            let hash = match hashes.get(name) {
                Some(hash) => *hash,
                None => {
                    let hash = keccak256(recursive_encode_type(data, types, name)?);
                    hashes.insert(name.clone(), hash);
                    hash
                }
            };
            let mut encoded = hash.to_vec();
            encoded.extend(recursive_encode_data(data, types, tuple, hashes)?);
            Ok(keccak256(encoded))
        }
        DynSolValue::Array(values) | DynSolValue::FixedArray(values) => Ok(keccak256(
            recursive_encode_data(data, types, values, hashes)?,
        )),
        _ => data
            .resolver
            .eip712_data_word(value)
            .map_err(|e| e.to_string()),
    }
}

fn typed(operation: &str, input: Term<'_>) -> Result<Vec<u8>> {
    typed_value(operation, json(input)?)
}

fn typed_value(operation: &str, value: Value) -> Result<Vec<u8>> {
    let recursive = check_type(
        &value["types"],
        value["primaryType"].as_str().ok_or("primary_type")?,
        &mut Vec::new(),
        &mut 100_000,
    )?;
    let data: TypedData = serde_json::from_value(value.clone()).map_err(|e| e.to_string())?;
    if recursive {
        let types = &value["types"];
        if operation == "encode_type" {
            return recursive_encode_type(&data, types, &data.primary_type).map(String::into_bytes);
        }
        let message = coerce_recursive(
            &data,
            &value["types"],
            &data.primary_type,
            &data.message,
            0,
            &mut 100_000,
        )?;
        let mut hashes = BTreeMap::new();
        return match operation {
            "encode_data" => match &message {
                DynSolValue::CustomStruct { tuple, .. } => {
                    recursive_encode_data(&data, types, tuple, &mut hashes)
                }
                _ => Err("expected_struct".into()),
            },
            "hash_struct" | "hash" | "encode" => {
                let hash = recursive_data_word(&data, types, &message, &mut hashes)?;
                if operation == "hash_struct" {
                    return Ok(hash.to_vec());
                }
                let mut out = vec![0x19, 0x01];
                out.extend_from_slice(data.domain.separator().as_slice());
                out.extend_from_slice(hash.as_slice());
                Ok(if operation == "hash" {
                    keccak256(out).to_vec()
                } else {
                    out
                })
            }
            _ => Err("unknown_operation".into()),
        };
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn alloy_resolves_values_but_not_recursive_types() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../test/support/fixtures/recursive_typed_before_alloy.json"
        ))
        .expect("oracle JSON");
        let mut document = fixture["input"].clone();
        document["primaryType"] = "Node".into();
        document["message"] = document["value"].take();
        let data: TypedData = serde_json::from_value(document.clone()).expect("typed data");
        assert!(matches!(
            data.coerce(),
            Err(alloy_dyn_abi::Error::CircularDependency(_))
        ));
        assert_eq!(
            typed_value("hash", document).expect("finite recursive hash"),
            alloy_primitives::hex::decode(fixture["hash"].as_str().expect("digest"))
                .expect("hex digest")
        );
        assert_eq!(
            coerce_recursive(
                &data,
                &fixture["input"]["types"],
                "Node",
                &data.message,
                65,
                &mut 100_000
            ),
            Err("depth_limit".into())
        );
        assert_eq!(
            coerce_recursive(
                &data,
                &fixture["input"]["types"],
                "Node",
                &data.message,
                0,
                &mut 1
            ),
            Err("value_limit".into())
        );
    }
}
