//! ABI JSON codegen input, without a Solidity compiler frontend.
use alloy_json_abi::{
    Constructor, Error as AbiError, Event, EventParam, Function, JsonAbi, Param, StateMutability,
};
use alloy_primitives::hex;
use rustler::{Encoder, Env, Term};
use std::panic::{catch_unwind, AssertUnwindSafe};
mod atoms {
    rustler::atoms! {
        ok,
        error,
        parse_error,

        // Map keys
        name,
        signature,
        selector,
        return_type,
        state_mutability,
        inputs,
        outputs,
        functions,
        events,
        errors,
        constructor,
        anonymous,
        topic,
        indexed,
        ty, // "type" is reserved in Rust
        components,

        // New keys for .sol parsing
        structs,
        enums,
        constants,
        natspec,
        notice,
        params,
        returns,
        fields,
        variants,
        value,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_abi_json<'a>(env: Env<'a>, json: &str) -> Term<'a> {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if json.len() > super::MAX_BYTES {
            return Err("payload_limit".to_owned());
        }
        let abi = serde_json::from_str::<JsonAbi>(json).map_err(|e| e.to_string())?;
        Ok(encode_abi(env, &abi))
    }));
    match result {
        Ok(Ok(value)) => (atoms::ok(), value).encode(env),
        Ok(Err(reason)) => (atoms::error(), (atoms::parse_error(), reason)).encode(env),
        Err(_) => (atoms::error(), (atoms::parse_error(), "native_panic")).encode(env),
    }
}

fn encode_abi<'a>(env: Env<'a>, abi: &JsonAbi) -> Term<'a> {
    let funcs: Vec<Term<'a>> = abi.functions().map(|f| encode_function(env, f)).collect();
    let evts: Vec<Term<'a>> = abi.events().map(|e| encode_event(env, e)).collect();
    let errs: Vec<Term<'a>> = abi.errors().map(|e| encode_error(env, e)).collect();

    let ctor: Term<'a> = match &abi.constructor {
        Some(c) => encode_constructor(env, c),
        None => rustler::types::atom::nil().encode(env),
    };

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::functions().encode(env), funcs.encode(env));
    map = map_put(map, atoms::events().encode(env), evts.encode(env));
    map = map_put(map, atoms::errors().encode(env), errs.encode(env));
    map = map_put(map, atoms::constructor().encode(env), ctor);
    map
}

fn encode_function<'a>(env: Env<'a>, f: &Function) -> Term<'a> {
    let sig = f.signature();
    let sel = format!("0x{}", hex::encode(f.selector().as_ref() as &[u8]));
    let ret = build_return_type(&f.outputs);
    let mutability = mutability_str(&f.state_mutability);

    let ins: Vec<Term<'a>> = f.inputs.iter().map(|p| encode_param(env, p)).collect();
    let outs: Vec<Term<'a>> = f.outputs.iter().map(|p| encode_param(env, p)).collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), f.name.as_str().encode(env));
    map = map_put(
        map,
        atoms::signature().encode(env),
        sig.as_str().encode(env),
    );
    map = map_put(map, atoms::selector().encode(env), sel.as_str().encode(env));
    map = map_put(
        map,
        atoms::return_type().encode(env),
        ret.as_str().encode(env),
    );
    map = map_put(
        map,
        atoms::state_mutability().encode(env),
        mutability.encode(env),
    );
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map = map_put(map, atoms::outputs().encode(env), outs.encode(env));
    map
}

fn encode_event<'a>(env: Env<'a>, e: &Event) -> Term<'a> {
    let sig = e.signature();
    let topic_hash = format!("0x{}", hex::encode(e.selector().as_ref() as &[u8]));

    let ins: Vec<Term<'a>> = e
        .inputs
        .iter()
        .map(|p| encode_event_param(env, p))
        .collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), e.name.as_str().encode(env));
    map = map_put(
        map,
        atoms::signature().encode(env),
        sig.as_str().encode(env),
    );
    map = map_put(
        map,
        atoms::topic().encode(env),
        topic_hash.as_str().encode(env),
    );
    map = map_put(map, atoms::anonymous().encode(env), e.anonymous.encode(env));
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map
}

fn encode_error<'a>(env: Env<'a>, e: &AbiError) -> Term<'a> {
    let sig = e.signature();
    let sel = format!("0x{}", hex::encode(e.selector().as_ref() as &[u8]));

    let ins: Vec<Term<'a>> = e.inputs.iter().map(|p| encode_param(env, p)).collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), e.name.as_str().encode(env));
    map = map_put(
        map,
        atoms::signature().encode(env),
        sig.as_str().encode(env),
    );
    map = map_put(map, atoms::selector().encode(env), sel.as_str().encode(env));
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map
}

fn encode_constructor<'a>(env: Env<'a>, c: &Constructor) -> Term<'a> {
    let mutability = mutability_str(&c.state_mutability);
    let ins: Vec<Term<'a>> = c.inputs.iter().map(|p| encode_param(env, p)).collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map = map_put(
        map,
        atoms::state_mutability().encode(env),
        mutability.encode(env),
    );
    map
}

fn encode_param<'a>(env: Env<'a>, p: &Param) -> Term<'a> {
    let comps: Vec<Term<'a>> = p.components.iter().map(|c| encode_param(env, c)).collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), p.name.as_str().encode(env));
    map = map_put(map, atoms::ty().encode(env), p.ty.as_str().encode(env));
    map = map_put(map, atoms::components().encode(env), comps.encode(env));
    map
}

fn encode_event_param<'a>(env: Env<'a>, p: &EventParam) -> Term<'a> {
    let comps: Vec<Term<'a>> = p.components.iter().map(|c| encode_param(env, c)).collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), p.name.as_str().encode(env));
    map = map_put(map, atoms::ty().encode(env), p.ty.as_str().encode(env));
    map = map_put(map, atoms::indexed().encode(env), p.indexed.encode(env));
    map = map_put(map, atoms::components().encode(env), comps.encode(env));
    map
}

// --- Helpers ---

/// Build the return type string compatible with Onchain.ABI.decode_response/2.
/// E.g., "(uint256,uint256,bool)" or "(uint256)" for single returns.
fn build_return_type(outputs: &[Param]) -> String {
    if outputs.is_empty() {
        return String::from("()");
    }

    let types: Vec<String> = outputs.iter().map(canonical_type).collect();
    format!("({})", types.join(","))
}

/// Get the canonical type string for a param, handling tuple/struct types recursively.
fn canonical_type(p: &Param) -> String {
    if p.components.is_empty() {
        // Simple type — use the ty field directly
        p.ty.clone()
    } else {
        // Tuple/struct type — build from components
        // Handle array of tuples (e.g., "tuple[]")
        let suffix = if p.ty.starts_with("tuple") {
            &p.ty["tuple".len()..]
        } else {
            ""
        };
        let inner: Vec<String> = p.components.iter().map(canonical_type).collect();
        format!("({}){}", inner.join(","), suffix)
    }
}

/// Convert StateMutability enum to its Solidity string representation.
fn mutability_str(m: &StateMutability) -> &'static str {
    match m {
        StateMutability::Pure => "pure",
        StateMutability::View => "view",
        StateMutability::NonPayable => "nonpayable",
        StateMutability::Payable => "payable",
    }
}

/// Helper to put a key-value pair into a map term.
fn map_put<'a>(map: Term<'a>, key: Term<'a>, value: Term<'a>) -> Term<'a> {
    map.map_put(key, value).expect("failed to put map entry")
}
