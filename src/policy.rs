//! Политика пароля и детерминированное кодирование байтового потока в пароль.

use serde::{Deserialize, Serialize};

use crate::{Error, Result};

pub const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
pub const UPPER: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const DIGITS: &str = "0123456789";
/// Символы, которые принимает подавляющее большинство сайтов: без пробела,
/// кавычек, обратного слэша и скобок.
pub const SYMBOLS: &str = "!#$%&*+-.:;=?@^_~";

pub const MIN_LENGTH: u8 = 8;
pub const MAX_LENGTH: u8 = 64;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Policy {
    pub length: u8,
    pub lower: bool,
    pub upper: bool,
    pub digits: bool,
    pub symbols: bool,
}

impl Default for Policy {
    fn default() -> Self {
        Policy {
            length: 20,
            lower: true,
            upper: true,
            digits: true,
            symbols: true,
        }
    }
}

impl Policy {
    pub fn validate(&self) -> Result<()> {
        if !(MIN_LENGTH..=MAX_LENGTH).contains(&self.length) {
            return Err(Error::Policy(format!(
                "длина {} вне диапазона {MIN_LENGTH}..={MAX_LENGTH}",
                self.length
            )));
        }
        if self.classes().is_empty() {
            return Err(Error::Policy("нужен хотя бы один класс символов".into()));
        }
        Ok(())
    }

    /// Каноническая строка политики; входит в HKDF info, поэтому её формат
    /// заморожен спецификацией v1.
    pub fn canonical(&self) -> String {
        let mut cls = String::new();
        for (on, c) in [
            (self.lower, 'l'),
            (self.upper, 'u'),
            (self.digits, 'd'),
            (self.symbols, 's'),
        ] {
            if on {
                cls.push(c);
            }
        }
        format!("len={};cls={}", self.length, cls)
    }

    fn classes(&self) -> Vec<&'static str> {
        [
            (self.lower, LOWER),
            (self.upper, UPPER),
            (self.digits, DIGITS),
            (self.symbols, SYMBOLS),
        ]
        .into_iter()
        .filter_map(|(on, set)| on.then_some(set))
        .collect()
    }

    /// Кодирует детерминированный поток байтов в пароль:
    /// по одному символу каждого включённого класса, остальное из объединения
    /// классов, затем перемешивание Фишера–Йетса. Все выборки — rejection
    /// sampling, без смещения по модулю.
    pub fn encode(&self, stream: &mut ByteStream) -> Result<String> {
        self.validate()?;
        let classes: Vec<Vec<char>> = self.classes().iter().map(|s| s.chars().collect()).collect();
        let all: Vec<char> = classes.iter().flatten().copied().collect();

        let mut out = Vec::with_capacity(self.length as usize);
        for class in &classes {
            out.push(class[stream.uniform(class.len())?]);
        }
        while out.len() < self.length as usize {
            out.push(all[stream.uniform(all.len())?]);
        }
        for i in (1..out.len()).rev() {
            let j = stream.uniform(i + 1)?;
            out.swap(i, j);
        }
        Ok(out.into_iter().collect())
    }
}

/// Конечный детерминированный поток байтов (выход HKDF-Expand).
pub struct ByteStream {
    buf: zeroize::Zeroizing<Vec<u8>>,
    pos: usize,
}

impl ByteStream {
    pub fn new(buf: Vec<u8>) -> Self {
        ByteStream {
            buf: zeroize::Zeroizing::new(buf),
            pos: 0,
        }
    }

    fn next(&mut self) -> Result<u8> {
        let b = *self
            .buf
            .get(self.pos)
            .ok_or_else(|| Error::Derivation("исчерпан поток байтов".into()))?;
        self.pos += 1;
        Ok(b)
    }

    /// Равномерное число в `0..2048` (индекс слова BIP39): младшие 11 бит из двух байт.
    pub fn bits11(&mut self) -> Result<usize> {
        let hi = self.next()? as usize;
        let lo = self.next()? as usize;
        Ok(((hi << 8) | lo) & 0x7ff)
    }

    /// Равномерное число в `0..n`, `1 <= n <= 256`.
    pub fn uniform(&mut self, n: usize) -> Result<usize> {
        assert!((1..=256).contains(&n));
        let limit = 256 - 256 % n;
        loop {
            let b = self.next()? as usize;
            if b < limit {
                return Ok(b % n);
            }
        }
    }
}
