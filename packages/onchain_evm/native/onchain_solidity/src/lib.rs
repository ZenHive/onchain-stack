//! Solidity and ABI parsing for Elixir, backed by [alloy-json-abi] and [solar-parse].
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
//! | `parse_sol` | Solidity source | Parse source via `solar-parse`, no compiler needed |
//!
//! Selectors and topic hashes are computed here with `tiny-keccak` over the
//! canonical signature, so the Elixir side never has to re-derive them.
//!
//! # Source parsing is a parser, not a compiler
//!
//! `parse_sol` reads a parse tree; it does not type-check, resolve inheritance,
//! or evaluate constant expressions. Type and expression rendering falls back to
//! a stable placeholder for shapes that are not modelled (see `type_to_string`
//! and the expression helpers), and syntax `solar-parse` does not know is
//! returned as a `:parse_error`. Recursion in type rendering is bounded by
//! `MAX_TYPE_RECURSION_DEPTH`; NatSpec is attached by proximity, bounded by
//! `MAX_NATSPEC_DISTANCE_BYTES`.
//!
//! Prefer `parse_abi_json` when a compiled ABI is available: it is the exact
//! contract surface, whereas source parsing is a best-effort read of what the
//! source declares.
//!
//! [alloy-json-abi]: https://docs.rs/alloy-json-abi
//! [solar-parse]: https://docs.rs/solar-parse

// `cargo clippy --all-targets` lints #[cfg(test)] modules too.
#![cfg_attr(test, allow(clippy::unwrap_used))]

use alloy_json_abi::{
    Constructor, Error as AbiError, Event, EventParam, Function, JsonAbi, Param, StateMutability,
};
use rustler::{Encoder, Env, NifResult, Term};
use solar_parse::{
    ast::{self, Arena},
    interface::{source_map::FileName, ColorChoice, Session},
    Parser,
};
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

// --- Owned source-tree extracted from Solar (private; never crosses the NIF) ---

struct ParsedUnit {
    items: Vec<ParsedItem>,
}

enum ParsedItem {
    Contract(ParsedContract),
    Function(ParsedFunction),
    Variable(ParsedVariable),
    Struct(ParsedStruct),
    Enum(ParsedEnum),
    Event(ParsedEvent),
    Error(ParsedError),
    Import(String),
}

struct ParsedContract {
    name: String,
    items: Vec<ParsedItem>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ParsedFnKind {
    Function,
    Constructor,
}

struct ParsedFunction {
    kind: ParsedFnKind,
    name: String,
    span_start: usize,
    params: Vec<ParsedParam>,
    returns: Vec<ParsedParam>,
    mutability: &'static str,
}

struct ParsedParam {
    name: String,
    ty: String,
    indexed: bool,
}

struct ParsedVariable {
    name: String,
    ty: String,
    value: String,
    is_constant: bool,
}

struct ParsedStruct {
    name: String,
    fields: Vec<SolField>,
}

struct ParsedEnum {
    name: String,
    variants: Vec<String>,
}

struct ParsedEvent {
    name: String,
    fields: Vec<ParsedParam>,
    anonymous: bool,
}

struct ParsedError {
    name: String,
    fields: Vec<ParsedParam>,
}

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

fn parse_source_unit(source: &str) -> Result<ParsedUnit, String> {
    let sess = Session::builder()
        .with_buffer_emitter(ColorChoice::Never)
        .single_threaded()
        .build();

    let extracted = sess.enter_sequential(|| -> Result<ParsedUnit, ()> {
        let arena = Arena::new();
        let mut parser = Parser::from_source_code(
            &sess,
            &arena,
            FileName::Custom("<input>".into()),
            source.to_string(),
        )
        .map_err(|_| ())?;

        let unit = parser.parse_file().map_err(|err| {
            err.emit();
        })?;

        Ok(extract_parsed_unit(&sess, &unit))
    });

    match sess.emitted_errors() {
        Some(Err(diags)) => Err(diags.to_string()),
        _ => extracted.map_err(|_| "parse error".to_string()),
    }
}

fn extract_parsed_unit(sess: &Session, unit: &ast::SourceUnit<'_>) -> ParsedUnit {
    ParsedUnit {
        items: extract_items(sess, unit.items.iter()),
    }
}

fn extract_items<'a, 'ast: 'a>(
    sess: &Session,
    items: impl IntoIterator<Item = &'a ast::Item<'ast>>,
) -> Vec<ParsedItem> {
    items
        .into_iter()
        .filter_map(|item| extract_item(sess, item))
        .collect()
}

