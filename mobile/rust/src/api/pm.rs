//! API ядра bip39-pm для Dart. Алгоритм целиком живёт в крейте `bip39-pm`,
//! здесь только преобразование типов, поэтому пароли совпадают с CLI `pm`.
//!
//! На устройстве хранится `k_app` (32 байта), а не seed-фраза: из него выводятся
//! все пароли, но не ключи криптокошелька на той же фразе.

use anyhow::{bail, Result};
use bip39_pm::index::{SecretEntry, Template};
use bip39_pm::{transfer, wrap, AppKey, Entry, Index, Policy, SecretKind, Site};
use flutter_rust_bridge::frb;

/// Политика пароля (SPEC.md, раздел 4).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PasswordPolicy {
    pub length: u8,
    pub lower: bool,
    pub upper: bool,
    pub digits: bool,
    pub symbols: bool,
}

impl PasswordPolicy {
    #[frb(sync)]
    pub fn default_policy() -> PasswordPolicy {
        Policy::default().into()
    }

    /// Каноническая строка, например `len=20;cls=luds`.
    #[frb(sync)]
    pub fn canonical(&self) -> String {
        Policy::from(*self).canonical()
    }
}

impl From<Policy> for PasswordPolicy {
    fn from(p: Policy) -> Self {
        PasswordPolicy {
            length: p.length,
            lower: p.lower,
            upper: p.upper,
            digits: p.digits,
            symbols: p.symbols,
        }
    }
}

impl From<PasswordPolicy> for Policy {
    fn from(p: PasswordPolicy) -> Self {
        Policy {
            length: p.length,
            lower: p.lower,
            upper: p.upper,
            digits: p.digits,
            symbols: p.symbols,
        }
    }
}

/// Запись индекса: параметры аккаунта без пароля.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Account {
    pub domain: String,
    pub login: String,
    pub counter: u32,
    pub policy: PasswordPolicy,
    pub note: Option<String>,
}

impl From<Entry> for Account {
    fn from(e: Entry) -> Self {
        Account {
            domain: e.domain,
            login: e.login,
            counter: e.counter,
            policy: e.policy.into(),
            note: e.note,
        }
    }
}

impl From<Account> for Entry {
    fn from(a: Account) -> Self {
        Entry {
            domain: a.domain,
            login: a.login,
            counter: a.counter,
            policy: a.policy.into(),
            note: a.note,
        }
    }
}

/// Вид секрета из фразы.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SecretType {
    Pin,
    Words,
    Wifi,
    Ssh,
}

/// Секрет без значения: вид, размер (длина или число слов, для SSH 0), метка, версия.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SecretItem {
    pub kind: SecretType,
    pub size: u8,
    pub label: String,
    pub counter: u32,
    pub note: Option<String>,
}

impl SecretItem {
    fn spec(kind: SecretType, size: u8) -> SecretKind {
        match kind {
            SecretType::Pin => SecretKind::Pin { length: size },
            SecretType::Words => SecretKind::Words { count: size },
            SecretType::Wifi => SecretKind::Wifi { length: size },
            SecretType::Ssh => SecretKind::Ssh,
        }
    }
}

impl From<SecretEntry> for SecretItem {
    fn from(e: SecretEntry) -> Self {
        let (kind, size) = match e.kind {
            SecretKind::Pin { length } => (SecretType::Pin, length),
            SecretKind::Words { count } => (SecretType::Words, count),
            SecretKind::Wifi { length } => (SecretType::Wifi, length),
            SecretKind::Ssh => (SecretType::Ssh, 0),
        };
        SecretItem {
            kind,
            size,
            label: e.label,
            counter: e.counter,
            note: e.note,
        }
    }
}

impl From<SecretItem> for SecretEntry {
    fn from(s: SecretItem) -> Self {
        SecretEntry {
            kind: SecretItem::spec(s.kind, s.size),
            label: s.label,
            counter: s.counter,
            note: s.note,
        }
    }
}

