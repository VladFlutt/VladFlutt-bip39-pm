//! Вход по логину и мастер-паролю: `k_app`, зашифрованный на устройстве.
//!
//! Seed-фраза при этом не хранится, только производный `k_app`. Формат:
//! `PMVT` | версия (1) | m_kib, t, p (u32 BE) | соль (16) | nonce (24) |
//! XChaCha20-Poly1305(k_app). Ключ — Argon2id(мастер-пароль, соль).
//! Associated data — заголовок до nonce и нормализованный логин, поэтому
//! блоб нельзя переложить под другой логин или ослабить параметры KDF.

use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use unicode_normalization::UnicodeNormalization;
use zeroize::Zeroizing;

use crate::{normalize, AppKey, Error, Result};

const MAGIC: &[u8; 4] = b"PMVT";
const VERSION: u8 = 1;
pub const SALT_LEN: usize = 16;
pub const NONCE_LEN: usize = 24;
const HEADER_LEN: usize = 4 + 1 + 12 + SALT_LEN;
const AAD_DOMAIN: &[u8] = b"bip39-pm/v1/vault";
/// Минимальная длина мастер-пароля в символах.
pub const MIN_PASSWORD_CHARS: usize = 10;

/// Параметры Argon2id. Границы проверяются и при чтении блоба, чтобы
/// подменённый файл не заставил считать KDF часами или с нулевой стоимостью.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KdfParams {
    pub m_kib: u32,
    pub t: u32,
    pub p: u32,
}

impl Default for KdfParams {
    /// 64 МиБ, 3 прохода: заметно выше минимума OWASP и ~1 с в WASM.
    fn default() -> Self {
        KdfParams {
            m_kib: 64 * 1024,
            t: 3,
            p: 1,
        }
    }
}

impl KdfParams {
    fn check(&self, strict: bool) -> Result<()> {
        let min_m = if strict { 19 * 1024 } else { 8 };
        if !(min_m..=1024 * 1024).contains(&self.m_kib)
            || !(1..=10).contains(&self.t)
            || !(1..=4).contains(&self.p)
        {
            return Err(Error::Vault("недопустимые параметры Argon2id".into()));
        }
        Ok(())
    }
}

fn kek(password: &str, salt: &[u8], params: KdfParams) -> Result<Zeroizing<[u8; 32]>> {
    let password = Zeroizing::new(password.nfkc().collect::<String>());
    let params = Params::new(params.m_kib, params.t, params.p, Some(32))
        .map_err(|e| Error::Vault(e.to_string()))?;
    let mut out = Zeroizing::new([0u8; 32]);
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(password.as_bytes(), salt, out.as_mut())
        .map_err(|e| Error::Vault(e.to_string()))?;
    Ok(out)
}

fn aad(header: &[u8], login: &str) -> Vec<u8> {
    let login = normalize::login(login);
    let mut aad = Vec::with_capacity(AAD_DOMAIN.len() + header.len() + 4 + login.len());
    aad.extend_from_slice(AAD_DOMAIN);
    aad.extend_from_slice(header);
    aad.extend_from_slice(&(login.len() as u32).to_be_bytes());
    aad.extend_from_slice(login.as_bytes());
    aad
}

/// Шифрует `k_app` под логин и мастер-пароль. Соль и nonce — случайные,
/// их передаёт вызывающий (в WASM — из `crypto.getRandomValues`).
pub fn seal(
    key: &AppKey,
    login: &str,
    password: &str,
    params: KdfParams,
    salt: &[u8; SALT_LEN],
    nonce: &[u8; NONCE_LEN],
) -> Result<Vec<u8>> {
    params.check(true)?;
    seal_with(key, login, password, params, salt, nonce)
}

fn seal_with(
    key: &AppKey,
    login: &str,
    password: &str,
    params: KdfParams,
    salt: &[u8; SALT_LEN],
    nonce: &[u8; NONCE_LEN],
) -> Result<Vec<u8>> {
    if normalize::login(login).is_empty() {
        return Err(Error::Vault("пустой логин".into()));
    }
    if password.chars().count() < MIN_PASSWORD_CHARS {
        return Err(Error::Vault(format!(
            "мастер-пароль короче {MIN_PASSWORD_CHARS} символов"
        )));
    }
    let mut out = Vec::with_capacity(HEADER_LEN + NONCE_LEN + 48);
    out.extend_from_slice(MAGIC);
    out.push(VERSION);
    for v in [params.m_kib, params.t, params.p] {
        out.extend_from_slice(&v.to_be_bytes());
    }
    out.extend_from_slice(salt);
    let kek = kek(password, salt, params)?;
    let k_app = key.to_bytes();
    let ct = XChaCha20Poly1305::new(kek.as_ref().into())
        .encrypt(
            XNonce::from_slice(nonce),
            Payload {
                msg: k_app.as_ref(),
                aad: &aad(&out, login),
            },
        )
        .map_err(|_| Error::Vault("ошибка шифрования".into()))?;
    out.extend_from_slice(nonce);
    out.extend_from_slice(&ct);
    Ok(out)
}

