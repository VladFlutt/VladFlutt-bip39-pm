//! Детерминированный менеджер паролей на основе BIP39 seed.
//!
//! Цепочка: BIP39 mnemonic (+ passphrase) → BIP32 master → BIP85 entropy
//! (`m/83696968'/20567'/0'`) → `k_app` → HKDF(домен, логин, счётчик, политика)
//! → `k_site` → кодирование по политике. Полная спецификация — в `SPEC.md`.

pub mod derive;
pub mod index;
pub mod license;
pub mod normalize;
pub mod policy;

pub use derive::{AppKey, Site};
pub use index::{Entry, Index};
pub use license::{Edition, License};
pub use policy::Policy;

#[derive(Debug)]
pub enum Error {
    Mnemonic(String),
    Derivation(String),
    Domain(String),
    Policy(String),
    Index(String),
    License(String),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Mnemonic(m) => write!(f, "некорректная seed-фраза: {m}"),
            Error::Derivation(m) => write!(f, "ошибка деривации: {m}"),
            Error::Domain(m) => write!(f, "некорректный домен: {m}"),
            Error::Policy(m) => write!(f, "некорректная политика: {m}"),
            Error::Index(m) => write!(f, "ошибка индекса: {m}"),
            Error::License(m) => write!(f, "ключ Pro: {m}"),
        }
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;
