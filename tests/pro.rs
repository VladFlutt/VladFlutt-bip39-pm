use bip39_pm::index::{SecretEntry, Template};
use bip39_pm::{transfer, wrap, AppKey, Entry, Index, Policy, SecretKind};

const ABANDON: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

fn key() -> AppKey {
    AppKey::from_mnemonic(ABANDON, "").unwrap()
}

/// Замороженные векторы секретов (SPEC.md, раздел 10). PIN, слова и Wi‑Fi сверены
/// с `reference/pm_ref.py`.
#[test]
fn secret_vectors() {
    let k = key();
    let cases = [
        (SecretKind::Pin { length: 4 }, "карта", "5987"),
        (SecretKind::Pin { length: 6 }, " Карта Сбер ", "936802"),
        (
            SecretKind::Words { count: 4 },
            "secret question",
            "rice trade budget staff",
        ),
        (
            SecretKind::Wifi { length: 20 },
            "home wifi",
            "1w2hnpKJyh93chs4N61a",
        ),
    ];
    for (kind, label, want) in cases {
        let s = k.secret(&kind, label, 1).unwrap();
        assert_eq!(s.value.as_str(), want, "{kind:?} {label}");
        assert!(s.public.is_none());
    }
    let ssh = k.secret(&SecretKind::Ssh, "GitHub Laptop", 1).unwrap();
    assert_eq!(
        ssh.public.as_deref(),
        Some("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJv18B347hIuVqi6ZQ6S6DHpx082zNUl7P3W8NcYfnQT github laptop")
    );
    assert!(ssh
        .value
        .starts_with("-----BEGIN OPENSSH PRIVATE KEY-----\n"));
    let again = k.secret(&SecretKind::Ssh, "github laptop", 1).unwrap();
    assert_eq!(ssh.value.as_str(), again.value.as_str());
}

#[test]
fn secrets_differ_by_kind_label_counter() {
    let k = key();
    let pin = |label: &str, c: u32| {
        k.secret(&SecretKind::Pin { length: 12 }, label, c)
            .unwrap()
            .value
            .to_string()
    };
    assert_ne!(pin("a", 1), pin("b", 1));
    assert_ne!(pin("a", 1), pin("a", 2));
    let six = k.secret(&SecretKind::Pin { length: 6 }, "a", 1).unwrap();
    assert_ne!(&pin("a", 1)[..6], six.value.as_str());
}

#[test]
fn secret_validation() {
    let k = key();
    for kind in [
        SecretKind::Pin { length: 3 },
        SecretKind::Pin { length: 13 },
        SecretKind::Words { count: 2 },
        SecretKind::Words { count: 9 },
        SecretKind::Wifi { length: 11 },
        SecretKind::Wifi { length: 64 },
    ] {
        assert!(k.secret(&kind, "x", 1).is_err(), "{kind:?}");
    }
    assert!(k.secret(&SecretKind::Ssh, "  ", 1).is_err());
    assert!(k.secret(&SecretKind::Ssh, "x", 0).is_err());
}

fn sample() -> Index {
    Index {
        entries: vec![Entry {
            domain: "github.com".into(),
            login: "vlad".into(),
            counter: 2,
            policy: Policy::default(),
            note: None,
        }],
        secrets: vec![SecretEntry {
            label: "карта".into(),
            kind: SecretKind::Pin { length: 4 },
            counter: 1,
            note: None,
        }],
        templates: vec![Template {
            name: "Банк".into(),
            policy: Policy {
                length: 16,
                symbols: false,
                ..Policy::default()
            },
        }],
        default_policy: Some(Policy {
            length: 24,
            ..Policy::default()
        }),
    }
}

#[test]
fn transfer_roundtrip() {
    let k = key();
    let code = transfer::export_text(&sample(), &k).unwrap();
    assert!(code.starts_with("PMX1:"));
    let spaced: String = code
        .chars()
        .enumerate()
        .flat_map(|(i, c)| (i % 40 == 39).then_some('\n').into_iter().chain([c]))
        .collect();
    assert_eq!(transfer::import_text(&spaced, &k).unwrap(), sample());

    let other = AppKey::from_mnemonic(ABANDON, "другая").unwrap();
    assert!(transfer::import_text(&code, &other).is_err());
    assert!(transfer::import_text("PMX1:!!!", &k).is_err());
    assert!(transfer::import_text("hello", &k).is_err());
}

#[test]
fn old_index_json_still_reads() {
    let json = r#"{"entries":[{"domain":"a.ru","login":"x","counter":1,
        "policy":{"length":20,"lower":true,"upper":true,"digits":true,"symbols":true}}]}"#;
    let idx: Index = serde_json::from_str(json).unwrap();
    assert_eq!(idx.entries.len(), 1);
    assert!(idx.secrets.is_empty() && idx.templates.is_empty() && idx.default_policy.is_none());
    // Пустые новые поля не пишутся: старые версии `pm` читают файл как раньше.
    assert!(!serde_json::to_string(&idx).unwrap().contains("secrets"));
}

#[test]
fn merge_rules() {
    let mut local = sample();
    local.entries[0].counter = 3;
    local.default_policy = None;
    let mut incoming = sample();
    incoming.entries.push(Entry {
        domain: "bank.ru".into(),
        login: "vlad".into(),
        counter: 1,
        policy: Policy::default(),
        note: None,
    });
    incoming.secrets[0].counter = 5;
    incoming.secrets[0].label = "Карта".into();
    incoming.templates.push(Template {
        name: "Короткий".into(),
        policy: Policy {
            length: 12,
            ..Policy::default()
        },
    });
    let r = local.merge(incoming);
    assert_eq!((r.added, r.updated, r.kept), (2, 1, 2));
    assert_eq!(local.entries.len(), 2);
    assert_eq!(local.find("github.com", "vlad").unwrap().counter, 3);
    assert_eq!(local.secrets.len(), 1);
    assert_eq!(local.secrets[0].counter, 5);
    assert_eq!(local.templates.len(), 2);
    assert_eq!(local.default_policy.unwrap().length, 24);
}

#[test]
fn wrap_roundtrip() {
    let secret = [42u8; 32];
    let blob = wrap::wrap(&secret, "1234").unwrap();
    assert_eq!(wrap::unwrap(&blob, "1234").unwrap().as_slice(), &secret);
    assert!(wrap::unwrap(&blob, "1235").is_err());
    assert_ne!(
        blob,
        wrap::wrap(&secret, "1234").unwrap(),
        "соль и nonce случайные"
    );
    assert!(wrap::wrap(&secret, " ").is_err());
    let mut broken = blob.clone();
    *broken.last_mut().unwrap() ^= 1;
    assert!(wrap::unwrap(&broken, "1234").is_err());
}
