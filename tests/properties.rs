use bip39_pm::policy::{DIGITS, LOWER, SYMBOLS, UPPER};
use bip39_pm::{normalize, AppKey, Entry, Index, Policy, Site};

fn key() -> AppKey {
    AppKey::from_mnemonic(
        "legal winner thank year wave sausage worth useful legal winner thank yellow",
        "",
    )
    .unwrap()
}

#[test]
fn passwords_satisfy_policy() {
    let k = key();
    let policies = [
        Policy::default(),
        Policy {
            length: 8,
            ..Policy::default()
        },
        Policy {
            length: 64,
            ..Policy::default()
        },
        Policy {
            length: 12,
            symbols: false,
            ..Policy::default()
        },
        Policy {
            length: 10,
            lower: false,
            upper: false,
            symbols: false,
            ..Policy::default()
        },
        Policy {
            length: 16,
            digits: false,
            symbols: false,
            ..Policy::default()
        },
    ];
    for policy in policies {
        for i in 0..300 {
            let site = Site::new(&format!("site{i}.com"), "user", 1).unwrap();
            let pw = k.password(&site, &policy).unwrap();
            assert_eq!(pw.chars().count(), policy.length as usize);
            for (on, set) in [
                (policy.lower, LOWER),
                (policy.upper, UPPER),
                (policy.digits, DIGITS),
                (policy.symbols, SYMBOLS),
            ] {
                let has = pw.chars().any(|c| set.contains(c));
                assert_eq!(has, on, "{} {:?}", pw.as_str(), policy);
            }
        }
    }
}

#[test]
fn invalid_policies_rejected() {
    let k = key();
    let s = Site::new("a.com", "u", 1).unwrap();
    assert!(k
        .password(
            &s,
            &Policy {
                length: 7,
                ..Policy::default()
            }
        )
        .is_err());
    assert!(k
        .password(
            &s,
            &Policy {
                length: 65,
                ..Policy::default()
            }
        )
        .is_err());
    let none = Policy {
        lower: false,
        upper: false,
        digits: false,
        symbols: false,
        ..Policy::default()
    };
    assert!(k.password(&s, &none).is_err());
    assert!(Site::new("a.com", "u", 0).is_err());
}

#[test]
fn domain_normalization() {
    for (input, want) in [
        ("github.com", "github.com"),
        ("https://www.GitHub.com/login", "github.com"),
        ("gist.github.com", "github.com"),
        ("accounts.google.com", "google.com"),
        ("www.youtube.com", "google.com"),
        ("mail.yandex.ru", "yandex.ru"),
        ("foo.bar.co.uk", "bar.co.uk"),
        ("user.github.io", "user.github.io"),
        ("пример.рф", "xn--e1afmkfd.xn--p1ai"),
        ("http://192.168.1.1:8080/admin", "192.168.1.1"),
        ("example.com.", "example.com"),
    ] {
        assert_eq!(normalize::domain(input).unwrap(), want, "{input}");
    }
    assert!(normalize::domain("   ").is_err());
}

#[test]
fn login_normalization() {
    assert_eq!(normalize::login("  Vlad@Mail.RU "), "vlad@mail.ru");
    assert_eq!(normalize::login("ＶＬＡＤ"), "vlad"); // полноширинные символы → NFKC
}

#[test]
fn index_roundtrip_and_wrong_key() {
    let k = key();
    let mut idx = Index::default();
    idx.upsert(Entry {
        domain: "b.com".into(),
        login: "u".into(),
        counter: 1,
        policy: Policy::default(),
        note: None,
    });
    idx.upsert(Entry {
        domain: "a.com".into(),
        login: "u".into(),
        counter: 3,
        policy: Policy::default(),
        note: Some("pin".into()),
    });
    idx.upsert(Entry {
        domain: "b.com".into(),
        login: "u".into(),
        counter: 2,
        policy: Policy::default(),
        note: None,
    });
    assert_eq!(idx.entries.len(), 2);
    assert_eq!(idx.entries[0].domain, "a.com");
    assert_eq!(idx.find("b.com", "u").unwrap().counter, 2);

    let blob = idx.encrypt(&k.index_key()).unwrap();
    assert_eq!(Index::decrypt(&blob, &k.index_key()).unwrap(), idx);
    // Два шифрования одного индекса различаются (случайный nonce).
    assert_ne!(blob, idx.encrypt(&k.index_key()).unwrap());

    let other = AppKey::from_mnemonic(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        "",
    )
    .unwrap();
    assert!(Index::decrypt(&blob, &other.index_key()).is_err());

    let mut tampered = blob.clone();
    *tampered.last_mut().unwrap() ^= 1;
    assert!(Index::decrypt(&tampered, &k.index_key()).is_err());
}
