//! Другие секреты из той же фразы: PIN-коды, кодовые слова, пароли Wi‑Fi, ключи SSH.
//!
//! Секрет — функция от `(k_app, вид, метка, счётчик)`, как и пароль сайта, но с
//! отдельным HKDF info, поэтому пароли сайтов не меняются. Алгоритм — SPEC.md, раздел 10.

use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::derive::AppKey;
use crate::policy::{ByteStream, Policy, DIGITS};
use crate::{normalize, Error, Result};

const INFO_SECRET: &[u8] = b"bip39-pm/v1/secret";
const INFO_STREAM: &[u8] = b"bip39-pm/v1/stream";
const STREAM_LEN: usize = 1024;

/// Вид секрета и его параметры.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum SecretKind {
    /// Цифровой код, 4..=12 цифр.
    Pin { length: u8 },
    /// Слова BIP39 через пробел (кодовое слово, ответ на секретный вопрос), 3..=8 слов.
    Words { count: u8 },
    /// Пароль Wi‑Fi: буквы и цифры, без символов (удобно вводить на телевизоре), 12..=63.
    Wifi { length: u8 },
    /// Ключ SSH Ed25519.
    Ssh,
}

impl SecretKind {
    pub fn validate(&self) -> Result<()> {
        let (v, range, what) = match *self {
            SecretKind::Pin { length } => (length, 4..=12, "длина PIN"),
            SecretKind::Words { count } => (count, 3..=8, "число слов"),
            SecretKind::Wifi { length } => (length, 12..=63, "длина пароля Wi‑Fi"),
            SecretKind::Ssh => return Ok(()),
        };
        if !range.contains(&v) {
            return Err(Error::Policy(format!(
                "{what} {v} вне диапазона {}..={}",
                range.start(),
                range.end()
            )));
        }
        Ok(())
    }

    /// Каноническая строка; входит в HKDF info, формат заморожен.
    pub fn canonical(&self) -> String {
        match *self {
            SecretKind::Pin { length } => format!("pin;len={length}"),
            SecretKind::Words { count } => format!("words;n={count}"),
            SecretKind::Wifi { length } => format!("wifi;len={length}"),
            SecretKind::Ssh => "ssh-ed25519".into(),
        }
    }
}

/// Вычисленный секрет.
pub struct Secret {
    /// PIN, слова, пароль или закрытый ключ SSH в формате OpenSSH.
    pub value: Zeroizing<String>,
    /// Открытый ключ SSH (`ssh-ed25519 AAAA… метка`), для остальных видов `None`.
    pub public: Option<String>,
}

impl AppKey {
    /// `k_secret` = HKDF(k_app, "bip39-pm/v1/secret" ‖ lp(вид) ‖ lp(метка) ‖ u32be(счётчик)).
    fn secret_key(&self, kind: &SecretKind, label: &str, counter: u32) -> Zeroizing<[u8; 32]> {
        let mut info = INFO_SECRET.to_vec();
        for field in [kind.canonical().as_bytes(), label.as_bytes()] {
            info.extend_from_slice(&(field.len() as u32).to_be_bytes());
            info.extend_from_slice(field);
        }
        info.extend_from_slice(&counter.to_be_bytes());
        self.hkdf_32(&info)
    }

    /// Секрет по метке (метка нормализуется как логин: NFKC, пробелы, регистр).
    pub fn secret(&self, kind: &SecretKind, label: &str, counter: u32) -> Result<Secret> {
        kind.validate()?;
        if counter == 0 {
            return Err(Error::Derivation("счётчик начинается с 1".into()));
        }
        let label = normalize::login(label);
        if label.is_empty() {
            return Err(Error::Derivation("пустая метка".into()));
        }
        let k = self.secret_key(kind, &label, counter);
        let stream = || {
            let mut buf = vec![0u8; STREAM_LEN];
            Hkdf::<Sha256>::from_prk(k.as_ref())
                .expect("32-byte PRK")
                .expand(INFO_STREAM, &mut buf)
                .expect("output length within HKDF limit");
            ByteStream::new(buf)
        };
        let value = match *kind {
            SecretKind::Pin { length } => {
                let digits: Vec<char> = DIGITS.chars().collect();
                let mut s = stream();
                let mut pin = String::with_capacity(length as usize);
                for _ in 0..length {
                    pin.push(digits[s.uniform(10)?]);
                }
                pin
            }
            SecretKind::Words { count } => {
                let list = bip39::Language::English.word_list();
                let mut s = stream();
                let mut words = Vec::with_capacity(count as usize);
                for _ in 0..count {
                    words.push(list[s.bits11()?]);
                }
                words.join(" ")
            }
            SecretKind::Wifi { length } => Policy {
                length,
                lower: true,
                upper: true,
                digits: true,
                symbols: false,
            }
            .encode(&mut stream())?,
            SecretKind::Ssh => return ssh(&k, &label),
        };
        Ok(Secret {
            value: Zeroizing::new(value),
            public: None,
        })
    }
}

fn ssh(seed: &[u8; 32], label: &str) -> Result<Secret> {
    use ssh_key::private::{Ed25519Keypair, KeypairData, PrivateKey};
    let err = |e: ssh_key::Error| Error::Derivation(format!("ключ SSH: {e}"));
    let pair = Ed25519Keypair::from_seed(seed);
    // Без явного checkint ssh-key выводит его из ключа, поэтому файл детерминирован.
    let key = PrivateKey::new(KeypairData::Ed25519(pair), label).map_err(err)?;
    let private = key.to_openssh(ssh_key::LineEnding::LF).map_err(err)?;
    let public = key.public_key().to_openssh().map_err(err)?;
    Ok(Secret {
        value: Zeroizing::new(private.as_str().to_owned()),
        public: Some(public),
    })
}
