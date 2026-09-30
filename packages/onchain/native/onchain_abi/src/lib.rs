//! Generic, bounded ABI boundary. All exported operations contain panics.
use alloy_dyn_abi::{DynSolType, DynSolValue};
use alloy_primitives::{Address, FixedBytes, I256, U256};
use rustler::{types::tuple, BigInt, Binary, Encoder, Env, NewBinary, ResourceArc, Term};
use std::panic::{catch_unwind, AssertUnwindSafe};

mod contract;
mod transaction;

mod atoms {
    rustler::atoms! { ok, error, encode, decode, packed, event, events, raw_encode, raw_decode, parse, type_atom = "type", params, signature, profile, name, indexed, uint, int, address, bool_atom = "bool", function, string, bytes_atom = "bytes", array, tuple_atom = "tuple" }
}

const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_NODES: usize = 100_000;
type Result<T> = std::result::Result<T, String>;

fn bad_input(_: rustler::Error) -> String {
    "invalid_term".into()
}

fn bytes<'a>(term: Term<'a>) -> Result<Binary<'a>> {
    let bin = term.decode::<Binary>().map_err(bad_input)?;
    if bin.len() > MAX_BYTES {
        return Err("payload_limit".into());
    }
    Ok(bin)
}

fn binary<'a>(env: Env<'a>, bytes: &[u8]) -> Term<'a> {
    let mut result = NewBinary::new(env, bytes.len());
    result.as_mut_slice().copy_from_slice(bytes);
    result.into()
}

fn spend(remaining: &mut usize) -> Result<()> {
    *remaining = remaining.checked_sub(1).ok_or("value_limit")?;
    Ok(())
}

fn list(mut term: Term, limit: usize) -> Result<Vec<Term>> {
    let mut items = Vec::new();
    while !term.is_empty_list() {
        if items.len() == limit {
            return Err("value_limit".into());
        }
        let (head, tail) = term.list_get_cell().map_err(bad_input)?;
        items.push(head);
        term = tail;
    }
    Ok(items)
}

fn from_term(
    ty: &DynSolType,
    term: Term,
    remaining: &mut usize,
    byte_budget: &mut usize,
) -> Result<DynSolValue> {
    spend(remaining)?;
    if let Ok(bin) = term.decode::<Binary>() {
        *byte_budget = byte_budget.checked_sub(bin.len()).ok_or("payload_limit")?;
    }
    Ok(match ty {
        DynSolType::CustomStruct { .. } => return Err("custom_struct_not_abi".into()),
        DynSolType::Bool => DynSolValue::Bool(term.decode().map_err(bad_input)?),
        DynSolType::Uint(bits) => {
            let value = if let Ok(value) = term.decode::<u64>() {
                U256::from(value)
            } else {
                let big = term.decode::<BigInt>().map_err(bad_input)?;
                let (sign, bytes) = big.to_bytes_be();
                if sign == num_bigint::Sign::Minus || bytes.len() > 32 {
                    return Err("integer_overflow".into());
                }
                U256::from_be_slice(&bytes)
            };
            if value.bit_len() > *bits {
                return Err("integer_overflow".into());
            }
            DynSolValue::Uint(value, *bits)
        }
        DynSolType::Int(bits) => {
            let big = term.decode::<BigInt>().map_err(bad_input)?;
            let data = big.to_signed_bytes_be();
            if data.len() > 32 {
                return Err("integer_overflow".into());
            }
            let negative = big < BigInt::from(0);
            let mut word = [if negative { 0xff } else { 0 }; 32];
            word[32 - data.len()..].copy_from_slice(&data);
            let value = I256::from_raw(U256::from_be_bytes(word));
            let min = -(BigInt::from(1) << (bits - 1));
            let max = (BigInt::from(1) << (bits - 1)) - 1;
            if big < min || big > max {
                return Err("integer_overflow".into());
            }
            DynSolValue::Int(value, *bits)
        }
        DynSolType::Address => {
            let data = bytes(term)?;
            if data.len() != 20 {
                return Err("address_length".into());
            }
            DynSolValue::Address(Address::from_slice(data.as_slice()))
        }
        DynSolType::Function => {
            let data = bytes(term)?;
            if data.len() != 24 {
                return Err("function_length".into());
            }
            DynSolValue::Function(FixedBytes::<24>::from_slice(data.as_slice()).into())
        }
        DynSolType::FixedBytes(n) => {
            let data = bytes(term)?;
            if data.len() > *n || *n > 32 {
                return Err("bytes_length".into());
            }
            let mut word = [0; 32];
            word[..data.len()].copy_from_slice(data.as_slice());
            DynSolValue::FixedBytes(word.into(), *n)
        }
        DynSolType::Bytes => DynSolValue::Bytes(bytes(term)?.as_slice().to_vec()),
        DynSolType::String => {
            let data = bytes(term)?;
            DynSolValue::String(
                std::str::from_utf8(data.as_slice())
                    .map_err(|_| "invalid_utf8")?
                    .into(),
            )
        }
        DynSolType::Tuple(types) => {
            let values = if term.is_tuple() {
                tuple::get_tuple(term).map_err(bad_input)?
            } else {
                list(term, *remaining)?
            };
            if values.len() != types.len() {
                return Err("arity".into());
            }
            DynSolValue::Tuple(
                types
                    .iter()
                    .zip(values)
                    .map(|(ty, value)| from_term(ty, value, remaining, byte_budget))
                    .collect::<Result<_>>()?,
            )
        }
        DynSolType::Array(inner) | DynSolType::FixedArray(inner, _) => {
            let values = list(term, *remaining)?;
            if values.len() > *remaining {
                return Err("value_limit".into());
            }
            if let DynSolType::FixedArray(_, n) = ty {
                if values.len() != *n {
                    return Err("array_length".into());
                }
            }
            let items = values
                .into_iter()
                .map(|value| from_term(inner, value, remaining, byte_budget))
                .collect::<Result<Vec<_>>>()?;
            if matches!(ty, DynSolType::FixedArray(..)) {
                DynSolValue::FixedArray(items)
            } else {
                DynSolValue::Array(items)
            }
        }
    })
}