fn extract_item<'ast>(sess: &Session, item: &ast::Item<'ast>) -> Option<ParsedItem> {
    match &item.kind {
        ast::ItemKind::Contract(contract) => Some(ParsedItem::Contract(ParsedContract {
            name: contract.name.to_string(),
            items: extract_items(sess, contract.body.iter()),
        })),
        ast::ItemKind::Function(function) => {
            extract_function(sess, function).map(ParsedItem::Function)
        }
        ast::ItemKind::Variable(variable) => Some(ParsedItem::Variable(extract_variable(variable))),
        ast::ItemKind::Struct(struct_def) => Some(ParsedItem::Struct(extract_struct(struct_def))),
        ast::ItemKind::Enum(enum_def) => Some(ParsedItem::Enum(extract_enum(enum_def))),
        ast::ItemKind::Event(event_def) => Some(ParsedItem::Event(extract_event(event_def))),
        ast::ItemKind::Error(error_def) => Some(ParsedItem::Error(extract_error(error_def))),
        ast::ItemKind::Import(import) => {
            Some(ParsedItem::Import(import.path.value.as_str().to_string()))
        }
        _ => None,
    }
}

fn extract_function<'ast>(
    sess: &Session,
    function: &ast::ItemFunction<'ast>,
) -> Option<ParsedFunction> {
    let kind = match function.kind {
        ast::FunctionKind::Function => ParsedFnKind::Function,
        ast::FunctionKind::Constructor => ParsedFnKind::Constructor,
        _ => return None,
    };

    Some(ParsedFunction {
        kind,
        name: function
            .header
            .name
            .map(|ident| ident.to_string())
            .unwrap_or_default(),
        span_start: span_local_start(sess, function.header.span),
        params: extract_params(&function.header.parameters),
        returns: function
            .header
            .returns
            .as_ref()
            .map(extract_params)
            .unwrap_or_default(),
        mutability: sol_function_mutability(&function.header),
    })
}

fn extract_variable<'ast>(variable: &ast::VariableDefinition<'ast>) -> ParsedVariable {
    ParsedVariable {
        name: variable
            .name
            .map(|ident| ident.to_string())
            .unwrap_or_default(),
        ty: type_to_string(&variable.ty),
        value: variable
            .initializer
            .as_deref()
            .map(expr_to_value_string)
            .unwrap_or_default(),
        is_constant: matches!(
            variable.mutability,
            Some(ast::VarMut::Constant | ast::VarMut::Immutable)
        ),
    }
}

fn extract_struct<'ast>(struct_def: &ast::ItemStruct<'ast>) -> ParsedStruct {
    ParsedStruct {
        name: struct_def.name.to_string(),
        fields: struct_def
            .fields
            .iter()
            .map(|field| SolField {
                name: field
                    .name
                    .map(|ident| ident.to_string())
                    .unwrap_or_default(),
                ty: type_to_string(&field.ty),
            })
            .collect(),
    }
}

fn extract_enum<'ast>(enum_def: &ast::ItemEnum<'ast>) -> ParsedEnum {
    ParsedEnum {
        name: enum_def.name.to_string(),
        variants: enum_def
            .variants
            .iter()
            .map(|ident| ident.to_string())
            .collect(),
    }
}

fn extract_event<'ast>(event_def: &ast::ItemEvent<'ast>) -> ParsedEvent {
    ParsedEvent {
        name: event_def.name.to_string(),
        fields: extract_params(&event_def.parameters),
        anonymous: event_def.anonymous,
    }
}

