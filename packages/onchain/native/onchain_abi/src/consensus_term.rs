//! Bounded BEAM terms for alloy's serde value adapters, without JSON text.
use crate::{bad_input, spend, Result, MAX_BYTES, MAX_NODES};
use rustler::{types::map::MapIterator, Binary, Encoder, Env, Term};
use serde_json::Value;

struct Budget {
    nodes: usize,
    bytes: usize,
}

impl Budget {
    fn new() -> Self {
        Self {
            nodes: MAX_NODES,
            bytes: MAX_BYTES,
        }
    }

    fn visit(&mut self, depth: usize) -> Result<()> {
        if depth > 64 {
            return Err("depth_limit".into());
        }
        spend(&mut self.nodes)
    }

    fn string(&mut self, size: usize) -> Result<()> {
        self.bytes = self.bytes.checked_sub(size).ok_or("payload_limit")?;
        Ok(())
    }
}

pub(crate) fn from_term(term: Term<'_>) -> Result<Value> {
    if !term.is_map() {
        return Err("expected_map".into());
    }
    decode(term, 0, &mut Budget::new())
}

fn string(term: Term<'_>, budget: &mut Budget) -> Result<String> {
    let bin = term.decode::<Binary>().map_err(bad_input)?;
    budget.string(bin.len())?;
    Ok(std::str::from_utf8(bin.as_slice())
        .map_err(|_| "invalid_utf8")?
        .to_owned())
}

fn decode(term: Term<'_>, depth: usize, budget: &mut Budget) -> Result<Value> {
    budget.visit(depth)?;
    if term.is_binary() {
        return string(term, budget).map(Value::String);
    }
    if term.is_map() {
        let mut map = serde_json::Map::new();
        for (key, value) in term.decode::<MapIterator>().map_err(bad_input)? {
            budget.visit(depth + 1)?;
            let key = string(key, budget)?;
            map.insert(key, decode(value, depth + 1, budget)?);
        }
        return Ok(Value::Object(map));
    }
    if term.is_list() {
        let mut tail = term;
        let mut list = Vec::new();
        while !tail.is_empty_list() {
            let (head, rest) = tail.list_get_cell().map_err(bad_input)?;
            list.push(decode(head, depth + 1, budget)?);
            tail = rest;
        }
        return Ok(Value::Array(list));
    }
    if term == rustler::types::atom::nil().encode(term.get_env()) {
        return Ok(Value::Null);
    }
    if let Ok(value) = term.decode::<bool>() {
        return Ok(Value::Bool(value));
    }
    if let Ok(value) = term.decode::<u64>() {
        return Ok(value.into());
    }
    if let Ok(value) = term.decode::<i64>() {
        return Ok(value.into());
    }
    // Adapters pass wider EVM integers as decimal or hex strings, losslessly.
    Err("invalid_term".into())
}

pub(crate) fn to_term<'a>(env: Env<'a>, value: &Value) -> Result<Term<'a>> {
    encode(env, value, 0, &mut Budget::new())
}

fn encode<'a>(env: Env<'a>, value: &Value, depth: usize, budget: &mut Budget) -> Result<Term<'a>> {
    budget.visit(depth)?;
    Ok(match value {
        Value::Null => rustler::types::atom::nil().encode(env),
        Value::Bool(value) => value.encode(env),
        Value::Number(value) => {
            if let Some(value) = value.as_u64() {
                value.encode(env)
            } else {
                value.as_i64().ok_or("invalid_number")?.encode(env)
            }
        }
        Value::String(value) => {
            budget.string(value.len())?;
            value.encode(env)
        }
        Value::Array(items) => items
            .iter()
            .map(|item| encode(env, item, depth + 1, budget))
            .collect::<Result<Vec<_>>>()?
            .encode(env),
        Value::Object(items) => {
            let mut pairs = Vec::with_capacity(items.len());
            for (key, value) in items {
                budget.visit(depth + 1)?;
                budget.string(key.len())?;
                pairs.push((key.encode(env), encode(env, value, depth + 1, budget)?));
            }
            Term::map_from_pairs(env, &pairs).map_err(bad_input)?
        }
    })
}
