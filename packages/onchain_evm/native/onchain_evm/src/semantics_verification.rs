use super::*;
use alloy_primitives::B256;
use revm::state::AccountInfo;
use revm_database::EmptyDB;
use serde_json::Value;

const BLOCK_CALL: &str = include_str!("../testdata/semantics/official/call_output_1.json");
const BLOCK_CREATE: &str =
    include_str!("../testdata/semantics/official/create_empty_contract_with_storage.json");
const BLOCK_CREATE_TX: &str = include_str!(
    "../testdata/semantics/official/create_empty000_create_in_initcode_transaction.json"
);
const BLOCK_REVERT: &str = include_str!("../testdata/semantics/official/revert_opcode.json");
const VM_LOG: &str = include_str!("../testdata/semantics/official/log1_non_empty_mem.json");
const VM_SSTORE: &str = include_str!("../testdata/semantics/official/sstore_load_1.json");
const VM_SSTORE_BAD: &str =
    include_str!("../testdata/semantics/negative/sstore_load_1_bad_storage.json");
const LEDGER: &str = include_str!("../testdata/semantics/verification-ledger.json");

const TEST_SENDER: &str = "0xa94f5374fce5edbc8e2a8697c15331677e6ebf0b";
const TRANSACTION_INTRINSIC_GAS: u64 = 21_000;

/// KEVM GST checking for VMTESTS keeps these keys. A committed VMTest vector
/// must declare all of them; the comparator asserts every key the fixture has,
/// so a new vector cannot under-assert by omitting a call site.
const VMTEST_ORACLE_KEYS: [&str; 4] = ["out", "gas", "logs", "post"];
const BLOCKCHAIN_CHECKED_KEYS: [&str; 5] = ["status", "output", "gasUsed", "logs", "postState"];

type TestDb = CacheDB<EmptyDB>;

#[derive(Debug)]
struct ExecutedVector {
    result: TxResult,
    db: TestDb,
    gas_remaining: Option<u64>,
}

fn parse_json(source: &str) -> Value {
    serde_json::from_str(source).expect("committed semantic fixture must be valid JSON")
}

fn parse_hex_u64(value: &str) -> u64 {
    u64::from_str_radix(value.trim_start_matches("0x"), 16).expect("fixture u64 hex")
}

fn parse_hex_u128(value: &str) -> u128 {
    u128::from_str_radix(value.trim_start_matches("0x"), 16).expect("fixture u128 hex")
}

fn string_field<'a>(value: &'a Value, field: &str) -> &'a str {
    value[field]
        .as_str()
        .unwrap_or_else(|| panic!("fixture field {field} must be a string"))
}

fn named_case<'a>(fixture: &'a Value, name: &str) -> &'a Value {
    fixture
        .get(name)
        .unwrap_or_else(|| panic!("fixture case {name} is missing"))
}

fn canonical_hex(value: &str) -> String {
    bytes_to_hex(&decode_hex_to_bytes(value).expect("fixture hex"))
}

fn load_pre_state(pre: &Value) -> TestDb {
    let mut db = CacheDB::new(EmptyDB::default());

    for (address_hex, account) in pre.as_object().expect("pre must be an object") {
        let address = decode_hex_to_address(address_hex).expect("fixture address");
        let code = Bytecode::new_raw(Bytes::from(
            decode_hex_to_bytes(string_field(account, "code")).expect("fixture code"),
        ));
        let info = AccountInfo::default()
            .with_balance(
                decode_hex_to_u256(string_field(account, "balance")).expect("fixture balance"),
            )
            .with_nonce(parse_hex_u64(string_field(account, "nonce")))
            .with_code(code);
        db.insert_account_info(address, info);

        for (slot, value) in account["storage"]
            .as_object()
            .expect("storage must be an object")
        {
            db.insert_account_storage(
                address,
                decode_hex_to_u256(slot).expect("fixture storage slot"),
                decode_hex_to_u256(value.as_str().expect("storage value must be a string"))
                    .expect("fixture storage value"),
            )
            .expect("EmptyDB storage insert is infallible");
        }
    }

    db
}

