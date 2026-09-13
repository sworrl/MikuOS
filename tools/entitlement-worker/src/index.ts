/**
 * Miku Music remote-entitlement Worker.
 *
 * Public (called by the app, com.miku.player.entitlement.EntitlementClient):
 *   POST /v1/check           body {deviceId, appVersion, appVersionCode?, nonce, ts}
 *   GET  /v1/status?deviceId=…[&nonce=…]     (same signed shape; for curl/dashboards)
 *   GET  /healthz
 *
 * Admin (Authorization: Bearer <ADMIN_TOKEN>):
 *   GET    /admin/devices                 list every KV record (status + last-seen)
 *   GET    /admin/devices/:deviceId
 *   PUT    /admin/devices/:deviceId       body {status:"allow"|"deny", note?}
 *   DELETE /admin/devices/:deviceId       back to default (unknown ⇒ allow)
 *
 * Response signing — MUST stay byte-identical to EntitlementConfig.canonical() in the app:
 *   canonical = ["v1", deviceId, verdict, nonce, String(ts), String(expiresAt), note].join("\n")
 *   sig       = hex(HMAC-SHA256(ENTITLEMENT_HMAC_SECRET, canonical))
 *
 * Safety properties mirrored from the client:
 *   - unknown device ⇒ ALLOW (default-allow)
 *   - OWNER_EXEMPT_DEVICE_IDS ⇒ ALLOW, always, even if KV says deny
 *   - every verdict carries the caller's nonce + an expiry, so a stale/forged reply is inert
 */

export interface Env {
  ENTITLEMENT_KV: KVNamespace;
  ENTITLEMENT_HMAC_SECRET: string;
  ADMIN_TOKEN: string;
  OWNER_EXEMPT_DEVICE_IDS?: string;
  ALLOW_TTL_MS?: string;
  DENY_TTL_MS?: string;
}

type Status = "allow" | "deny";
interface DeviceRecord { status: Status; note: string; updatedAt: number; }
interface SeenRecord { appVersion: string; appVersionCode?: number; lastSeenAt: number; ip?: string; country?: string; }

const API = "v1";
const DEVICE_ID_RE = /^[0-9a-f]{64}$/;
const DEFAULT_ALLOW_TTL = 30 * 24 * 3600 * 1000;
const DEFAULT_DENY_TTL = 14 * 24 * 3600 * 1000;

// ---------------------------------------------------------------------------------------------
// crypto
// ---------------------------------------------------------------------------------------------

function hex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

function secretBytes(secret: string): Uint8Array {
  const s = secret.trim();
  const isHex = s.length % 2 === 0 && s.length >= 32 && /^[0-9a-fA-F]+$/.test(s);
  if (isHex) {
    const out = new Uint8Array(s.length / 2);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
    return out;
  }
  return new TextEncoder().encode(s);
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", secretBytes(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
}

export function canonical(deviceId: string, verdict: string, nonce: string, ts: number, expiresAt: number, note: string): string {
  return [API, deviceId, verdict, nonce, String(ts), String(expiresAt), note].join("\n");
}

/** Owner override code the app accepts: HMAC(secret, "owner-override\n<deviceId>")[0..12] as XXXX-XXXX-XXXX. */
export async function ownerCode(secret: string, deviceId: string): Promise<string> {
  const h = (await hmacHex(secret, `owner-override\n${deviceId}`)).toUpperCase().slice(0, 12);
  return `${h.slice(0, 4)}-${h.slice(4, 8)}-${h.slice(8, 12)}`;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------------------------

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}

function exemptSet(env: Env): Set<string> {
  return new Set((env.OWNER_EXEMPT_DEVICE_IDS ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean));
}

function ttl(env: Env, status: Status): number {
  const v = Number(status === "allow" ? env.ALLOW_TTL_MS : env.DENY_TTL_MS);
  return Number.isFinite(v) && v > 60_000 ? v : status === "allow" ? DEFAULT_ALLOW_TTL : DEFAULT_DENY_TTL;
}

async function getDevice(env: Env, deviceId: string): Promise<DeviceRecord | null> {
  return env.ENTITLEMENT_KV.get<DeviceRecord>(`device:${deviceId}`, "json");
}

/** Resolve the verdict for a device: exempt ⇒ allow; KV deny ⇒ deny; anything else ⇒ allow. */
async function resolve(env: Env, deviceId: string): Promise<{ verdict: "ALLOW" | "DISALLOW"; note: string; source: string }> {
  if (exemptSet(env).has(deviceId)) return { verdict: "ALLOW", note: "", source: "owner-exempt" };
  const rec = await getDevice(env, deviceId);
  if (!rec) return { verdict: "ALLOW", note: "", source: "default" };
  if (rec.status === "deny") return { verdict: "DISALLOW", note: rec.note ?? "", source: "kv" };
  return { verdict: "ALLOW", note: rec.note ?? "", source: "kv" };
}

async function signedVerdict(env: Env, deviceId: string, nonce: string): Promise<Response> {
  if (!env.ENTITLEMENT_HMAC_SECRET) {
    // Never emit an unsigned verdict — the client would ignore it anyway (fail-open).
    return json({ error: "worker not configured: ENTITLEMENT_HMAC_SECRET missing" }, 503);
  }
  const { verdict, note, source } = await resolve(env, deviceId);
  const ts = Date.now();
  const expiresAt = ts + ttl(env, verdict === "ALLOW" ? "allow" : "deny");
  const sig = await hmacHex(env.ENTITLEMENT_HMAC_SECRET, canonical(deviceId, verdict, nonce, ts, expiresAt, note));
  return json({ v: API, deviceId, verdict, nonce, ts, expiresAt, note, alg: "HMAC-SHA256", sig, source });
}