/// Расшифровывает `k_app`. Неверный логин и неверный пароль неразличимы.
pub fn open(data: &[u8], login: &str, password: &str) -> Result<AppKey> {
    if data.len() != HEADER_LEN + NONCE_LEN + 32 + 16 || &data[..4] != MAGIC {
        return Err(Error::Vault("данные не являются сохранённым входом".into()));
    }
    if data[4] != VERSION {
        return Err(Error::Vault(format!(
            "неподдерживаемая версия входа {}",
            data[4]
        )));
    }
    let u32_at = |i: usize| u32::from_be_bytes(data[i..i + 4].try_into().expect("4 байта"));
    let params = KdfParams {
        m_kib: u32_at(5),
        t: u32_at(9),
        p: u32_at(13),
    };
    params.check(false)?;
    let (header, rest) = data.split_at(HEADER_LEN);
    let (nonce, ct) = rest.split_at(NONCE_LEN);
    let kek = kek(password, &header[17..], params)?;
    let plain = Zeroizing::new(
        XChaCha20Poly1305::new(kek.as_ref().into())
            .decrypt(
                XNonce::from_slice(nonce),
                Payload {
                    msg: ct,
                    aad: &aad(header, login),
                },
            )
            .map_err(|_| Error::Vault("Неверный логин или пароль".into()))?,
    );
    let k: [u8; 32] = plain.as_slice().try_into().expect("32 байта");
    Ok(AppKey::from_array(k))
}

#[cfg(test)]
mod tests {
    use super::*;

    const FAST: KdfParams = KdfParams {
        m_kib: 64,
        t: 1,
        p: 1,
    };
    const PW: &str = "correct horse battery";

    fn key() -> AppKey {
        AppKey::from_array([7u8; 32])
    }

    fn sealed() -> Vec<u8> {
        seal_with(&key(), "Vlad", PW, FAST, &[1; SALT_LEN], &[2; NONCE_LEN]).unwrap()
    }

    #[test]
    fn roundtrip_with_normalized_login() {
        let opened = open(&sealed(), "  VLAD ", PW).unwrap();
        assert_eq!(opened.to_bytes().as_ref(), key().to_bytes().as_ref());
    }

    #[test]
    fn wrong_password_or_login_fails() {
        let data = sealed();
        assert!(open(&data, "vlad", "correct horse batterY").is_err());
        assert!(open(&data, "other", PW).is_err());
    }

    #[test]
    fn tampered_params_fail() {
        let mut data = sealed();
        data[12] ^= 1; // t
        assert!(open(&data, "vlad", PW).is_err());
        let mut data = sealed();
        data[20] ^= 1; // соль
        assert!(open(&data, "vlad", PW).is_err());
    }

    #[test]
    fn rejects_weak_inputs() {
        assert!(seal(
            &key(),
            "vlad",
            "short",
            KdfParams::default(),
            &[1; 16],
            &[2; 24]
        )
        .is_err());
        assert!(seal(&key(), "  ", PW, KdfParams::default(), &[1; 16], &[2; 24]).is_err());
        assert!(seal(&key(), "vlad", PW, FAST, &[1; 16], &[2; 24]).is_err());
        let mut data = sealed();
        data[5..9].copy_from_slice(&(u32::MAX).to_be_bytes());
        assert!(open(&data, "vlad", PW).is_err());
    }

    /// Вектор формата с параметрами по умолчанию (их и использует веб-версия).
    #[test]
    fn default_params_vector() {
        let data = seal(&key(), "vlad", PW, KdfParams::default(), &[1; 16], &[2; 24]).unwrap();
        assert_eq!(
            &data[..17],
            b"PMVT\x01\x00\x01\x00\x00\x00\x00\x00\x03\x00\x00\x00\x01"
        );
        assert_eq!(data.len(), 33 + 24 + 48);
        assert!(open(&data, "vlad", PW).is_ok());
    }
}
