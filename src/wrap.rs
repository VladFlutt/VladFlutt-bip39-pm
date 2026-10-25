//! Ключ, закрытый кодом: так хранятся скрытые профили приложения.
//!
//! Формат: `PMKW` | версия | соль (16) | nonce (24) | XChaCha20-Poly1305(секрет).
//! Ключ шифрования — PBKDF2-HMAC-SHA512(NFKC(код), соль, 210 000 итераций).

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use sha2::Sha512;
use unicode_normalization::UnicodeNormalization;
use zeroize::Zeroizing;

use crate::{Error, Result};

const MAGIC: &[u8; 4] = b"PMKW";
const VERSION: u8 = 1;
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 24;
const HEAD_LEN: usize = 5 + SALT_LEN;
/// OWASP 2023 для PBKDF2-HMAC-SHA512.
const ROUNDS: u32 = 210_000;

fn kdf(code: &str, salt: &[u8]) -> Zeroizing<[u8; 32]> {
    let code = Zeroizing::new(code.nfkc().collect::<String>());
    let mut k = Zeroizing::new([0u8; 32]);
    pbkdf2::pbkdf2_hmac::<Sha512>(code.as_bytes(), salt, ROUNDS, k.as_mut());
    k
}

fn err(m: &str) -> Error {
    Error::Derivation(m.to_string())
}

/// Закрыть секрет кодом.
pub fn wrap(secret: &[u8], code: &str) -> Result<Vec<u8>> {
    if code.trim().is_empty() {
        return Err(err("пустой код"));
    }
    let mut salt_nonce = [0u8; SALT_LEN + NONCE_LEN];
    getrandom::getrandom(&mut salt_nonce).map_err(|e| err(&e.to_string()))?;
    let (salt, nonce) = salt_nonce.split_at(SALT_LEN);
    let mut out = Vec::with_capacity(HEAD_LEN + NONCE_LEN + secret.len() + 16);
    out.extend_from_slice(MAGIC);
    out.push(VERSION);
    out.extend_from_slice(salt);
    let ct = XChaCha20Poly1305::new(kdf(code, salt).as_ref().into())
        .encrypt(
            XNonce::from_slice(nonce),
            Payload {
                msg: secret,
                aad: &out,
            },
        )
        .map_err(|_| err("ошибка шифрования"))?;
    out.extend_from_slice(nonce);
    out.extend_from_slice(&ct);
    Ok(out)
}

/// Открыть секрет кодом. Неверный код и повреждённые данные неразличимы.
pub fn unwrap(blob: &[u8], code: &str) -> Result<Zeroizing<Vec<u8>>> {
    if blob.len() < HEAD_LEN + NONCE_LEN + 16 || &blob[..4] != MAGIC || blob[4] != VERSION {
        return Err(err("неизвестный формат"));
    }
    let (head, rest) = blob.split_at(HEAD_LEN);
    let (nonce, ct) = rest.split_at(NONCE_LEN);
    let plain = XChaCha20Poly1305::new(kdf(code, &head[5..]).as_ref().into())
        .decrypt(XNonce::from_slice(nonce), Payload { msg: ct, aad: head })
        .map_err(|_| err("неверный код"))?;
    Ok(Zeroizing::new(plain))
}