function isAdmin(req: Request, env: Env): boolean {
  if (!env.ADMIN_TOKEN) return false;
  const h = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return !!m && timingSafeEqual(m[1].trim(), env.ADMIN_TOKEN);
}

// ---------------------------------------------------------------------------------------------
// handler
// ---------------------------------------------------------------------------------------------

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    try {
      if (path === "/healthz") return json({ ok: true, ts: Date.now(), configured: !!env.ENTITLEMENT_HMAC_SECRET });

      // ---- public ----------------------------------------------------------------------------
      if (path === `/${API}/check` && req.method === "POST") {
        let body: any;
        try { body = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }
        const deviceId = String(body?.deviceId ?? "").toLowerCase();
        const nonce = String(body?.nonce ?? "");
        if (!DEVICE_ID_RE.test(deviceId)) return json({ error: "deviceId must be 64 hex chars" }, 400);
        if (!/^[0-9a-f]{16,64}$/i.test(nonce)) return json({ error: "nonce must be 16-64 hex chars" }, 400);

        const seen: SeenRecord = {
          appVersion: String(body?.appVersion ?? ""),
          appVersionCode: Number.isFinite(Number(body?.appVersionCode)) ? Number(body.appVersionCode) : undefined,
          lastSeenAt: Date.now(),
          ip: req.headers.get("cf-connecting-ip") ?? undefined,
          country: (req as any).cf?.country ?? undefined,
        };
        ctx.waitUntil(env.ENTITLEMENT_KV.put(`seen:${deviceId}`, JSON.stringify(seen)));
        return signedVerdict(env, deviceId, nonce);
      }

      if (path === `/${API}/status` && req.method === "GET") {
        const deviceId = (url.searchParams.get("deviceId") ?? "").toLowerCase();
        const nonce = url.searchParams.get("nonce") ?? "";
        if (!DEVICE_ID_RE.test(deviceId)) return json({ error: "deviceId must be 64 hex chars" }, 400);
        return signedVerdict(env, deviceId, nonce);
      }

      // ---- admin -----------------------------------------------------------------------------
      if (path.startsWith("/admin/")) {
        if (!isAdmin(req, env)) return json({ error: "unauthorized" }, 401, { "www-authenticate": "Bearer" });

        if (path === "/admin/devices" && req.method === "GET") {
          const out: Record<string, unknown>[] = [];
          const list = await env.ENTITLEMENT_KV.list({ prefix: "device:" });
          for (const k of list.keys) {
            const id = k.name.slice("device:".length);
            const rec = await getDevice(env, id);
            const seen = await env.ENTITLEMENT_KV.get<SeenRecord>(`seen:${id}`, "json");
            out.push({ deviceId: id, ...rec, seen, exempt: exemptSet(env).has(id) });
          }
          // Devices that have checked in but have no explicit record (default-allow).
          const seenList = await env.ENTITLEMENT_KV.list({ prefix: "seen:" });
          for (const k of seenList.keys) {
            const id = k.name.slice("seen:".length);
            if (out.some((o) => o.deviceId === id)) continue;
            const seen = await env.ENTITLEMENT_KV.get<SeenRecord>(`seen:${id}`, "json");
            out.push({ deviceId: id, status: "allow", note: "(default — no record)", seen, exempt: exemptSet(env).has(id) });
          }
          return json({ devices: out, exempt: [...exemptSet(env)] });
        }

        const m = /^\/admin\/devices\/([0-9a-fA-F]{64})$/.exec(path);
        if (m) {
          const id = m[1].toLowerCase();
          if (req.method === "GET") {
            const rec = await getDevice(env, id);
            const seen = await env.ENTITLEMENT_KV.get<SeenRecord>(`seen:${id}`, "json");
            const code = env.ENTITLEMENT_HMAC_SECRET ? await ownerCode(env.ENTITLEMENT_HMAC_SECRET, id) : null;
            return json({ deviceId: id, record: rec, seen, exempt: exemptSet(env).has(id), ownerCode: code });
          }
          if (req.method === "PUT" || req.method === "POST") {
            let body: any;
            try { body = await req.json(); } catch { return json({ error: "invalid JSON" }, 400); }
            const status = String(body?.status ?? "").toLowerCase();
            if (status !== "allow" && status !== "deny") return json({ error: "status must be allow|deny" }, 400);
            const rec: DeviceRecord = { status, note: String(body?.note ?? "").slice(0, 500), updatedAt: Date.now() };
            await env.ENTITLEMENT_KV.put(`device:${id}`, JSON.stringify(rec));
            return json({ deviceId: id, record: rec, exempt: exemptSet(env).has(id) });
          }
          if (req.method === "DELETE") {
            await env.ENTITLEMENT_KV.delete(`device:${id}`);
            return json({ deviceId: id, record: null });
          }
        }
        return json({ error: "not found" }, 404);
      }

      return json({ error: "not found" }, 404);
    } catch (e: any) {
      return json({ error: "internal", detail: String(e?.message ?? e) }, 500);
    }
  },
};
