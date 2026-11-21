use bip39_pm::{transfer, AppKey, Entry, Index, Policy};

const PHRASE: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

fn account(password: Option<&str>, counter: u32) -> Entry {
    Entry {
        domain: "example.com".into(),
        login: "user".into(),
        counter,
        policy: Policy::default(),
        note: Some("work account".into()),
        custom_password: password.map(str::to_owned),
    }
}

#[test]
fn custom_password_is_encrypted_and_survives_transfer() {
    let key = AppKey::from_mnemonic(PHRASE, "").unwrap();
    let password = "  My own 🔑 пароль\nWith Spaces  ";
    let mut index = Index::default();
    index.upsert(account(Some(password), 2));
    let blob = index.encrypt(&key.index_key()).unwrap();
    assert_eq!(blob[4], 2);
    assert!(!blob
        .windows(password.len())
        .any(|w| w == password.as_bytes()));
    assert_eq!(Index::decrypt(&blob, &key.index_key()).unwrap(), index);
    assert!(Index::decrypt(&blob, &[42; 32]).is_err());
    let code = transfer::export_text(&index, &key).unwrap();
    assert_eq!(transfer::import_text(&code, &key).unwrap(), index);
    let mut tampered = blob;
    tampered[4] = 1;
    assert!(Index::decrypt(&tampered, &key.index_key()).is_err());
}

#[test]
fn generated_accounts_keep_v1_and_old_json_is_readable() {
    let legacy = r#"{"entries":[{"domain":"example.com","login":"user","counter":1,"policy":{"length":20,"lower":true,"upper":true,"digits":true,"symbols":true}}]}"#;
    let index: Index = serde_json::from_str(legacy).unwrap();
    assert_eq!(index.entries[0].custom_password, None);
    let blob = index.encrypt(&[9; 32]).unwrap();
    assert_eq!(blob[4], 1);
    assert_eq!(Index::decrypt(&blob, &[9; 32]).unwrap(), index);
}

#[test]
fn merge_preserves_custom_values_and_can_return_to_generated() {
    let mut local = Index::default();
    local.upsert(account(None, 1));
    let mut incoming = Index::default();
    incoming.upsert(account(Some("first"), 2));
    assert_eq!(local.merge(incoming.clone()).updated, 1);
    assert_eq!(local.entries[0].custom_password.as_deref(), Some("first"));
    incoming.upsert(account(Some("changed"), 3));
    assert_eq!(local.merge(incoming.clone()).updated, 1);
    assert_eq!(local.entries[0].custom_password.as_deref(), Some("changed"));
    incoming.upsert(account(None, 4));
    local.merge(incoming);
    assert_eq!(local.entries[0].custom_password, None);
    assert_eq!(local.encrypt(&[9; 32]).unwrap()[4], 1);
}