fn to_term<'a>(env: Env<'a>, value: DynSolValue, remaining: &mut usize) -> Result<Term<'a>> {
    spend(remaining)?;
    Ok(match value {
        DynSolValue::CustomStruct { .. } => return Err("custom_struct_not_abi".into()),
        DynSolValue::Bool(value) => value.encode(env),
        DynSolValue::Uint(value, _) => {
            if value.bit_len() <= 64 {
                value.to::<u64>().encode(env)
            } else {
                BigInt::from_bytes_be(num_bigint::Sign::Plus, &value.to_be_bytes::<32>())
                    .encode(env)
            }
        }
        DynSolValue::Int(value, _) => {
            BigInt::from_signed_bytes_be(&value.to_be_bytes::<32>()).encode(env)
        }
        DynSolValue::Address(value) => binary(env, value.as_slice()),
        DynSolValue::Function(value) => binary(env, value.as_slice()),
        DynSolValue::FixedBytes(value, n) => binary(env, &value[..n]),
        DynSolValue::Bytes(value) => binary(env, &value),
        DynSolValue::String(value) => binary(env, value.as_bytes()),
        DynSolValue::Tuple(values) => {
            let terms = values
                .into_iter()
                .map(|value| to_term(env, value, remaining))
                .collect::<Result<Vec<_>>>()?;
            tuple::make_tuple(env, &terms)
        }
        DynSolValue::Array(values) | DynSolValue::FixedArray(values) => values
            .into_iter()
            .map(|value| to_term(env, value, remaining))
            .collect::<Result<Vec<_>>>()?
            .encode(env),
    })
}

// alloy packs array elements with left-zero padding, including bytes and signed
// integers. Preserve the public packed API by supplying alloy's standard padded
// scalar words as raw bytes to its packed encoder.
fn packed_compatible(value: DynSolValue) -> DynSolValue {
    match value {
        DynSolValue::Tuple(values) => {
            DynSolValue::Tuple(values.into_iter().map(packed_compatible).collect())
        }
        DynSolValue::Array(values) | DynSolValue::FixedArray(values) => DynSolValue::Tuple(
            values
                .into_iter()
                .map(|value| {
                    let encoded = value.abi_encode();
                    let offset = if matches!(value, DynSolValue::Bytes(_) | DynSolValue::String(_))
                    {
                        64
                    } else {
                        0
                    };
                    DynSolValue::Bytes(encoded[offset..].to_vec())
                })
                .collect(),
        ),
        value => value,
    }
}

