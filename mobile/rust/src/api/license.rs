//! Ключи Pro для Dart: проверка офлайн публичным ключом издателя.

use anyhow::Result;
use bip39_pm::license::{publisher_key, License};
use flutter_rust_bridge::frb;

/// Публичный ключ издателя (`pm-license keygen`). Приватная пара хранится только у издателя.
const PUBLISHER_KEY: &str = "aa86d0207e48356fb0ac77797b2debb19c3b3c355803dce1dbed0387f9b3568a";

/// Отозванные серийные номера: утёкшие или возвращённые ключи.
const REVOKED: &[u32] = &[];

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
    let lic = License::verify(&key, &publisher_key(PUBLISHER_KEY)?, REVOKED)?;
    Ok(ProLicense {
        serial: lic.serial,
        issued: issued_date(lic.issued_day),
    })
}

/// Дни от 2026-01-01 → дата (алгоритм days-from-civil, Howard Hinnant).
fn issued_date(day: u16) -> String {
    let z = 20_454 + i64::from(day) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        assert_eq!(issued_date(0), "2026-01-01");
        assert_eq!(issued_date(58), "2026-02-28");
        assert_eq!(issued_date(59), "2026-03-01");
        assert_eq!(issued_date(297), "2026-10-25");
        assert_eq!(issued_date(365 + 31 + 28), "2027-03-01");
    }

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
        assert!(publisher_key(PUBLISHER_KEY).is_ok());
    }
}
