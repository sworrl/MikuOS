# TV companion: mirroring the M500 to an Android TV

Status as of 2026-10-08. The M500 side exists and compiles; the TV app is not written yet.

## What this is

The M500 stays in your pocket and keeps being the player. An Android TV app receives what it is
playing, outputs it over TOSLINK to the THX system, shows the now-playing UI and runs projectM on
the big screen, and can drive transport back the other way.

## Mirroring without losing bit-perfect

The obvious way to mirror a device's audio is `AudioPlaybackCapture`, and it is the wrong way
here. That API taps **after** the system mixer, so anything it captures has already been resampled
to the mixer rate (48kHz on this device) with every other stream folded in. Mirroring a 24/96 FLAC
through it would hand the TV 48kHz of already-degraded audio, which throws away the entire reason
for the hardware.

We own the decoder, so we do not have to capture anything. `MikuDirectAudioSink` holds the decoded
buffer immediately before `AudioTrack.write`, at the file's own rate and depth, having bypassed
the mixer through the DIRECT path. Teeing there means the bytes the TV receives are the bytes in
the file.

So the answer to "mirror it" and the answer to "keep it bit-perfect" turn out to be the same
design, as long as the tee is in the right place.

What the TV then does with it is the TV's limit, not ours. TOSLINK carries stereo PCM up to
24/192 in principle and many sets clamp to 24/96; the app asks for the stream's native rate and
reports honestly what it actually got rather than claiming the file's rate.

## Pieces

### On the M500 (done, `com.miku.player.cast`)

| Part | What it does |
|---|---|
| `MikuCastTap` | Takes the decoded PCM off the audio thread into a 4 MiB ring (~5.5s at 24/96). Never blocks, never allocates beyond a copy. A no-op when no TV is connected |
| `MikuCastProtocol` | Frame format: 4-byte magic, 1-byte type, 4-byte length, payload. Types: FORMAT, PCM, META, CONTROL, PING, SKIP |
| `MikuCastServer` | Listens on 8796, advertises `_mikucast._tcp` over mDNS, streams PCM, accepts control frames back |

Two decisions worth keeping:

**One socket, both directions.** Control traffic is a few bytes a second against a 4.6 Mbit audio
stream, so a second connection buys nothing and costs correlation, re-pairing after every Wi-Fi
blip, and matched teardown. A dropped link is now unambiguous.

**Overrun is reported, not hidden.** If the network cannot keep up, the ring drops the *oldest*
audio (a late listener wants to catch up to live, not replay a backlog) and the server sends a
SKIP frame. The TV flushes and says so on screen. A mirror that silently drifts is worse than one
that admits a gap.

### On the TV (not written)

1. Discover `_mikucast._tcp` over NSD, or accept a typed-in address.
2. Read FORMAT, configure an `AudioTrack` at exactly that rate, depth and channel count, and
   report what the device actually granted.
3. Feed PCM frames straight in. The same bytes also drive projectM, so the visualiser is reacting
   to the real waveform rather than a second analysis pass.
4. Compose UI for the 10-foot view, D-pad focus, now-playing from META frames.
5. Transport buttons send CONTROL frames back.

## Known limits, stated up front

- **The M500 also plays locally.** Nothing here mutes it, so you will hear both, slightly out of
  step. Whether the player should go silent while casting is a product decision, not a technical
  one, and it is not made yet.
- **Latency is not addressed.** There is roughly a ring's worth of slack plus network and the TV's
  own buffer. Fine for listening, wrong for anything lip-synced to video.
- **One TV.** A second connection displaces the first. Multi-room needs a shared clock and is a
  different feature.
- **Nothing is tested on real hardware yet.** The TV was not on the network when this was written.

## Next

1. Create the `mikuos-tv` module (Android TV leanback, Compose, minSdk matched to the set).
2. Client: discovery, framed reader, AudioTrack, honest format reporting.
3. projectM on the TV, fed from the same PCM.
4. Decide the local-mute question.
