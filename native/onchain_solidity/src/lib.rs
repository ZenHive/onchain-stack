//! Solidity and ABI parsing for Elixir, backed by [alloy-json-abi] and [solang-parser].
//!
//! This crate is the native half of `Onchain.Solidity` and the compile-time
//! engine behind `Onchain.Contract.Generator`. It turns either a JSON ABI or
//! Solidity source into an Erlang-term description of a contract: functions
//! with canonical signatures and 4-byte selectors, events with topic hashes,
//! custom errors, structs, enums and constants, plus any NatSpec attached to
//! them.
//!
//! # Exposed NIFs
//!
//! | NIF | Input | Purpose |
//! |-----|-------|---------|
//! | `parse_abi_json` | JSON ABI | Parse a compiled ABI via `alloy-json-abi` |
//! | `parse_sol` | Solidity source | Parse source via `solang-parser`, no compiler needed |
//!
//! Selectors and topic hashes are computed here with `tiny-keccak` over the
//! canonical signature, so the Elixir side never has to re-derive them.
//!
//! # Source parsing is a parser, not a compiler
//!
//! `parse_sol` reads a parse tree; it does not type-check, resolve inheritance,
//! or evaluate constant expressions. Type and expression rendering falls back to
//! a debug rendering for shapes that are not modelled (see `type_to_string` and
//! the expression helpers), and syntax `solang-parser` does not know is returned
//! as a `:parse_error`. Recursion in type rendering is bounded by
//! `MAX_TYPE_RECURSION_DEPTH`; NatSpec is attached by proximity, bounded by
//! `MAX_NATSPEC_DISTANCE_BYTES`.
//!
//! Prefer `parse_abi_json` when a compiled ABI is available: it is the exact
//! contract surface, whereas source parsing is a best-effort read of what the
//! source declares.
//!
//! [alloy-json-abi]: https://docs.rs/alloy-json-abi
//! [solang-parser]: https://docs.rs/solang-parser

use alloy_json_abi::{
    Constructor, Error as AbiError, Event, EventParam, Function, JsonAbi, Param, StateMutability,
};
use rustler::{Encoder, Env, NifResult, Term};
use solang_parser::pt;
use std::collections::{HashMap, HashSet};
use tiny_keccak::{Hasher, Keccak};

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

/// Maximum byte distance between a doc comment's target offset and a function's
/// start offset for the comment to be associated with that function.
const MAX_NATSPEC_DISTANCE_BYTES: usize = 100;

// --- NIF functions ---

#[rustler::nif]
fn parse_abi_json<'a>(env: Env<'a>, json: &str) -> NifResult<Term<'a>> {
    match serde_json::from_str::<JsonAbi>(json) {
        Ok(abi) => {
            let result = encode_abi(env, &abi);
            Ok((atoms::ok(), result).encode(env))
        }
        Err(e) => {
            let reason = format!("{}", e);
            Ok((atoms::error(), (atoms::parse_error(), reason)).encode(env))
        }
    }
}

#[rustler::nif]
fn parse_sol<'a>(env: Env<'a>, source: &str) -> NifResult<Term<'a>> {
    encode_parse_result(env, parse_sol_source(env, source, None))
}

#[rustler::nif]
fn __parse_sol_root__<'a>(env: Env<'a>, source: &str, root_contract: &str) -> NifResult<Term<'a>> {
    encode_parse_result(env, parse_sol_source(env, source, Some(root_contract)))
}

#[rustler::nif]
fn __extract_sol_imports__<'a>(env: Env<'a>, source: &str) -> NifResult<Term<'a>> {
    match parse_source_unit(source) {
        Ok(tree) => {
            let imports = collect_imports(&tree);
            Ok((atoms::ok(), imports).encode(env))
        }
        Err(reason) => Ok((atoms::error(), (atoms::parse_error(), reason)).encode(env)),
    }
}

fn encode_parse_result<'a>(env: Env<'a>, result: Result<Term<'a>, String>) -> NifResult<Term<'a>> {
    match result {
        Ok(map) => Ok((atoms::ok(), map).encode(env)),
        Err(reason) => Ok((atoms::error(), (atoms::parse_error(), reason)).encode(env)),
    }
}

fn parse_sol_source<'a>(
    env: Env<'a>,
    source: &str,
    root_contract: Option<&str>,
) -> Result<Term<'a>, String> {
    let tree = parse_source_unit(source)?;
    let registry = build_type_registry(&tree);
    let mut doc_comments = extract_doc_comments(source);

    encode_sol_source(env, &tree, root_contract, &registry, &mut doc_comments)
}

fn parse_source_unit(source: &str) -> Result<pt::SourceUnit, String> {
    match solang_parser::parse(source, 0) {
        Ok((tree, _comments)) => Ok(tree),
        Err(diags) => {
            let msgs: Vec<String> = diags.iter().map(|d| format!("{:?}", d)).collect();
            Err(msgs.join("; "))
        }
    }
}

// --- Type registry ---

#[derive(Clone)]
struct SolStruct {
    name: String,
    fields: Vec<SolField>,
}

#[derive(Clone)]
struct SolField {
    name: String,
    ty: String,
}

#[derive(Clone)]
struct SolEnum {
    name: String,
    variants: Vec<String>,
}

