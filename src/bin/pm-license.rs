//! `pm-license` — выпуск офлайн-ключей Pro. Запускается только у издателя.

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

use bip39_pm::license::{publisher_key, Edition, License};
use clap::{Parser, Subcommand};
use ed25519_dalek::SigningKey;
use zeroize::Zeroizing;

/// Номер дня 2026-01-01 от начала эпохи Unix.
const EPOCH_2026: u64 = 20_454;

#[derive(Parser)]
#[command(name = "pm-license", about = "Выпуск офлайн-ключей Pro для ManagerBIP")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Создать ключ издателя. Файл хранить офлайн, в приложение идёт только публичный ключ.
    Keygen {
        #[arg(long)]
        out: PathBuf,
    },
    /// Выпустить пачку ключей: строки `серийный_номер,ключ`.
    Issue {
        /// Файл ключа издателя.
        #[arg(long)]
        key: PathBuf,
        /// Первый серийный номер. Номера не должны повторяться между пачками.
        #[arg(long)]
        from: u32,
        #[arg(long, default_value_t = 1)]
        count: u32,
    },
    /// Проверить ключ пользователя.
    Verify {
        /// Публичный ключ издателя, hex.
        #[arg(long)]
        pubkey: String,
        license: String,
    },
}

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("ошибка: {e}");
            ExitCode::FAILURE
        }
    }
}

type AnyResult<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn run(cli: Cli) -> AnyResult<()> {
    match cli.command {
        Command::Keygen { out } => {
            let mut seed = Zeroizing::new([0u8; 32]);
            getrandom::getrandom(seed.as_mut())?;
            let signer = SigningKey::from_bytes(&seed);
            write_secret(&out, &hex::encode(seed.as_ref()))?;
            println!("{}", hex::encode(signer.verifying_key().to_bytes()));
            eprintln!(
                "Публичный ключ выше вшейте в приложение. Сделайте резервную копию файла ключа."
            );
        }
        Command::Issue { key, from, count } => {
            let signer = load_signer(&key)?;
            let last = from
                .checked_add(count.saturating_sub(1))
                .ok_or("серийные номера выходят за u32")?;
            let issued_day = today()?;
            for serial in from..=last {
                let lic = License {
                    edition: Edition::Pro,
                    serial,
                    issued_day,
                };
                println!("{serial},{}", lic.issue(&signer));
            }
        }
        Command::Verify { pubkey, license } => {
            let lic = License::verify(&license, &publisher_key(&pubkey)?, &[])?;
            println!(
                "ok: {:?}, серийный номер {}, выпущен на день {}",
                lic.edition, lic.serial, lic.issued_day
            );
        }
    }
    Ok(())
}

fn today() -> AnyResult<u16> {
    let days = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() / 86_400;
    Ok(u16::try_from(days.saturating_sub(EPOCH_2026))?)
}

fn load_signer(path: &PathBuf) -> AnyResult<SigningKey> {
    let text = Zeroizing::new(std::fs::read_to_string(path)?);
    let bytes = Zeroizing::new(hex::decode(text.trim())?);
    let seed: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| "файл ключа издателя повреждён")?;
    Ok(SigningKey::from_bytes(&seed))
}

fn write_secret(path: &PathBuf, contents: &str) -> AnyResult<()> {
    use std::io::Write;
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    let mut f = opts.open(path).map_err(|e| {
        format!(
            "{}: {e} (существующий ключ не перезаписывается)",
            path.display()
        )
    })?;
    writeln!(f, "{contents}")?;
    Ok(())
}
