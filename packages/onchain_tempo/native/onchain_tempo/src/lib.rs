use alloy_consensus::SignableTransaction;
use alloy_primitives::{Address, Signature, U256, hex};
use alloy_rlp::Header;
use rustler::types::atom::Atom;
use serde_json::{Value, json};
use tempo_primitives::transaction::{KeyAuthorization, SignatureType};
use tempo_primitives::{
    AASigned, TempoSignature, TempoTransaction, transaction::PrimitiveSignature,
};

mod atoms {
    rustler::atoms! { ok, error }
}

type Result<T> = std::result::Result<T, String>;

fn signature(value: &Value) -> Result<Signature> {
    let bytes =
        hex::decode(value.as_str().ok_or("missing signature")?).map_err(|e| e.to_string())?;
    if bytes.len() != 65 {
        return Err("Invalid sender signature format: expected 65 bytes (r, s, v)".into());
    }
    Signature::try_from(bytes.as_slice()).map_err(|e| e.to_string())
}

fn transaction(value: &Value) -> Result<TempoTransaction> {
    let tx: TempoTransaction = serde_json::from_value(value.clone()).map_err(|e| e.to_string())?;
    if let Some(auth) = &tx.key_authorization
        && (auth.key_type != SignatureType::Secp256k1
            || !matches!(auth.signature, PrimitiveSignature::Secp256k1(_)))
    {
        return Err("Only Secp256k1 key authorizations are supported".into());
    }
    Ok(tx)
}

// tempo-primitives emits the service marker but its consensus decoder only
// accepts None or an RLP signature. Adapt that single marker before decoding;
// all transaction fields and signatures are decoded by tempo-primitives.
fn decode(bytes: &[u8]) -> Result<(AASigned, bool)> {
    if bytes.first() != Some(&0x76) {
        return Err("Not a Tempo transaction: expected 0x76 type prefix".into());
    }
    let mut body = &bytes[1..];
    let header = Header::decode(&mut body).map_err(|e| e.to_string())?;
    if !header.list || header.payload_length != body.len() {
        return Err("invalid transaction length".into());
    }
    let mut cursor = body;
    for _ in 0..11 {
        let h = Header::decode(&mut cursor).map_err(|e| e.to_string())?;
        cursor = cursor.get(h.payload_length..).ok_or("truncated field")?;
    }
    let placeholder = cursor.first() == Some(&0);
    let mut normalized = bytes[1..].to_vec();
    if placeholder {
        let offset = normalized.len() - cursor.len();
        normalized[offset] = 0x80;
    }
    let mut input = normalized.as_slice();
    let signed = AASigned::rlp_decode(&mut input).map_err(|e| e.to_string())?;
    if !input.is_empty() {
        return Err("trailing transaction bytes".into());
    }
    if !matches!(
        signed.signature(),
        TempoSignature::Primitive(PrimitiveSignature::Secp256k1(_))
    ) {
        return Err("Only Secp256k1 sender signatures are supported".into());
    }
    let sig = signed.signature().clone();
    let mut tx = signed.strip_signature();
    if placeholder {
        tx.fee_payer_signature = Some(Signature::new(U256::ZERO, U256::ZERO, false));
    }
    Ok((tx.into_signed(sig), placeholder))
}

