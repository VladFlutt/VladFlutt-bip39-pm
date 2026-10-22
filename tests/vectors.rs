use std::str::FromStr;

use bip39_pm::derive::{bip85_entropy_from_xprv, BIP85_PURPOSE};
use bip39_pm::{AppKey, Policy, Site};

const ABANDON: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

/// Официальный тестовый вектор BIP85, случай 1.
#[test]
fn bip85_official_vector() {
    let master = bip32::XPrv::from_str(
        "xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb",
    )
    .unwrap();
    let entropy = bip85_entropy_from_xprv(master, &[BIP85_PURPOSE, 0, 0]).unwrap();
    assert_eq!(
        hex::encode(entropy.as_ref()),
        "efecfbccffea313214232d29e71563d941229afb4338c21f9517c41aaa0d16f00b83d2a09ef747e7a64e8e2bd5a14869e693da66ce94ac2da570ab7ee48618f7"
    );
}

fn key() -> AppKey {
    AppKey::from_mnemonic(ABANDON, "").unwrap()
}

/// Замороженные векторы спецификации v1. Если тест падает — изменился
/// алгоритм, и у пользователей поменяются пароли.
#[test]
fn spec_v1_vectors() {
    let k = key();
    assert_eq!(k.fingerprint(), "era-primary-finish");
    let cases = [
        (
            "github.com",
            "vlad@mail.ru",
            1,
            Policy::default(),
            "q~9Tlw:qOyeSzu?69AUx",
            "amused-liquid",
        ),
        (
            "github.com",
            "vlad@mail.ru",
            2,
            Policy::default(),
            "eITvMChQRH+*gVT-n4FJ",
            "marble-clarify",
        ),
        (
            "github.com",
            "other@mail.ru",
            1,
            Policy::default(),
            "l4nhKOQY$x$E85uidyw4",
            "consider-glow",
        ),
        (
            "bank.ru",
            "vlad",
            1,
            Policy {
                length: 16,
                symbols: false,
                ..Policy::default()
            },
            "oh1fWuHJh2e3emF0",
            "change-want",
        ),
        (
            "xn--e1afmkfd.xn--p1ai",
            "vlad",
            1,
            Policy {
                length: 8,
                lower: false,
                upper: false,
                symbols: false,
                ..Policy::default()
            },
            "48777879",
            "topple-seminar",
        ),
    ];
    for (domain, login, counter, policy, password, check) in cases {
        let site = Site::new(domain, login, counter).unwrap();
        assert_eq!(
            k.password(&site, &policy).unwrap().as_str(),
            password,
            "{domain} {login} {counter}"
        );
        assert_eq!(k.check_words(&site, &policy), check);
    }
}

/// Тот же аккаунт, записанный по-разному, даёт тот же пароль.
#[test]
fn same_account_different_spelling() {
    let k = key();
    let p = Policy::default();
    let a = k
        .password(
            &Site::new("https://www.GitHub.com/login?x=1", "  Vlad@Mail.RU ", 1).unwrap(),
            &p,
        )
        .unwrap();
    let b = k
        .password(&Site::new("github.com", "vlad@mail.ru", 1).unwrap(), &p)
        .unwrap();
    assert_eq!(a, b);
}

#[test]
fn passphrase_changes_everything() {
    let a = AppKey::from_mnemonic(ABANDON, "").unwrap();
    let b = AppKey::from_mnemonic(ABANDON, "TREZOR").unwrap();
    assert_ne!(a.fingerprint(), b.fingerprint());
    let s = Site::new("github.com", "vlad", 1).unwrap();
    assert_ne!(
        a.password(&s, &Policy::default()).unwrap(),
        b.password(&s, &Policy::default()).unwrap()
    );
}

#[test]
fn bad_checksum_rejected() {
    let bad = ABANDON.replace("about", "abandon");
    assert!(AppKey::from_mnemonic(&bad, "").is_err());
}

#[test]
fn mnemonic_whitespace_and_case_tolerated() {
    let messy = format!("  {}  ", ABANDON.to_uppercase().replace(' ', "   "));
    assert_eq!(
        AppKey::from_mnemonic(&messy, "").unwrap().fingerprint(),
        key().fingerprint()
    );
}
