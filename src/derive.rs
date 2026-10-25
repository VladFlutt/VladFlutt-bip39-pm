//! Деривация ключей: BIP39 → BIP32 → BIP85 → HKDF.

use bip32::{ChildNumber, XPrv};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::{Sha256, Sha512};
use zeroize::Zeroizing;

use crate::policy::{ByteStream, Policy};
use crate::{normalize, Error, Result};

/// BIP85: purpose `83696968'`.
pub const BIP85_PURPOSE: u32 = 83_696_968;
/// Номер приложения BIP85 для этого менеджера: 0x5057 = «PW».
pub const PM_APP: u32 = 20_567;

const HKDF_SALT: &[u8] = b"bip39-pm/v1";
const INFO_PASSWORD: &[u8] = b"bip39-pm/v1/password";
const INFO_STREAM: &[u8] = b"bip39-pm/v1/stream";
const INFO_CHECK: &[u8] = b"bip39-pm/v1/check";
const INFO_FINGERPRINT: &[u8] = b"bip39-pm/v1/fingerprint";
const INFO_INDEX_KEY: &[u8] = b"bip39-pm/v1/index-key";
const STREAM_LEN: usize = 1024;

/// Нормализованные параметры аккаунта.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Site {
    pub domain: String,
    pub login: String,
    pub counter: u32,
}

impl Site {
    /// Нормализует домен (или URL) и логин; счётчик начинается с 1.
    pub fn new(domain_or_url: &str, login: &str, counter: u32) -> Result<Self> {
        if counter == 0 {
            return Err(Error::Derivation("счётчик начинается с 1".into()));
        }
        Ok(Site {
            domain: normalize::domain(domain_or_url)?,
            login: normalize::login(login),
            counter,
        })
    }
}

/// BIP85: энтропия из hardened-пути (все индексы трактуются как hardened).
pub fn bip85_entropy(seed: &[u8], path: &[u32]) -> Result<Zeroizing<[u8; 64]>> {
    let master = XPrv::new(seed).map_err(|e| Error::Derivation(e.to_string()))?;
    bip85_entropy_from_xprv(master, path)
}

/// BIP85 от готового мастер-ключа (нужно для официальных тестовых векторов).
pub fn bip85_entropy_from_xprv(master: XPrv, path: &[u32]) -> Result<Zeroizing<[u8; 64]>> {
    let mut key = master;
    for &i in path {
        let child = ChildNumber::new(i, true).map_err(|e| Error::Derivation(e.to_string()))?;
        key = key
            .derive_child(child)
            .map_err(|e| Error::Derivation(e.to_string()))?;
    }
    let priv_bytes = Zeroizing::new(key.private_key().to_bytes());
    let mut mac = <Hmac<Sha512> as Mac>::new_from_slice(b"bip-entropy-from-k")
        .expect("HMAC accepts any key length");
    mac.update(&priv_bytes);
    let mut out = Zeroizing::new([0u8; 64]);
    out.copy_from_slice(&mac.finalize().into_bytes());
    Ok(out)
}

/// Ключ приложения `k_app`. Всё, что ниже, вычисляется только из него.
pub struct AppKey(Zeroizing<[u8; 32]>);

impl AppKey {
    pub fn from_mnemonic(phrase: &str, passphrase: &str) -> Result<Self> {
        let mnemonic = bip39::Mnemonic::parse_normalized(&normalize::mnemonic(phrase))
            .map_err(|e| Error::Mnemonic(e.to_string()))?;
        let seed = Zeroizing::new(mnemonic.to_seed_normalized(passphrase));
        Self::from_seed(seed.as_ref())
    }