/// Размер секрета: `[минимум, максимум, по умолчанию]`; у SSH размера нет.
#[frb(sync)]
pub fn secret_size_bounds(kind: SecretType) -> Vec<u8> {
    match kind {
        SecretType::Pin => vec![4, 12, 4],
        SecretType::Words => vec![3, 8, 4],
        SecretType::Wifi => vec![12, 63, 20],
        SecretType::Ssh => vec![0, 0, 0],
    }
}

/// Метка секрета так, как она входит в деривацию.
#[frb(sync)]
pub fn normalize_label(input: String) -> String {
    bip39_pm::normalize::login(&input)
}

/// Значение секрета. Для SSH `value` — закрытый ключ OpenSSH, `public` — открытый.
#[derive(Clone, Debug)]
pub struct SecretValue {
    pub label: String,
    pub value: String,
    pub public: Option<String>,
}

/// Именованное правило пароля.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RuleTemplate {
    pub name: String,
    pub policy: PasswordPolicy,
}

/// Всё содержимое индекса профиля.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct IndexData {
    pub accounts: Vec<Account>,
    pub secrets: Vec<SecretItem>,
    pub templates: Vec<RuleTemplate>,
    pub default_policy: Option<PasswordPolicy>,
}

impl From<Index> for IndexData {
    fn from(i: Index) -> Self {
        IndexData {
            accounts: i.entries.into_iter().map(Account::from).collect(),
            secrets: i.secrets.into_iter().map(SecretItem::from).collect(),
            templates: i
                .templates
                .into_iter()
                .map(|t| RuleTemplate {
                    name: t.name,
                    policy: t.policy.into(),
                })
                .collect(),
            default_policy: i.default_policy.map(PasswordPolicy::from),
        }
    }
}

impl From<IndexData> for Index {
    fn from(d: IndexData) -> Self {
        let mut index = Index {
            secrets: d.secrets.into_iter().map(SecretEntry::from).collect(),
            templates: d
                .templates
                .into_iter()
                .map(|t| Template {
                    name: t.name,
                    policy: t.policy.into(),
                })
                .collect(),
            default_policy: d.default_policy.map(Policy::from),
            ..Index::default()
        };
        for a in d.accounts {
            index.upsert(a.into());
        }
        index
    }
}

/// Итог слияния: новый индекс и сколько записей добавлено, обновлено, осталось как было.
#[derive(Clone, Debug)]
pub struct MergeResult {
    pub data: IndexData,
    pub added: u32,
    pub updated: u32,
    pub kept: u32,
}

/// Влить пришедший индекс в свой: побеждает больший счётчик, при равенстве — свой.
#[frb(sync)]
pub fn merge_index(local: IndexData, incoming: IndexData) -> MergeResult {
    let mut index = Index::from(local);
    let r = index.merge(incoming.into());
    MergeResult {
        data: index.into(),
        added: r.added,
        updated: r.updated,
        kept: r.kept,
    }
}

/// Закрыть ключ профиля кодом (PBKDF2, доли секунды — вызов асинхронный).
pub fn wrap_secret(secret: Vec<u8>, code: String) -> Result<Vec<u8>> {
    let secret = zeroize::Zeroizing::new(secret);
    Ok(wrap::wrap(&secret, &code)?)
}

/// Открыть ключ профиля кодом. Ошибка — неверный код.
pub fn unwrap_secret(blob: Vec<u8>, code: String) -> Result<Vec<u8>> {
    Ok(wrap::unwrap(&blob, &code)?.to_vec())
}

/// Вычисленный пароль и нормализованные параметры, под которыми он получен.
#[derive(Clone, Debug)]
pub struct Derived {
    pub domain: String,
    pub login: String,
    pub counter: u32,
    pub password: String,
    pub check_words: String,
}

/// Допустимое число слов seed-фразы: 12, 15, 18, 21, 24.
#[frb(sync)]
pub fn seed_word_counts() -> Vec<u32> {
    bip39_pm::SEED_WORD_COUNTS
        .iter()
        .map(|&n| n as u32)
        .collect()
}

