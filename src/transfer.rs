//! Перенос индекса между устройствами: текстовый код `PMX1:…` и слияние списков.
//!
//! Код — тот же зашифрованный индекс `PMIX` в base64url. Открыть его может только
//! устройство с той же seed-фразой и passphrase, поэтому код можно пересылать как угодно.

use data_encoding::BASE64URL_NOPAD;

use crate::derive::AppKey;
use crate::index::Index;
use crate::{normalize, Error, Result};

const PREFIX: &str = "PMX1:";

/// Индекс → код для переноса.
pub fn export_text(index: &Index, key: &AppKey) -> Result<String> {
    let blob = index.encrypt(&key.index_key())?;
    Ok(format!("{PREFIX}{}", BASE64URL_NOPAD.encode(&blob)))
}

/// Код для переноса → индекс. Пробелы и переносы строк внутри кода не важны.
pub fn import_text(text: &str, key: &AppKey) -> Result<Index> {
    let compact: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    let body = compact
        .strip_prefix(PREFIX)
        .ok_or_else(|| Error::Index("это не код переноса ManagerBIP".into()))?;
    let blob = BASE64URL_NOPAD
        .decode(body.as_bytes())
        .map_err(|_| Error::Index("код переноса повреждён".into()))?;
    Index::decrypt(&blob, &key.index_key())
}

/// Сколько записей добавлено, обновлено и оставлено как было при слиянии.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MergeReport {
    pub added: u32,
    pub updated: u32,
    pub kept: u32,
}

impl Index {
    /// Вливает другой индекс. Для одного сайта или секрета побеждает больший счётчик
    /// (более новый пароль), при равенстве остаётся своя запись. Шаблоны добавляются
    /// по имени, своё правило по умолчанию не заменяется.
    pub fn merge(&mut self, other: Index) -> MergeReport {
        let mut r = MergeReport::default();
        for e in other.entries {
            match self.find(&e.domain, &e.login) {
                None => {
                    r.added += 1;
                    self.upsert(e);
                }
                Some(local) if local.counter < e.counter => {
                    r.updated += 1;
                    self.upsert(e);
                }
                Some(_) => r.kept += 1,
            }
        }
        for s in other.secrets {
            let same = |x: &&mut crate::index::SecretEntry| {
                x.kind == s.kind && normalize::login(&x.label) == normalize::login(&s.label)
            };
            match self.secrets.iter_mut().find(same) {
                None => {
                    r.added += 1;
                    self.secrets.push(s);
                }
                Some(local) if local.counter < s.counter => {
                    r.updated += 1;
                    *local = s;
                }
                Some(_) => r.kept += 1,
            }
        }
        for t in other.templates {
            if self.templates.iter().any(|x| x.name == t.name) {
                r.kept += 1;
            } else {
                r.added += 1;
                self.templates.push(t);
            }
        }
        if self.default_policy.is_none() {
            self.default_policy = other.default_policy;
        }
        r
    }
}