fn block_env(header: &Value) -> BlockEnv {
    BlockEnv {
        number: U256::from(parse_hex_u64(string_field(header, "number"))),
        beneficiary: decode_hex_to_address(string_field(header, "coinbase"))
            .expect("fixture coinbase"),
        timestamp: U256::from(parse_hex_u64(string_field(header, "timestamp"))),
        gas_limit: parse_hex_u64(string_field(header, "gasLimit")),
        prevrandao: Some(
            string_field(header, "mixHash")
                .parse::<B256>()
                .expect("fixture mix hash"),
        ),
        ..Default::default()
    }
}

fn execute_blockchain_case(case: &Value) -> ExecutedVector {
    let mut db = load_pre_state(&case["pre"]);
    let block = &case["blocks"][0];
    let header = &block["blockHeader"];
    let fixture_tx = &block["transactions"][0];
    let to = string_field(fixture_tx, "to");
    let kind = if to.is_empty() {
        TxKind::Create
    } else {
        TxKind::Call(decode_hex_to_address(to).expect("fixture tx target"))
    };
    let tx = TxEnv::builder()
        .caller(decode_hex_to_address(TEST_SENDER).expect("test sender"))
        .kind(kind)
        .data(Bytes::from(
            decode_hex_to_bytes(string_field(fixture_tx, "data")).expect("fixture tx data"),
        ))
        .value(decode_hex_to_u256(string_field(fixture_tx, "value")).expect("fixture tx value"))
        .gas_limit(parse_hex_u64(string_field(fixture_tx, "gasLimit")))
        .gas_price(parse_hex_u128(string_field(fixture_tx, "gasPrice")))
        .nonce(parse_hex_u64(string_field(fixture_tx, "nonce")))
        .build()
        .expect("fixture transaction");

    let execution_result = {
        let mut evm = Context::mainnet()
            .with_block(block_env(header))
            .with_db(&mut db)
            .modify_cfg_chained(|cfg| configure_fork_cfg(cfg, SpecId::ISTANBUL, false))
            .build_mainnet();
        evm.transact_commit(tx)
            .expect("EmptyDB execution is infallible")
    };

    ExecutedVector {
        result: extract_tx_result(execution_result).expect("fixture must not halt"),
        db,
        gas_remaining: None,
    }
}

fn execute_vm_case(case: &Value) -> ExecutedVector {
    let exec = &case["exec"];
    let mut db = load_pre_state(&case["pre"]);
    let caller = decode_hex_to_address(string_field(exec, "caller")).expect("fixture caller");

    let execution_gas = parse_hex_u64(string_field(exec, "gas"));
    let tx = TxEnv::builder()
        .caller(caller)
        .call(decode_hex_to_address(string_field(exec, "address")).expect("fixture address"))
        .data(Bytes::from(
            decode_hex_to_bytes(string_field(exec, "data")).expect("fixture input"),
        ))
        .value(decode_hex_to_u256(string_field(exec, "value")).expect("fixture value"))
        .gas_limit(execution_gas + TRANSACTION_INTRINSIC_GAS)
        .gas_price(parse_hex_u128(string_field(exec, "gasPrice")))
        .build()
        .expect("VM transaction adapter");
    let fixture_env = &case["env"];
    let env = BlockEnv {
        number: U256::from(parse_hex_u64(string_field(fixture_env, "currentNumber"))),
        beneficiary: decode_hex_to_address(string_field(fixture_env, "currentCoinbase"))
            .expect("fixture coinbase"),
        timestamp: U256::from(parse_hex_u64(string_field(fixture_env, "currentTimestamp"))),
        gas_limit: execution_gas + TRANSACTION_INTRINSIC_GAS,
        ..Default::default()
    };

    let execution_result = {
        let mut evm = Context::mainnet()
            .with_block(env)
            .with_db(&mut db)
            .modify_cfg_chained(|cfg| {
                configure_fork_cfg(cfg, SpecId::FRONTIER, true);
                cfg.disable_balance_check = true;
            })
            .build_mainnet();
        evm.transact_commit(tx)
            .expect("EmptyDB execution is infallible")
    };
    let result = extract_tx_result(execution_result).expect("fixture must not halt");
    let execution_gas_used = result
        .gas_used
        .checked_sub(TRANSACTION_INTRINSIC_GAS)
        .expect("transaction gas includes the intrinsic charge");

    ExecutedVector {
        gas_remaining: Some(execution_gas - execution_gas_used),
        result,
        db,
    }
}