fn execute(request: Value) -> Result<Value> {
    let operation = request["operation"].as_str().ok_or("missing operation")?;
    if operation == "decode" {
        let bytes = hex::decode(request["raw"].as_str().ok_or("missing raw")?)
            .map_err(|e| e.to_string())?;
        let (signed, placeholder) = decode(&bytes)?;
        return Ok(
            json!({"transaction": signed.tx(), "signature": hex::encode_prefixed(signed.signature().to_bytes()), "placeholder": placeholder}),
        );
    }
    if operation == "key_hash" {
        let authorization: KeyAuthorization =
            serde_json::from_value(request["authorization"].clone()).map_err(|e| e.to_string())?;
        if authorization.key_type != SignatureType::Secp256k1 {
            return Err("Only Secp256k1 access keys are supported".into());
        }
        return Ok(json!(authorization.signature_hash()));
    }
    let tx = transaction(&request["transaction"])?;
    match operation {
        "prepare" => {
            let mut payload = Vec::new();
            tx.encode_for_signing(&mut payload);
            Ok(json!({"payload": hex::encode_prefixed(payload), "hash": tx.signature_hash()}))
        }
        "serialize" => {
            let signed = tx.into_signed(signature(&request["signature"])?.into());
            let mut bytes = Vec::new();
            if request["placeholder"].as_bool() == Some(true) {
                signed.encode_for_fee_payer_service(&mut bytes);
            } else {
                signed.eip2718_encode(&mut bytes);
            }
            Ok(json!(hex::encode_prefixed(bytes)))
        }
        "sender" => {
            let sig = signature(&request["signature"])?;
            let normalized = sig.normalize_s().unwrap_or(sig);
            let sender = normalized
                .recover_address_from_prehash(&tx.signature_hash())
                .map_err(|e| e.to_string())?;
            Ok(json!(sender))
        }
        "fee_hash" => {
            let sender: Address =
                serde_json::from_value(request["sender"].clone()).map_err(|e| e.to_string())?;
            Ok(json!(tx.fee_payer_signature_hash(sender)))
        }
        "fee_payer" => {
            let sender: Address =
                serde_json::from_value(request["sender"].clone()).map_err(|e| e.to_string())?;
            Ok(json!(
                tx.recover_fee_payer(sender).map_err(|e| e.to_string())?
            ))
        }
        _ => Err("unknown operation".into()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn transaction_json(input: String) -> (Atom, String) {
    match serde_json::from_str(&input)
        .map_err(|e| e.to_string())
        .and_then(execute)
    {
        Ok(value) => (atoms::ok(), value.to_string()),
        Err(reason) => (atoms::error(), reason),
    }
}

rustler::init!("Elixir.Onchain.Tempo.Native");

#[cfg(test)]
mod tests {
    use super::*;

    const OX: &str = include_str!("../../../priv/verification/0x76/ox_vectors.json");
    const KEY: &str =
        include_str!("../../../priv/verification/0x76/tempo_primitives_key_authorization.json");

    #[test]
    fn canonical_vectors_round_trip_through_tempo_primitives() {
        let vectors: Value = serde_json::from_str(OX).unwrap();
        for vector in vectors["cases"].as_object().unwrap().values() {
            let bytes = hex::decode(vector["serialized"].as_str().unwrap()).unwrap();
            let (signed, placeholder) = decode(&bytes).unwrap();
            let mut encoded = Vec::new();
            if placeholder {
                signed.encode_for_fee_payer_service(&mut encoded);
            } else {
                signed.eip2718_encode(&mut encoded);
            }
            assert_eq!(encoded, bytes);
            assert_eq!(signed.signature_hash().to_string(), vector["sign_payload"]);
        }
    }

    #[test]
    fn key_authorization_commits_in_both_domains() {
        let vector: Value = serde_json::from_str(KEY).unwrap();
        let bytes = hex::decode(vector["serialized"].as_str().unwrap()).unwrap();
        let (signed, placeholder) = decode(&bytes).unwrap();
        assert!(placeholder);
        let mut tx = signed.strip_signature();
        assert!(tx.key_authorization.is_some());
        assert_eq!(tx.signature_hash().to_string(), vector["signing_hash"]);
        tx.fee_token = Some(
            "0x20c0000000000000000000000000000000000000"
                .parse()
                .unwrap(),
        );
        let sender: Address = vector["sender"].as_str().unwrap().parse().unwrap();
        let fee_hash = tx.fee_payer_signature_hash(sender);
        assert_eq!(fee_hash.to_string(), vector["fee_payer_hash"]);
        let preimage = hex::decode(vector["fee_payer_preimage"].as_str().unwrap()).unwrap();
        assert_eq!(alloy_primitives::keccak256(preimage), fee_hash);
        tx.key_authorization = None;
        assert_ne!(tx.signature_hash().to_string(), vector["signing_hash"]);
        assert_ne!(tx.fee_payer_signature_hash(sender), fee_hash);
    }

    #[test]
    fn malformed_envelopes_and_trailing_bytes_are_rejected() {
        let vectors: Value = serde_json::from_str(OX).unwrap();
        let raw = hex::decode(
            vectors["cases"]["fee_payer_placeholder"]["serialized"]
                .as_str()
                .unwrap(),
        )
        .unwrap();
        for end in 0..raw.len() {
            assert!(
                decode(&raw[..end]).is_err(),
                "accepted truncated envelope at {end}"
            );
        }
        let mut trailing = raw;
        trailing.push(0);
        assert!(decode(&trailing).is_err());
        assert!(decode(&[0x76, 0xc1, 0xc0]).is_err());
    }
}