fn schema_size(ty: &DynSolType) -> Result<usize> {
    let size = match ty {
        DynSolType::Tuple(types) => types.iter().try_fold(1usize, |n, t| {
            n.checked_add(schema_size(t)?)
                .ok_or_else(|| "type_limit".to_string())
        })?,
        DynSolType::Array(inner) => 1 + schema_size(inner)?,
        DynSolType::FixedArray(inner, n) => schema_size(inner)?
            .checked_mul(*n)
            .and_then(|n| n.checked_add(1))
            .ok_or("type_limit")?,
        _ => 1,
    };
    if size > MAX_NODES {
        Err("type_limit".into())
    } else {
        Ok(size)
    }
}

fn head_bytes(ty: &DynSolType) -> usize {
    if ty.is_dynamic() {
        32
    } else {
        ty.minimum_words() * 32
    }
}

// Validate the entire traversal before alloy allocates its token tree. Byte
// limits alone cannot bound nested arrays whose offsets alias the same bytes.
fn preflight(ty: &DynSolType, data: &[u8], body: bool, nodes: &mut usize) -> Result<()> {
    spend(nodes)?;
    if data.len() > MAX_BYTES {
        return Err("payload_limit".into());
    }
    let raw = if !body && ty.is_dynamic() {
        data.get(word_usize(data)?..).ok_or("offset")?
    } else {
        data
    };
    match ty {
        DynSolType::Tuple(types) => {
            let mut head = 0;
            for ty in types {
                let data = raw.get(head..).ok_or("truncated_head")?;
                let data = if ty.is_dynamic() {
                    raw.get(word_usize(data)?..).ok_or("offset")?
                } else {
                    data
                };
                preflight(ty, data, true, nodes)?;
                head += head_bytes(ty);
            }
        }
        DynSolType::Array(inner) | DynSolType::FixedArray(inner, _) => {
            let (count, raw) = if let DynSolType::FixedArray(_, n) = ty {
                (*n, raw)
            } else {
                (word_usize(raw)?, raw.get(32..).ok_or("length")?)
            };
            if count > *nodes {
                return Err("value_limit".into());
            }
            let width = head_bytes(inner);
            for i in 0..count {
                let data = raw
                    .get(i.checked_mul(width).ok_or("length_limit")?..)
                    .ok_or("truncated_head")?;
                let data = if inner.is_dynamic() {
                    raw.get(word_usize(data)?..).ok_or("offset")?
                } else {
                    data
                };
                preflight(inner, data, true, nodes)?;
            }
        }
        DynSolType::Bytes | DynSolType::String => {
            let len = word_usize(raw)?;
            if len > raw.len().saturating_sub(32) {
                return Err("length_limit".into());
            }
        }
        _ => {
            if raw.len() < 32 {
                return Err("truncated_word".into());
            }
        }
    }
    Ok(())
}

fn has_zero(ty: &DynSolType) -> bool {
    match ty {
        DynSolType::Tuple(types) => types.is_empty() || types.iter().any(has_zero),
        DynSolType::Array(inner) => has_zero(inner),
        DynSolType::FixedArray(inner, n) => *n == 0 || has_zero(inner),
        _ => false,
    }
}

fn word_usize(data: &[u8]) -> Result<usize> {
    let word = data.get(..32).ok_or("truncated_word")?;
    U256::from_be_slice(word)
        .try_into()
        .map_err(|_| "length_limit".into())
}