struct PendingStruct {
    canonical_name: String,
    short_name: String,
    fields: Vec<SolField>,
}

struct PendingEnum {
    canonical_name: String,
    short_name: String,
    variants: Vec<String>,
}

struct TypeRegistry {
    struct_defs: Vec<SolStruct>,
    enum_defs: Vec<SolEnum>,
    struct_lookup: HashMap<String, SolStruct>,
    enum_lookup: HashSet<String>,
    contract_lookup: HashSet<String>,
}

struct NatSpecComment {
    notice: String,
    params: Vec<(String, String)>,
    returns: Vec<(String, String)>,
}

fn build_type_registry(tree: &pt::SourceUnit) -> TypeRegistry {
    let mut pending_structs: Vec<PendingStruct> = Vec::new();
    let mut pending_enums: Vec<PendingEnum> = Vec::new();
    let mut contract_lookup: HashSet<String> = HashSet::new();

    for part in &tree.0 {
        match part {
            pt::SourceUnitPart::ContractDefinition(contract) => {
                let owner_name = contract
                    .name
                    .as_ref()
                    .map(|id| id.name.clone())
                    .unwrap_or_default();

                if !owner_name.is_empty() {
                    contract_lookup.insert(owner_name.clone());
                }

                for contract_part in &contract.parts {
                    match contract_part {
                        pt::ContractPart::StructDefinition(struct_def) => {
                            register_contract_struct(
                                &mut pending_structs,
                                struct_def,
                                &owner_name,
                                &contract.ty,
                            );
                        }
                        pt::ContractPart::EnumDefinition(enum_def) => {
                            register_contract_enum(
                                &mut pending_enums,
                                enum_def,
                                &owner_name,
                                &contract.ty,
                            );
                        }
                        _ => {}
                    }
                }
            }
            pt::SourceUnitPart::StructDefinition(struct_def) => {
                pending_structs.push(PendingStruct {
                    canonical_name: struct_def
                        .name
                        .as_ref()
                        .map(|id| id.name.clone())
                        .unwrap_or_default(),
                    short_name: struct_def
                        .name
                        .as_ref()
                        .map(|id| id.name.clone())
                        .unwrap_or_default(),
                    fields: collect_struct_fields(struct_def),
                });
            }
            pt::SourceUnitPart::EnumDefinition(enum_def) => {
                let name = enum_def
                    .name
                    .as_ref()
                    .map(|id| id.name.clone())
                    .unwrap_or_default();

                pending_enums.push(PendingEnum {
                    canonical_name: name.clone(),
                    short_name: name,
                    variants: collect_enum_variants(enum_def),
                });
            }
            _ => {}
        }
    }

    finalize_type_registry(pending_structs, pending_enums, contract_lookup)
}

fn finalize_type_registry(
    pending_structs: Vec<PendingStruct>,
    pending_enums: Vec<PendingEnum>,
    contract_lookup: HashSet<String>,
) -> TypeRegistry {
    let mut struct_short_counts: HashMap<String, usize> = HashMap::new();
    let mut enum_short_counts: HashMap<String, usize> = HashMap::new();

    for pending in &pending_structs {
        *struct_short_counts
            .entry(pending.short_name.clone())
            .or_insert(0) += 1;
    }

    for pending in &pending_enums {
        *enum_short_counts
            .entry(pending.short_name.clone())
            .or_insert(0) += 1;
    }

    let struct_defs: Vec<SolStruct> = pending_structs
        .iter()
        .map(|pending| SolStruct {
            name: pending.canonical_name.clone(),
            fields: pending.fields.clone(),
        })
        .collect();

    let enum_defs: Vec<SolEnum> = pending_enums
        .iter()
        .map(|pending| SolEnum {
            name: pending.canonical_name.clone(),
            variants: pending.variants.clone(),
        })
        .collect();

    let mut struct_lookup: HashMap<String, SolStruct> = HashMap::new();

    for struct_def in &struct_defs {
        struct_lookup.insert(struct_def.name.clone(), struct_def.clone());
    }

    for pending in &pending_structs {
        if struct_short_counts.get(&pending.short_name) == Some(&1) {
            struct_lookup
                .entry(pending.short_name.clone())
                .or_insert_with(|| SolStruct {
                    name: pending.canonical_name.clone(),
                    fields: pending.fields.clone(),
                });
        }
    }

    let mut enum_lookup: HashSet<String> = HashSet::new();

    for enum_def in &enum_defs {
        enum_lookup.insert(enum_def.name.clone());
    }

    for pending in &pending_enums {
        if enum_short_counts.get(&pending.short_name) == Some(&1) {
            enum_lookup.insert(pending.short_name.clone());
        }
    }

    TypeRegistry {
        struct_defs,
        enum_defs,
        struct_lookup,
        enum_lookup,
        contract_lookup,
    }
}

fn register_contract_struct(
    pending_structs: &mut Vec<PendingStruct>,
    struct_def: &pt::StructDefinition,
    owner_name: &str,
    contract_ty: &pt::ContractTy,
) {
    let short_name = struct_def
        .name
        .as_ref()
        .map(|id| id.name.clone())
        .unwrap_or_default();

    let canonical_name = qualify_user_type(owner_name, contract_ty, &short_name);

    pending_structs.push(PendingStruct {
        canonical_name,
        short_name,
        fields: collect_struct_fields(struct_def),
    });
}

