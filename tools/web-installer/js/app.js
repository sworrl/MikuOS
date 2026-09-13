// MikuOS Web Installer - UI controller (steps wizard).
import * as fastboot from "./vendor/fastboot.min.mjs";
import { CONFIG, ACTIONS } from "./config.js";
import {
  Flasher, UrlSource, FileSource, validateManifest, resolveImageUrl,
  buildPlan, actionAvailability, fmtBytes, StallError,
} from "./flasher.js";

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

const state = {
  step: 1,
  manifest: null,
  manifestUrl: null,
  manifestProblems: [],
  localFiles: new Map(), // imageKey -> File
  fb: new fastboot.FastbootDevice(),
  flasher: null,
  info: null,
  productOk: false,
  action: null,
  withRoot: false,
  plan: null,
  resume: null,
  running: false,
  lastError: null,
};

// ----------------------------------------------------------------------------
// Logging console
// ----------------------------------------------------------------------------
const logEl = () => $("#log");
function log(level, msg) {
  const line = document.createElement("div");
  line.className = `log-line log-${level}`;
  const t = new Date().toLocaleTimeString([], { hour12: false });
  line.textContent = `[${t}] ${msg}`;
  logEl().appendChild(line);
  logEl().scrollTop = logEl().scrollHeight;
  if (level === "error") console.error(msg); else console.log(`[${level}] ${msg}`);
}
$("#log-clear")?.addEventListener("click", () => (logEl().innerHTML = ""));
$("#log-copy")?.addEventListener("click", async () => {
  try { await navigator.clipboard.writeText(logEl().innerText); log("ok", "Log copied to clipboard"); } catch (e) { log("warn", `copy failed: ${e.message}`); }
});

// ----------------------------------------------------------------------------
// Steps
// ----------------------------------------------------------------------------
function showStep(n) {
  state.step = n;
  $$(".step").forEach((el) => el.classList.toggle("active", Number(el.dataset.step) === n));
  $$(".stepnav li").forEach((el) => {
    const s = Number(el.dataset.step);
    el.classList.toggle("current", s === n);
    el.classList.toggle("done", s < n);
  });
  window.scrollTo({ top: 0, behavior: "smooth" });
}
$$("[data-goto]").forEach((b) => b.addEventListener("click", () => {
  if (state.running) return;
  showStep(Number(b.dataset.goto));
}));

// ----------------------------------------------------------------------------
// Step 1: requirements
// ----------------------------------------------------------------------------
function checkRequirements() {
  const ua = navigator.userAgent;
  const isChromium = /Chrome\/|Chromium\/|Edg\//.test(ua) && !/OPR\//.test(ua) ? true : /Chrome\//.test(ua);
  const hasUsb = Boolean(navigator.usb);
  const secure = window.isSecureContext;
  const mobile = /Android|iPhone|iPad/.test(ua);
  const set = (id, ok, text) => {
    const el = $(id); el.className = `req ${ok ? "ok" : "bad"}`; el.querySelector(".req-text").textContent = text;
  };
  set("#req-browser", isChromium && !mobile, isChromium && !mobile ? "Chromium-based desktop browser detected" : "Use desktop Chrome, Edge, Brave or another Chromium browser (Firefox/Safari have no WebUSB)");
  set("#req-webusb", hasUsb, hasUsb ? "WebUSB is available" : "navigator.usb missing - WebUSB unavailable in this browser/profile");
  set("#req-https", secure, secure ? "Secure context (HTTPS or localhost)" : "Page must be served over HTTPS (or http://localhost) for WebUSB");
  const ok = isChromium && !mobile && hasUsb && secure;
  $("#req-continue").disabled = !ok || !$("#req-battery").checked || !$("#req-backup").checked;
  return ok;
}
["#req-battery", "#req-backup"].forEach((id) => $(id).addEventListener("change", checkRequirements));

