// MikuOS Web Installer - flash engine.
//
// Talks to the bootloader through fastboot.js' PUBLIC API only (getVariable, runCommand,
// upload). Chunking, sparse-wrapping, hashing and the partition plan are implemented here
// so that the M500's hard limits are honoured regardless of what the bootloader advertises:
//   * every payload <= 64 MiB (sparse headers included), one at a time, never two streams,
//   * every byte is SHA-256-verified against the manifest BEFORE it is uploaded,
//   * a failed chunk is retried, and a failed run can be resumed at the exact chunk.
import { CONFIG, BOOT_CHAIN, VBMETA_DISABLED, VBMETA_STOCK, REQUIRED_IMAGES } from "./config.js";

const BLOCK = CONFIG.BLOCK_SIZE;

// ----------------------------------------------------------------------------
// Sparse image format (AOSP libsparse), little-endian.
// ----------------------------------------------------------------------------
const SPARSE_MAGIC = 0xed26ff3a;
const FILE_HDR = 28;
const CHUNK_HDR = 12;
const CHUNK_RAW = 0xcac1;
const CHUNK_FILL = 0xcac2;
const CHUNK_DONT_CARE = 0xcac3;

/**
 * Wrap `data` (raw bytes for blocks [startBlock, startBlock + n) of a partition that is
 * `totalBlocks` long) into a self-contained sparse image. Runs of all-zero blocks become
 * FILL(0) chunks (fewer bytes on the wire, exactly what host fastboot's libsparse does),
 * everything before/after becomes DONT_CARE so the bootloader leaves those blocks alone.
 * Every chunk in a run is therefore a complete, independently flashable image - which is
 * what makes resume-at-chunk safe.
 */
export function buildSparseImage(data, startBlock, totalBlocks) {
  if (data.byteLength % BLOCK !== 0) {
    throw new Error(`sparse: data length ${data.byteLength} is not a multiple of ${BLOCK}`);
  }
  const nBlocks = data.byteLength / BLOCK;
  const u32 = new Uint32Array(data); // data comes from fetch/slice -> offset 0, aligned
  const wordsPerBlock = BLOCK / 4;

  // Pass 1: classify blocks into runs (zero / raw).
  const runs = []; // {zero: bool, start: blockIdx, count}
  for (let b = 0; b < nBlocks; b++) {
    const base = b * wordsPerBlock;
    let zero = true;
    for (let w = 0; w < wordsPerBlock; w++) {
      if (u32[base + w] !== 0) { zero = false; break; }
    }
    const last = runs[runs.length - 1];
    if (last && last.zero === zero) last.count++;
    else runs.push({ zero, start: b, count: 1 });
  }

  // Pass 2: size the output.
  let chunks = 0;
  let bytes = FILE_HDR;
  if (startBlock > 0) { chunks++; bytes += CHUNK_HDR; }
  for (const r of runs) {
    chunks++;
    bytes += CHUNK_HDR + (r.zero ? 4 : r.count * BLOCK);
  }
  const tailBlocks = totalBlocks - (startBlock + nBlocks);
  if (tailBlocks < 0) throw new Error("sparse: chunk extends past end of partition");
  if (tailBlocks > 0) { chunks++; bytes += CHUNK_HDR; }

  const out = new ArrayBuffer(bytes);
  const dv = new DataView(out);
  const u8 = new Uint8Array(out);
  const src = new Uint8Array(data);
  let off = 0;
  dv.setUint32(off, SPARSE_MAGIC, true); off += 4;
  dv.setUint16(off, 1, true); off += 2;       // major
  dv.setUint16(off, 0, true); off += 2;       // minor
  dv.setUint16(off, FILE_HDR, true); off += 2;
  dv.setUint16(off, CHUNK_HDR, true); off += 2;
  dv.setUint32(off, BLOCK, true); off += 4;
  dv.setUint32(off, totalBlocks, true); off += 4;
  dv.setUint32(off, chunks, true); off += 4;
  dv.setUint32(off, 0, true); off += 4;       // checksum: unused (AOSP sets 0)

  const hdr = (type, blocksInChunk, payloadBytes) => {
    dv.setUint16(off, type, true); off += 2;
    dv.setUint16(off, 0, true); off += 2;
    dv.setUint32(off, blocksInChunk, true); off += 4;
    dv.setUint32(off, CHUNK_HDR + payloadBytes, true); off += 4;
  };
  if (startBlock > 0) hdr(CHUNK_DONT_CARE, startBlock, 0);
  for (const r of runs) {
    if (r.zero) {
      hdr(CHUNK_FILL, r.count, 4);
      dv.setUint32(off, 0, true); off += 4;
    } else {
      const len = r.count * BLOCK;
      hdr(CHUNK_RAW, r.count, len);
      u8.set(src.subarray(r.start * BLOCK, r.start * BLOCK + len), off);
      off += len;
    }
  }
  if (tailBlocks > 0) hdr(CHUNK_DONT_CARE, tailBlocks, 0);
  if (off !== bytes) throw new Error("sparse: internal size mismatch");
  return out;
}