fn register_contract_enum(
    pending_enums: &mut Vec<PendingEnum>,
    enum_def: &pt::EnumDefinition,
    owner_name: &str,
    contract_ty: &pt::ContractTy,
) {
    let short_name = enum_def
        .name
        .as_ref()
        .map(|id| id.name.clone())
        .unwrap_or_default();

    let canonical_name = qualify_user_type(owner_name, contract_ty, &short_name);

    pending_enums.push(PendingEnum {
        canonical_name,
        short_name,
        variants: collect_enum_variants(enum_def),
    });
}

fn qualify_user_type(owner_name: &str, _contract_ty: &pt::ContractTy, short_name: &str) -> String {
    if !owner_name.is_empty() {
        format!("{}.{}", owner_name, short_name)
    } else {
        short_name.to_string()
    }
}

/// Extract the owner prefix from a canonical name (e.g., "IA.Data" → "IA", "Data" → "").
fn owner_from_canonical(name: &str) -> &str {
    match name.rfind('.') {
        Some(pos) => &name[..pos],
        None => "",
    }
}

/// Context-aware struct lookup: tries owner-qualified name first, then direct.
fn resolve_struct<'a>(base_ty: &str, owner: &str, registry: &'a TypeRegistry) -> Option<&'a SolStruct> {
    if !owner.is_empty() {
        let qualified = format!("{}.{}", owner, base_ty);
        if let Some(s) = registry.struct_lookup.get(&qualified) {
            return Some(s);
        }
    }
    registry.struct_lookup.get(base_ty)
}

/// Context-aware enum lookup: tries owner-qualified name first, then direct.
fn resolve_enum(base_ty: &str, owner: &str, registry: &TypeRegistry) -> bool {
    if !owner.is_empty() {
        let qualified = format!("{}.{}", owner, base_ty);
        if registry.enum_lookup.contains(&qualified) {
            return true;
        }
    }
    registry.enum_lookup.contains(base_ty)
}

fn collect_struct_fields(struct_def: &pt::StructDefinition) -> Vec<SolField> {
    struct_def
        .fields
        .iter()
        .map(|field| SolField {
            name: field
                .name
                .as_ref()
                .map(|id| id.name.clone())
                .unwrap_or_default(),
            ty: expr_to_type_string(&field.ty),
        })
        .collect()
}

fn collect_enum_variants(enum_def: &pt::EnumDefinition) -> Vec<String> {
    enum_def
        .values
        .iter()
        .map(|value| value.as_ref().map(|id| id.name.clone()).unwrap_or_default())
        .collect()
}

// --- Solidity source encoding helpers ---

fn encode_sol_source<'a>(
    env: Env<'a>,
    tree: &pt::SourceUnit,
    root_contract: Option<&str>,
    registry: &TypeRegistry,
    doc_comments: &mut Vec<(usize, NatSpecComment)>,
) -> Result<Term<'a>, String> {
    let sol_structs: Vec<Term<'a>> = registry
        .struct_defs
        .iter()
        .map(|struct_def| encode_sol_struct(env, struct_def, registry))
        .collect();

    let sol_enums: Vec<Term<'a>> = registry
        .enum_defs
        .iter()
        .map(|enum_def| encode_sol_enum(env, enum_def))
        .collect();

    let mut sol_constants: Vec<Term<'a>> = Vec::new();
    let mut sol_functions: Vec<Term<'a>> = Vec::new();
    let mut sol_events: Vec<Term<'a>> = Vec::new();
    let mut sol_errors: Vec<Term<'a>> = Vec::new();
    let mut sol_constructor: Term<'a> = rustler::types::atom::nil().encode(env);
    let mut root_found = root_contract.is_none();

    for part in &tree.0 {
        match part {
            pt::SourceUnitPart::ContractDefinition(contract) => {
                let contract_name = contract
                    .name
                    .as_ref()
                    .map(|id| id.name.as_str())
                    .unwrap_or("");

                for contract_part in &contract.parts {
                    if let pt::ContractPart::VariableDefinition(var) = contract_part {
                        if let Some(constant) = encode_sol_constant(env, var, contract_name, registry) {
                            sol_constants.push(constant);
                        }
                    }
                }

                let is_target = match root_contract {
                    Some(target) => contract_name == target,
                    None => true,
                };

                if !is_target {
                    continue;
                }

                root_found = true;

                for contract_part in &contract.parts {
                    match contract_part {
                        pt::ContractPart::FunctionDefinition(function_def) => {
                            match &function_def.ty {
                                pt::FunctionTy::Constructor => {
                                    sol_constructor =
                                        encode_sol_constructor(env, function_def, contract_name, registry);
                                }
                                pt::FunctionTy::Function => {
                                    let natspec = take_natspec_for_offset(
                                        doc_comments,
                                        function_def.loc.start(),
                                    );
                                    sol_functions.push(encode_sol_function(
                                        env,
                                        function_def,
                                        natspec.as_ref(),
                                        contract_name,
                                        registry,
                                    ));
                                }
                                _ => {}
                            }
                        }
                        pt::ContractPart::EventDefinition(event_def) => {
                            sol_events.push(encode_sol_event(env, event_def, contract_name, registry));
                        }
                        pt::ContractPart::ErrorDefinition(error_def) => {
                            sol_errors.push(encode_sol_error(env, error_def, contract_name, registry));
                        }
                        _ => {}
                    }
                }
            }
            pt::SourceUnitPart::VariableDefinition(var) => {
                if let Some(constant) = encode_sol_constant(env, var, "", registry) {
                    sol_constants.push(constant);
                }
            }
            pt::SourceUnitPart::FunctionDefinition(function_def) if root_contract.is_none() => {
                if let pt::FunctionTy::Function = &function_def.ty {
                    let natspec = take_natspec_for_offset(doc_comments, function_def.loc.start());
                    sol_functions.push(encode_sol_function(
                        env,
                        function_def,
                        natspec.as_ref(),
                        "",
                        registry,
                    ));
                }
            }
            pt::SourceUnitPart::EventDefinition(event_def) if root_contract.is_none() => {
                sol_events.push(encode_sol_event(env, event_def, "", registry));
            }
            pt::SourceUnitPart::ErrorDefinition(error_def) if root_contract.is_none() => {
                sol_errors.push(encode_sol_error(env, error_def, "", registry));
            }
            _ => {}
        }
    }

    if let Some(target) = root_contract {
        if !root_found {
            return Err(format!("root contract `{}` not found", target));
        }
    }

    let mut map = Term::map_new(env);
    map = map_put(
        map,
        atoms::functions().encode(env),
        sol_functions.encode(env),
    );
    map = map_put(map, atoms::events().encode(env), sol_events.encode(env));
    map = map_put(map, atoms::errors().encode(env), sol_errors.encode(env));
    map = map_put(map, atoms::constructor().encode(env), sol_constructor);
    map = map_put(map, atoms::structs().encode(env), sol_structs.encode(env));
    map = map_put(map, atoms::enums().encode(env), sol_enums.encode(env));
    map = map_put(
        map,
        atoms::constants().encode(env),
        sol_constants.encode(env),
    );

    Ok(map)
}

