use bip39_pm::license::{publisher_key, Edition, License};
use ed25519_dalek::SigningKey;

fn signer() -> SigningKey {
    SigningKey::from_bytes(&[7u8; 32])
}

fn lic(serial: u32) -> License {
    License {
        edition: Edition::Pro,
        serial,
        issued_day: 297,
    }
}

#[test]
fn issued_key_verifies() {
    let s = signer();
    let key = lic(42).issue(&s);
    assert!(key.starts_with("MBIP-"));
    let got = License::verify(&key, &s.verifying_key(), &[]).unwrap();
    assert_eq!(got, lic(42));
}

#[test]
fn input_is_forgiving() {
    let s = signer();
    let key = lic(1).issue(&s);
    let messy = format!("  {} ", key.to_lowercase().replace('-', " "));
    assert!(License::verify(&messy, &s.verifying_key(), &[]).is_ok());
    let digits = key.replace('O', "0").replace('I', "1").replace('B', "8");
    assert!(License::verify(&digits, &s.verifying_key(), &[]).is_ok());
}

#[test]
fn wrong_publisher_rejected() {
    let key = lic(1).issue(&signer());
    let other = SigningKey::from_bytes(&[8u8; 32]).verifying_key();
    assert!(License::verify(&key, &other, &[]).is_err());
}

#[test]
fn tampered_key_rejected() {
    let s = signer();
    let key = lic(1).issue(&s);
    // Меняем один символ полезной нагрузки (серийный номер).
    let mut chars: Vec<char> = key.chars().collect();
    let i = 8;
    chars[i] = if chars[i] == 'A' { 'C' } else { 'A' };
    let forged: String = chars.into_iter().collect();
    assert!(License::verify(&forged, &s.verifying_key(), &[]).is_err());
}

#[test]
fn revoked_serial_rejected() {
    let s = signer();
    let key = lic(13).issue(&s);
    assert!(License::verify(&key, &s.verifying_key(), &[13]).is_err());
    assert!(License::verify(&key, &s.verifying_key(), &[12, 14]).is_ok());
}

#[test]
fn garbage_rejected() {
    let vk = signer().verifying_key();
    for k in ["", "MBIP", "MBIP-AAAA", "XXXX-AAAA", "MBIP-!!!!"] {
        assert!(License::verify(k, &vk, &[]).is_err(), "{k}");
    }
}

#[test]
fn publisher_key_roundtrip() {
    let vk = signer().verifying_key();
    let parsed = publisher_key(&hex::encode(vk.to_bytes())).unwrap();
    assert_eq!(parsed, vk);
    assert!(publisher_key("abcd").is_err());
}