// alloy intentionally collapses zero-width aggregates. Reconstruct their shape
// with a node budget for compatibility with ABI's historical zero-length arrays.
fn decode_compatible(ty: &DynSolType, data: &[u8], budget: &mut usize) -> Result<DynSolValue> {
    spend(budget)?;
    if !has_zero(ty) {
        return ty.abi_decode_params(data).map_err(|e| format!("{e}"));
    }
    match ty {
        DynSolType::Tuple(types) => {
            let mut head = 0;
            let mut values = Vec::new();
            for ty in types {
                let position = if ty.is_dynamic() {
                    word_usize(data.get(head..).ok_or("offset")?)?
                } else {
                    head
                };
                let raw = data.get(position..).ok_or("offset")?;
                let prefixed;
                let raw = if ty.is_dynamic() && !matches!(ty, DynSolType::Tuple(_)) {
                    prefixed = [U256::from(32).to_be_bytes::<32>().as_slice(), raw].concat();
                    prefixed.as_slice()
                } else {
                    raw
                };
                values.push(decode_compatible(ty, raw, budget)?);
                head += if ty.is_dynamic() {
                    32
                } else {
                    ty.minimum_words() * 32
                };
            }
            Ok(DynSolValue::Tuple(values))
        }
        DynSolType::Array(inner) | DynSolType::FixedArray(inner, _) => {
            let (count, raw) = match ty {
                DynSolType::Array(_) => {
                    let offset = word_usize(data)?;
                    let tail = data.get(offset..).ok_or("offset")?;
                    (word_usize(tail)?, tail.get(32..).ok_or("length")?)
                }
                DynSolType::FixedArray(_, n) => {
                    let offset = if ty.is_dynamic() {
                        word_usize(data)?
                    } else {
                        0
                    };
                    (*n, data.get(offset..).ok_or("offset")?)
                }
                _ => return Err("schema".into()),
            };
            if count > *budget {
                return Err("value_limit".into());
            }
            let tuple = DynSolType::Tuple(vec![(**inner).clone(); count]);
            let DynSolValue::Tuple(values) = decode_compatible(&tuple, raw, budget)? else {
                return Err("schema".into());
            };
            Ok(if matches!(ty, DynSolType::Array(_)) {
                DynSolValue::Array(values)
            } else {
                DynSolValue::FixedArray(values)
            })
        }
        _ => ty.abi_decode_params(data).map_err(|e| format!("{e}")),
    }
}

// Only small, static schemas can enter the normal scheduler. Dynamic lengths
// can amplify tiny payloads, so a byte threshold alone is insufficient.
fn small_type(ty: &DynSolType, budget: &mut usize) -> bool {
    if spend(budget).is_err() {
        return false;
    }
    match ty {
        DynSolType::Tuple(types) => types.iter().all(|ty| small_type(ty, budget)),
        DynSolType::Array(_)
        | DynSolType::FixedArray(_, _)
        | DynSolType::Bytes
        | DynSolType::String => false,
        _ => true,
    }
}

fn decode_event<'a>(
    env: Env<'a>,
    ty: &DynSolType,
    value: Term<'a>,
    small: bool,
    remaining: &mut usize,
    signature: &[u8],
) -> Result<Term<'a>> {
    let (topics, data): (Term, Binary) = value.decode().map_err(bad_input)?;
    let topics = list(topics, 4)?
        .into_iter()
        .map(|t| t.decode::<Binary>().map_err(bad_input))
        .collect::<Result<Vec<_>>>()?;
    if !signature.is_empty() && topics.first().map(|t| t.as_slice()) != Some(signature) {
        return Err("event_signature_mismatch".into());
    }
    let DynSolType::Tuple(parts) = ty else {
        return Err("event_schema".into());
    };
    let [DynSolType::Tuple(indexed), body] = parts.as_slice() else {
        return Err("event_schema".into());
    };
    if topics.len() != indexed.len() || topics.len() > 4 {
        return Err("topic_count".into());
    }
    if data.len() > if small { 4096 } else { MAX_BYTES } {
        return Err("payload_limit".into());
    }
    let mut decoded = Vec::new();
    for (ty, topic) in indexed.iter().zip(topics) {
        if topic.len() != 32 {
            return Err("topic_length".into());
        }
        let value = ty
            .abi_decode_params(topic.as_slice())
            .map_err(|e| format!("{e}"))?;
        decoded.push(to_term(env, value, remaining)?);
    }
    preflight(body, data.as_slice(), true, &mut { MAX_NODES })?;
    let value = decode_compatible(body, data.as_slice(), remaining)?;
    Ok((decoded, to_term(env, value, remaining)?).encode(env))
}