fn encode_sol_struct<'a>(
    env: Env<'a>,
    struct_def: &SolStruct,
    registry: &TypeRegistry,
) -> Term<'a> {
    // Use the struct's own owner for resolving field types
    let struct_owner = owner_from_canonical(&struct_def.name);

    let fields: Vec<Term<'a>> = struct_def
        .fields
        .iter()
        .map(|field| {
            let mut map = Term::map_new(env);
            map = map_put(
                map,
                atoms::name().encode(env),
                field.name.as_str().encode(env),
            );
            map = map_put(
                map,
                atoms::ty().encode(env),
                normalize_struct_field_type(&field.ty, struct_owner, registry).encode(env),
            );
            map
        })
        .collect();

    let mut map = Term::map_new(env);
    map = map_put(
        map,
        atoms::name().encode(env),
        struct_def.name.as_str().encode(env),
    );
    map = map_put(map, atoms::fields().encode(env), fields.encode(env));
    map
}

fn encode_sol_enum<'a>(env: Env<'a>, enum_def: &SolEnum) -> Term<'a> {
    let variants: Vec<&str> = enum_def
        .variants
        .iter()
        .map(|variant| variant.as_str())
        .collect();

    let mut map = Term::map_new(env);
    map = map_put(
        map,
        atoms::name().encode(env),
        enum_def.name.as_str().encode(env),
    );
    map = map_put(map, atoms::variants().encode(env), variants.encode(env));
    map
}

fn encode_sol_constant<'a>(
    env: Env<'a>,
    v: &pt::VariableDefinition,
    owner: &str,
    registry: &TypeRegistry,
) -> Option<Term<'a>> {
    // Only include constant/immutable variables
    let is_constant = v.attrs.iter().any(|a| {
        matches!(
            a,
            pt::VariableAttribute::Constant(_) | pt::VariableAttribute::Immutable(_)
        )
    });
    if !is_constant {
        return None;
    }

    let name_str = v.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");
    let ty_str = normalize_struct_field_type(&expr_to_type_string(&v.ty), owner, registry);
    let val_str = v
        .initializer
        .as_ref()
        .map(expr_to_value_string)
        .unwrap_or_default();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), name_str.encode(env));
    map = map_put(map, atoms::ty().encode(env), ty_str.as_str().encode(env));
    map = map_put(
        map,
        atoms::value().encode(env),
        val_str.as_str().encode(env),
    );
    Some(map)
}