/// Новая seed-фраза BIP39 из 12, 15, 18, 21 или 24 слов.
#[frb(sync)]
pub fn generate_mnemonic(words: u32) -> Result<String> {
    if !bip39_pm::SEED_WORD_COUNTS.contains(&(words as usize)) {
        bail!("поддерживается 12, 15, 18, 21 или 24 слова");
    }
    Ok(bip39::Mnemonic::generate(words as usize)?.to_string())
}

/// Английский словарь BIP39 (2048 слов) для подсказок при вводе фразы.
#[frb(sync)]
pub fn bip39_wordlist() -> Vec<String> {
    bip39::Language::English
        .word_list()
        .iter()
        .map(|w| w.to_string())
        .collect()
}

/// URL или домен → домен, под которым выводится пароль (eTLD+1, алиасы).
#[frb(sync)]
pub fn normalize_domain(input: String) -> Result<String> {
    Ok(bip39_pm::normalize::domain(&input)?)
}

#[frb(sync)]
pub fn normalize_login(input: String) -> String {
    bip39_pm::normalize::login(&input)
}

/// Открытое хранилище: держит `k_app` в памяти Rust, наружу ключ отдаёт
/// только для записи в Keychain/Keystore.
#[frb(opaque)]
pub struct Vault {
    key: AppKey,
}

impl Vault {
    /// Seed-фраза (+ passphrase) → `k_app`. PBKDF2 занимает доли секунды,
    /// поэтому вызов асинхронный.
    pub fn unlock(phrase: String, passphrase: String) -> Result<Vault> {
        let phrase = zeroize::Zeroizing::new(phrase);
        let passphrase = zeroize::Zeroizing::new(passphrase);
        Ok(Vault {
            key: AppKey::from_mnemonic(&phrase, &passphrase)?,
        })
    }

    #[frb(sync)]
    pub fn from_key(key: Vec<u8>) -> Result<Vault> {
        let key = zeroize::Zeroizing::new(key);
        Ok(Vault {
            key: AppKey::from_bytes(&key)?,
        })
    }

    #[frb(sync)]
    pub fn key_bytes(&self) -> Vec<u8> {
        self.key.to_bytes().to_vec()
    }

    /// Три слова — отпечаток seed + passphrase.
    #[frb(sync)]
    pub fn fingerprint(&self) -> String {
        self.key.fingerprint()
    }

    #[frb(sync)]
    pub fn derive(
        &self,
        site: String,
        login: String,
        counter: u32,
        policy: PasswordPolicy,
    ) -> Result<Derived> {
        let policy = Policy::from(policy);
        policy.validate()?;
        let site = Site::new(&site, &login, counter)?;
        let password = self.key.password(&site, &policy)?;
        Ok(Derived {
            check_words: self.key.check_words(&site, &policy),
            password: password.as_str().to_owned(),
            domain: site.domain,
            login: site.login,
            counter: site.counter,
        })
    }

    /// Индекс → зашифрованный файл (формат `PMIX`, совместим с CLI).
    #[frb(sync)]
    pub fn encrypt_index(&self, data: IndexData) -> Result<Vec<u8>> {
        Ok(Index::from(data).encrypt(&self.key.index_key())?)
    }

    #[frb(sync)]
    pub fn decrypt_index(&self, data: Vec<u8>) -> Result<IndexData> {
        Ok(Index::decrypt(&data, &self.key.index_key())?.into())
    }

    /// Индекс → код переноса `PMX1:…` (открывается только той же фразой).
    #[frb(sync)]
    pub fn export_text(&self, data: IndexData) -> Result<String> {
        Ok(transfer::export_text(&data.into(), &self.key)?)
    }

    #[frb(sync)]
    pub fn import_text(&self, text: String) -> Result<IndexData> {
        Ok(transfer::import_text(&text, &self.key)?.into())
    }

