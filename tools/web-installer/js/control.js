// MikuOS Web Installer - operator control agent.
//
// WHAT THIS IS
// A tab opened with no `#control=` fragment never reaches any of this: `attachControl`
// returns null before it touches the network, and the installer behaves exactly as the
// public site does. With the fragment, the page additionally takes signed commands from a
// local control server and streams back everything it logs, so the installer can be driven
// from a terminal while a human watches the real UI do the work.
//
// Commands do not get a private code path. Each one calls the same function the matching
// button calls, and where a control is a checkbox or a radio it is set and dispatched so the
// existing handler runs. What the operator drives is what the public gets.
//
// TRUST
// The secret arrives in the URL fragment, which the browser never sends to a server. The
// page verifies each command's signature itself, over the exact bytes the issuer signed, so
// a compromised control server can withhold commands but cannot invent one. Replays die on
// the monotonic sequence number and on the nonce; stale commands die on the timestamp.
// Data-destroying actions need a matching confirm string inside the signed envelope, and
// bootloader unlock is deliberately not a command at all.

const PROTO = "MIKUOSCTL1";
const CMD_PROTO = "MIKUOSCMD1";
const AGENT = "mikuos-installer-agent/1";

const MAX_COMMAND_AGE_MS = 300_000;
const EVENT_FLUSH_MS = 1000;      // progress fires per chunk write; coalesce before sending
const HEARTBEAT_MS = 5000;
const POLL_WAIT_S = 25;
const BACKOFF_START_MS = 1000;
const BACKOFF_MAX_MS = 30_000;

// Must match DESTRUCTIVE_ACTIONS in control_server.py.
const DESTRUCTIVE_ACTIONS = { install_clean: "WIPE", rollback_stock: "WIPE" };

const enc = new TextEncoder();
const dec = new TextDecoder();