fn encode_sol_function<'a>(
    env: Env<'a>,
    f: &pt::FunctionDefinition,
    natspec: Option<&NatSpecComment>,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let name_str = f.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");

    // Build inputs
    let input_types: Vec<String> = f
        .params
        .iter()
        .map(|(_, p)| param_to_canonical_type(p, owner, registry))
        .collect();

    let ins: Vec<Term<'a>> = f
        .params
        .iter()
        .map(|(_, p)| encode_sol_param(env, p, owner, registry))
        .collect();

    // Build outputs
    let output_types: Vec<String> = f
        .returns
        .iter()
        .map(|(_, p)| param_to_canonical_type(p, owner, registry))
        .collect();

    let outs: Vec<Term<'a>> = f
        .returns
        .iter()
        .map(|(_, p)| encode_sol_param(env, p, owner, registry))
        .collect();

    // Build signature: name(type1,type2)
    let sig = format!("{}({})", name_str, input_types.join(","));

    // Compute selector (first 4 bytes of keccak256)
    let selector = compute_selector(&sig);

    // Build return_type: (type1,type2)
    let ret = format!("({})", output_types.join(","));

    // State mutability
    let mutability = sol_function_mutability(f);

    // NatSpec
    let natspec_term = match natspec {
        Some(ns) => {
            let mut m = Term::map_new(env);
            m = map_put(
                m,
                atoms::notice().encode(env),
                ns.notice.as_str().encode(env),
            );

            let mut pm = Term::map_new(env);
            for (k, v) in &ns.params {
                pm = map_put(pm, k.as_str().encode(env), v.as_str().encode(env));
            }
            m = map_put(m, atoms::params().encode(env), pm);

            let mut rm = Term::map_new(env);
            for (k, v) in &ns.returns {
                rm = map_put(rm, k.as_str().encode(env), v.as_str().encode(env));
            }
            m = map_put(m, atoms::returns().encode(env), rm);
            m
        }
        None => rustler::types::atom::nil().encode(env),
    };

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), name_str.encode(env));
    map = map_put(
        map,
        atoms::signature().encode(env),
        sig.as_str().encode(env),
    );
    map = map_put(
        map,
        atoms::selector().encode(env),
        selector.as_str().encode(env),
    );
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
    map = map_put(map, atoms::natspec().encode(env), natspec_term);
    map
}

fn encode_sol_constructor<'a>(
    env: Env<'a>,
    f: &pt::FunctionDefinition,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let ins: Vec<Term<'a>> = f
        .params
        .iter()
        .map(|(_, p)| encode_sol_param(env, p, owner, registry))
        .collect();

    let mutability = sol_function_mutability(f);

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map = map_put(
        map,
        atoms::state_mutability().encode(env),
        mutability.encode(env),
    );
    map
}

fn encode_sol_event<'a>(
    env: Env<'a>,
    e: &pt::EventDefinition,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let name_str = e.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");

    let input_types: Vec<String> = e
        .fields
        .iter()
        .map(|p| {
            let raw = expr_to_type_string(&p.ty);
            type_to_canonical(&raw, owner, registry)
        })
        .collect();

    let sig = format!("{}({})", name_str, input_types.join(","));
    let topic_hash = compute_topic_hash(&sig);

    let ins: Vec<Term<'a>> = e
        .fields
        .iter()
        .map(|p| {
            let pname = p.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");
            let raw_ty = expr_to_type_string(&p.ty);
            let (canonical_ty, components) = resolve_type_info(&raw_ty, owner, registry);

            let comps: Vec<Term<'a>> = components
                .iter()
                .map(|field| encode_sol_field(env, field, owner, registry))
                .collect();

            let mut m = Term::map_new(env);
            m = map_put(m, atoms::name().encode(env), pname.encode(env));
            m = map_put(
                m,
                atoms::ty().encode(env),
                canonical_ty.as_str().encode(env),
            );
            m = map_put(m, atoms::indexed().encode(env), p.indexed.encode(env));
            m = map_put(m, atoms::components().encode(env), comps.encode(env));
            m
        })
        .collect();

    let is_anonymous = e.anonymous;

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), name_str.encode(env));
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
    map = map_put(
        map,
        atoms::anonymous().encode(env),
        is_anonymous.encode(env),
    );
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map
}

fn encode_sol_error<'a>(
    env: Env<'a>,
    e: &pt::ErrorDefinition,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let name_str = e.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");

    let input_types: Vec<String> = e
        .fields
        .iter()
        .map(|p| {
            let raw = expr_to_type_string(&p.ty);
            type_to_canonical(&raw, owner, registry)
        })
        .collect();

    let sig = format!("{}({})", name_str, input_types.join(","));
    let selector = compute_selector(&sig);

    let ins: Vec<Term<'a>> = e
        .fields
        .iter()
        .map(|p| {
            let pname = p.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");
            let raw_ty = expr_to_type_string(&p.ty);
            let (canonical_ty, components) = resolve_type_info(&raw_ty, owner, registry);

            let comps: Vec<Term<'a>> = components
                .iter()
                .map(|field| encode_sol_field(env, field, owner, registry))
                .collect();

            let mut m = Term::map_new(env);
            m = map_put(m, atoms::name().encode(env), pname.encode(env));
            m = map_put(
                m,
                atoms::ty().encode(env),
                canonical_ty.as_str().encode(env),
            );
            m = map_put(m, atoms::components().encode(env), comps.encode(env));
            m
        })
        .collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), name_str.encode(env));
    map = map_put(
        map,
        atoms::signature().encode(env),
        sig.as_str().encode(env),
    );
    map = map_put(
        map,
        atoms::selector().encode(env),
        selector.as_str().encode(env),
    );
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map
}

