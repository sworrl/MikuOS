# Miku Music — remote entitlement Worker

Signed allow/disallow ("kill-switch") endpoint for Miku Music on the HiBy M500.
Client side lives in `miku-player-kotlin/app/src/main/java/com/miku/player/entitlement/`.

**Safety model (read before deploying):**

* The app is **fail-open**. No network, Worker down, HTTP error, bad JSON, missing/wrong
  signature, nonce mismatch, clock skew > 12 h, expired verdict → the device is ALLOWED and
  nothing is recorded.
* Only a properly signed `DISALLOW` is recorded, and the app enforces it only after
  **3 consecutive signed disallows spanning ≥ 72 h** (one check per 24 h → at least 3 days of
  warning), and only while the newest one is unexpired (`DENY_TTL_MS`, 14 days). Turning the
  Worker off therefore *unlocks* devices, never locks them.
* The feature is **off** unless `miku.entitlement.url` + `miku.entitlement.hmac` are baked into
  the APK **and** the user turns on Settings → License → "Remote entitlement".
* Owner units listed in `OWNER_EXEMPT_DEVICE_IDS` always get `ALLOW`.
* "Disallowed" is a screen with the note, contact, device ID, re-check, an owner-override code
  entry and a "turn feature off" button. No data is ever deleted.

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/check` | none | App check-in `{deviceId, appVersion, nonce, ts}` → signed verdict |
| GET | `/v1/status?deviceId=…&nonce=…` | none | Same signed verdict, for curl/dashboards |
| GET | `/healthz` | none | Liveness + whether the secret is configured |
| GET | `/admin/devices` | Bearer | List all records + last-seen |
| GET | `/admin/devices/:id` | Bearer | One record, last-seen, exempt flag, **owner override code** |
| PUT | `/admin/devices/:id` | Bearer | `{status:"allow"\|"deny", note?}` |
| DELETE | `/admin/devices/:id` | Bearer | Remove record (device returns to default-allow) |

Signed response:

```json
{ "v":"v1", "deviceId":"<64 hex>", "verdict":"ALLOW|DISALLOW", "nonce":"<echoed>",
  "ts":1724900000000, "expiresAt":1727492000000, "note":"", "alg":"HMAC-SHA256",
  "sig":"<hex hmac>", "source":"default|kv|owner-exempt" }
```

`sig = hex(HMAC-SHA256(secret, ["v1", deviceId, verdict, nonce, ts, expiresAt, note].join("\n")))`
— identical to `EntitlementConfig.canonical()` in the app. Change one, change both.

## Deploy (one time)

```bash
cd tools/entitlement-worker
npm install
npx wrangler login

# KV namespace — paste the printed ids into wrangler.toml
npx wrangler kv namespace create ENTITLEMENT_KV
npx wrangler kv namespace create ENTITLEMENT_KV --preview

# Shared secret: SAME value goes into miku-player-kotlin/local.properties as miku.entitlement.hmac
SECRET=$(openssl rand -hex 32); echo "miku.entitlement.hmac=$SECRET"
printf '%s' "$SECRET" | npx wrangler secret put ENTITLEMENT_HMAC_SECRET

# Admin bearer token for /admin/*
ADMIN=$(openssl rand -hex 24); echo "ADMIN_TOKEN=$ADMIN"
printf '%s' "$ADMIN" | npx wrangler secret put ADMIN_TOKEN

npx wrangler deploy
```

Then in `miku-player-kotlin/local.properties` (gitignored):

```
miku.entitlement.url=https://mikusan.falcontechnix.com     # or the *.workers.dev URL
miku.entitlement.hmac=<SECRET from above>
miku.entitlement.contact=Justin@FalconTechnix.com
```

Rebuild; Settings → License & Entitlement now shows "Configured: yes". Flip the toggle on, tap
**Check now**, then copy the **Device ID** and put it into `OWNER_EXEMPT_DEVICE_IDS` in
`wrangler.toml` (comma-separated) and `wrangler deploy` again so your own units are exempt.

Custom domain: uncomment the `routes` line in `wrangler.toml` (zone must be on Cloudflare).

## curl tests

```bash
BASE=https://miku-entitlement.<account>.workers.dev      # or https://mikusan.falcontechnix.com
ID=$(printf 'test-device' | sha256sum | cut -c1-64)       # any 64-hex id
NONCE=$(openssl rand -hex 16)

curl -s $BASE/healthz
curl -s "$BASE/v1/status?deviceId=$ID&nonce=$NONCE" | jq .
curl -s -X POST $BASE/v1/check -H 'content-type: application/json' \
  -d "{\"deviceId\":\"$ID\",\"appVersion\":\"2.0.254\",\"nonce\":\"$NONCE\",\"ts\":$(date +%s000)}" | jq .

# deny it, check again, then clear
curl -s -X PUT $BASE/admin/devices/$ID -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"status":"deny","note":"test revoke — contact Justin@FalconTechnix.com"}' | jq .
curl -s "$BASE/v1/status?deviceId=$ID&nonce=$NONCE" | jq .verdict     # "DISALLOW"
curl -s $BASE/admin/devices -H "authorization: Bearer $ADMIN" | jq .
curl -s -X DELETE $BASE/admin/devices/$ID -H "authorization: Bearer $ADMIN" | jq .
```

Verify a signature by hand (must print `true`):

```bash
R=$(curl -s "$BASE/v1/status?deviceId=$ID&nonce=$NONCE")
CANON=$(printf 'v1\n%s\n%s\n%s\n%s\n%s\n%s' \
  "$(jq -r .deviceId <<<"$R")" "$(jq -r .verdict <<<"$R")" "$(jq -r .nonce <<<"$R")" \
  "$(jq -r .ts <<<"$R")" "$(jq -r .expiresAt <<<"$R")" "$(jq -r .note <<<"$R")")
# hex secret → -mac HMAC -macopt hexkey; plain-text secret → -macopt key:
CALC=$(printf '%s' "$CANON" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$SECRET | awk '{print $2}')
[ "$CALC" = "$(jq -r .sig <<<"$R")" ] && echo true || echo false
```

## Owner override code

If a device is ever shown the blocked screen (yours or a customer's you want to unlock offline),
the code is derived from the secret and device ID — nothing is stored:

```bash
# easiest: the admin endpoint prints it
curl -s $BASE/admin/devices/$ID -H "authorization: Bearer $ADMIN" | jq -r .ownerCode

# or offline with openssl (hex secret shown; use -macopt key:… for a plain-text secret)
printf 'owner-override\n%s' "$ID" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$SECRET \
  | awk '{print toupper(substr($2,1,4)"-"substr($2,5,4)"-"substr($2,9,4))}'
```

Enter it on the blocked screen or under Settings → License → Owner override. It pins that device
to ALLOWED until "Remove override" is tapped.

## Notes

* Unknown devices default to ALLOW; KV is an explicit allow/deny overlay, not an allow-list.
* `seen:<id>` records (app version, last check-in, IP/country) are written on every `/v1/check`
  so `/admin/devices` doubles as a dashboard.
* Rotating the secret invalidates nothing dangerous: old devices simply start failing signature
  verification → fail-open → ALLOWED until they get the new key in a rebuilt APK.
