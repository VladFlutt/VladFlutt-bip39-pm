//! Зашифрованный индекс аккаунтов: домены, логины, счётчики, политики.
//! Паролей в нём нет. Формат файла: `PMIX` | версия (1 байт) | nonce (24) |
//! XChaCha20-Poly1305(JSON), заголовок — associated data.

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use serde::{Deserialize, Serialize};

use crate::policy::Policy;
use crate::{Error, Result};

const MAGIC: &[u8; 4] = b"PMIX";
const VERSION: u8 = 1;
const HEADER_LEN: usize = 5;
const NONCE_LEN: usize = 24;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    pub domain: String,
    pub login: String,
    pub counter: u32,
    pub policy: Policy,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Index {
    pub entries: Vec<Entry>,
}

impl Index {
    pub fn find(&self, domain: &str, login: &str) -> Option<&Entry> {
        self.entries
            .iter()
            .find(|e| e.domain == domain && e.login == login)
    }

    /// Вставляет или заменяет запись с тем же доменом и логином; список остаётся отсортированным.
    pub fn upsert(&mut self, entry: Entry) {
        match self
            .entries
            .iter_mut()
            .find(|e| e.domain == entry.domain && e.login == entry.login)
        {
            Some(existing) => *existing = entry,
            None => self.entries.push(entry),
        }
        self.entries
            .sort_by(|a, b| (&a.domain, &a.login).cmp(&(&b.domain, &b.login)));
    }

    pub fn encrypt(&self, key: &[u8; 32]) -> Result<Vec<u8>> {
        let mut nonce = [0u8; NONCE_LEN];
        getrandom::getrandom(&mut nonce).map_err(|e| Error::Index(e.to_string()))?;
        let plain = zeroize::Zeroizing::new(
            serde_json::to_vec(self).map_err(|e| Error::Index(e.to_string()))?,
        );
        let mut out = Vec::with_capacity(HEADER_LEN + NONCE_LEN + plain.len() + 16);
        out.extend_from_slice(MAGIC);
        out.push(VERSION);
        let ct = XChaCha20Poly1305::new(key.into())
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: &plain,
                    aad: &out[..HEADER_LEN],
                },
            )
            .map_err(|_| Error::Index("ошибка шифрования".into()))?;
        out.extend_from_slice(&nonce);
        out.extend_from_slice(&ct);
        Ok(out)
    }

    pub fn decrypt(data: &[u8], key: &[u8; 32]) -> Result<Self> {
        if data.len() < HEADER_LEN + NONCE_LEN || &data[..4] != MAGIC {
            return Err(Error::Index("файл не является индексом".into()));
        }
        if data[4] != VERSION {
            return Err(Error::Index(format!(
                "неподдерживаемая версия индекса {}",
                data[4]
            )));
        }
        let (header, rest) = data.split_at(HEADER_LEN);
        let (nonce, ct) = rest.split_at(NONCE_LEN);
        let plain = zeroize::Zeroizing::new(
            XChaCha20Poly1305::new(key.into())
                .decrypt(
                    XNonce::from_slice(nonce),
                    Payload {
                        msg: ct,
                        aad: header,
                    },
                )
                .map_err(|_| {
                    Error::Index(
                        "не удалось расшифровать: другая seed/passphrase или файл повреждён".into(),
                    )
                })?,
        );
        serde_json::from_slice(&plain).map_err(|e| Error::Index(e.to_string()))
    }
}