fn encode_sol_param<'a>(
    env: Env<'a>,
    p: &Option<pt::Parameter>,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    match p {
        Some(param) => {
            let pname = param.name.as_ref().map(|id| id.name.as_str()).unwrap_or("");
            let raw_ty = expr_to_type_string(&param.ty);

            // Check if the type references a known struct
            let (canonical_ty, components) = resolve_type_info(&raw_ty, owner, registry);

            let comps: Vec<Term<'a>> = components
                .iter()
                .map(|field| encode_sol_field(env, field, owner, registry))
                .collect();

            let mut m = Term::map_new(env);
            m = map_put(m, atoms::name().encode(env), pname.encode(env));
            m = map_put(
                m,
                atoms::ty().encode(env),
                canonical_ty.as_str().encode(env),
            );
            m = map_put(m, atoms::components().encode(env), comps.encode(env));
            m
        }
        None => {
            let mut m = Term::map_new(env);
            m = map_put(m, atoms::name().encode(env), "".encode(env));
            m = map_put(m, atoms::ty().encode(env), "".encode(env));
            m = map_put(
                m,
                atoms::components().encode(env),
                Vec::<Term<'a>>::new().encode(env),
            );
            m
        }
    }
}

/// Resolve a type that may reference a struct definition.
/// Returns (canonical_type, components) where:
/// - If it's a struct: ("tuple", [fields...]) or ("tuple[]", [fields...])
/// - If it's a primitive: (type_string, [])
/// The `owner` parameter provides contract context for resolving unqualified type names.
fn resolve_type_info(ty: &str, owner: &str, registry: &TypeRegistry) -> (String, Vec<SolField>) {
    let (base_ty, suffix) = split_array_suffix(ty);

    if let Some(struct_def) = resolve_struct(&base_ty, owner, registry) {
        return (format!("tuple{}", suffix), struct_def.fields.clone());
    }

    if registry.contract_lookup.contains(&base_ty) {
        return (format!("address{}", suffix), Vec::new());
    }

    if resolve_enum(&base_ty, owner, registry) {
        return (format!("uint8{}", suffix), Vec::new());
    }

    (format!("{}{}", base_ty, suffix), Vec::new())
}

/// Maximum recursion depth for struct expansion to prevent stack overflow
/// on malformed Solidity with circular struct references.
const MAX_TYPE_RECURSION_DEPTH: usize = 10;

/// Recursively resolve a type string to its canonical ABI form.
/// Struct names become expanded tuple types (e.g., "UserData" → "(uint256,address,bool)").
/// Handles nested structs: a struct field that references another struct is expanded recursively.
/// The `owner` parameter provides contract context for resolving unqualified type names.
fn type_to_canonical(ty: &str, owner: &str, registry: &TypeRegistry) -> String {
    type_to_canonical_inner(ty, owner, registry, 0)
}

fn type_to_canonical_inner(ty: &str, owner: &str, registry: &TypeRegistry, depth: usize) -> String {
    if depth > MAX_TYPE_RECURSION_DEPTH {
        return ty.to_string();
    }

    let (base_ty, suffix) = split_array_suffix(ty);

    if let Some(struct_def) = resolve_struct(&base_ty, owner, registry) {
        // Resolve nested fields in the struct's own owner context
        let struct_owner = owner_from_canonical(&struct_def.name);
        let inner: Vec<String> = struct_def
            .fields
            .iter()
            .map(|field| type_to_canonical_inner(&field.ty, struct_owner, registry, depth + 1))
            .collect();
        return format!("({}){}", inner.join(","), suffix);
    }

    if registry.contract_lookup.contains(&base_ty) {
        return format!("address{}", suffix);
    }

    if resolve_enum(&base_ty, owner, registry) {
        return format!("uint8{}", suffix);
    }

    format!("{}{}", base_ty, suffix)
}

/// Encode a SolField as a Rustler term, recursively resolving nested struct types.
fn encode_sol_field<'a>(env: Env<'a>, field: &SolField, owner: &str, registry: &TypeRegistry) -> Term<'a> {
    let (canonical_ty, components) = resolve_type_info(&field.ty, owner, registry);

    let comps: Vec<Term<'a>> = components
        .iter()
        .map(|nested_field| encode_sol_field(env, nested_field, owner, registry))
        .collect();

    let mut m = Term::map_new(env);
    m = map_put(
        m,
        atoms::name().encode(env),
        field.name.as_str().encode(env),
    );
    m = map_put(
        m,
        atoms::ty().encode(env),
        canonical_ty.as_str().encode(env),
    );
    m = map_put(m, atoms::components().encode(env), comps.encode(env));
    m
}

/// Get the canonical type for a parameter, resolving struct references to tuple types.
fn param_to_canonical_type(p: &Option<pt::Parameter>, owner: &str, registry: &TypeRegistry) -> String {
    match p {
        Some(param) => {
            let raw = expr_to_type_string(&param.ty);
            type_to_canonical(&raw, owner, registry)
        }
        None => String::new(),
    }
}

fn normalize_struct_field_type(ty: &str, owner: &str, registry: &TypeRegistry) -> String {
    let (base_ty, suffix) = split_array_suffix(ty);

    if let Some(struct_def) = resolve_struct(&base_ty, owner, registry) {
        return format!("{}{}", struct_def.name, suffix);
    }

    if registry.contract_lookup.contains(&base_ty) {
        return format!("address{}", suffix);
    }

    if resolve_enum(&base_ty, owner, registry) {
        return format!("uint8{}", suffix);
    }

    format!("{}{}", base_ty, suffix)
}

