//! `pm` — командная строка детерминированного менеджера паролей.

use std::path::PathBuf;
use std::process::ExitCode;

use bip39_pm::index::SecretEntry;
use bip39_pm::{transfer, AppKey, Entry, Index, Policy, SecretKind, Site};
use clap::{Args, Parser, Subcommand};
use zeroize::Zeroizing;

#[derive(Parser)]
#[command(
    name = "pm",
    version,
    about = "Детерминированный менеджер паролей на BIP39 seed"
)]
struct Cli {
    /// Путь к зашифрованному индексу.
    #[arg(long, env = "PM_INDEX", global = true)]
    index: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Создать новую seed-фразу BIP39.
    NewSeed {
        /// Число слов: 12 или 24.
        #[arg(long, default_value_t = 24)]
        words: usize,
    },
    /// Показать отпечаток seed + passphrase (сверка после восстановления).
    Fingerprint,
    /// Вычислить пароль для сайта и логина.
    Get {
        /// Домен или URL сайта.
        site: String,
        /// Логин или e-mail.
        login: String,
        #[command(flatten)]
        opts: PolicyOpts,
        /// Сохранить параметры в индекс.
        #[arg(long)]
        save: bool,
        /// Вывести только пароль.
        #[arg(short, long)]
        quiet: bool,
    },
    /// Сменить пароль: счётчик + 1 (сохраняется в индекс).
    Rotate {
        site: String,
        login: String,
        #[arg(short, long)]
        quiet: bool,
    },
    /// Список аккаунтов из индекса.
    List,
    /// Секрет из той же фразы: PIN, кодовые слова, пароль Wi‑Fi, ключ SSH.
    Secret {
        #[arg(value_enum)]
        kind: SecretArg,
        /// Метка: «карта сбер», «домашний wifi», «github laptop».
        label: String,
        /// Длина PIN или пароля Wi‑Fi, число слов.
        #[arg(long)]
        size: Option<u8>,
        #[arg(long, default_value_t = 1)]
        counter: u32,
        /// Сохранить метку в индекс (значение не сохраняется).
        #[arg(long)]
        save: bool,
    },
    /// Код переноса индекса на другое устройство (`PMX1:…`).
    Export,
    /// Влить индекс из кода переноса (аргумент или stdin).
    Import { code: Option<String> },
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum SecretArg {
    Pin,
    Words,
    Wifi,
    Ssh,
}

impl SecretArg {
    fn kind(self, size: Option<u8>) -> SecretKind {
        match self {
            SecretArg::Pin => SecretKind::Pin {
                length: size.unwrap_or(4),
            },
            SecretArg::Words => SecretKind::Words {
                count: size.unwrap_or(4),
            },
            SecretArg::Wifi => SecretKind::Wifi {
                length: size.unwrap_or(20),
            },
            SecretArg::Ssh => SecretKind::Ssh,
        }
    }
}

#[derive(Args)]
struct PolicyOpts {
    /// Номер версии пароля (по умолчанию 1 или из индекса).
    #[arg(long)]
    counter: Option<u32>,
    /// Длина пароля, 8..=64.
    #[arg(long)]
    length: Option<u8>,
    #[arg(long)]
    no_lower: bool,
    #[arg(long)]
    no_upper: bool,
    #[arg(long)]
    no_digits: bool,
    #[arg(long)]
    no_symbols: bool,
}

impl PolicyOpts {
    /// Флаги командной строки поверх сохранённой (или стандартной) политики.
    fn apply(&self, base: &Policy) -> Policy {
        Policy {
            length: self.length.unwrap_or(base.length),
            lower: base.lower && !self.no_lower,
            upper: base.upper && !self.no_upper,
            digits: base.digits && !self.no_digits,
            symbols: base.symbols && !self.no_symbols,
        }
    }
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
    let index_path = cli.index.clone().or_else(default_index_path);
    match cli.command {
        Command::NewSeed { words } => {
            if !bip39_pm::NEW_SEED_WORD_COUNTS.contains(&words) {
                return Err("новая фраза бывает из 12 или 24 слов".into());
            }
            let m = bip39::Mnemonic::generate(words)?;
            println!("{m}");
            eprintln!("Запишите фразу на бумагу. Не фотографируйте и не храните её в облаке.");
        }
        Command::Fingerprint => {
            let key = unlock()?;
            println!("{}", key.fingerprint());
        }
        Command::Get {
            site,
            login,
            opts,
            save,
            quiet,
        } => {
            let key = unlock()?;
            let mut index = load_index(&key, index_path.as_ref())?;
            let probe = Site::new(&site, &login, 1)?;
            let (base_counter, base_policy) = index
                .find(&probe.domain, &probe.login)
                .map_or((1, index.default_policy.unwrap_or_default()), |e| {
                    (e.counter, e.policy)
                });
            let counter = opts.counter.unwrap_or(base_counter);
            let policy = opts.apply(&base_policy);
            let site = Site { counter, ..probe };
            print_password(&key, &site, &policy, quiet)?;
            if save {
                index.upsert(Entry {
                    domain: site.domain,
                    login: site.login,
                    counter,
                    policy,
                    note: None,
                });
                save_index(&key, &index, index_path.as_ref())?;
            }
        }
        Command::Rotate { site, login, quiet } => {
            let key = unlock()?;
            let mut index = load_index(&key, index_path.as_ref())?;
            let probe = Site::new(&site, &login, 1)?;
            let mut entry = index
                .find(&probe.domain, &probe.login)
                .cloned()
                .unwrap_or(Entry {
                    domain: probe.domain.clone(),
                    login: probe.login.clone(),
                    counter: 1,
                    policy: index.default_policy.unwrap_or_default(),
                    note: None,
                });
            entry.counter += 1;
            let site = Site {
                counter: entry.counter,
                ..probe
            };
            print_password(&key, &site, &entry.policy, quiet)?;
            index.upsert(entry);
            save_index(&key, &index, index_path.as_ref())?;
        }
        Command::List => {
            let key = unlock()?;
            let index = load_index(&key, index_path.as_ref())?;
            if index.entries.is_empty() {
                eprintln!("индекс пуст");
            }
            for e in &index.entries {
                println!(
                    "{}\t{}\t#{}\t{}",
                    e.domain,
                    e.login,
                    e.counter,
                    e.policy.canonical()
                );
            }
            for s in &index.secrets {
                println!(
                    "секрет\t{}\t#{}\t{}",
                    s.label,
                    s.counter,
                    s.kind.canonical()
                );
            }
        }
        Command::Secret {
            kind,
            label,
            size,
            counter,
            save,
        } => {
            let key = unlock()?;
            let kind = kind.kind(size);
            let secret = key.secret(&kind, &label, counter)?;
            if let Some(public) = &secret.public {
                eprintln!("открытый ключ:\n{public}\n");
            }
            println!("{}", secret.value.as_str());
            if save {
                let mut index = load_index(&key, index_path.as_ref())?;
                let label = bip39_pm::normalize::login(&label);
                index
                    .secrets
                    .retain(|s| !(s.kind == kind && s.label == label));
                index.secrets.push(SecretEntry {
                    label,
                    kind,
                    counter,
                    note: None,
                });
                save_index(&key, &index, index_path.as_ref())?;
            }
        }
        Command::Export => {
            let key = unlock()?;
            let index = load_index(&key, index_path.as_ref())?;
            println!("{}", transfer::export_text(&index, &key)?);
        }
        Command::Import { code } => {
            let code = match code {
                Some(c) => c,
                None => std::io::read_to_string(std::io::stdin())?,
            };
            let key = unlock()?;
            let mut index = load_index(&key, index_path.as_ref())?;
            let r = index.merge(transfer::import_text(&code, &key)?);
            eprintln!(
                "добавлено: {}, обновлено: {}, без изменений: {}",
                r.added, r.updated, r.kept
            );
            save_index(&key, &index, index_path.as_ref())?;
        }
    }
    Ok(())
}

fn print_password(key: &AppKey, site: &Site, policy: &Policy, quiet: bool) -> AnyResult<()> {
    let pw = key.password(site, policy)?;
    if quiet {
        println!("{}", pw.as_str());
    } else {
        println!("сайт:     {}", site.domain);
        println!("логин:    {}", site.login);
        println!("версия:   {}  ({})", site.counter, policy.canonical());
        println!("пароль:   {}", pw.as_str());
        println!("проверка: {}", key.check_words(site, policy));
    }
    Ok(())
}

/// Seed берётся из `PM_MNEMONIC` (для скриптов и тестов) или вводится скрыто.
fn unlock() -> AnyResult<AppKey> {
    let phrase = match std::env::var("PM_MNEMONIC") {
        Ok(v) => Zeroizing::new(v),
        Err(_) => Zeroizing::new(rpassword::prompt_password("Seed-фраза: ")?),
    };
    let passphrase = match std::env::var("PM_PASSPHRASE") {
        Ok(v) => Zeroizing::new(v),
        Err(_) if std::env::var("PM_MNEMONIC").is_ok() => Zeroizing::new(String::new()),
        Err(_) => Zeroizing::new(rpassword::prompt_password(
            "Passphrase (Enter — без неё): ",
        )?),
    };
    let key = AppKey::from_mnemonic(&phrase, &passphrase)?;
    eprintln!("отпечаток seed: {}", key.fingerprint());
    Ok(key)
}

fn default_index_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("bip39-pm").join("index.pmx"))
}

fn load_index(key: &AppKey, path: Option<&PathBuf>) -> AnyResult<Index> {
    match path {
        Some(p) if p.exists() => Ok(Index::decrypt(&std::fs::read(p)?, &key.index_key())?),
        _ => Ok(Index::default()),
    }
}

fn save_index(key: &AppKey, index: &Index, path: Option<&PathBuf>) -> AnyResult<()> {
    let p = path.ok_or("не удалось определить путь к индексу, задайте --index")?;
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = p.with_extension("tmp");
    std::fs::write(&tmp, index.encrypt(&key.index_key())?)?;
    std::fs::rename(&tmp, p)?;
    eprintln!("индекс сохранён: {}", p.display());
    Ok(())
}