fn state_mismatches(db: &TestDb, expected: &Value, compare_balances: bool) -> Vec<String> {
    let mut mismatches = Vec::new();

    for (address_hex, account) in expected.as_object().expect("post state must be an object") {
        let address = decode_hex_to_address(address_hex).expect("fixture address");
        let Some(info) = db.basic_ref(address).expect("EmptyDB lookup is infallible") else {
            mismatches.push(format!("{address_hex}: missing account"));
            continue;
        };

        if compare_balances {
            let expected_balance =
                decode_hex_to_u256(string_field(account, "balance")).expect("post balance");
            if info.balance != expected_balance {
                mismatches.push(format!(
                    "{address_hex}: balance expected {expected_balance:#x}, got {:#x}",
                    info.balance
                ));
            }
        }

        let expected_nonce = parse_hex_u64(string_field(account, "nonce"));
        if info.nonce != expected_nonce {
            mismatches.push(format!(
                "{address_hex}: nonce expected {expected_nonce}, got {}",
                info.nonce
            ));
        }

        let expected_code =
            decode_hex_to_bytes(string_field(account, "code")).expect("post bytecode");
        let actual_code = db
            .code_by_hash_ref(info.code_hash)
            .expect("EmptyDB code lookup is infallible")
            .original_bytes();
        if actual_code.as_ref() != expected_code {
            mismatches.push(format!("{address_hex}: bytecode mismatch"));
        }

        let expected_storage = account["storage"]
            .as_object()
            .expect("post storage must be an object");
        for (slot_hex, expected_value) in expected_storage {
            let slot = decode_hex_to_u256(slot_hex).expect("post storage slot");
            let expected_value = decode_hex_to_u256(
                expected_value
                    .as_str()
                    .expect("post storage value must be a string"),
            )
            .expect("post storage value");
            let actual = db
                .storage_ref(address, slot)
                .expect("EmptyDB storage lookup is infallible");
            if actual != expected_value {
                mismatches.push(format!(
                    "{address_hex}[{slot_hex}]: expected {expected_value:#x}, got {actual:#x}"
                ));
            }
        }

        if let Some(cached) = db.cache.accounts.get(&address) {
            for (slot, actual) in &cached.storage {
                let expected_slot = expected_storage.keys().any(|slot_hex| {
                    decode_hex_to_u256(slot_hex).expect("post storage slot") == *slot
                });
                if !expected_slot && !actual.is_zero() {
                    mismatches.push(format!(
                        "{address_hex}[{slot:#x}]: unexpected value {actual:#x}"
                    ));
                }
            }
        }
    }

    mismatches
}

fn rlp_len_bytes(len: usize) -> Vec<u8> {
    let bytes = len.to_be_bytes();
    bytes.into_iter().skip_while(|byte| *byte == 0).collect()
}

fn rlp_header(short_offset: u8, long_offset: u8, payload_len: usize) -> Vec<u8> {
    if payload_len <= 55 {
        vec![short_offset + payload_len as u8]
    } else {
        let len_bytes = rlp_len_bytes(payload_len);
        let mut header = vec![long_offset + len_bytes.len() as u8];
        header.extend_from_slice(&len_bytes);
        header
    }
}