// ----------------------------------------------------------------------------
// Manifest
// ----------------------------------------------------------------------------
async function loadManifest() {
  const params = new URLSearchParams(location.search);
  const url = params.get("manifest") || CONFIG.MANIFEST_URL;
  state.manifestUrl = new URL(url, location.href).href;
  const box = $("#manifest-status");
  try {
    const res = await fetch(state.manifestUrl, { cache: "no-store" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    applyManifest(await res.json(), state.manifestUrl);
  } catch (e) {
    state.manifest = null;
    box.className = "notice bad";
    box.innerHTML = `<b>No release manifest.</b> Could not load <code>${state.manifestUrl}</code> (${e.message}). ` +
      `Generate one with <code>make_release_manifest.py</code> and place it next to index.html, pass <code>?manifest=URL</code>, or load one from disk below.`;
    log("error", `manifest: ${e.message}`);
  }
}
function applyManifest(m, url) {
  state.manifest = m;
  state.manifestProblems = validateManifest(m);
  const box = $("#manifest-status");
  if (state.manifestProblems.length) {
    box.className = "notice bad";
    box.innerHTML = `<b>Manifest ${escapeHtml(m.name ?? "")} ${escapeHtml(m.version ?? "")} has problems:</b><ul>` +
      state.manifestProblems.map((p) => `<li>${escapeHtml(p)}</li>`).join("") + "</ul>";
    log("error", `manifest problems: ${state.manifestProblems.join(" | ")}`);
  } else {
    box.className = "notice ok";
    const imgs = Object.entries(m.images).map(([k, v]) => `${k} (${fmtBytes(v.size)})`).join(", ");
    box.innerHTML = `<b>${escapeHtml(m.name ?? "MikuOS")} ${escapeHtml(m.version ?? "")}</b>` +
      (m.build_date ? ` built ${escapeHtml(m.build_date)}` : "") +
      (m.notes_url ? ` - <a href="${escapeHtml(m.notes_url)}" target="_blank" rel="noopener">release notes</a>` : "") +
      `<div class="muted small">Images: ${escapeHtml(imgs)}</div>`;
    log("ok", `manifest loaded: ${m.name ?? ""} ${m.version ?? ""} from ${url}`);
  }
  renderLocalFileSlots();
  renderActions();
}
$("#manifest-file").addEventListener("change", async (ev) => {
  const f = ev.target.files?.[0];
  if (!f) return;
  try {
    applyManifest(JSON.parse(await f.text()), state.manifestUrl);
    log("info", `manifest loaded from local file ${f.name}; image URLs still resolve against ${state.manifestUrl} unless you pick local image files.`);
  } catch (e) { log("error", `bad manifest file: ${e.message}`); }
});

// Local image override: lets a developer flash from mikuos/out without hosting 5 GB.
function renderLocalFileSlots() {
  const wrap = $("#local-files");
  wrap.innerHTML = "";
  if (!state.manifest?.images) return;
  for (const [key, img] of Object.entries(state.manifest.images)) {
    const row = document.createElement("label");
    row.className = "file-row";
    const have = state.localFiles.get(key);
    row.innerHTML = `<span class="mono">${escapeHtml(key)}</span><span class="muted small">${escapeHtml(img.file ?? img.url ?? "")} - ${fmtBytes(img.size)}</span>` +
      `<input type="file" data-key="${escapeHtml(key)}"><span class="file-state">${have ? "local: " + escapeHtml(have.name) : "from URL"}</span>`;
    row.querySelector("input").addEventListener("change", (ev) => {
      const f = ev.target.files?.[0];
      if (!f) { state.localFiles.delete(key); }
      else if (f.size !== img.size) {
        log("error", `${key}: ${f.name} is ${f.size} bytes, manifest says ${img.size}. Ignored.`);
        ev.target.value = "";
        state.localFiles.delete(key);
      } else { state.localFiles.set(key, f); log("info", `${key}: using local file ${f.name}`); }
      renderLocalFileSlots();
    });
    wrap.appendChild(row);
  }
}
$("#local-toggle").addEventListener("click", () => $("#local-panel").classList.toggle("open"));

function getSource(step) {
  const f = state.localFiles.get(step.imageKey);
  if (f) return new FileSource(f);
  return new UrlSource(resolveImageUrl(state.manifest, state.manifestUrl, step.image), step.image.size);
}

// ----------------------------------------------------------------------------
// Step 2: connect + guard rails
// ----------------------------------------------------------------------------
fastboot.setDebugLevel(1);

async function connect() {
  if (state.running) return;
  const btn = $("#btn-connect");
  btn.disabled = true;
  try {
    log("info", "Requesting USB device (pick the M500 in the browser dialog)...");
    await state.fb.connect();
    const d = state.fb.device;
    log("ok", `USB: ${d.manufacturerName ?? ""} ${d.productName ?? ""} ${hex4(d.vendorId)}:${hex4(d.productId)} serial=${d.serialNumber ?? "?"}`);
    if (d.vendorId !== CONFIG.USB_VENDOR_ID || d.productId !== CONFIG.USB_PRODUCT_ID) {
      log("warn", `USB id ${hex4(d.vendorId)}:${hex4(d.productId)} is not the M500's fastboot id ${hex4(CONFIG.USB_VENDOR_ID)}:${hex4(CONFIG.USB_PRODUCT_ID)}. Continuing to the product check.`);
    }
    state.flasher = new Flasher(state.fb, log, getSource);
    await refreshInfo();
  } catch (e) {
    log("error", `connect failed: ${e.message}`);
    if (/No device selected/.test(e.message)) log("info", "No device chosen. Is the M500 in fastboot mode and plugged into THIS computer? On Linux you may need a udev rule for 18d1:d00d.");
  } finally {
    btn.disabled = false;
  }
}
$("#btn-connect").addEventListener("click", connect);
$("#btn-refresh").addEventListener("click", () => refreshInfo().catch((e) => log("error", e.message)));

async function refreshInfo() {
  if (!state.fb.isConnected) throw new Error("not connected");
  const info = await state.flasher.readDeviceInfo();
  state.info = info;
  const tbl = $("#device-info");
  tbl.innerHTML = "";
  const rows = [
    ["product", info.product], ["serialno", info.serialno], ["current-slot", info["current-slot"]],
    ["unlocked", info.unlocked], ["secure", info.secure], ["version-bootloader", info["version-bootloader"]],
    ["max-download-size", info["max-download-size"] ? `${info["max-download-size"]} (${fmtBytes(parseInt(info["max-download-size"], 16))})` : null],
    ["partition-size:super", info["partition-size:super"] ? `${info["partition-size:super"]} (${fmtBytes(parseInt(info["partition-size:super"], 16))})` : null],
    ["battery-voltage", info["battery-voltage"]], ["battery-soc-ok", info["battery-soc-ok"]],
    ["variant", info.variant], ["hw-revision", info["hw-revision"]],
  ];
  for (const [k, v] of rows) {
    if (v == null) continue;
    const tr = document.createElement("tr");
    tr.innerHTML = `<th>${escapeHtml(k)}</th><td class="mono">${escapeHtml(String(v))}</td>`;
    tbl.appendChild(tr);
  }
  $("#getvar-all").textContent = info.all || "(bootloader refused getvar:all)";
  log("info", `getvar product=${info.product} serialno=${info.serialno} current-slot=${info["current-slot"]} unlocked=${info.unlocked} max-download-size=${info["max-download-size"]} partition-size:super=${info["partition-size:super"]}`);
  evaluateGuards();
}

function evaluateGuards() {
  const info = state.info;
  const guard = $("#guard");
  const items = [];
  let block = false;

  // 1. product
  const placeholder = CONFIG.EXPECTED_PRODUCTS.every((p) => p.startsWith("__TODO"));
  const product = (info.product ?? "").trim();
  const matches = CONFIG.EXPECTED_PRODUCTS.some((p) => p.toLowerCase() === product.toLowerCase());
  if (placeholder) {
    items.push({ ok: false, text: `Product check not configured. Device reports product="${product}". MAINTAINER: put that value in js/config.js EXPECTED_PRODUCTS (marked TODO). Flashing is locked until then.` });
    block = true;
    log("warn", `EXPECTED_PRODUCTS is still the placeholder. Observed getvar product = "${product}"`);
  } else if (!matches) {
    items.push({ ok: false, text: `This device reports product="${product}", expected ${CONFIG.EXPECTED_PRODUCTS.join(" / ")}. This is NOT a HiBy M500 - refusing to flash.` });
    block = true;
  } else {
    items.push({ ok: true, text: `Product "${product}" matches the HiBy M500.` });
  }

  // 2. super size
  if (info["partition-size:super"]) {
    const n = parseInt(info["partition-size:super"], 16);
    if (n === CONFIG.EXPECTED_SUPER_SIZE) items.push({ ok: true, text: `super partition is ${n} bytes (matches MikuOS bundle).` });
    else { items.push({ ok: false, text: `super partition is ${n} bytes; MikuOS bundle expects ${CONFIG.EXPECTED_SUPER_SIZE}. Wrong device or firmware layout - refusing.` }); block = true; }
  } else {
    items.push({ ok: null, text: "Bootloader did not report partition-size:super; relying on the product check only." });
  }

  // 3. unlocked
  if (info.unlocked === "yes") items.push({ ok: true, text: "Bootloader is unlocked." });
  else if (info.unlocked === "no") { items.push({ ok: false, text: "Bootloader is LOCKED. Enable OEM unlocking in Developer options, then use 'Unlock bootloader' below (wipes data)." }); block = true; }
  else items.push({ ok: null, text: `Bootloader did not report 'unlocked' (got ${info.unlocked}). Flashing will fail with FAIL if it is locked.` });

  // 4. fastbootd vs bootloader
  if (info["is-userspace"] === "yes") { items.push({ ok: false, text: "Device is in fastbootd (userspace), not the bootloader. Run `fastboot reboot bootloader` / choose 'Reboot to bootloader'." }); block = true; }

  // 5. battery hint
  const mv = parseInt(info["battery-voltage"] ?? "", 10);
  if (Number.isFinite(mv) && mv > 1000) {
    let pct = 0;
    for (const [v, p] of CONFIG.BATTERY_MV_HINT) { if (mv >= v) { pct = p; break; } }
    const ok = pct >= CONFIG.MIN_BATTERY_PERCENT;
    items.push({ ok: ok ? true : false, text: `Battery ~${mv} mV (roughly ${pct}%). ${ok ? "" : "Charge to >= 50% on a wall charger first - fastboot does NOT charge the M500 and an install takes ~10 min."}` });
    if (!ok) block = block || !$("#battery-override").checked;
  }

  const override = $("#dev-override").checked;
  guard.innerHTML = items.map((i) => `<li class="${i.ok === true ? "ok" : i.ok === false ? "bad" : "meh"}">${escapeHtml(i.text)}</li>`).join("");
  state.productOk = !block || override;
  if (block && override) log("warn", "DEVELOPER OVERRIDE is on: guard rails bypassed. You accept the risk of bricking a device.");
  $("#btn-unlock").hidden = info.unlocked !== "no";
  $("#connect-continue").disabled = !state.productOk || !state.manifest || state.manifestProblems.length > 0;
}
$("#dev-override").addEventListener("change", () => state.info && evaluateGuards());
$("#battery-override").addEventListener("change", () => state.info && evaluateGuards());

$("#btn-unlock").addEventListener("click", async () => {
  if (!confirm("Unlock the bootloader? This WIPES all user data. You must have enabled 'OEM unlocking' in Developer options first, and may need to confirm on the device.")) return;
  try {
    const r = await state.flasher.unlockBootloader();
    log("ok", `flashing unlock -> ${r || "OKAY"}. The device will likely reboot/wipe; re-enter fastboot and Connect again.`);
  } catch (e) { log("error", `unlock failed: ${e.message}`); }
});
$("#btn-reboot-bl").addEventListener("click", async () => {
  try { await state.flasher._lock(() => state.fb.runCommand("reboot-bootloader")); log("info", "reboot-bootloader sent; Connect again when it re-enumerates."); }
  catch (e) { log("error", e.message); }
});

// ----------------------------------------------------------------------------
// Step 3: choose action
// ----------------------------------------------------------------------------
function renderActions() {
  const avail = actionAvailability(state.manifest);
  const wrap = $("#actions");
  wrap.innerHTML = "";
  for (const [key, a] of Object.entries(ACTIONS)) {
    const ok = avail[key];
    const card = document.createElement("label");
    card.className = `action danger-${a.danger} ${ok ? "" : "disabled"}`;
    card.innerHTML = `<input type="radio" name="action" value="${key}" ${ok ? "" : "disabled"}>` +
      `<div><div class="action-title">${escapeHtml(a.title)}</div><div class="muted">${escapeHtml(a.blurb)}</div>` +
      (ok ? "" : `<div class="small bad-text">Not available in this release (missing images).</div>`) + `</div>`;
    card.querySelector("input").addEventListener("change", () => selectAction(key));
    wrap.appendChild(card);
  }
  $("#opt-root-wrap").hidden = !state.manifest?.images?.init_boot_rooted;
}
$("#opt-root").addEventListener("change", (ev) => { state.withRoot = ev.target.checked; if (state.action) selectAction(state.action); });

function selectAction(key) {
  state.action = key;
  const isInstall = key === "install_keepdata" || key === "install_clean";
  $("#opt-root-wrap").hidden = !(isInstall && state.manifest?.images?.init_boot_rooted);
  try {
    state.plan = buildPlan(key, state.manifest, { withRoot: isInstall && state.withRoot });
    state.resume = null;
    renderPlanPreview();
    $("#choose-continue").disabled = false;
  } catch (e) {
    log("error", e.message);
    $("#plan-preview").textContent = e.message;
    $("#choose-continue").disabled = true;
  }
}
function renderPlanPreview() {
  const lines = state.plan.map((s) => s.kind === "flash"
    ? `fastboot ${s.image.size > CONFIG.RAW_SINGLE_PAYLOAD_LIMIT ? "-S 64M " : ""}flash ${s.partition} ${s.image.file ?? s.imageKey}`
    : `fastboot ${s.command.replace(":", " ")}`);
  $("#plan-preview").textContent = lines.join("\n");
  const total = state.plan.filter((s) => s.kind === "flash").reduce((a, s) => a + s.image.size, 0);
  $("#plan-total").textContent = `${state.plan.length} steps, ${fmtBytes(total)} to transfer`;
}
$("#choose-continue").addEventListener("click", () => {
  const a = ACTIONS[state.action];
  if (a.danger === "high" && !confirm(`${a.title}\n\nThis ERASES all user data on the M500. Continue?`)) return;
  showStep(4);
  renderFlashList();
  startRun();
});

// ----------------------------------------------------------------------------
// Step 4: flash
// ----------------------------------------------------------------------------
function renderFlashList() {
  const ul = $("#flash-steps");
  ul.innerHTML = "";
  for (const s of state.plan) {
    const li = document.createElement("li");
    li.dataset.index = s.index;
    li.innerHTML = `<div class="fs-head"><span class="fs-name">${escapeHtml(s.kind === "flash" ? `flash ${s.partition}` : s.label)}</span>` +
      `<span class="fs-status">pending</span></div>` +
      (s.kind === "flash" ? `<div class="bar"><div class="fill"></div></div><div class="fs-detail small muted"></div>` : "");
    ul.appendChild(li);
  }
}
function stepEl(i) { return $(`#flash-steps li[data-index="${i}"]`); }

async function startRun() {
  if (state.running) return;
  if (!state.fb.isConnected) { log("error", "Device not connected. Go back to Connect."); showStep(2); return; }
  state.running = true;
  state.lastError = null;
  setRunningUi(true);
  const t0 = Date.now();
  try {
    if (!state.resume) {
      log("info", "Pre-flight: checking image sources...");
      await state.flasher.preflight(state.plan);
    }
    // Re-read max-download-size in case we reconnected to a fresh gadget.
    if (state.flasher.maxDownload == null) await state.flasher.readDeviceInfo();
    await state.flasher.runPlan(state.plan, state.manifest, {
      resume: state.resume,
      onStep: (s, status) => {
        const el = stepEl(s.index);
        el.className = status;
        el.querySelector(".fs-status").textContent = status;
      },
      onProgress: (s, p) => {
        const el = stepEl(s.index);
        const pct = Math.min(100, (p.bytesSent / p.bytesTotal) * 100);
        el.querySelector(".fill").style.width = `${pct.toFixed(1)}%`;
        el.querySelector(".fs-detail").textContent = p.chunks > 1
          ? `chunk ${p.chunk}/${p.chunks} - ${fmtBytes(p.bytesSent)} / ${fmtBytes(p.bytesTotal)} (${pct.toFixed(1)}%)`
          : `${fmtBytes(p.bytesSent)} / ${fmtBytes(p.bytesTotal)} (${pct.toFixed(0)}%)`;
        $("#overall").textContent = overallText(t0);
      },
    });
    const secs = Math.round((Date.now() - t0) / 1000);
    log("ok", `All steps completed in ${Math.floor(secs / 60)}m${secs % 60}s.`);
    state.resume = null;
    finish(true);
  } catch (e) {
    state.lastError = e;
    const prog = state.flasher.progress;
    state.resume = { stepIndex: prog.stepIndex, chunkIndex: prog.chunkIndex };
    const el = stepEl(prog.stepIndex);
    if (el) { el.className = "failed"; el.querySelector(".fs-status").textContent = "FAILED"; }
    log("error", `Flash failed at step ${prog.stepIndex + 1} (${state.plan[prog.stepIndex]?.partition ?? state.plan[prog.stepIndex]?.label}), chunk ${prog.chunkIndex + 1}: ${e.message}`);
    if (e instanceof StallError || !state.fb.isConnected) {
      log("warn", "RECOVERY: 1) unplug USB, 2) hold POWER ~10 s until the device is fully off, 3) re-enter fastboot (adb is gone, so use the key combo or let the bootloader fall back to fastboot), 4) plug in, 5) click 'Reconnect & Resume'. Do NOT reboot into Android with a half-written super.");
    }
    $("#btn-resume").hidden = false;
  } finally {
    state.running = false;
    setRunningUi(false);
  }
}
function overallText(t0) {
  const done = state.plan.filter((s) => stepEl(s.index)?.classList.contains("done")).length;
  const secs = Math.round((Date.now() - t0) / 1000);
  return `${done}/${state.plan.length} steps - ${Math.floor(secs / 60)}m${String(secs % 60).padStart(2, "0")}s elapsed`;
}
function setRunningUi(on) {
  $("#running-banner").hidden = !on;
  $("#btn-abort").hidden = !on;
  $$(".stepnav li").forEach((li) => li.classList.toggle("locked", on));
  if (on) $("#btn-resume").hidden = true;
}
$("#btn-abort").addEventListener("click", () => {
  if (!confirm("Abort? Aborting mid-super leaves the device unbootable until you re-run the install. The current chunk finishes first.")) return;
  state.flasher.abortRequested = true;
  log("warn", "Abort requested; stopping after the current chunk.");
});
$("#btn-resume").addEventListener("click", async () => {
  if (state.running) return;
  try {
    if (!state.fb.isConnected) {
      log("info", "Reconnecting...");
      await state.fb.connect();
      state.flasher = new Flasher(state.fb, log, getSource);
      await refreshInfo();
      if (!state.productOk) { log("error", "Guard rails failed after reconnect; not resuming."); return; }
    }
    log("info", `Resuming at step ${state.resume.stepIndex + 1}, chunk ${state.resume.chunkIndex + 1}`);
    await startRun();
  } catch (e) { log("error", `resume: ${e.message}`); }
});

// ----------------------------------------------------------------------------
// Step 5: done
// ----------------------------------------------------------------------------
function finish(ok) {
  showStep(5);
  const a = ACTIONS[state.action];
  $("#done-title").textContent = ok ? `${a.title}: complete` : `${a.title}: failed`;
  $("#done-body").innerHTML = ok
    ? `<p>The M500 was told to reboot. First boot after a super flash takes a few minutes (dexopt, key setup); the Miku boot animation will appear. ` +
      (state.action === "root" || (state.withRoot && /install/.test(state.action)) ? `<p>Root: open the Magisk app once Android is up; it should show as installed and be able to grant su.</p>` : "") +
      (state.action === "install_clean" || state.action === "rollback_stock" ? `<p>Data was wiped: expect the first-run setup.</p>` : "") +
      `</p>`
    : `<p>See the log for the failing step. Use Reconnect &amp; Resume on the Flash page after a power-cycle.</p>`;
}
$("#btn-again").addEventListener("click", () => { state.resume = null; showStep(3); });

// ----------------------------------------------------------------------------
// USB disconnect awareness
// ----------------------------------------------------------------------------
navigator.usb?.addEventListener("disconnect", (ev) => {
  if (ev.device === state.fb.device) {
    log(state.running ? "error" : "info", `USB device disconnected${state.running ? " DURING FLASHING" : ""}.`);
    $("#conn-state").textContent = "disconnected";
    $("#conn-state").className = "pill bad";
  }
});
navigator.usb?.addEventListener("connect", () => {
  log("info", "A USB device connected. Click Connect / Reconnect & Resume.");
});
setInterval(() => {
  const c = state.fb.isConnected;
  $("#conn-state").textContent = c ? "connected" : "not connected";
  $("#conn-state").className = `pill ${c ? "ok" : "bad"}`;
}, 1000);

// ----------------------------------------------------------------------------
// Utilities
// ----------------------------------------------------------------------------
function escapeHtml(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function hex4(n) { return (n ?? 0).toString(16).padStart(4, "0"); }

// ----------------------------------------------------------------------------
// Boot
// ----------------------------------------------------------------------------
$("#year").textContent = new Date().getFullYear();
$("#expected-product").textContent = CONFIG.EXPECTED_PRODUCTS.join(", ");
checkRequirements();
loadManifest();
showStep(1);
log("info", `MikuOS Web Installer ready. fastboot.js ${navigator.usb ? "(WebUSB ok)" : "(no WebUSB)"}`);
