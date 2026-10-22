// Обёртка над WASM-ядром (pm_core.wasm, собирается из crate bip39-pm-wasm).
// Работает и в расширении, и в Node (тесты).

export async function loadCore(source) {
  const bytes =
    source instanceof ArrayBuffer || ArrayBuffer.isView(source)
      ? source
      : await (await fetch(source)).arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const ex = instance.exports;
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function call(request) {
    const input = encoder.encode(JSON.stringify(request));
    const ptr = ex.pm_alloc(input.length);
    new Uint8Array(ex.memory.buffer, ptr, input.length).set(input);
    input.fill(0);
    const packed = ex.pm_call(ptr, input.length);
    ex.pm_free(ptr, input.length);
    const outPtr = Number(packed >> 32n);
    const outLen = Number(packed & 0xffffffffn);
    const text = decoder.decode(new Uint8Array(ex.memory.buffer, outPtr, outLen).slice());
    ex.pm_free(outPtr, outLen);
    const response = JSON.parse(text);
    if ("error" in response) throw new Error(response.error);
    return response.ok;
  }

  return {
    call,
    memoryBytes: () => ex.memory.buffer.byteLength,
    generate(words = 24) {
      const entropy = crypto.getRandomValues(new Uint8Array(words === 12 ? 16 : 32));
      return call({ op: "generate", entropy: toHex(entropy) }).mnemonic;
    },
    unlock: (mnemonic, passphrase = "") => call({ op: "unlock", mnemonic, passphrase }),
    domain: (url) => call({ op: "domain", url }).domain,
    password: (kApp, site, login, counter, policy) =>
      call({ op: "password", k_app: kApp, site, login, counter, policy }),
    encryptIndex: (kApp, index) =>
      call({ op: "index_encrypt", k_app: kApp, index, nonce: toHex(crypto.getRandomValues(new Uint8Array(24))) })
        .data,
    decryptIndex: (kApp, data) => call({ op: "index_decrypt", k_app: kApp, data }).index,
  };
}

export const DEFAULT_POLICY = Object.freeze({ length: 20, lower: true, upper: true, digits: true, symbols: true });

export function toHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/// Вставка/замена записи; порядок как в Rust-ядре (домен, затем логин).
export function upsertEntry(index, entry) {
  const entries = index.entries.filter((e) => !(e.domain === entry.domain && e.login === entry.login));
  entries.push(entry);
  entries.sort((a, b) => (a.domain + "\u0000" + a.login < b.domain + "\u0000" + b.login ? -1 : 1));
  return { ...index, entries };
}