fn rlp_bytes(bytes: &[u8]) -> Vec<u8> {
    if bytes.len() == 1 && bytes[0] < 0x80 {
        return bytes.to_vec();
    }
    let mut encoded = rlp_header(0x80, 0xb7, bytes.len());
    encoded.extend_from_slice(bytes);
    encoded
}

fn rlp_list(items: &[Vec<u8>]) -> Vec<u8> {
    let payload_len: usize = items.iter().map(Vec::len).sum();
    let mut encoded = rlp_header(0xc0, 0xf7, payload_len);
    for item in items {
        encoded.extend_from_slice(item);
    }
    encoded
}

fn vmtest_logs_hash(logs: &[LogEntry]) -> String {
    let encoded_logs: Vec<Vec<u8>> = logs
        .iter()
        .map(|log| {
            let topics = log
                .topics
                .iter()
                .map(|topic| rlp_bytes(&decode_hex_to_bytes(topic).expect("log topic")))
                .collect::<Vec<_>>();
            rlp_list(&[
                rlp_bytes(&decode_hex_to_bytes(&log.address).expect("log address")),
                rlp_list(&topics),
                rlp_bytes(&decode_hex_to_bytes(&log.data).expect("log data")),
            ])
        })
        .collect();
    bytes_to_hex(alloy_primitives::keccak256(rlp_list(&encoded_logs)).as_slice())
}

fn declared_vmtest_keys(case: &Value) -> Vec<&'static str> {
    VMTEST_ORACLE_KEYS
        .into_iter()
        .filter(|key| case.get(*key).is_some())
        .collect()
}

fn vm_mismatches(executed: &ExecutedVector, case: &Value) -> Vec<String> {
    let mut mismatches = Vec::new();

    for key in declared_vmtest_keys(case) {
        match key {
            "out" => {
                let expected = canonical_hex(string_field(case, "out"));
                if executed.result.output != expected {
                    mismatches.push(format!(
                        "out: expected {expected}, got {}",
                        executed.result.output
                    ));
                }
            }
            "gas" => {
                let expected = parse_hex_u64(string_field(case, "gas"));
                match executed.gas_remaining {
                    Some(actual) if actual == expected => {}
                    Some(actual) => {
                        mismatches.push(format!("gas: expected {expected:#x}, got {actual:#x}"))
                    }
                    None => mismatches.push("gas: remaining gas was not recorded".into()),
                }
            }
            "logs" => {
                let expected = canonical_hex(string_field(case, "logs"));
                let actual = vmtest_logs_hash(&executed.result.logs);
                if actual != expected {
                    mismatches.push(format!("logs: expected {expected}, got {actual}"));
                }
            }
            "post" => {
                mismatches.extend(state_mismatches(&executed.db, &case["post"], false));
            }
            other => panic!("unhandled VMTEST oracle key {other}"),
        }
    }

    mismatches
}

fn assert_vm_vector(source: &str, case_name: &str) {
    let fixture = parse_json(source);
    let case = named_case(&fixture, case_name);
    assert_eq!(
        declared_vmtest_keys(case).as_slice(),
        &VMTEST_ORACLE_KEYS,
        "{case_name} must declare every KEVM VMTEST key so the comparator cannot under-assert"
    );
    let executed = execute_vm_case(case);
    assert!(executed.result.success, "{case_name} status");
    assert_eq!(
        vm_mismatches(&executed, case),
        Vec::<String>::new(),
        "{case_name} oracle keys"
    );
}

fn assert_blockchain_vector(source: &str, case_name: &str, success: bool, output: &str) {
    let fixture = parse_json(source);
    let case = named_case(&fixture, case_name);
    let executed = execute_blockchain_case(case);
    let header = &case["blocks"][0]["blockHeader"];
    let beneficiary = string_field(header, "coinbase");
    let mut expected_post = case["postState"].clone();
    expected_post
        .as_object_mut()
        .expect("postState object")
        .remove(beneficiary);

    assert_eq!(executed.result.success, success, "{case_name} status");
    assert_eq!(executed.result.output, output, "{case_name} output");
    assert_eq!(
        executed.result.gas_used,
        parse_hex_u64(string_field(header, "gasUsed")),
        "{case_name} gas"
    );
    assert!(executed.result.logs.is_empty(), "{case_name} logs");
    assert_eq!(
        state_mismatches(&executed.db, &expected_post, true),
        Vec::<String>::new(),
        "{case_name} post-state"
    );
}