    #[frb(sync)]
    pub fn derive_secret(
        &self,
        kind: SecretType,
        size: u8,
        label: String,
        counter: u32,
    ) -> Result<SecretValue> {
        let s = self
            .key
            .secret(&SecretItem::spec(kind, size), &label, counter)?;
        Ok(SecretValue {
            label: bip39_pm::normalize::login(&label),
            value: s.value.as_str().to_owned(),
            public: s.public,
        })
    }
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;

    const ABANDON: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    /// Векторы из SPEC.md: мост не должен менять пароли.
    #[test]
    fn spec_vectors_through_api() {
        let v = Vault::unlock(ABANDON.into(), String::new()).unwrap();
        assert_eq!(v.fingerprint(), "era-primary-finish");
        let d = v
            .derive(
                "https://www.GitHub.com/login".into(),
                " Vlad@Mail.ru ".into(),
                1,
                PasswordPolicy::default_policy(),
            )
            .unwrap();
        assert_eq!(d.domain, "github.com");
        assert_eq!(d.login, "vlad@mail.ru");
        assert_eq!(d.password, "q~9Tlw:qOyeSzu?69AUx");
        assert_eq!(d.check_words, "amused-liquid");
    }

    #[test]
    fn key_roundtrip_and_index() {
        let v = Vault::unlock(ABANDON.into(), String::new()).unwrap();
        let restored = Vault::from_key(v.key_bytes()).unwrap();
        assert_eq!(restored.fingerprint(), v.fingerprint());
        let acc = Account {
            domain: "github.com".into(),
            login: "vlad".into(),
            counter: 3,
            policy: PasswordPolicy::default_policy(),
            note: Some("work".into()),
        };
        let data = IndexData {
            accounts: vec![acc],
            secrets: vec![SecretItem {
                kind: SecretType::Pin,
                size: 4,
                label: "карта".into(),
                counter: 1,
                note: None,
            }],
            templates: vec![RuleTemplate {
                name: "Банк".into(),
                policy: PasswordPolicy::default_policy(),
            }],
            default_policy: Some(PasswordPolicy::default_policy()),
        };
        let blob = v.encrypt_index(data.clone()).unwrap();
        assert_eq!(restored.decrypt_index(blob).unwrap(), data);
        let code = v.export_text(data.clone()).unwrap();
        assert_eq!(restored.import_text(code).unwrap(), data);
        let m = merge_index(IndexData::default(), data.clone());
        assert_eq!((m.added, m.updated, m.kept), (3, 0, 0));
        assert_eq!(m.data, data);
        assert!(Vault::from_key(vec![0; 31]).is_err());
    }

    #[test]
    fn mnemonic_generation() {
        for n in seed_word_counts() {
            let m = generate_mnemonic(n).unwrap();
            assert_eq!(m.split(' ').count(), n as usize);
            assert!(Vault::unlock(m, String::new()).is_ok());
        }
        assert!(generate_mnemonic(13).is_err());
        assert!(generate_mnemonic(27).is_err());
        assert_eq!(bip39_wordlist().len(), 2048);
    }

    #[test]
    fn secrets_through_api() {
        let v = Vault::unlock(ABANDON.into(), String::new()).unwrap();
        let pin = v
            .derive_secret(SecretType::Pin, 4, " Карта ".into(), 1)
            .unwrap();
        assert_eq!((pin.label.as_str(), pin.value.as_str()), ("карта", "5987"));
        let ssh = v
            .derive_secret(SecretType::Ssh, 0, "github laptop".into(), 1)
            .unwrap();
        assert!(ssh.public.unwrap().starts_with("ssh-ed25519 "));
        for k in [SecretType::Pin, SecretType::Words, SecretType::Wifi] {
            let b = secret_size_bounds(k);
            assert!(v.derive_secret(k, b[2], "x".into(), 1).is_ok());
            assert!(v.derive_secret(k, b[1] + 1, "x".into(), 1).is_err());
        }
        let blob = wrap_secret(v.key_bytes(), "7777".into()).unwrap();
        assert_eq!(
            unwrap_secret(blob.clone(), "7777".into()).unwrap(),
            v.key_bytes()
        );
        assert!(unwrap_secret(blob, "7778".into()).is_err());
    }
}
