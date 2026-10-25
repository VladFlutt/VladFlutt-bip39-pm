//! Офлайн-ключи Pro-версии.
//!
//! Ключ — подписанная Ed25519 запись `(версия, редакция, серийный номер, день выпуска)`.
//! Приватный ключ хранится только у издателя, в приложение зашивается публичный,
//! поэтому подделать ключ без приватного ключа нельзя, а проверка не требует сети.
//!
//! Формат: `MBIP-XXXX-XXXX-…`, base32 (RFC 4648, без `=`) от `payload ‖ подпись`.
//! При вводе регистр, пробелы и дефисы не важны, `0`/`1`/`8` читаются как `O`/`I`/`B`.

use data_encoding::BASE32_NOPAD;
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};

use crate::{Error, Result};

const PREFIX: &str = "MBIP";
const VERSION: u8 = 1;
const PAYLOAD_LEN: usize = 8;
const KEY_LEN: usize = PAYLOAD_LEN + 64;
/// Разделение доменов подписи: ключ лицензии не совпадёт с подписью чего-то ещё.
const CONTEXT: &[u8] = b"managerbip-license-v1";

/// Редакция приложения, которую открывает ключ.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edition {
    Pro = 1,
}

impl Edition {
    fn from_u8(v: u8) -> Option<Self> {
        match v {
            1 => Some(Edition::Pro),
            _ => None,
        }
    }
}

/// Проверенная лицензия.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct License {
    pub edition: Edition,
    /// Серийный номер: по нему отзываются утёкшие ключи.
    pub serial: u32,
    /// День выпуска, число дней от 2026-01-01.
    pub issued_day: u16,
}

impl License {
    fn payload(&self) -> [u8; PAYLOAD_LEN] {
        let mut p = [0u8; PAYLOAD_LEN];
        p[0] = VERSION;
        p[1] = self.edition as u8;
        p[2..6].copy_from_slice(&self.serial.to_be_bytes());
        p[6..8].copy_from_slice(&self.issued_day.to_be_bytes());
        p
    }

    /// Подписать лицензию и вернуть ключ для пользователя. Только для издателя.
    pub fn issue(&self, signer: &SigningKey) -> String {
        let payload = self.payload();
        let sig = signer.sign(&signed_message(&payload));
        let mut raw = Vec::with_capacity(KEY_LEN);
        raw.extend_from_slice(&payload);
        raw.extend_from_slice(&sig.to_bytes());
        let body = BASE32_NOPAD.encode(&raw);
        let groups: Vec<&str> = body
            .as_bytes()
            .chunks(4)
            .map(|c| std::str::from_utf8(c).expect("base32 — ASCII"))
            .collect();
        format!("{PREFIX}-{}", groups.join("-"))
    }

    /// Проверить ключ публичным ключом издателя. `revoked` — отозванные серийные номера.
    pub fn verify(key: &str, publisher: &VerifyingKey, revoked: &[u32]) -> Result<License> {
        let raw = decode(key)?;
        let (payload, sig) = raw.split_at(PAYLOAD_LEN);
        let sig = Signature::from_slice(sig).map_err(|_| bad("повреждённая подпись"))?;
        publisher
            .verify(&signed_message(payload), &sig)
            .map_err(|_| bad("ключ не подходит"))?;
        if payload[0] != VERSION {
            return Err(bad("неподдерживаемая версия ключа"));
        }
        let edition = Edition::from_u8(payload[1]).ok_or_else(|| bad("неизвестная редакция"))?;
        let serial = u32::from_be_bytes(payload[2..6].try_into().expect("4 байта"));
        let issued_day = u16::from_be_bytes(payload[6..8].try_into().expect("2 байта"));
        if revoked.contains(&serial) {
            return Err(bad("ключ отозван"));
        }
        Ok(License {
            edition,
            serial,
            issued_day,
        })
    }
}

/// Публичный ключ издателя из hex (64 символа).
pub fn publisher_key(hex_str: &str) -> Result<VerifyingKey> {
    let bytes: [u8; 32] = hex::decode(hex_str.trim())
        .ok()
        .and_then(|b| b.try_into().ok())
        .ok_or_else(|| bad("публичный ключ должен быть 32 байта в hex"))?;
    VerifyingKey::from_bytes(&bytes).map_err(|_| bad("некорректный публичный ключ"))
}

fn signed_message(payload: &[u8]) -> Vec<u8> {
    [CONTEXT, payload].concat()
}

fn decode(key: &str) -> Result<Vec<u8>> {
    let cleaned: String = key
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .map(|c| match c.to_ascii_uppercase() {
            '0' => 'O',
            '1' => 'I',
            '8' => 'B',
            u => u,
        })
        .collect();
    let body = cleaned
        .strip_prefix(PREFIX)
        .ok_or_else(|| bad("ключ должен начинаться с MBIP"))?;
    let raw = BASE32_NOPAD
        .decode(body.as_bytes())
        .map_err(|_| bad("в ключе опечатка"))?;
    if raw.len() != KEY_LEN {
        return Err(bad("неверная длина ключа"));
    }
    Ok(raw)
}

fn bad(m: &str) -> Error {
    Error::License(m.to_string())
}