struct Schema {
    ty: DynSolType,
    small: bool,
    topic0: Vec<u8>,
}

#[rustler::resource_impl]
impl rustler::Resource for Schema {}

fn parse_schema(type_string: Term, topic0: Term) -> Result<ResourceArc<Schema>> {
    let raw: Binary = type_string.decode().map_err(bad_input)?;
    if raw.len() > 4096 {
        return Err("type_limit".into());
    }
    let text = std::str::from_utf8(raw.as_slice()).map_err(|_| "invalid_type")?;
    if text.bytes().filter(|b| *b == b'(' || *b == b'[').count() > 64 {
        return Err("type_limit".into());
    }
    let ty: DynSolType = text.parse().map_err(|e| format!("{e}"))?;
    schema_size(&ty)?;
    let topic0 = topic0.decode::<Binary>().map_err(bad_input)?;
    if !topic0.is_empty() && topic0.len() != 32 {
        return Err("topic_length".into());
    }
    Ok(ResourceArc::new(Schema {
        small: text.len() <= 256 && small_type(&ty, &mut 32),
        ty,
        topic0: topic0.as_slice().to_vec(),
    }))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn compile<'a>(env: Env<'a>, types: Term<'a>, topic0: Term<'a>) -> Term<'a> {
    match catch_unwind(AssertUnwindSafe(|| parse_schema(types, topic0))) {
        Ok(Ok(schema)) => (atoms::ok(), schema).encode(env),
        Ok(Err(reason)) => (atoms::error(), reason).encode(env),
        Err(_) => (atoms::error(), "panic").encode(env),
    }
}

fn parsed_type<'a>(env: Env<'a>, ty: &alloy_sol_type_parser::TypeSpecifier) -> Result<Term<'a>> {
    use alloy_sol_type_parser::TypeStem;
    let mut term = match &ty.stem {
        TypeStem::Tuple(tuple) => {
            let types = tuple
                .types
                .iter()
                .map(|ty| {
                    Term::map_new(env)
                        .map_put(atoms::type_atom(), parsed_type(env, ty)?)
                        .map_err(bad_input)
                })
                .collect::<Result<Vec<_>>>()?;
            (atoms::tuple_atom(), types).encode(env)
        }
        TypeStem::Root(root) => {
            let text = root.as_ref();
            if text == "fixed"
                || text == "ufixed"
                || text.starts_with("fixed")
                || text.starts_with("ufixed")
            {
                return Err(format!("unsupported:{text}"));
            }
            match DynSolType::parse(text).map_err(|e| format!("{e}"))? {
                DynSolType::Uint(n) => (atoms::uint(), n).encode(env),
                DynSolType::Int(n) => (atoms::int(), n).encode(env),
                DynSolType::Bool => atoms::bool_atom().encode(env),
                DynSolType::Address => atoms::address().encode(env),
                DynSolType::Function => atoms::function().encode(env),
                DynSolType::String => atoms::string().encode(env),
                DynSolType::Bytes => atoms::bytes_atom().encode(env),
                DynSolType::FixedBytes(n) => (atoms::bytes_atom(), n).encode(env),
                _ => return Err("invalid_type".into()),
            }
        }
    };
    for size in &ty.sizes {
        term = if let Some(size) = size {
            let n = if size.get() == usize::MAX {
                0
            } else {
                size.get()
            };
            (atoms::array(), term, n).encode(env)
        } else {
            (atoms::array(), term).encode(env)
        };
    }
    Ok(term)
}