fn split_array_suffix(ty: &str) -> (String, String) {
    let mut base_ty = ty.to_string();
    let mut suffix = String::new();

    loop {
        if base_ty.ends_with("[]") {
            base_ty.truncate(base_ty.len() - 2);
            suffix.insert_str(0, "[]");
        } else if let Some(bracket_pos) = base_ty.rfind('[') {
            let inside = &base_ty[bracket_pos + 1..base_ty.len() - 1];
            if base_ty.ends_with(']') && inside.chars().all(|c| c.is_ascii_digit()) && !inside.is_empty() {
                let array_suffix = &base_ty[bracket_pos..];
                suffix.insert_str(0, array_suffix);
                base_ty.truncate(bracket_pos);
            } else {
                break;
            }
        } else {
            break;
        }
    }

    (base_ty, suffix)
}

// --- Type expression to string conversion ---

fn expr_to_type_string(expr: &pt::Expression) -> String {
    match expr {
        pt::Expression::Type(_, ty) => match ty {
            pt::Type::Address => "address".to_string(),
            pt::Type::AddressPayable => "address".to_string(),
            pt::Type::Bool => "bool".to_string(),
            pt::Type::String => "string".to_string(),
            pt::Type::Bytes(n) => format!("bytes{}", n),
            pt::Type::DynamicBytes => "bytes".to_string(),
            pt::Type::Int(n) => format!("int{}", n),
            pt::Type::Uint(n) => format!("uint{}", n),
            pt::Type::Mapping { .. } => "mapping".to_string(),
            _ => format!("{:?}", ty),
        },
        pt::Expression::ArraySubscript(_, base, size) => {
            match size {
                Some(size_expr) => format!("{}[{}]", expr_to_type_string(base), expr_to_value_string(size_expr)),
                None => format!("{}[]", expr_to_type_string(base)),
            }
        }
        pt::Expression::Parenthesis(_, expr) => expr_to_type_string(expr),
        pt::Expression::Variable(id) => {
            // This handles custom type references (struct names, enum names)
            id.name.clone()
        }
        pt::Expression::MemberAccess(_, expr, member) => {
            format!("{}.{}", expr_to_type_string(expr), member.name)
        }
        _ => format!("{:?}", expr),
    }
}

fn expr_to_value_string(expr: &pt::Expression) -> String {
    match expr {
        pt::Expression::NumberLiteral(_, val, _, _) => val.clone(),
        pt::Expression::HexNumberLiteral(_, val, _) => val.clone(),
        pt::Expression::StringLiteral(vals) => {
            vals.iter().map(|s| s.string.clone()).collect::<String>()
        }
        pt::Expression::BoolLiteral(_, b) => b.to_string(),
        _ => format!("{:?}", expr),
    }
}

fn sol_function_mutability(f: &pt::FunctionDefinition) -> &'static str {
    for attr in &f.attributes {
        if let pt::FunctionAttribute::Mutability(m) = attr { match m {
            pt::Mutability::Pure(_) => return "pure",
            pt::Mutability::View(_) => return "view",
            pt::Mutability::Payable(_) => return "payable",
            pt::Mutability::Constant(_) => return "view",
        } }
    }
    "nonpayable"
}

fn collect_imports(tree: &pt::SourceUnit) -> Vec<String> {
    tree.0
        .iter()
        .filter_map(|part| match part {
            pt::SourceUnitPart::ImportDirective(import) => Some(import_to_path_string(import)),
            _ => None,
        })
        .collect()
}

fn import_to_path_string(import: &pt::Import) -> String {
    match import {
        pt::Import::Plain(path, _)
        | pt::Import::GlobalSymbol(path, _, _)
        | pt::Import::Rename(path, _, _) => import_path_to_string(path),
    }
}

fn import_path_to_string(path: &pt::ImportPath) -> String {
    match path {
        pt::ImportPath::Filename(literal) => literal.string.clone(),
        pt::ImportPath::Path(identifier_path) => identifier_path_to_string(identifier_path),
    }
}

fn identifier_path_to_string(path: &pt::IdentifierPath) -> String {
    path.identifiers
        .iter()
        .map(|identifier| identifier.name.as_str())
        .collect::<Vec<&str>>()
        .join(".")
}

// --- Keccak-256 via tiny-keccak ---

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut output = [0u8; 32];
    hasher.finalize(&mut output);
    output
}

fn compute_selector(signature: &str) -> String {
    let hash = keccak256(signature.as_bytes());
    format!("0x{}", hex::encode(&hash[..4]))
}

fn compute_topic_hash(signature: &str) -> String {
    let hash = keccak256(signature.as_bytes());
    format!("0x{}", hex::encode(hash))
}

// --- NatSpec comment extraction ---

