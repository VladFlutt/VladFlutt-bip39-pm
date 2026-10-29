//! Ключи Pro для Dart: проверка офлайн публичным ключом издателя.

use anyhow::Result;
use bip39_pm::license::verify_pro;
use flutter_rust_bridge::frb;

/// Проверенный ключ Pro.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProLicense {
    pub serial: u32,
    /// Дата выпуска, `ГГГГ-ММ-ДД`.
    pub issued: String,
}

/// Проверить ключ `MBIP-…`. Ошибка — с текстом для пользователя.
#[frb(sync)]
pub fn verify_pro_key(key: String) -> Result<ProLicense> {
    let lic = verify_pro(&key)?;
    Ok(ProLicense {
        serial: lic.serial,
        issued: lic.issued_date(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39_pm::License;

    #[test]
    fn rejects_foreign_and_garbage_keys() {
        let foreign = License {
            edition: bip39_pm::Edition::Pro,
            serial: 1,
            issued_day: 0,
        }
        .issue(&ed25519_dalek::SigningKey::from_bytes(&[7; 32]));
        assert!(verify_pro_key(foreign).is_err());
        assert!(verify_pro_key("MBIP-AAAA".into()).is_err());
    }
}