fn extract_error<'ast>(error_def: &ast::ItemError<'ast>) -> ParsedError {
    ParsedError {
        name: error_def.name.to_string(),
        fields: extract_params(&error_def.parameters),
    }
}

fn extract_params<'ast>(params: &ast::ParameterList<'ast>) -> Vec<ParsedParam> {
    params
        .vars
        .iter()
        .map(|param| ParsedParam {
            name: param
                .name
                .map(|ident| ident.to_string())
                .unwrap_or_default(),
            ty: type_to_string(&param.ty),
            indexed: param.indexed,
        })
        .collect()
}

fn span_local_start(sess: &Session, span: ast::Span) -> usize {
    sess.source_map()
        .span_to_range(span)
        .map(|range| range.start)
        .unwrap_or_else(|_| span.to_range().start)
}

fn type_to_string(ty: &ast::Type<'_>) -> String {
    match &ty.kind {
        ast::TypeKind::Elementary(elem) => elem.to_abi_str().into_owned(),
        ast::TypeKind::Array(arr) => {
            let base = type_to_string(&arr.element);
            match arr.size.as_deref() {
                Some(size) => format!("{}[{}]", base, expr_to_value_string(size)),
                None => format!("{}[]", base),
            }
        }
        ast::TypeKind::Custom(path) => path_to_string(path),
        ast::TypeKind::Mapping(_) => "mapping".to_string(),
        ast::TypeKind::Function(_) => "function".to_string(),
    }
}

fn path_to_string(path: &ast::PathSlice) -> String {
    path.segments()
        .iter()
        .map(|ident| ident.to_string())
        .collect::<Vec<_>>()
        .join(".")
}

fn expr_to_value_string(expr: &ast::Expr<'_>) -> String {
    match &expr.kind {
        ast::ExprKind::Lit(lit, _) => lit.symbol.as_str().to_string(),
        ast::ExprKind::Ident(ident) => ident.to_string(),
        ast::ExprKind::Type(ty) => type_to_string(ty),
        ast::ExprKind::Member(inner, member) => {
            format!("{}.{}", expr_to_value_string(inner), member)
        }
        _ => "<expr>".to_string(),
    }
}