/// Extract doc comments (/// and /** */) from source.
/// Returns a map of byte_offset → NatSpecComment where byte_offset is the start
/// of the first non-comment line after the doc comment block.
fn extract_doc_comments(source: &str) -> Vec<(usize, NatSpecComment)> {
    let lines: Vec<&str> = source.lines().collect();
    let mut results: Vec<(usize, NatSpecComment)> = Vec::new();

    // Build a cumulative byte offset table: byte_offsets[i] = byte offset of line i
    let mut byte_offsets: Vec<usize> = Vec::with_capacity(lines.len() + 1);
    let mut offset = 0;
    for line in &lines {
        byte_offsets.push(offset);
        offset += line.len() + 1; // +1 for newline
    }
    byte_offsets.push(offset); // sentinel for past-end

    let mut i = 0;
    while i < lines.len() {
        let trimmed = lines[i].trim();

        // Check for /// style doc comments
        if trimmed.starts_with("///") {
            let mut doc_lines: Vec<&str> = Vec::new();

            while i < lines.len() && lines[i].trim().starts_with("///") {
                let line = lines[i].trim().trim_start_matches("///").trim();
                doc_lines.push(line);
                i += 1;
            }

            // Skip blank lines between doc comment and definition
            while i < lines.len() && lines[i].trim().is_empty() {
                i += 1;
            }

            // target_line_offset = byte offset of the definition line
            if i < lines.len() {
                if let Some(ns) = parse_natspec_lines(&doc_lines) {
                    results.push((byte_offsets[i], ns));
                }
            }
            continue;
        }

        // Check for /** ... */ style block doc comments
        if trimmed.starts_with("/**") {
            let mut doc_lines: Vec<&str> = Vec::new();

            if trimmed.ends_with("*/") {
                // Single-line block comment: /** @notice foo */
                let content = trimmed
                    .trim_start_matches("/**")
                    .trim_end_matches("*/")
                    .trim();
                if !content.is_empty() {
                    doc_lines.push(content);
                }
                i += 1;
            } else {
                // Multi-line block comment
                let first = trimmed.trim_start_matches("/**").trim();
                if !first.is_empty() {
                    doc_lines.push(first);
                }
                i += 1;

                while i < lines.len() {
                    let line = lines[i].trim();
                    if line.ends_with("*/") || line == "*/" {
                        let content = line
                            .trim_end_matches("*/")
                            .trim()
                            .trim_start_matches('*')
                            .trim();
                        if !content.is_empty() {
                            doc_lines.push(content);
                        }
                        i += 1;
                        break;
                    } else {
                        let content = line.trim_start_matches('*').trim();
                        if !content.is_empty() {
                            doc_lines.push(content);
                        }
                        i += 1;
                    }
                }
            }

            // Skip blank lines between doc comment and definition
            while i < lines.len() && lines[i].trim().is_empty() {
                i += 1;
            }

            if i < lines.len() {
                if let Some(ns) = parse_natspec_lines(&doc_lines) {
                    results.push((byte_offsets[i], ns));
                }
            }
            continue;
        }

        i += 1;
    }

    results
}

fn parse_natspec_lines(lines: &[&str]) -> Option<NatSpecComment> {
    let mut notice = String::new();
    let mut params: Vec<(String, String)> = Vec::new();
    let mut returns: Vec<(String, String)> = Vec::new();

    for line in lines {
        let line = line.trim();
        if line.starts_with("@notice ") {
            notice = line.trim_start_matches("@notice ").to_string();
        } else if line.starts_with("@param ") {
            let rest = line.trim_start_matches("@param ");
            if let Some(pos) = rest.find(' ') {
                params.push((rest[..pos].to_string(), rest[pos + 1..].to_string()));
            }
        } else if line.starts_with("@return ") || line.starts_with("@returns ") {
            let rest = if line.starts_with("@returns ") {
                line.trim_start_matches("@returns ")
            } else {
                line.trim_start_matches("@return ")
            };
            if let Some(pos) = rest.find(' ') {
                returns.push((rest[..pos].to_string(), rest[pos + 1..].to_string()));
            }
        } else if line.starts_with("@title ")
            || line.starts_with("@dev ")
            || line.starts_with("@author ")
        {
            // Skip @title, @dev, @author
        } else if !line.is_empty() && notice.is_empty() {
            // Bare doc comment without tag — treat as notice
            notice = line.to_string();
        }
    }

    if notice.is_empty() && params.is_empty() && returns.is_empty() {
        return None;
    }

    Some(NatSpecComment {
        notice,
        params,
        returns,
    })
}

/// Find and consume the NatSpec comment targeting this function.
/// Each doc comment is consumed at most once — prevents bleeding to adjacent functions.
fn take_natspec_for_offset(
    doc_comments: &mut Vec<(usize, NatSpecComment)>,
    func_byte_offset: usize,
) -> Option<NatSpecComment> {
    // Find the closest doc comment whose target offset is <= func_byte_offset
    let mut best_idx: Option<usize> = None;
    let mut best_distance = usize::MAX;

    for (i, (offset, _)) in doc_comments.iter().enumerate() {
        if *offset <= func_byte_offset {
            let distance = func_byte_offset - *offset;
            if distance < best_distance {
                best_idx = Some(i);
                best_distance = distance;
            }
        }
    }

    // Only match if within ~100 bytes (a couple lines of whitespace)
    match best_idx {
        Some(idx) if best_distance < MAX_NATSPEC_DISTANCE_BYTES => {
            let (_, ns) = doc_comments.remove(idx);
            Some(ns)
        }
        _ => None,
    }
}

// --- ABI JSON encoding helpers (unchanged) ---

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

rustler::init!("Elixir.Onchain.Solidity");