fn assert_create_transaction_vector(source: &str, case_name: &str, success: bool, output: &str) {
    let fixture = parse_json(source);
    let case = named_case(&fixture, case_name);
    assert_eq!(
        string_field(&case["blocks"][0]["transactions"][0], "to"),
        "",
        "{case_name} must be a top-level create transaction"
    );
    assert_blockchain_vector(source, case_name, success, output);
}

#[test]
fn revm_matches_official_blockchain_vectors() {
    assert_blockchain_vector(BLOCK_CALL, "callOutput1_d0g0v0_Istanbul", true, "0x");
    assert_blockchain_vector(
        BLOCK_CREATE,
        "CREATE_EmptyContractWithStorage_d0g0v0_Istanbul",
        true,
        "0x",
    );
    assert_create_transaction_vector(
        BLOCK_CREATE_TX,
        "CREATE_empty000CreateinInitCode_Transaction_d0g0v0_Istanbul",
        true,
        "0x",
    );
    assert_blockchain_vector(BLOCK_REVERT, "RevertOpcode_d0g0v0_Istanbul", false, "0x00");
}

#[test]
fn revm_matches_official_vm_storage_log_and_gas_vectors() {
    assert_vm_vector(VM_SSTORE, "sstore_load_1");
    assert_vm_vector(VM_LOG, "log1_nonEmptyMem");
}

#[test]
fn vm_assertion_set_is_derived_from_the_fixture() {
    let fixture = parse_json(VM_LOG);
    let case = named_case(&fixture, "log1_nonEmptyMem");
    assert_eq!(declared_vmtest_keys(case).as_slice(), &VMTEST_ORACLE_KEYS);

    let mut truncated = case.clone();
    truncated
        .as_object_mut()
        .expect("vm case object")
        .remove("out");
    assert_eq!(
        declared_vmtest_keys(&truncated),
        ["gas", "logs", "post"],
        "assertion set must follow the fixture, not a per-case list"
    );

    let executed = execute_vm_case(case);
    let mut corrupted_out = truncated.clone();
    corrupted_out["out"] = Value::String("0x00".into());
    assert!(
        vm_mismatches(&executed, &truncated)
            .iter()
            .all(|mismatch| !mismatch.starts_with("out:")),
        "undeclared out must not be checked"
    );
    assert!(
        vm_mismatches(&executed, &corrupted_out)
            .iter()
            .any(|mismatch| mismatch.starts_with("out:")),
        "declaring out must check it"
    );
}

#[test]
fn corrupted_storage_control_is_rejected() {
    let official_fixture = parse_json(VM_SSTORE);
    let official = named_case(&official_fixture, "sstore_load_1");
    let executed = execute_vm_case(official);
    let bad_fixture = parse_json(VM_SSTORE_BAD);
    let corrupted_post = &named_case(&bad_fixture, "sstore_load_1")["post"];
    let mismatches = state_mismatches(&executed.db, corrupted_post, false);

    assert_eq!(
        mismatches.len(),
        1,
        "unexpected comparator result: {mismatches:?}"
    );
    assert!(mismatches[0].contains("expected 0xfe, got 0xff"));
}