fn parse<'a>(env: Env<'a>, input: Term<'a>, kind: Term<'a>) -> Result<Term<'a>> {
    let input = bytes(input)?;
    if input.len() > 4096 {
        return Err("type_limit".into());
    }
    let input = std::str::from_utf8(input.as_slice()).map_err(|_| "invalid_type")?;
    if input.bytes().filter(|b| *b == b'(' || *b == b'[').count() > 64 {
        return Err("type_limit".into());
    }
    // Zero-length fixed arrays are part of ABI's legacy API, though Solidity
    // cannot emit them and alloy's source grammar uses NonZeroUsize.
    let sentinel = format!("[{}]", usize::MAX);
    if input.contains(&sentinel) {
        return Err("type_limit".into());
    }
    let text = input.replace("[0]", &sentinel);
    if kind == atoms::type_atom().to_term(env) {
        let ty = alloy_sol_type_parser::TypeSpecifier::parse(&text).map_err(|e| format!("{e}"))?;
        parsed_type(env, &ty)
    } else if kind == atoms::params().to_term(env) {
        let params = alloy_sol_type_parser::Parameters::parse(&text).map_err(|e| format!("{e}"))?;
        params
            .params
            .iter()
            .map(|param| {
                let mut map = Term::map_new(env)
                    .map_put(atoms::type_atom(), parsed_type(env, &param.ty)?)
                    .map_err(bad_input)?;
                if let Some(name) = param.name {
                    map = map.map_put(atoms::name(), name).map_err(bad_input)?;
                }
                if param.indexed {
                    map = map.map_put(atoms::indexed(), true).map_err(bad_input)?;
                }
                Ok(map)
            })
            .collect::<Result<Vec<_>>>()
            .map(|p| p.encode(env))
    } else {
        Err("invalid_operation".into())
    }
}

fn run<'a>(
    env: Env<'a>,
    operation: Term<'a>,
    type_string: Term<'a>,
    value: Term<'a>,
    small: bool,
) -> Result<Term<'a>> {
    if operation == atoms::signature().to_term(env) {
        if small {
            return Err("dirty_required".into());
        }
        let raw = bytes(type_string)?;
        if raw.len() > 4096 {
            return Err("type_limit".into());
        }
        let text = std::str::from_utf8(raw.as_slice()).map_err(|_| "invalid_type")?;
        if text.bytes().filter(|b| *b == b'(' || *b == b'[').count() > 64 {
            return Err("type_limit".into());
        }
        // Legacy zero-length fixed arrays have a signature but aren't accepted
        // by alloy's Solidity-source grammar.
        if text.contains("[0]") || text.starts_with('(') {
            let hash = alloy_primitives::keccak256(text.as_bytes());
            return Ok(binary(
                env,
                if value == atoms::event().to_term(env) {
                    hash.as_slice()
                } else {
                    &hash[..4]
                },
            ));
        }
        if value == atoms::event().to_term(env) {
            let item = alloy_json_abi::Event::parse(text).map_err(|e| format!("{e}"))?;
            Ok(binary(env, item.selector().as_slice()))
        } else {
            let item = alloy_json_abi::Function::parse(text).map_err(|e| format!("{e}"))?;
            Ok(binary(env, item.selector().as_slice()))
        }
    } else if operation == atoms::parse().to_term(env) {
        if small {
            return Err("dirty_required".into());
        }
        parse(env, type_string, value)
    } else {
        run_codec(env, operation, type_string, value, small)
    }
}

