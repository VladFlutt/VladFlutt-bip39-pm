//! Минимальный C-ABI поверх ядра для JavaScript без wasm-bindgen.
//!
//! Протокол: JS кладёт JSON-запрос в память через `pm_alloc`, вызывает
//! `pm_call(ptr, len)` и получает упакованные `(ptr << 32) | len` ответа,
//! после чего освобождает обе области через `pm_free`. Ответ —
//! `{"ok": ...}` или `{"error": "..."}`.

use bip39_pm::index::NONCE_LEN;
use bip39_pm::{license, normalize, transfer, vault, AppKey, Index, Policy, SecretKind, Site};
use serde::Deserialize;
use serde_json::{json, Value};
use zeroize::Zeroizing;

#[no_mangle]
pub extern "C" fn pm_alloc(len: usize) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(len);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// Освобождает и затирает область.
///
/// # Safety
/// `ptr`/`len` должны быть получены из `pm_alloc` или `pm_call`.
#[no_mangle]
pub unsafe extern "C" fn pm_free(ptr: *mut u8, len: usize) {
    let mut buf = Vec::from_raw_parts(ptr, len, len);
    buf.iter_mut().for_each(|b| *b = 0);
}

/// # Safety
/// `ptr`/`len` должны указывать на JSON, записанный через `pm_alloc`.
#[no_mangle]
pub unsafe extern "C" fn pm_call(ptr: *const u8, len: usize) -> u64 {
    let input = std::slice::from_raw_parts(ptr, len);
    let response = match handle(input) {
        Ok(v) => json!({ "ok": v }),
        Err(e) => json!({ "error": e }),
    };
    let mut out = serde_json::to_vec(&response)
        .expect("serializable")
        .into_boxed_slice();
    let (out_ptr, out_len) = (out.as_mut_ptr(), out.len());
    std::mem::forget(out);
    ((out_ptr as u64) << 32) | out_len as u64
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum Request {
    /// Новая мнемоника из внешней энтропии (16 или 32 байта, hex).
    Generate {
        entropy: String,
    },
    Unlock {
        mnemonic: Zeroizing<String>,
        #[serde(default)]
        passphrase: Zeroizing<String>,
    },
    Fingerprint {
        k_app: Zeroizing<String>,
    },
    Domain {
        url: String,
    },
    Password {
        k_app: Zeroizing<String>,
        site: String,
        login: String,
        counter: u32,
        policy: Policy,
    },
    IndexEncrypt {
        k_app: Zeroizing<String>,
        index: Index,
        nonce: String,
    },
    IndexDecrypt {
        k_app: Zeroizing<String>,
        data: String,
    },
    /// Вход по логину и мастер-паролю: шифрует k_app (Argon2id + XChaCha20).
    VaultSeal {
        k_app: Zeroizing<String>,
        login: String,
        password: Zeroizing<String>,
        salt: String,
        nonce: String,
    },
    VaultOpen {
        data: String,
        login: String,
        password: Zeroizing<String>,
    },
    /// Ключ ManagerBIP Pro `MBIP-…`, проверка офлайн.
    License {
        key: String,
    },
    /// PIN, слова, пароль Wi‑Fi или ключ SSH по метке.
    Secret {
        k_app: Zeroizing<String>,
        #[serde(flatten)]
        kind: SecretKind,
        label: String,
        counter: u32,
    },
    /// Индекс → код переноса `PMX1:…`.
    TransferExport {
        k_app: Zeroizing<String>,
        index: Index,
        nonce: String,
    },
    /// Код переноса, влитый в индекс: больший счётчик побеждает.
    TransferImport {
        k_app: Zeroizing<String>,
        index: Index,
        code: String,
    },
}

fn handle(input: &[u8]) -> Result<Value, String> {
    let req: Request =
        serde_json::from_slice(input).map_err(|e| format!("некорректный запрос: {e}"))?;
    Ok(match req {
        Request::Generate { entropy } => {
            let m =
                bip39::Mnemonic::from_entropy(&from_hex(&entropy)?).map_err(|e| e.to_string())?;
            json!({ "mnemonic": m.to_string() })
        }
        Request::Unlock {
            mnemonic,
            passphrase,
        } => {
            let key = AppKey::from_mnemonic(&mnemonic, &passphrase).map_err(|e| e.to_string())?;
            json!({ "k_app": to_hex(key.to_bytes().as_ref()), "fingerprint": key.fingerprint() })
        }
        Request::Fingerprint { k_app } => json!({ "fingerprint": app_key(&k_app)?.fingerprint() }),
        Request::Domain { url } => {
            json!({ "domain": normalize::domain(&url).map_err(|e| e.to_string())? })
        }
        Request::Password {
            k_app,
            site,
            login,
            counter,
            policy,
        } => {
            let key = app_key(&k_app)?;
            let site = Site::new(&site, &login, counter).map_err(|e| e.to_string())?;
            let password = key.password(&site, &policy).map_err(|e| e.to_string())?;
            json!({
                "domain": site.domain,
                "login": site.login,
                "counter": site.counter,
                "policy": policy.canonical(),
                "password": password.as_str(),
                "check": key.check_words(&site, &policy),
            })
        }
        Request::IndexEncrypt {
            k_app,
            index,
            nonce,
        } => {
            let nonce: [u8; NONCE_LEN] = from_hex(&nonce)?
                .try_into()
                .map_err(|_| "nonce: нужно 24 байта")?;
            let data = index
                .encrypt_with_nonce(&app_key(&k_app)?.index_key(), &nonce)
                .map_err(|e| e.to_string())?;
            json!({ "data": to_hex(&data) })
        }
        Request::IndexDecrypt { k_app, data } => {
            let index = Index::decrypt(&from_hex(&data)?, &app_key(&k_app)?.index_key())
                .map_err(|e| e.to_string())?;
            json!({ "index": index })
        }
        Request::VaultSeal {
            k_app,
            login,
            password,
            salt,
            nonce,
        } => {
            let salt: [u8; vault::SALT_LEN] = from_hex(&salt)?
                .try_into()
                .map_err(|_| "salt: нужно 16 байт")?;
            let nonce: [u8; vault::NONCE_LEN] = from_hex(&nonce)?
                .try_into()
                .map_err(|_| "nonce: нужно 24 байта")?;
            let data = vault::seal(
                &app_key(&k_app)?,
                &login,
                &password,
                vault::KdfParams::default(),
                &salt,
                &nonce,
            )
            .map_err(|e| e.to_string())?;
            json!({ "data": to_hex(&data), "login": normalize::login(&login) })
        }
        Request::VaultOpen {
            data,
            login,
            password,
        } => {
            let key =
                vault::open(&from_hex(&data)?, &login, &password).map_err(|e| e.to_string())?;
            json!({ "k_app": to_hex(key.to_bytes().as_ref()), "fingerprint": key.fingerprint() })
        }
        Request::License { key } => {
            let lic = license::verify_pro(&key).map_err(|e| e.to_string())?;
            json!({ "serial": lic.serial, "issued": lic.issued_date() })
        }
        Request::Secret {
            k_app,
            kind,
            label,
            counter,
        } => {
            let secret = app_key(&k_app)?
                .secret(&kind, &label, counter)
                .map_err(|e| e.to_string())?;
            json!({
                "label": normalize::login(&label),
                "value": secret.value.as_str(),
                "public": secret.public,
            })
        }
        Request::TransferExport {
            k_app,
            index,
            nonce,
        } => {
            let nonce: [u8; NONCE_LEN] = from_hex(&nonce)?
                .try_into()
                .map_err(|_| "nonce: нужно 24 байта")?;
            let code = transfer::export_text_with_nonce(&index, &app_key(&k_app)?, &nonce)
                .map_err(|e| e.to_string())?;
            json!({ "code": code })
        }
        Request::TransferImport {
            k_app,
            mut index,
            code,
        } => {
            let other =
                transfer::import_text(&code, &app_key(&k_app)?).map_err(|e| e.to_string())?;
            let r = index.merge(other);
            json!({ "index": index, "added": r.added, "updated": r.updated, "kept": r.kept })
        }
    })
}

fn app_key(hex: &str) -> Result<AppKey, String> {
    let bytes = Zeroizing::new(from_hex(hex)?);
    let k: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| "k_app: нужно 32 байта".to_string())?;
    Ok(AppKey::from_array(k))
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn from_hex(s: &str) -> Result<Vec<u8>, String> {
    if !s.len().is_multiple_of(2) {
        return Err("hex: нечётная длина".into());
    }
    (0..s.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| "hex: некорректный символ".to_string())
        })
        .collect()
}