#[test]
fn corrupted_out_and_post_are_rejected() {
    let official_fixture = parse_json(VM_LOG);
    let official = named_case(&official_fixture, "log1_nonEmptyMem");
    let executed = execute_vm_case(official);

    let mut bad_out = official.clone();
    bad_out["out"] = Value::String("0x00".into());
    let out_mismatches = vm_mismatches(&executed, &bad_out);
    assert!(
        out_mismatches
            .iter()
            .any(|mismatch| mismatch.contains("out: expected 0x00, got 0x")),
        "corrupted out must fail: {out_mismatches:?}"
    );

    let mut bad_post = official.clone();
    bad_post["post"]["0x0f572e5295c57f15886f9b263e2f6d2d6c7b5ec6"]["nonce"] =
        Value::String("0x01".into());
    let post_mismatches = vm_mismatches(&executed, &bad_post);
    assert!(
        post_mismatches
            .iter()
            .any(|mismatch| mismatch.contains("nonce expected 1, got 0")),
        "corrupted post must fail: {post_mismatches:?}"
    );
}

#[test]
fn ledger_pins_fixtures_bytecode_and_tool_versions() {
    let ledger = parse_json(LEDGER);
    assert_eq!(ledger["schema"], 1);
    assert_eq!(ledger["tools"]["revm"], "42.0.1");
    assert_eq!(ledger["tools"]["revm_database"], "42.0.0");
    assert!(include_str!("../Cargo.lock").contains("name = \"revm\"\nversion = \"42.0.1\""));

    for entry in ledger["vectors"].as_array().expect("ledger vectors") {
        let id = string_field(entry, "id");
        let source = match id {
            "call-output-1" => BLOCK_CALL,
            "create-empty-contract-with-storage" => BLOCK_CREATE,
            "create-empty000-create-in-initcode-transaction" => BLOCK_CREATE_TX,
            "revert-opcode" => BLOCK_REVERT,
            "log1-non-empty-mem" => VM_LOG,
            "sstore-load-1" => VM_SSTORE,
            other => panic!("unknown ledger vector {other}"),
        };
        assert_eq!(
            bytes_to_hex(alloy_primitives::keccak256(source.as_bytes()).as_slice()),
            string_field(entry, "fixture_keccak256"),
            "{id} fixture hash"
        );

        let fixture = parse_json(source);
        let case = named_case(&fixture, string_field(entry, "case"));
        assert_eq!(
            entry["filler_source_hash"], case["_info"]["sourceHash"],
            "{id} filler provenance"
        );
        assert_eq!(entry["revm"], "pass", "{id} revm outcome");
        assert_eq!(entry["kevm"], "pass", "{id} KEVM outcome");
        assert!(!string_field(entry, "configuration").is_empty());

        let checked: Vec<&str> = entry["checked_keys"]
            .as_array()
            .unwrap_or_else(|| panic!("{id} checked_keys"))
            .iter()
            .map(|key| key.as_str().expect("checked key string"))
            .collect();
        match string_field(entry, "oracle_mode") {
            "VMTESTS" => {
                assert_eq!(checked, VMTEST_ORACLE_KEYS, "{id} VMTEST key set");
                assert_eq!(
                    checked,
                    declared_vmtest_keys(case),
                    "{id} ledger keys must match the fixture-derived set"
                );
            }
            "NORMAL" => {
                assert_eq!(checked, BLOCKCHAIN_CHECKED_KEYS, "{id} blockchain key set");
            }
            other => panic!("{id} unknown oracle_mode {other}"),
        }

        assert_eq!(
            bytes_to_hex(
                alloy_primitives::keccak256(
                    serde_json::to_vec(&case["pre"]).expect("serialize fixture pre-state")
                )
                .as_slice()
            ),
            string_field(entry, "initial_state_keccak256"),
            "{id} initial-state hash"
        );

        for (address, expected_hash) in entry["bytecode_keccak256"]
            .as_object()
            .expect("bytecode hash object")
        {
            let code = string_field(&case["pre"][address], "code");
            assert_eq!(
                bytes_to_hex(
                    alloy_primitives::keccak256(
                        decode_hex_to_bytes(code).expect("ledger bytecode")
                    )
                    .as_slice()
                ),
                expected_hash.as_str().expect("bytecode hash string"),
                "{id} bytecode at {address}"
            );
        }
    }

    assert_eq!(ledger["negative_control"]["observed"], "expected failure");
}