// Diagnostic operation only: native phase timings exclude BEAM preparation,
// scheduler handoff and this timing operation's result envelope.
fn profile<'a>(env: Env<'a>, ty: &DynSolType, value: Term<'a>) -> Result<Term<'a>> {
    use std::time::Instant;
    let (operation, input): (rustler::Atom, Term) = value.decode().map_err(bad_input)?;
    let start = Instant::now();
    let mut nodes = MAX_NODES;
    if operation == atoms::encode() || operation == atoms::raw_encode() {
        let value = from_term(ty, input, &mut nodes, &mut { MAX_BYTES })?;
        let input_ns = start.elapsed().as_nanos() as u64;
        let start = Instant::now();
        let encoded = if operation == atoms::raw_encode() {
            let DynSolValue::Tuple(values) = value else {
                return Err("schema".into());
            };
            let mut encoded = Vec::new();
            for value in values {
                let bytes = value.abi_encode_params();
                let offset = if value.is_dynamic() && !matches!(value, DynSolValue::Tuple(_)) {
                    32
                } else {
                    0
                };
                encoded.extend_from_slice(&bytes[offset..]);
            }
            encoded
        } else {
            value.abi_encode_params()
        };
        let codec_ns = start.elapsed().as_nanos() as u64;
        let start = Instant::now();
        let result = binary(env, &encoded);
        let output_ns = start.elapsed().as_nanos() as u64;
        return Ok((result, (input_ns, codec_ns, output_ns)).encode(env));
    }
    if operation == atoms::event() {
        let (topics, data): (Term, Binary) = input.decode().map_err(bad_input)?;
        let topics = list(topics, 4)?
            .into_iter()
            .map(|t| t.decode::<Binary>().map_err(bad_input))
            .collect::<Result<Vec<_>>>()?;
        let DynSolType::Tuple(parts) = ty else {
            return Err("schema".into());
        };
        let [DynSolType::Tuple(indexed), body] = parts.as_slice() else {
            return Err("schema".into());
        };
        if topics.len() != indexed.len() || topics.len() > 4 {
            return Err("topic_count".into());
        }
        let input_ns = start.elapsed().as_nanos() as u64;
        let start = Instant::now();
        let mut values = Vec::new();
        for (ty, topic) in indexed.iter().zip(topics) {
            if topic.len() != 32 {
                return Err("topic_length".into());
            }
            values.push(
                ty.abi_decode_params(topic.as_slice())
                    .map_err(|e| format!("{e}"))?,
            );
        }
        preflight(body, data.as_slice(), true, &mut nodes)?;
        let body = decode_compatible(body, data.as_slice(), &mut nodes)?;
        let codec_ns = start.elapsed().as_nanos() as u64;
        let start = Instant::now();
        let topics = values
            .into_iter()
            .map(|v| to_term(env, v, &mut nodes))
            .collect::<Result<Vec<_>>>()?;
        let result = (topics, to_term(env, body, &mut nodes)?).encode(env);
        let output_ns = start.elapsed().as_nanos() as u64;
        return Ok((result, (input_ns, codec_ns, output_ns)).encode(env));
    }
    if operation == atoms::decode() {
        let data = bytes(input)?;
        let input_ns = start.elapsed().as_nanos() as u64;
        let start = Instant::now();
        preflight(
            ty,
            data.as_slice(),
            matches!(ty, DynSolType::Tuple(_)),
            &mut nodes,
        )?;
        let decoded = decode_compatible(ty, data.as_slice(), &mut nodes)?;
        let codec_ns = start.elapsed().as_nanos() as u64;
        let start = Instant::now();
        let result = to_term(env, decoded, &mut nodes)?;
        let output_ns = start.elapsed().as_nanos() as u64;
        return Ok((result, (input_ns, codec_ns, output_ns)).encode(env));
    }
    Err("invalid_operation".into())
}