function b64urlToBytes(s) {
  const pad = s.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(pad + "=".repeat((4 - (pad.length % 4)) % 4));
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}
function bytesToHex(buf) {
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function hexEq(a, b) {
  // Constant-ish time: the inputs are hex of the same length, so compare every character.
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]", "::1"]);

export function attachControl(hooks) {
  const token = /(?:^|[#&])control=([A-Za-z0-9_-]+)/.exec(location.hash || "")?.[1];
  if (!token) return null;

  // The control server is a loopback tool and the API paths this agent calls are
  // same-origin. Refusing anywhere else means the copy of this file served from
  // mikuos.falcontechnix.com cannot be put into control mode at all, by anyone, even with a
  // crafted link - rather than relying on that host happening to 404 the endpoints.
  if (!LOCAL_HOSTS.has(location.hostname)) {
    hooks.log("warn", `Ignoring a #control= token: this page is served from ${location.hostname}, ` +
                      `and the control channel only runs against a control server on localhost.`);
    return null;
  }

  // Scrub the secret out of the address bar before anything else. This runs on a machine
  // whose screen is likely being watched, and the key stays in memory either way.
  const cleanHash = (location.hash || "").replace(/(?:^|[#&])control=[A-Za-z0-9_-]+/, "").replace(/^#&?/, "#");
  history.replaceState(null, "", location.pathname + location.search + (cleanHash === "#" ? "" : cleanHash));

  const agent = new ControlAgent(token, hooks);
  agent.start();
  return agent;
}

class ControlAgent {
  constructor(token, hooks) {
    this.tokenBytes = b64urlToBytes(token);
    this.hooks = hooks;
    this.key = null;
    // Two separate counters on purpose. lastSeq is only the poll cursor: it has to advance
    // the moment a command is received, or the next poll asks for it again while it is still
    // being carried out and the replay guard refuses the duplicate - which works, but prints a
    // refusal for every single command and would bury a real one. lastExecutedSeq is what the
    // replay guard actually compares against.
    this.lastSeq = 0;
    this.lastExecutedSeq = 0;
    this.seenNonces = new Set();
    this.queue = Promise.resolve();   // commands run strictly one at a time
    this.pending = [];                // events waiting for the next flush
    this.progress = new Map();        // stepIndex -> latest progress, coalesced
    this.results = {};
    this.banner = null;
    this.alive = false;
    this.backoff = BACKOFF_START_MS;
  }

  // --- lifecycle -----------------------------------------------------------
  async start() {
    this.renderBanner("connecting", "control channel: handshaking with the local server");
    this.key = await crypto.subtle.importKey(
      "raw", this.tokenBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
    this.hooks.log("info", "Control channel enabled for this tab (operator-driven). The flash path is unchanged.");

    // Start from the server's current head, not from zero. A reloaded tab must not re-run
    // the commands the previous tab already carried out: replaying a `start` would begin a
    // second flash on a device that is mid-write. Only commands issued after this tab
    // attached are its to execute.
    try {
      const head = await this.request("GET", "/api/v1/state?tail=0");
      this.lastSeq = Math.max(0, (head.next_seq ?? 1) - 1);
      this.lastExecutedSeq = this.lastSeq;
      if (this.lastSeq > 0) {
        this.hooks.log("info", `Control channel: skipping ${this.lastSeq} command(s) issued before this tab opened.`);
      }
    } catch (e) {
      this.hooks.log("warn", `control: could not read the command head (${e.message}); waiting for the server.`);
    }

    this.pollLoop();
    setInterval(() => this.flush(), EVENT_FLUSH_MS);
    setInterval(() => this.emit({ kind: "heartbeat" }), HEARTBEAT_MS);
  }

  async pollLoop() {
    for (;;) {
      try {
        const r = await this.request("GET", `/api/v1/poll?after=${this.lastSeq}&wait=${POLL_WAIT_S}`);
        if (!this.alive) {
          this.alive = true;
          this.renderBanner("ok", "control channel: connected");
        }
        this.backoff = BACKOFF_START_MS;
        for (const envelope of r.commands ?? []) {
          // Advance the cursor at intake, before the command has run.
          this.lastSeq = Math.max(this.lastSeq, envelope.seq);
          this.enqueue(envelope);
        }
      } catch (e) {
        this.alive = false;
        this.renderBanner("bad", `control channel: ${e.message}`);
        await new Promise((res) => setTimeout(res, this.backoff));
        this.backoff = Math.min(this.backoff * 2, BACKOFF_MAX_MS);
      }
    }
  }

  // --- signed transport ----------------------------------------------------
  async sign(method, path, bodyBytes) {
    const ts = String(Math.floor(Date.now() / 1000));
    const nonce = bytesToHex(crypto.getRandomValues(new Uint8Array(12)));
    const digest = bytesToHex(await crypto.subtle.digest("SHA-256", bodyBytes));
    const canon = [PROTO, method.toUpperCase(), path, ts, nonce, digest].join("\n");
    const sig = bytesToHex(await crypto.subtle.sign("HMAC", this.key, enc.encode(canon)));
    return { "X-Miku-Ts": ts, "X-Miku-Nonce": nonce, "X-Miku-Sig": sig };
  }

  async request(method, pathWithQuery, bodyObj) {
    const path = pathWithQuery.split("?")[0];
    const bodyBytes = bodyObj === undefined ? new Uint8Array(0) : enc.encode(JSON.stringify(bodyObj));
    const headers = await this.sign(method, path, bodyBytes);
    if (bodyObj !== undefined) headers["Content-Type"] = "application/json";
    const res = await fetch(pathWithQuery, {
      method, headers, cache: "no-store",
      body: bodyObj === undefined ? undefined : bodyBytes,
    });
    const text = await res.text();
    // Verify the server's own signature over the reply. The page acts on these answers, so
    // an unsigned or wrongly signed reply is treated as if the server were not there.
    const want = [PROTO, "RESPONSE", path, res.headers.get("X-Miku-Ts") ?? "",
                  res.headers.get("X-Miku-Nonce") ?? "",
                  bytesToHex(await crypto.subtle.digest("SHA-256", enc.encode(text)))].join("\n");
    const good = await crypto.subtle.verify(
      "HMAC", this.key,
      hexToBytes(res.headers.get("X-Miku-Sig") ?? ""), enc.encode(want));
    if (!good) throw new Error("server reply is not signed with the control secret");
    const json = text ? JSON.parse(text) : {};
    if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
    return json;
  }

  // --- command intake ------------------------------------------------------
  enqueue(envelope) {
    this.queue = this.queue.then(() => this.handle(envelope)).catch((e) => {
      this.hooks.log("error", `control: ${e.message}`);
    });
  }

  async verify(envelope) {
    const raw = b64urlToBytes(envelope.payload_b64);
    const good = await crypto.subtle.verify(
      "HMAC", this.key, hexToBytes(envelope.sig),
      concat(enc.encode(CMD_PROTO + "\n"), raw));
    if (!good) throw new Error(`command #${envelope.seq} has a bad signature; ignored`);
    const env = JSON.parse(dec.decode(raw));
    if (env.v !== 1) throw new Error(`command #${envelope.seq} is envelope v${env.v}, not v1`);
    if (env.seq !== envelope.seq) throw new Error("command seq disagrees with its signed payload");
    if (env.seq <= this.lastExecutedSeq) {
      throw new Error(`command #${env.seq} is not newer than #${this.lastExecutedSeq}; replay refused`);
    }
    if (Math.abs(Date.now() - env.issued) > MAX_COMMAND_AGE_MS) {
      throw new Error(`command #${env.seq} was issued ${Math.round((Date.now() - env.issued) / 1000)}s ago; too old`);
    }
    if (this.seenNonces.has(env.nonce)) throw new Error(`command #${env.seq} reuses a nonce; replay refused`);
    this.seenNonces.add(env.nonce);
    return env;
  }

  async handle(envelope) {
    let env;
    try {
      env = await this.verify(envelope);
    } catch (e) {
      // Still advance past it, or one bad envelope blocks the queue forever.
      this.lastExecutedSeq = Math.max(this.lastExecutedSeq, envelope.seq);
      this.hooks.log("error", `control: ${e.message}`);
      this.emit({ kind: "refused", seq: envelope.seq, why: e.message });
      return;
    }
    this.lastExecutedSeq = env.seq;
    this.hooks.log("info", `control #${env.seq}: ${env.cmd}${Object.keys(env.args ?? {}).length ? " " + JSON.stringify(env.args) : ""}`);
    try {
      const out = await this.run(env);
      this.results[env.seq] = { ok: true, cmd: env.cmd, out: out ?? null };
    } catch (e) {
      this.hooks.log("error", `control #${env.seq} ${env.cmd} failed: ${e.message}`);
      this.results[env.seq] = { ok: false, cmd: env.cmd, error: e.message };
    }
    this.flush();
  }

  // --- the commands --------------------------------------------------------
  async run(env) {
    const h = this.hooks;
    const a = env.args ?? {};
    switch (env.cmd) {
      case "ping":
        return { agent: AGENT, webusb: !!navigator.usb, secure: isSecureContext };

      case "status":
        return this.snapshot();

      case "load_manifest":
        if (!a.url) throw new Error("load_manifest needs args.url");
        await h.loadManifest(a.url);
        return this.snapshot();

      case "connect": {
        const paired = (await navigator.usb?.getDevices?.()) ?? [];
        if (paired.length !== 1) {
          // requestDevice() needs a user gesture, so say so plainly instead of throwing a
          // SecurityError the operator has to decode.
          h.log("warn", paired.length === 0
            ? "control: this browser has no paired fastboot device yet. Click Connect once on the page; after that the operator can reconnect without a click."
            : `control: ${paired.length} paired USB devices; the browser must be asked which one. Click Connect on the page.`);
          return { needs_user_gesture: true, paired: paired.length };
        }
        await h.connect();
        return this.snapshot();
      }

      case "refresh_info":
        await h.refreshInfo();
        return this.snapshot();

      case "set_override":
        if ("dev" in a) h.setCheckbox("#dev-override", !!a.dev);
        if ("battery" in a) h.setCheckbox("#battery-override", !!a.battery);
        return this.snapshot();

      case "select_action": {
        if (!a.action) throw new Error("select_action needs args.action");
        const need = DESTRUCTIVE_ACTIONS[a.action];
        if (need && env.confirm !== need) {
          throw new Error(`${a.action} erases user data; the signed envelope must carry confirm="${need}"`);
        }
        h.setCheckbox("#opt-root", !!a.with_root);
        h.selectActionRemote(a.action);
        if (!h.state.plan) throw new Error(`no plan was built for ${a.action}; see the log`);
        return this.snapshot();
      }

      case "goto_step":
        if (h.state.running) throw new Error("a flash is running; refusing to move the wizard");
        h.showStep(Number(a.step));
        return this.snapshot();

      case "start": {
        if (h.state.running) throw new Error("already running");
        if (!h.state.plan) throw new Error("no plan selected; send select_action first");
        // Consent before capability: an unconfirmed data-wiping run is refused whatever the
        // state of the device, so the answer never depends on what happens to be plugged in.
        const need = DESTRUCTIVE_ACTIONS[h.state.action];
        if (need && env.confirm !== need) {
          throw new Error(`${h.state.action} erases user data; the signed envelope must carry confirm="${need}"`);
        }
        // startRun() is fire-and-forget below, so its own checks cannot reach the operator.
        // Everything that would make it bail has to be refused here instead, or the channel
        // reports a run that never began.
        if (!h.state.fb?.isConnected) throw new Error("no device connected; send connect first");
        if (!h.state.productOk) {
          throw new Error("the guard rails are blocking this device; run status to see which, " +
                          "and fix the cause rather than overriding it");
        }
        h.showStep(4);
        h.renderFlashList();
        // Do not await: the flash takes ~10 minutes and the channel has to stay responsive
        // so abort and status keep working while it runs.
        h.startRun();
        return { started: true, steps: h.state.plan.length };
      }

      case "abort":
        if (!h.state.running) throw new Error("nothing is running");
        h.abort();
        return { aborting: true };

      case "resume":
        if (h.state.running) throw new Error("already running");
        if (!h.state.resume) throw new Error("there is nothing to resume from");
        h.resume();
        return { resuming: h.state.resume };

      case "reboot_bootloader":
        await h.rebootBootloader();
        return { sent: true };

      default:
        throw new Error(`unknown command ${env.cmd}`);
    }
  }

  // --- telemetry out -------------------------------------------------------
  snapshot() {
    const s = this.hooks.state;
    return {
      at: Date.now(),
      step: s.step,
      connected: !!s.fb?.isConnected,
      product_ok: s.productOk,
      manifest: s.manifest ? {
        name: s.manifest.name, version: s.manifest.version,
        build_date: s.manifest.build_date, chunk_size: s.manifest.chunk_size,
        images: Object.fromEntries(Object.entries(s.manifest.images ?? {})
          .map(([k, v]) => [k, { size: v.size, sha256: v.sha256, chunks: v.chunks?.length ?? 0 }])),
      } : null,
      manifest_url: s.manifestUrl,
      manifest_problems: s.manifestProblems,
      device: s.info ?? null,
      action: s.action,
      with_root: s.withRoot,
      plan: s.plan?.map((p) => ({
        index: p.index, kind: p.kind,
        partition: p.partition ?? null, image: p.imageKey ?? null,
        size: p.image?.size ?? null, command: p.command ?? null, label: p.label ?? null,
      })) ?? null,
      running: s.running,
      resume: s.resume,
      last_error: s.lastError ? String(s.lastError.message ?? s.lastError) : null,
      progress: Object.fromEntries(this.progress),
    };
  }

  emit(ev) {
    this.pending.push({ ...ev, at: ev.at ?? Date.now() });
  }

  /** Progress arrives far faster than it is worth sending; keep only the latest per step. */
  emitProgress(step, p) {
    this.progress.set(step.index, {
      partition: step.partition ?? step.label, chunk: p.chunk, chunks: p.chunks,
      sent: p.bytesSent, total: p.bytesTotal,
      pct: Math.round((p.bytesSent / p.bytesTotal) * 1000) / 10,
    });
  }

  async flush() {
    if (!this.key) return;
    const events = this.pending.splice(0, this.pending.length);
    const results = this.results;
    this.results = {};
    // The heartbeat timer pushes an event every HEARTBEAT_MS, so an empty flush means there
    // is genuinely nothing new and the snapshot the server holds is still current.
    if (!events.length && !Object.keys(results).length) return;
    try {
      await this.request("POST", "/api/v1/events", {
        agent: AGENT, events, results, snapshot: this.snapshot(),
      });
    } catch (e) {
      // Put the events back so nothing is lost across a server restart, but bound the queue.
      this.pending = events.concat(this.pending).slice(-500);
      Object.assign(this.results, results);
    }
  }

  // --- the strip at the top of the page ------------------------------------
  renderBanner(cls, text) {
    if (!this.banner) {
      this.banner = document.createElement("div");
      this.banner.id = "control-banner";
      document.body.prepend(this.banner);
    }
    this.banner.className = `control-banner ${cls}`;
    this.banner.textContent = text;
  }
}

function hexToBytes(hex) {
  const out = new Uint8Array(Math.floor(hex.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
function concat(a, b) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0); out.set(b, a.length);
  return out;
}
