#!/usr/bin/env python3
"""Независимая эталонная реализация спецификации bip39-pm v1 (только stdlib).

Нужна, чтобы доказать: пароли восстанавливаются без нашего приложения.
Принимает уже нормализованные домен и логин (см. SPEC.md, раздел 3).
"""
import hashlib
import hmac
import os
import struct
import sys
import unicodedata

N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
LOWER = "abcdefghijklmnopqrstuvwxyz"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
DIGITS = "0123456789"
SYMBOLS = "!#$%&*+-.:;=?@^_~"
SALT = b"bip39-pm/v1"


def seed_from_mnemonic(mnemonic, passphrase=""):
    m = unicodedata.normalize("NFKD", " ".join(mnemonic.lower().split()))
    s = unicodedata.normalize("NFKD", "mnemonic" + passphrase)
    return hashlib.pbkdf2_hmac("sha512", m.encode(), s.encode(), 2048)


def bip85_k_app(seed):
    i = hmac.new(b"Bitcoin seed", seed, hashlib.sha512).digest()
    k, chain = int.from_bytes(i[:32], "big"), i[32:]
    for idx in (83696968, 20567, 0):
        data = b"\x00" + k.to_bytes(32, "big") + struct.pack(">I", idx | 0x80000000)
        i = hmac.new(chain, data, hashlib.sha512).digest()
        k, chain = (int.from_bytes(i[:32], "big") + k) % N, i[32:]
    return hmac.new(b"bip-entropy-from-k", k.to_bytes(32, "big"), hashlib.sha512).digest()[:32]


def hkdf_expand(prk, info, length):
    out, t, c = b"", b"", 1
    while len(out) < length:
        t = hmac.new(prk, t + info + bytes([c]), hashlib.sha256).digest()
        out, c = out + t, c + 1
    return out[:length]


def hkdf(ikm, info, length, salt=SALT):
    return hkdf_expand(hmac.new(salt, ikm, hashlib.sha256).digest(), info, length)


def canonical(length, l, u, d, s):
    return "len=%d;cls=%s" % (length, "".join(c for on, c in zip((l, u, d, s), "luds") if on))


class Stream:
    def __init__(self, key):
        self.it = iter(hkdf_expand(key, b"bip39-pm/v1/stream", 1024))

    def uniform(self, n):
        limit = 256 - 256 % n
        while True:
            b = next(self.it)
            if b < limit:
                return b % n

    def bits11(self):
        return ((next(self.it) << 8) | next(self.it)) & 0x7FF


def encode(stream, length, l, u, d, s):
    uniform = stream.uniform
    classes = [c for on, c in zip((l, u, d, s), (LOWER, UPPER, DIGITS, SYMBOLS)) if on]
    union = "".join(classes)
    out = [c[uniform(len(c))] for c in classes]
    while len(out) < length:
        out.append(union[uniform(len(union))])
    for i in range(len(out) - 1, 0, -1):
        j = uniform(i + 1)
        out[i], out[j] = out[j], out[i]
    return "".join(out)


def password(k_app, domain, login, counter, length=20, l=True, u=True, d=True, s=True):
    info = b"bip39-pm/v1/password"
    for f in (domain.encode(), login.encode(), canonical(length, l, u, d, s).encode()):
        info += struct.pack(">I", len(f)) + f
    info += struct.pack(">I", counter)
    return encode(Stream(hkdf(k_app, info, 32)), length, l, u, d, s)


def secret(k_app, kind, size, label, counter, wordlist):
    """SPEC.md, раздел 10. Метка уже нормализована (NFKC, пробелы, нижний регистр)."""
    canon = {"pin": "pin;len=%d", "words": "words;n=%d", "wifi": "wifi;len=%d"}[kind] % size
    info = b"bip39-pm/v1/secret"
    for f in (canon.encode(), label.encode()):
        info += struct.pack(">I", len(f)) + f
    info += struct.pack(">I", counter)
    st = Stream(hkdf(k_app, info, 32))
    if kind == "pin":
        return "".join(DIGITS[st.uniform(10)] for _ in range(size))
    if kind == "words":
        return " ".join(wordlist[st.bits11()] for _ in range(size))
    return encode(st, size, True, True, True, False)


if __name__ == "__main__":
    k = bip85_k_app(seed_from_mnemonic(" ".join(["abandon"] * 11 + ["about"])))
    vectors = [
        (("github.com", "vlad@mail.ru", 1), {}, "q~9Tlw:qOyeSzu?69AUx"),
        (("github.com", "vlad@mail.ru", 2), {}, "eITvMChQRH+*gVT-n4FJ"),
        (("github.com", "other@mail.ru", 1), {}, "l4nhKOQY$x$E85uidyw4"),
        (("bank.ru", "vlad", 1), {"length": 16, "s": False}, "oh1fWuHJh2e3emF0"),
        (("xn--e1afmkfd.xn--p1ai", "vlad", 1), {"length": 8, "l": False, "u": False, "s": False}, "48777879"),
    ]
    ok = True
    for args, kw, want in vectors:
        got = password(k, *args, **kw)
        print("OK " if got == want else "FAIL", args, got)
        ok &= got == want
    # Официальный английский словарь BIP39 (sha256 2f5eed53…dbda).
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bip39-english.txt")) as f:
        wordlist = f.read().split()
    secrets = [
        (("pin", 4, "карта", 1), "5987"),
        (("pin", 6, "карта сбер", 1), "936802"),
        (("wifi", 20, "home wifi", 1), "1w2hnpKJyh93chs4N61a"),
        (("words", 4, "secret question", 1), "rice trade budget staff"),
    ]
    for args, want in secrets:
        got = secret(k, *args, wordlist)
        print("OK " if got == want else "FAIL", args, got)
        ok &= got == want
    sys.exit(0 if ok else 1)