    /// Восстанавливает ключ, сохранённый через [`AppKey::to_bytes`]. Нужно устройствам,
    /// которые хранят `k_app`, а не саму seed-фразу.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        let arr: [u8; 32] = bytes.try_into().map_err(|_| {
            Error::Derivation(format!("ключ должен быть 32 байта, а не {}", bytes.len()))
        })?;
        Ok(AppKey(Zeroizing::new(arr)))
    }

    pub fn to_bytes(&self) -> Zeroizing<[u8; 32]> {
        Zeroizing::new(*self.0)
    }

    pub fn from_seed(seed: &[u8]) -> Result<Self> {
        let entropy = bip85_entropy(seed, &[BIP85_PURPOSE, PM_APP, 0])?;
        let mut k = Zeroizing::new([0u8; 32]);
        k.copy_from_slice(&entropy[..32]);
        Ok(AppKey(k))
    }

    fn expand(&self, info: &[u8], out: &mut [u8]) {
        Hkdf::<Sha256>::new(Some(HKDF_SALT), self.0.as_ref())
            .expand(info, out)
            .expect("output length within HKDF limit");
    }

    /// 32 байта HKDF(k_app, info) для производных ключей других модулей.
    pub(crate) fn hkdf_32(&self, info: &[u8]) -> Zeroizing<[u8; 32]> {
        let mut k = Zeroizing::new([0u8; 32]);
        self.expand(info, k.as_mut());
        k
    }

    /// `k_site` = HKDF(k_app, info), info однозначно кодирует все поля
    /// (длина-префикс), чтобы `a|b` и `a`,`|b` не совпали.
    pub fn site_key(&self, site: &Site, policy: &Policy) -> Zeroizing<[u8; 32]> {
        let mut info = INFO_PASSWORD.to_vec();
        for field in [
            site.domain.as_bytes(),
            site.login.as_bytes(),
            policy.canonical().as_bytes(),
        ] {
            info.extend_from_slice(&(field.len() as u32).to_be_bytes());
            info.extend_from_slice(field);
        }
        info.extend_from_slice(&site.counter.to_be_bytes());
        let mut k = Zeroizing::new([0u8; 32]);
        self.expand(&info, k.as_mut());
        k
    }

    pub fn password(&self, site: &Site, policy: &Policy) -> Result<Zeroizing<String>> {
        let k_site = self.site_key(site, policy);
        let mut buf = vec![0u8; STREAM_LEN];
        Hkdf::<Sha256>::from_prk(k_site.as_ref())
            .expect("32-byte PRK")
            .expand(INFO_STREAM, &mut buf)
            .expect("output length within HKDF limit");
        Ok(Zeroizing::new(policy.encode(&mut ByteStream::new(buf))?))
    }

    /// Два слова BIP39 для визуальной сверки пароля (22 бита, сам пароль не раскрывают).
    pub fn check_words(&self, site: &Site, policy: &Policy) -> String {
        let k_site = self.site_key(site, policy);
        let mut b = [0u8; 4];
        Hkdf::<Sha256>::from_prk(k_site.as_ref())
            .expect("32-byte PRK")
            .expand(INFO_CHECK, &mut b)
            .expect("ok");
        words(u32::from_be_bytes(b), 2)
    }

    /// Три слова BIP39 — отпечаток seed + passphrase. Совпадает → seed введена верно.
    pub fn fingerprint(&self) -> String {
        let mut b = [0u8; 4];
        self.expand(INFO_FINGERPRINT, &mut b);
        // 33 бита не помещаются в u32; берём 32 и третье слово из 10 бит — достаточно для сверки.
        words(u32::from_be_bytes(b), 3)
    }

    /// Ключ шифрования индекса.
    pub fn index_key(&self) -> Zeroizing<[u8; 32]> {
        let mut k = Zeroizing::new([0u8; 32]);
        self.expand(INFO_INDEX_KEY, k.as_mut());
        k
    }
}

/// `n` слов из словаря BIP39 по 11 бит из старших битов `bits`
/// (для третьего слова недостающие биты — нули).
fn words(bits: u32, n: usize) -> String {
    let list = bip39::Language::English.word_list();
    let wide = (bits as u64) << 32;
    (0..n)
        .map(|i| list[((wide >> (64 - 11 * (i + 1))) & 0x7ff) as usize])
        .collect::<Vec<_>>()
        .join("-")
}