fn sol_function_mutability(header: &ast::FunctionHeader<'_>) -> &'static str {
    match header.state_mutability.as_ref().map(|m| m.data) {
        Some(ast::StateMutability::Pure) => "pure",
        Some(ast::StateMutability::View) => "view",
        Some(ast::StateMutability::Payable) => "payable",
        Some(ast::StateMutability::NonPayable) | None => "nonpayable",
    }
}

fn collect_imports(tree: &ParsedUnit) -> Vec<String> {
    tree.items
        .iter()
        .filter_map(|item| match item {
            ParsedItem::Import(path) => Some(path.clone()),
            _ => None,
        })
        .collect()
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

fn build_type_registry(tree: &ParsedUnit) -> TypeRegistry {
    let mut pending_structs: Vec<PendingStruct> = Vec::new();
    let mut pending_enums: Vec<PendingEnum> = Vec::new();
    let mut contract_lookup: HashSet<String> = HashSet::new();

    for item in &tree.items {
        match item {
            ParsedItem::Contract(contract) => {
                if !contract.name.is_empty() {
                    contract_lookup.insert(contract.name.clone());
                }

                for contract_item in &contract.items {
                    match contract_item {
                        ParsedItem::Struct(struct_def) => {
                            pending_structs.push(PendingStruct {
                                canonical_name: qualify_user_type(&contract.name, &struct_def.name),
                                short_name: struct_def.name.clone(),
                                fields: struct_def.fields.clone(),
                            });
                        }
                        ParsedItem::Enum(enum_def) => {
                            pending_enums.push(PendingEnum {
                                canonical_name: qualify_user_type(&contract.name, &enum_def.name),
                                short_name: enum_def.name.clone(),
                                variants: enum_def.variants.clone(),
                            });
                        }
                        _ => {}
                    }
                }
            }
            ParsedItem::Struct(struct_def) => {
                pending_structs.push(PendingStruct {
                    canonical_name: struct_def.name.clone(),
                    short_name: struct_def.name.clone(),
                    fields: struct_def.fields.clone(),
                });
            }
            ParsedItem::Enum(enum_def) => {
                pending_enums.push(PendingEnum {
                    canonical_name: enum_def.name.clone(),
                    short_name: enum_def.name.clone(),
                    variants: enum_def.variants.clone(),
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

fn qualify_user_type(owner_name: &str, short_name: &str) -> String {
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
fn resolve_struct<'a>(
    base_ty: &str,
    owner: &str,
    registry: &'a TypeRegistry,
) -> Option<&'a SolStruct> {
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

// --- Solidity source encoding helpers ---

fn encode_sol_source<'a>(
    env: Env<'a>,
    tree: &ParsedUnit,
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

    for item in &tree.items {
        match item {
            ParsedItem::Contract(contract) => {
                for contract_item in &contract.items {
                    if let ParsedItem::Variable(var) = contract_item {
                        if let Some(constant) =
                            encode_sol_constant(env, var, &contract.name, registry)
                        {
                            sol_constants.push(constant);
                        }
                    }
                }

                let is_target = match root_contract {
                    Some(target) => contract.name == target,
                    None => true,
                };

                if !is_target {
                    continue;
                }

                root_found = true;

                for contract_item in &contract.items {
                    match contract_item {
                        ParsedItem::Function(function_def) => match function_def.kind {
                            ParsedFnKind::Constructor => {
                                sol_constructor = encode_sol_constructor(
                                    env,
                                    function_def,
                                    &contract.name,
                                    registry,
                                );
                            }
                            ParsedFnKind::Function => {
                                let natspec =
                                    take_natspec_for_offset(doc_comments, function_def.span_start);
                                sol_functions.push(encode_sol_function(
                                    env,
                                    function_def,
                                    natspec.as_ref(),
                                    &contract.name,
                                    registry,
                                ));
                            }
                        },
                        ParsedItem::Event(event_def) => {
                            sol_events.push(encode_sol_event(
                                env,
                                event_def,
                                &contract.name,
                                registry,
                            ));
                        }
                        ParsedItem::Error(error_def) => {
                            sol_errors.push(encode_sol_error(
                                env,
                                error_def,
                                &contract.name,
                                registry,
                            ));
                        }
                        _ => {}
                    }
                }
            }
            ParsedItem::Variable(var) => {
                if let Some(constant) = encode_sol_constant(env, var, "", registry) {
                    sol_constants.push(constant);
                }
            }
            ParsedItem::Function(function_def)
                if root_contract.is_none() && function_def.kind == ParsedFnKind::Function =>
            {
                let natspec = take_natspec_for_offset(doc_comments, function_def.span_start);
                sol_functions.push(encode_sol_function(
                    env,
                    function_def,
                    natspec.as_ref(),
                    "",
                    registry,
                ));
            }
            ParsedItem::Event(event_def) if root_contract.is_none() => {
                sol_events.push(encode_sol_event(env, event_def, "", registry));
            }
            ParsedItem::Error(error_def) if root_contract.is_none() => {
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
    v: &ParsedVariable,
    owner: &str,
    registry: &TypeRegistry,
) -> Option<Term<'a>> {
    if !v.is_constant {
        return None;
    }

    let ty_str = normalize_struct_field_type(&v.ty, owner, registry);

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::name().encode(env), v.name.as_str().encode(env));
    map = map_put(map, atoms::ty().encode(env), ty_str.as_str().encode(env));
    map = map_put(
        map,
        atoms::value().encode(env),
        v.value.as_str().encode(env),
    );
    Some(map)
}

fn encode_sol_function<'a>(
    env: Env<'a>,
    f: &ParsedFunction,
    natspec: Option<&NatSpecComment>,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let input_types: Vec<String> = f
        .params
        .iter()
        .map(|p| type_to_canonical(&p.ty, owner, registry))
        .collect();

    let ins: Vec<Term<'a>> = f
        .params
        .iter()
        .map(|p| encode_sol_param(env, p, owner, registry))
        .collect();

    let output_types: Vec<String> = f
        .returns
        .iter()
        .map(|p| type_to_canonical(&p.ty, owner, registry))
        .collect();

    let outs: Vec<Term<'a>> = f
        .returns
        .iter()
        .map(|p| encode_sol_param(env, p, owner, registry))
        .collect();

    let sig = format!("{}({})", f.name, input_types.join(","));
    let selector = compute_selector(&sig);
    let ret = format!("({})", output_types.join(","));

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
    map = map_put(map, atoms::name().encode(env), f.name.as_str().encode(env));
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
        f.mutability.encode(env),
    );
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map = map_put(map, atoms::outputs().encode(env), outs.encode(env));
    map = map_put(map, atoms::natspec().encode(env), natspec_term);
    map
}

fn encode_sol_constructor<'a>(
    env: Env<'a>,
    f: &ParsedFunction,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let ins: Vec<Term<'a>> = f
        .params
        .iter()
        .map(|p| encode_sol_param(env, p, owner, registry))
        .collect();

    let mut map = Term::map_new(env);
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map = map_put(
        map,
        atoms::state_mutability().encode(env),
        f.mutability.encode(env),
    );
    map
}

fn encode_sol_event<'a>(
    env: Env<'a>,
    e: &ParsedEvent,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let input_types: Vec<String> = e
        .fields
        .iter()
        .map(|p| type_to_canonical(&p.ty, owner, registry))
        .collect();

    let sig = format!("{}({})", e.name, input_types.join(","));
    let topic_hash = compute_topic_hash(&sig);

    let ins: Vec<Term<'a>> = e
        .fields
        .iter()
        .map(|p| {
            let (canonical_ty, components) = resolve_type_info(&p.ty, owner, registry);

            let comps: Vec<Term<'a>> = components
                .iter()
                .map(|field| encode_sol_field(env, field, owner, registry))
                .collect();

            let mut m = Term::map_new(env);
            m = map_put(m, atoms::name().encode(env), p.name.as_str().encode(env));
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

fn encode_sol_error<'a>(
    env: Env<'a>,
    e: &ParsedError,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let input_types: Vec<String> = e
        .fields
        .iter()
        .map(|p| type_to_canonical(&p.ty, owner, registry))
        .collect();

    let sig = format!("{}({})", e.name, input_types.join(","));
    let selector = compute_selector(&sig);

    let ins: Vec<Term<'a>> = e
        .fields
        .iter()
        .map(|p| encode_sol_param(env, p, owner, registry))
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
        atoms::selector().encode(env),
        selector.as_str().encode(env),
    );
    map = map_put(map, atoms::inputs().encode(env), ins.encode(env));
    map
}

fn encode_sol_param<'a>(
    env: Env<'a>,
    p: &ParsedParam,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
    let (canonical_ty, components) = resolve_type_info(&p.ty, owner, registry);

    let comps: Vec<Term<'a>> = components
        .iter()
        .map(|field| encode_sol_field(env, field, owner, registry))
        .collect();

    let mut m = Term::map_new(env);
    m = map_put(m, atoms::name().encode(env), p.name.as_str().encode(env));
    m = map_put(
        m,
        atoms::ty().encode(env),
        canonical_ty.as_str().encode(env),
    );
    m = map_put(m, atoms::components().encode(env), comps.encode(env));
    m
}

/// Resolve a type that may reference a struct definition.
/// Returns (canonical_type, components) where:
/// - If it's a struct: ("tuple", [fields...]) or ("tuple[]", [fields...])
/// - If it's a primitive: (type_string, [])
///
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
fn encode_sol_field<'a>(
    env: Env<'a>,
    field: &SolField,
    owner: &str,
    registry: &TypeRegistry,
) -> Term<'a> {
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
            if base_ty.ends_with(']')
                && inside.chars().all(|c| c.is_ascii_digit())
                && !inside.is_empty()
            {
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

#[cfg(test)]
mod tests {
    use super::{
        build_type_registry, canonical_type, compute_selector, compute_topic_hash,
        extract_doc_comments, parse_source_unit, take_natspec_for_offset, type_to_canonical,
        type_to_canonical_inner, JsonAbi, ParsedEvent, ParsedFunction, ParsedItem, ParsedUnit,
        TypeRegistry, MAX_NATSPEC_DISTANCE_BYTES, MAX_TYPE_RECURSION_DEPTH,
    };

    const COMPILED_ABI_SOURCE: &str = r#"
        pragma solidity ^0.8.10;

        contract CanonicalFixture {
            struct Order {
                address maker;
                uint256[2] amounts;
            }

            event Submitted(Order order, bytes32[][2] proofs);

            function submit(Order calldata order, bytes32[][2] calldata proofs) external {
                emit Submitted(order, proofs);
            }
        }
    "#;
    const COMPILED_ABI_JSON: &str = r#"[
      {
        "anonymous": false,
        "inputs": [
          {
            "components": [
              {"internalType": "address", "name": "maker", "type": "address"},
              {"internalType": "uint256[2]", "name": "amounts", "type": "uint256[2]"}
            ],
            "indexed": false,
            "internalType": "struct CanonicalFixture.Order",
            "name": "order",
            "type": "tuple"
          },
          {
            "indexed": false,
            "internalType": "bytes32[][2]",
            "name": "proofs",
            "type": "bytes32[][2]"
          }
        ],
        "name": "Submitted",
        "type": "event"
      },
      {
        "inputs": [
          {
            "components": [
              {"internalType": "address", "name": "maker", "type": "address"},
              {"internalType": "uint256[2]", "name": "amounts", "type": "uint256[2]"}
            ],
            "internalType": "struct CanonicalFixture.Order",
            "name": "order",
            "type": "tuple"
          },
          {
            "internalType": "bytes32[][2]",
            "name": "proofs",
            "type": "bytes32[][2]"
          }
        ],
        "name": "submit",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      }
    ]"#;
    // solc 0.8.10 standard-json emitted the method identifier and embedded the
    // event topic as PUSH32 in this fixture's bytecode.
    const COMPILED_FUNCTION_SIGNATURE: &str = "submit((address,uint256[2]),bytes32[][2])";
    const COMPILED_FUNCTION_SELECTOR: &str = "0xcc6dcbb9";
    const COMPILED_EVENT_SIGNATURE: &str = "Submitted((address,uint256[2]),bytes32[][2])";
    const COMPILED_EVENT_TOPIC: &str =
        "0x4cb3cf49c9df3e693baf5dce395d49fe194469935f06f17c93eccef374838821";
    const EXPECTED_MAX_TYPE_RECURSION_DEPTH: usize = 10;

    fn registry_for(source: &str) -> TypeRegistry {
        let tree = parse_source_unit(source).expect("fixture source must parse");
        build_type_registry(&tree)
    }

    fn contract_items<'a>(tree: &'a ParsedUnit, contract_name: &str) -> &'a [ParsedItem] {
        tree.items
            .iter()
            .find_map(|item| match item {
                ParsedItem::Contract(contract) if contract.name == contract_name => {
                    Some(contract.items.as_slice())
                }
                _ => None,
            })
            .unwrap_or_else(|| panic!("contract `{contract_name}` not found in fixture"))
    }

    fn parsed_function<'a>(
        tree: &'a ParsedUnit,
        contract_name: &str,
        function_name: &str,
    ) -> &'a ParsedFunction {
        contract_items(tree, contract_name)
            .iter()
            .find_map(|item| match item {
                ParsedItem::Function(function) if function.name == function_name => Some(function),
                _ => None,
            })
            .unwrap_or_else(|| panic!("function `{function_name}` not found in fixture"))
    }

    fn parsed_event<'a>(
        tree: &'a ParsedUnit,
        contract_name: &str,
        event_name: &str,
    ) -> &'a ParsedEvent {
        contract_items(tree, contract_name)
            .iter()
            .find_map(|item| match item {
                ParsedItem::Event(event) if event.name == event_name => Some(event),
                _ => None,
            })
            .unwrap_or_else(|| panic!("event `{event_name}` not found in fixture"))
    }

    fn source_function_signature(
        function: &ParsedFunction,
        owner: &str,
        registry: &TypeRegistry,
    ) -> String {
        let input_types = function
            .params
            .iter()
            .map(|param| type_to_canonical(&param.ty, owner, registry))
            .collect::<Vec<_>>();

        format!("{}({})", function.name, input_types.join(","))
    }

    fn source_event_signature(event: &ParsedEvent, owner: &str, registry: &TypeRegistry) -> String {
        let input_types = event
            .fields
            .iter()
            .map(|param| type_to_canonical(&param.ty, owner, registry))
            .collect::<Vec<_>>();

        format!("{}({})", event.name, input_types.join(","))
    }

    fn function_span(tree: &ParsedUnit, contract_name: &str, function_name: &str) -> usize {
        parsed_function(tree, contract_name, function_name).span_start
    }

    fn selector_hex(function: &alloy_json_abi::Function) -> String {
        format!("0x{}", hex::encode(function.selector().as_ref() as &[u8]))
    }

    fn topic_hex(event: &alloy_json_abi::Event) -> String {
        format!("0x{}", hex::encode(event.selector().as_ref() as &[u8]))
    }

    #[test]
    fn compiled_tuple_array_signatures_have_known_selectors_and_topics() {
        let source_tree =
            parse_source_unit(COMPILED_ABI_SOURCE).expect("compiled source fixture must parse");
        let source_registry = build_type_registry(&source_tree);
        let source_function = parsed_function(&source_tree, "CanonicalFixture", "submit");
        let source_event = parsed_event(&source_tree, "CanonicalFixture", "Submitted");
        let source_function_signature =
            source_function_signature(source_function, "CanonicalFixture", &source_registry);
        let source_event_signature =
            source_event_signature(source_event, "CanonicalFixture", &source_registry);

        assert_eq!(source_function_signature, COMPILED_FUNCTION_SIGNATURE);
        assert_eq!(source_event_signature, COMPILED_EVENT_SIGNATURE);
        assert_eq!(
            compute_selector(&source_function_signature),
            COMPILED_FUNCTION_SELECTOR
        );
        assert_eq!(
            compute_topic_hash(&source_event_signature),
            COMPILED_EVENT_TOPIC
        );

        let abi: JsonAbi =
            serde_json::from_str(COMPILED_ABI_JSON).expect("solc ABI fixture must parse");
        let function = abi
            .functions()
            .find(|function| function.name == "submit")
            .expect("compiled ABI must contain submit");
        let event = abi
            .events()
            .find(|event| event.name == "Submitted")
            .expect("compiled ABI must contain Submitted");

        assert_eq!(canonical_type(&function.inputs[0]), "(address,uint256[2])");
        assert_eq!(canonical_type(&function.inputs[1]), "bytes32[][2]");
        assert_eq!(function.signature(), COMPILED_FUNCTION_SIGNATURE);
        assert_eq!(event.signature(), COMPILED_EVENT_SIGNATURE);
        assert_eq!(selector_hex(function), COMPILED_FUNCTION_SELECTOR);
        assert_eq!(topic_hex(event), COMPILED_EVENT_TOPIC);
    }

    #[test]
    fn canonicalizes_nested_arrays_fixed_arrays_structs_and_enums() {
        let registry = registry_for(
            r#"
            contract CanonicalFixture {
                enum Status { Pending, Filled }

                struct Detail {
                    uint256[2] prices;
                    Status status;
                }

                struct Order {
                    Detail[][3] details;
                    address maker;
                }
            }
            "#,
        );

        assert_eq!(
            type_to_canonical("Order[2][]", "CanonicalFixture", &registry),
            "((uint256[2],uint8)[][3],address)[2][]"
        );
        assert_eq!(
            type_to_canonical("uint8[][4]", "CanonicalFixture", &registry),
            "uint8[][4]"
        );
        assert_eq!(
            type_to_canonical("Status[5]", "CanonicalFixture", &registry),
            "uint8[5]"
        );
    }

    #[test]
    fn recursive_struct_canonicalization_stops_at_the_depth_limit() {
        let registry = registry_for(
            r#"
            contract RecursiveFixture {
                struct Node { Node child; }
            }
            "#,
        );

        assert_eq!(MAX_TYPE_RECURSION_DEPTH, EXPECTED_MAX_TYPE_RECURSION_DEPTH);
        assert_eq!(
            type_to_canonical_inner(
                "Node",
                "RecursiveFixture",
                &registry,
                MAX_TYPE_RECURSION_DEPTH
            ),
            "(Node)"
        );
        assert_eq!(
            type_to_canonical_inner(
                "Node",
                "RecursiveFixture",
                &registry,
                MAX_TYPE_RECURSION_DEPTH + 1
            ),
            "Node"
        );

        let mut expected = "Node".to_string();
        for _ in 0..=MAX_TYPE_RECURSION_DEPTH {
            expected = format!("({expected})");
        }
        assert_eq!(
            type_to_canonical("Node", "RecursiveFixture", &registry),
            expected
        );
    }

    #[test]
    fn adjacent_natspec_is_attached_to_the_function() {
        let source = r#"
            contract Docs {
                /// @notice Process an amount.
                /// @param amount Amount to process.
                /// @return result Processed amount.
                function process(uint256 amount) external pure returns (uint256 result);
            }
        "#;
        let tree = parse_source_unit(source).expect("NatSpec fixture must parse");
        let mut comments = extract_doc_comments(source);

        let natspec =
            take_natspec_for_offset(&mut comments, function_span(&tree, "Docs", "process"))
                .expect("adjacent NatSpec must attach");

        assert_eq!(natspec.notice, "Process an amount.");
        assert_eq!(
            natspec.params,
            vec![("amount".to_string(), "Amount to process.".to_string())]
        );
        assert_eq!(
            natspec.returns,
            vec![("result".to_string(), "Processed amount.".to_string())]
        );
        assert!(comments.is_empty());
    }

    #[test]
    fn natspec_beyond_the_distance_limit_is_not_attached() {
        let padding_name = "x".repeat(MAX_NATSPEC_DISTANCE_BYTES);
        let source = format!(
            r#"
            contract Docs {{
                /// @notice This belongs to the intervening declaration.
                uint256 constant {padding_name} = 1;
                function distant() external;
            }}
            "#
        );
        let tree = parse_source_unit(&source).expect("distant NatSpec fixture must parse");
        let mut comments = extract_doc_comments(&source);
        let span = function_span(&tree, "Docs", "distant");

        assert_eq!(comments.len(), 1);
        assert!(span - comments[0].0 > MAX_NATSPEC_DISTANCE_BYTES);
        assert!(take_natspec_for_offset(&mut comments, span).is_none());
    }

    #[test]
    fn solar_parse_accepts_documented_modern_solidity_syntax() {
        let cases = [
            (
                "transient state variable",
                "pragma solidity ^0.8.28; contract C { uint256 transient lock; }",
            ),
            (
                "literal custom storage layout",
                "pragma solidity ^0.8.29; contract C layout at 42 { uint256 value; }",
            ),
            (
                "constant custom storage layout",
                "pragma solidity ^0.8.31; uint256 constant BASE = 42; contract C layout at BASE { uint256 value; }",
            ),
            (
                "erc7201 custom storage layout",
                "pragma solidity ^0.8.35; contract C layout at erc7201(\"example.storage.C\") { uint256 value; }",
            ),
        ];

        for (name, source) in cases {
            parse_source_unit(source).unwrap_or_else(|error| {
                panic!("{name} failed to parse: {error}");
            });
        }
    }

    #[test]
    fn parse_source_unit_rejects_invalid_solidity() {
        let error = match parse_source_unit("not solidity {{{") {
            Ok(_) => panic!("invalid source should not parse"),
            Err(error) => error,
        };
        assert!(!error.is_empty(), "parse error reason must not be empty");
    }
}