// ----------------------------------------------------------------------------
// Hashing (Web Crypto). Buffers here are <= 128 MiB so a single digest call is fine.
// ----------------------------------------------------------------------------
export async function sha256Hex(buffer) {
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

// ----------------------------------------------------------------------------
// Image sources: something with a size and readRange(start, endExclusive) -> ArrayBuffer.
// ----------------------------------------------------------------------------
export class UrlSource {
  constructor(url, expectedSize) {
    this.url = url;
    this.size = expectedSize;
    this.kind = "url";
  }
  /** Cheap pre-flight: confirm the server has a file of the right size and speaks Range. */
  async probe() {
    let res;
    try {
      res = await fetch(this.url, { method: "HEAD", cache: "no-store" });
    } catch (e) {
      throw new Error(`Cannot reach ${this.url}: ${e.message} (CORS? offline?)`);
    }
    if (!res.ok) throw new Error(`HEAD ${this.url} -> HTTP ${res.status}`);
    const len = res.headers.get("content-length");
    if (len !== null && Number(len) !== this.size) {
      throw new Error(`${this.url}: server reports ${len} bytes, manifest says ${this.size}. Wrong file uploaded or stale manifest.`);
    }
    const ar = res.headers.get("accept-ranges");
    return { contentLength: len === null ? null : Number(len), acceptRanges: ar };
  }
  async readRange(start, end) {
    if (start === 0 && end >= this.size) {
      const res = await fetch(this.url, { cache: "no-store" });
      if (!res.ok) throw new Error(`GET ${this.url} -> HTTP ${res.status}`);
      const buf = await res.arrayBuffer();
      if (buf.byteLength !== this.size) throw new Error(`${this.url}: got ${buf.byteLength} bytes, expected ${this.size}`);
      return buf;
    }
    const res = await fetch(this.url, { headers: { Range: `bytes=${start}-${end - 1}` }, cache: "no-store" });
    if (res.status !== 206) {
      throw new Error(`Server did not honour the Range request for ${this.url} (HTTP ${res.status}). ` +
        `The image host must support HTTP Range requests (Cloudflare R2/Pages, GitHub, nginx, or tools/web-installer/serve.py do; python -m http.server does NOT).`);
    }
    const buf = await res.arrayBuffer();
    if (buf.byteLength !== end - start) throw new Error(`Range ${start}-${end - 1} of ${this.url}: got ${buf.byteLength} bytes`);
    return buf;
  }
}

export class FileSource {
  constructor(file) {
    this.file = file;
    this.size = file.size;
    this.kind = "file";
    this.url = file.name;
  }
  async probe() { return { contentLength: this.size, acceptRanges: "bytes" }; }
  async readRange(start, end) {
    return await this.file.slice(start, end).arrayBuffer();
  }
}

// ----------------------------------------------------------------------------
// Manifest handling
// ----------------------------------------------------------------------------
export function validateManifest(m) {
  const problems = [];
  if (!m || typeof m !== "object") return ["manifest is not a JSON object"];
  if (m.schema !== 1) problems.push(`unsupported manifest schema ${m.schema} (expected 1)`);
  if (!m.images || typeof m.images !== "object") problems.push("manifest has no images");
  const chunk = m.chunk_size ?? CONFIG.DEFAULT_CHUNK_BYTES;
  if (!Number.isInteger(chunk) || chunk % BLOCK !== 0 || chunk <= 0 || chunk > CONFIG.DEFAULT_CHUNK_BYTES) {
    problems.push(`chunk_size ${chunk} invalid: must be a positive multiple of ${BLOCK} and <= ${CONFIG.DEFAULT_CHUNK_BYTES} (64 MiB payload cap)`);
  }
  for (const key of REQUIRED_IMAGES) {
    if (!m.images?.[key]) problems.push(`missing required image "${key}"`);
  }
  for (const [key, img] of Object.entries(m.images ?? {})) {
    if (!img.url && !img.file) problems.push(`${key}: no url/file`);
    if (!Number.isInteger(img.size) || img.size <= 0) problems.push(`${key}: bad size`);
    if (!/^[0-9a-f]{64}$/i.test(img.sha256 ?? "")) problems.push(`${key}: bad sha256`);
    if (img.size > CONFIG.RAW_SINGLE_PAYLOAD_LIMIT) {
      const need = Math.ceil(img.size / chunk);
      if (!Array.isArray(img.chunks) || img.chunks.length !== need) {
        problems.push(`${key}: is ${img.size} bytes so it needs ${need} per-chunk sha256 entries in "chunks" (regenerate with make_release_manifest.py)`);
      }
      if (img.size % BLOCK !== 0) problems.push(`${key}: size must be a multiple of ${BLOCK} for chunked flashing`);
    }
  }
  const sup = m.images?.mikuos_system_bundle;
  if (sup && sup.size !== CONFIG.EXPECTED_SUPER_SIZE) {
    problems.push(`mikuos_system_bundle is ${sup.size} bytes; the M500 super partition is exactly ${CONFIG.EXPECTED_SUPER_SIZE}. Rebuild with build_mikuos_super.sh.`);
  }
  return problems;
}

export function resolveImageUrl(manifest, manifestUrl, img) {
  const base = manifest.base_url ? new URL(manifest.base_url, manifestUrl) : new URL(manifestUrl, location.href);
  return new URL(img.url ?? img.file, base).href;
}

// ----------------------------------------------------------------------------
// Plan builder - the exact partition sequence from the repo's proven scripts.
// ----------------------------------------------------------------------------
export function buildPlan(action, manifest, opts = {}) {
  const imgs = manifest.images;
  const has = (k) => Boolean(imgs[k]);
  const steps = [];
  const flash = (partition, imageKey) => steps.push({ kind: "flash", partition, imageKey, image: imgs[imageKey] });
  const cmd = (label, command) => steps.push({ kind: "cmd", label, command });

  const initBootKey = opts.withRoot ? "init_boot_rooted" : "init_boot";
  if (opts.withRoot && !has("init_boot_rooted")) throw new Error("This release has no init_boot_rooted image; root is unavailable.");

  const wipe = () => {
    // flash_mikuos_clean.sh / unbrick_factory.sh: after set_active a.
    cmd("Erase misc (clear boot-control block)", "erase:misc");
    cmd("Erase metadata (FBE keys)", "erase:metadata");
    cmd("Erase userdata", "erase:userdata");
    // Optional: pre-formatted empty userdata (what `fastboot -w` writes instead of a bare
    // erase). See README "wipe semantics".
    if (has("userdata_formatted")) flash("userdata", "userdata_formatted");
  };

  switch (action) {
    case "install_keepdata":
    case "install_clean": {
      for (const [p, k] of BOOT_CHAIN) flash(p, k === "init_boot" ? initBootKey : k);
      for (const [p, k] of VBMETA_DISABLED) flash(p, k);
      flash("super", "mikuos_system_bundle");
      cmd("Set active slot A", "set_active:a");
      if (action === "install_clean") wipe();
      cmd("Reboot into MikuOS", "reboot");
      break;
    }
    case "root": {
      if (!has("init_boot_rooted")) throw new Error("This release has no init_boot_rooted image.");
      flash("init_boot_a", "init_boot_rooted");
      flash("init_boot_b", "init_boot_rooted");
      cmd("Set active slot A", "set_active:a");
      cmd("Reboot", "reboot");
      break;
    }
    case "unroot": {
      flash("init_boot_a", "init_boot");
      flash("init_boot_b", "init_boot");
      cmd("Set active slot A", "set_active:a");
      cmd("Reboot", "reboot");
      break;
    }
    case "rollback_stock": {
      for (const k of ["stock_super", "vbmeta_stock", "vbmeta_system_stock"]) {
        if (!has(k)) throw new Error(`Rollback needs "${k}" in the release manifest.`);
      }
      for (const [p, k] of BOOT_CHAIN) flash(p, k);
      for (const [p, k] of VBMETA_STOCK) flash(p, k);
      flash("super", "stock_super");
      cmd("Set active slot A", "set_active:a");
      wipe();
      cmd("Reboot into stock firmware", "reboot");
      break;
    }
    default:
      throw new Error(`unknown action ${action}`);
  }
  steps.forEach((s, i) => (s.index = i));
  return steps;
}

export function actionAvailability(manifest) {
  const imgs = manifest?.images ?? {};
  return {
    install_keepdata: true,
    install_clean: true,
    root: Boolean(imgs.init_boot_rooted),
    unroot: Boolean(imgs.init_boot),
    rollback_stock: Boolean(imgs.stock_super && imgs.vbmeta_stock && imgs.vbmeta_system_stock),
  };
}

// ----------------------------------------------------------------------------
// Flasher: executes a plan against a connected FastbootDevice.
// ----------------------------------------------------------------------------
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class StallError extends Error {
  constructor(msg) { super(msg); this.name = "StallError"; }
}

export class Flasher {
  /**
   * @param fb   FastbootDevice (fastboot.js)
   * @param log  (level, message) => void
   * @param getSource (step) => UrlSource|FileSource
   */
  constructor(fb, log, getSource) {
    this.fb = fb;
    this.log = log;
    this.getSource = getSource;
    this.busy = false;       // single-stream guard: never two fastboot transfers at once
    this.abortRequested = false;
    this.maxDownload = null; // bootloader max-download-size in bytes
    this.progress = { stepIndex: 0, chunkIndex: 0 };
  }

  async _lock(fn) {
    if (this.busy) throw new Error("Another fastboot operation is already running. Never run two at once on the M500.");
    this.busy = true;
    try { return await fn(); } finally { this.busy = false; }
  }

  /** getvar helper that tolerates FAIL/empty. */
  async getvar(name) {
    try { return await this.fb.getVariable(name); } catch { return null; }
  }

  async readDeviceInfo() {
    return this._lock(async () => {
      const info = {};
      for (const v of ["product", "serialno", "current-slot", "unlocked", "secure",
        "version-bootloader", "version-baseband", "max-download-size", "partition-size:super",
        "slot-count", "battery-voltage", "battery-soc-ok", "variant", "hw-revision", "is-userspace"]) {
        info[v] = await this.getvar(v);
      }
      if (info["max-download-size"]) {
        const n = parseInt(info["max-download-size"], 16);
        this.maxDownload = Number.isFinite(n) && n > 0 ? n : null;
      }
      let all = "";
      try { all = (await this.fb.runCommand("getvar:all")).text; } catch { /* many ABLs refuse getvar:all */ }
      info.all = all;
      return info;
    });
  }

  async unlockBootloader() {
    return this._lock(async () => {
      this.log("warn", "Sending flashing:unlock. Confirm on the DEVICE if it asks. This wipes /data.");
      const r = await this.fb.runCommand("flashing:unlock");
      return r.text;
    });
  }

  async rebootDevice() {
    return this._lock(async () => { await this.fb.runCommand("reboot"); });
  }

  /** Verify a whole small image, or the per-chunk list of a big one, and return sources. */
  async preflight(plan) {
    const seen = new Map();
    for (const s of plan) {
      if (s.kind !== "flash" || seen.has(s.imageKey)) continue;
      const src = this.getSource(s);
      if (src.size !== s.image.size) {
        throw new Error(`${s.imageKey}: source is ${src.size} bytes but manifest says ${s.image.size}`);
      }
      const p = await src.probe();
      this.log("info", `${s.imageKey}: ${src.kind === "url" ? src.url : "local file " + src.url} (${fmtBytes(src.size)})${p.acceptRanges ? "" : " [server did not advertise Accept-Ranges]"}`);
      seen.set(s.imageKey, src);
    }
    return seen;
  }

  /**
   * Run the plan. `resume` = {stepIndex, chunkIndex} to continue after a failure.
   * onStep(step, status), onProgress(step, {chunk, chunks, bytesSent, bytesTotal}).
   */
  async runPlan(plan, manifest, { onStep, onProgress, resume } = {}) {
    return this._lock(async () => {
      this.abortRequested = false;
      const chunkBytes = manifest.chunk_size ?? CONFIG.DEFAULT_CHUNK_BYTES;
      const startStep = resume?.stepIndex ?? 0;
      for (const step of plan) {
        if (step.index < startStep) { onStep?.(step, "skipped"); continue; }
        if (this.abortRequested) throw new Error("Aborted by user");
        this.progress = { stepIndex: step.index, chunkIndex: 0 };
        onStep?.(step, "running");
        if (step.kind === "cmd") {
          this.log("cmd", `fastboot ${step.command.replace(":", " ")}`);
          const r = await this.fb.runCommand(step.command);
          if (r.text) this.log("info", r.text.trim());
          if (step.command === "reboot") this.log("ok", "Reboot sent. The USB connection will drop now - that is expected.");
        } else {
          const startChunk = step.index === startStep ? (resume?.chunkIndex ?? 0) : 0;
          await this._flashImage(step, chunkBytes, startChunk, onProgress);
        }
        onStep?.(step, "done");
      }
    });
  }

  async _flashImage(step, chunkBytes, startChunk, onProgress) {
    const { partition, imageKey, image } = step;
    const src = this.getSource(step);
    const size = image.size;
    const rawLimit = Math.min(CONFIG.RAW_SINGLE_PAYLOAD_LIMIT, this.maxDownload ?? Infinity);

    if (size <= rawLimit) {
      // Exactly what `fastboot flash <part> file.img` does for a small file: one raw payload.
      this.log("cmd", `fastboot flash ${partition} ${imageKey} (${fmtBytes(size)}, raw, single payload)`);
      const buf = await src.readRange(0, size);
      const h = await sha256Hex(buf);
      if (h !== image.sha256.toLowerCase()) {
        throw new Error(`${imageKey}: SHA-256 mismatch (got ${h}, manifest ${image.sha256}). Refusing to flash.`);
      }
      this.log("ok", `${imageKey}: sha256 verified`);
      await this._withRetry(`flash ${partition}`, async () => {
        await this._uploadWithWatchdog(partition, buf, (p) => onProgress?.(step, { chunk: 1, chunks: 1, bytesSent: p * size, bytesTotal: size }));
        await this.fb.runCommand(`flash:${partition}`);
      });
      onProgress?.(step, { chunk: 1, chunks: 1, bytesSent: size, bytesTotal: size });
      return;
    }

    // Big image: <= 64 MiB sparse chunks, each an independent, resumable image.
    if (size % BLOCK !== 0) throw new Error(`${imageKey}: size not block aligned`);
    const totalBlocks = size / BLOCK;
    const chunks = Math.ceil(size / chunkBytes);
    if (!Array.isArray(image.chunks) || image.chunks.length !== chunks) {
      throw new Error(`${imageKey}: manifest needs ${chunks} chunk hashes (has ${image.chunks?.length ?? 0})`);
    }
    // Belt and braces: never exceed what the bootloader will accept per download.
    if (this.maxDownload && chunkBytes + 1024 * 1024 > this.maxDownload) {
      throw new Error(`Bootloader max-download-size (${fmtBytes(this.maxDownload)}) is smaller than the manifest chunk size + headers. Regenerate release.json with --chunk-mib ${Math.floor(this.maxDownload / 1048576) - 1}.`);
    }
    this.log("cmd", `fastboot -S 64M flash ${partition} ${imageKey} (${fmtBytes(size)}, ${chunks} sparse chunks of <= ${fmtBytes(chunkBytes)})`);
    if (startChunk > 0) this.log("warn", `Resuming ${partition} at chunk ${startChunk + 1}/${chunks}`);

    for (let ci = startChunk; ci < chunks; ci++) {
      if (this.abortRequested) throw new Error("Aborted by user");
      this.progress.chunkIndex = ci;
      const start = ci * chunkBytes;
      const end = Math.min(size, start + chunkBytes);
      const expected = image.chunks[ci].toLowerCase();

      await this._withRetry(`${partition} chunk ${ci + 1}/${chunks}`, async () => {
        const data = await src.readRange(start, end);
        const h = await sha256Hex(data);
        if (h !== expected) {
          throw new Error(`${imageKey} chunk ${ci + 1}: SHA-256 mismatch (got ${h}, manifest ${expected}). Not sending it.`);
        }
        const sparse = buildSparseImage(data, start / BLOCK, totalBlocks);
        if (sparse.byteLength > CONFIG.MAX_PAYLOAD_BYTES) {
          throw new Error(`internal: sparse payload ${sparse.byteLength} > 64 MiB cap`);
        }
        await this._uploadWithWatchdog(partition, sparse, (p) =>
          onProgress?.(step, { chunk: ci + 1, chunks, bytesSent: start + p * (end - start), bytesTotal: size, payloadBytes: sparse.byteLength }));
        await this.fb.runCommand(`flash:${partition}`);
      });
      onProgress?.(step, { chunk: ci + 1, chunks, bytesSent: end, bytesTotal: size });
    }
    this.log("ok", `${partition}: all ${chunks} chunks flashed`);
  }

  async _withRetry(what, fn) {
    let attempt = 0;
    for (;;) {
      attempt++;
      try {
        return await fn();
      } catch (e) {
        const isHash = /SHA-256 mismatch/.test(e.message);
        const isStall = e instanceof StallError;
        if (isHash || isStall || attempt >= CONFIG.CHUNK_RETRIES || this.abortRequested || !this.fb.isConnected) {
          throw e;
        }
        this.log("warn", `${what} failed (attempt ${attempt}/${CONFIG.CHUNK_RETRIES}): ${e.message}. Retrying in ${CONFIG.RETRY_DELAY_MS / 1000}s...`);
        await sleep(CONFIG.RETRY_DELAY_MS);
      }
    }
  }

  /**
   * fastboot.js upload() with a stall watchdog. A wedged M500 gadget makes transferOut
   * hang forever with zero bytes moving (the host-side symptom is a D-state fastboot
   * process). WebUSB cannot cancel a pending transfer, so we close the device to abort
   * it and surface a StallError with the power-cycle instructions.
   */
  async _uploadWithWatchdog(partition, buffer, onProgress) {
    let lastTick = Date.now();
    let timer = null;
    const watchdog = new Promise((_, reject) => {
      timer = setInterval(() => {
        if (Date.now() - lastTick > CONFIG.STALL_TIMEOUT_MS) {
          clearInterval(timer);
          this.log("error", `No USB progress for ${CONFIG.STALL_TIMEOUT_MS / 1000}s while sending ${partition}. The M500's fastboot gadget has most likely wedged.`);
          try { this.fb.device?.close(); } catch { /* ignore */ }
          reject(new StallError("USB transfer stalled - device gadget wedged. Physically power-cycle the M500 (hold POWER ~10 s), re-enter fastboot, then Reconnect & Resume."));
        }
      }, 1000);
    });
    try {
      await Promise.race([
        this.fb.upload(partition, buffer, (p) => { lastTick = Date.now(); onProgress(p); }),
        watchdog,
      ]);
    } finally {
      clearInterval(timer);
    }
  }
}

export function fmtBytes(n) {
  if (n == null) return "?";
  const u = ["B", "KiB", "MiB", "GiB"];
  let i = 0; let v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v < 10 && i > 0 ? 2 : 0)} ${u[i]}`;
}
