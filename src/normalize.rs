//! Нормализация входа. Правила заморожены спецификацией v1: любое изменение
//! здесь меняет пароли пользователей.

use unicode_normalization::UnicodeNormalization;

use crate::{Error, Result};

/// Эквивалентные домены (v1, заморожено). Ключ → домен, под которым
/// выводится пароль.
const ALIASES: &[(&str, &str)] = &[("youtube.com", "google.com"), ("gmail.com", "google.com")];

/// URL или домен → регистрируемый домен (eTLD+1 по Public Suffix List),
/// нижний регистр, IDN в punycode.
pub fn domain(input: &str) -> Result<String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(Error::Domain("пустая строка".into()));
    }
    let with_scheme = if trimmed.contains("://") {
        trimmed.to_string()
    } else {
        format!("https://{trimmed}")
    };
    let url = url::Url::parse(&with_scheme).map_err(|e| Error::Domain(format!("{input}: {e}")))?;
    let host = match url.host() {
        Some(url::Host::Domain(d)) => d.trim_end_matches('.').to_string(),
        Some(ip) => return Ok(ip.to_string()),
        None => return Err(Error::Domain(format!("{input}: нет хоста"))),
    };
    let registrable = psl::domain_str(&host).unwrap_or(&host).to_string();
    let canonical = ALIASES
        .iter()
        .find(|(alias, _)| *alias == registrable)
        .map(|(_, target)| target.to_string())
        .unwrap_or(registrable);
    Ok(canonical)
}

/// Логин: Unicode NFKC, обрезка пробелов, нижний регистр.
pub fn login(input: &str) -> String {
    input.nfkc().collect::<String>().trim().to_lowercase()
}

/// Seed-фраза: NFKD, нижний регистр, одиночные пробелы между словами.
pub fn mnemonic(input: &str) -> String {
    input
        .nfkd()
        .collect::<String>()
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