fn run_codec<'a>(
    env: Env<'a>,
    operation: Term<'a>,
    type_string: Term<'a>,
    value: Term<'a>,
    small: bool,
) -> Result<Term<'a>> {
    if operation == atoms::parse().to_term(env) {
        if small {
            return Err("dirty_required".into());
        }
        return parse(env, type_string, value);
    }
    let schema = match type_string.decode::<ResourceArc<Schema>>() {
        Ok(schema) => schema,
        Err(_) => parse_schema(type_string, binary(env, &[]))?,
    };
    let ty = &schema.ty;
    if small && !schema.small {
        return Err("dirty_required".into());
    }
    if operation == atoms::profile().to_term(env) {
        if small {
            return Err("dirty_required".into());
        }
        return profile(env, ty, value);
    }
    if operation == atoms::event().to_term(env) {
        return decode_event(env, ty, value, small, &mut { MAX_NODES }, &schema.topic0);
    }
    if operation == atoms::events().to_term(env) {
        if small {
            return Err("dirty_required".into());
        }
        let logs = list(value, 10_000)?;
        if logs.len() > 10_000 {
            return Err("batch_limit".into());
        }
        let mut budget = MAX_NODES;
        return Ok(logs
            .into_iter()
            .map(
                |log| match decode_event(env, ty, log, false, &mut budget, &schema.topic0) {
                    Ok(value) => (atoms::ok(), value).encode(env),
                    Err(reason) => (atoms::error(), reason).encode(env),
                },
            )
            .collect::<Vec<_>>()
            .encode(env));
    }
    if small {
        return Err("dirty_required".into());
    }
    if operation == atoms::raw_decode().to_term(env) {
        let DynSolType::Tuple(types) = ty else {
            return Err("schema".into());
        };
        let chunks = list(value, types.len())?
            .into_iter()
            .map(bytes)
            .collect::<Result<Vec<_>>>()?;
        if chunks.iter().map(|b| b.len()).sum::<usize>() > MAX_BYTES {
            return Err("payload_limit".into());
        }
        if types.len() != chunks.len() {
            return Err("arity".into());
        }
        let mut remaining = MAX_NODES;
        let mut values = Vec::new();
        for (ty, chunk) in types.iter().zip(chunks) {
            let prefixed;
            let data = if ty.is_dynamic() && !matches!(ty, DynSolType::Tuple(_)) {
                prefixed = [
                    U256::from(32).to_be_bytes::<32>().as_slice(),
                    chunk.as_slice(),
                ]
                .concat();
                prefixed.as_slice()
            } else {
                chunk.as_slice()
            };
            preflight(ty, data, matches!(ty, DynSolType::Tuple(_)), &mut {
                MAX_NODES
            })?;
            let decoded = decode_compatible(ty, data, &mut remaining)?;
            values.push(to_term(env, decoded, &mut remaining)?);
        }
        return Ok(values.encode(env));
    }
    let mut remaining = MAX_NODES;
    if operation == atoms::raw_encode().to_term(env) {
        let DynSolValue::Tuple(values) = from_term(ty, value, &mut remaining, &mut { MAX_BYTES })?
        else {
            return Err("schema".into());
        };
        let mut encoded = Vec::new();
        for value in values {
            let bytes = value.abi_encode_params();
            let offset = if value.is_dynamic() && !matches!(value, DynSolValue::Tuple(_)) {
                32
            } else {
                0
            };
            encoded.extend_from_slice(&bytes[offset..]);
            if encoded.len() > MAX_BYTES {
                return Err("payload_limit".into());
            }
        }
        return Ok(binary(env, &encoded));
    }
    if operation == atoms::encode().to_term(env) || operation == atoms::packed().to_term(env) {
        let value = from_term(ty, value, &mut remaining, &mut { MAX_BYTES })?;
        let encoded = if operation == atoms::packed().to_term(env) {
            packed_compatible(value).abi_encode_packed()
        } else {
            value.abi_encode_params()
        };
        if encoded.len() > MAX_BYTES {
            return Err("payload_limit".into());
        }
        Ok(binary(env, &encoded))
    } else if operation == atoms::decode().to_term(env) {
        let data = bytes(value)?;
        preflight(
            ty,
            data.as_slice(),
            matches!(ty, DynSolType::Tuple(_)),
            &mut { MAX_NODES },
        )?;
        let decoded = ty
            .abi_decode_params(data.as_slice())
            .map_err(|e| format!("{e}"))?;
        to_term(env, decoded, &mut remaining)
    } else {
        Err("invalid_operation".into())
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn abi<'a>(env: Env<'a>, operation: Term<'a>, types: Term<'a>, value: Term<'a>) -> Term<'a> {
    match catch_unwind(AssertUnwindSafe(|| {
        run(env, operation, types, value, false)
    })) {
        Ok(Ok(value)) => (atoms::ok(), value).encode(env),
        Ok(Err(reason)) => (atoms::error(), reason).encode(env),
        Err(_) => (atoms::error(), "panic").encode(env),
    }
}

#[rustler::nif]
fn abi_small<'a>(env: Env<'a>, operation: Term<'a>, types: Term<'a>, value: Term<'a>) -> Term<'a> {
    match catch_unwind(AssertUnwindSafe(|| run(env, operation, types, value, true))) {
        Ok(Ok(value)) => (atoms::ok(), value).encode(env),
        Ok(Err(reason)) => (atoms::error(), reason).encode(env),
        Err(_) => (atoms::error(), "panic").encode(env),
    }
}

rustler::init!("Elixir.ABI.Native");
