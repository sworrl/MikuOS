# Driving the web installer from a terminal

The installer is a web page because WebUSB lives nowhere else: a browser tab is the only
thing that can talk to a device in fastboot mode without a native binary. That is fine for
someone installing MikuOS, who clicks five buttons. It is awkward for whoever maintains the
installer, who needs to run a real flash on real hardware repeatedly and read what happened.

So the page can take commands from a local control server. The important part is what this is
*not*: it is not a second flashing path. Every command calls the same function the matching
button calls, and sets the same checkbox or radio a hand would, so the page on screen always
shows the truth and the public install path is the one being exercised. If the control channel
ever diverged from the buttons, it would stop being a test of the thing people actually use.

```
python3 tools/web-installer/control_server.py --images /path/to/mikuos/out/web-release
```

It prints two URLs. The second carries a `#control=` fragment; open that one in Chrome. Then,
from another terminal:

```
./mikuctl status                     # device, manifest, plan, progress, recent log
./mikuctl watch                      # follow the page's log live
./mikuctl flash install_keepdata     # connect, refresh, plan, start, follow to the verdict
```

`./mikuctl --help` lists the rest. One thing needs a human once per browser profile: WebUSB
will not hand over a device without a user gesture, so click **Connect** on the page the first
time. After that `./mikuctl connect` attaches on its own, because the browser remembers the
permission. `connect` says so plainly (`needs_user_gesture: true`) rather than failing obscurely.

## Making a release to flash

```
python3 tools/web-installer/make_release_manifest.py \
    --repo ~/Documents/GitHub/m500 \
    --version 0.1.12 \
    --base-url http://localhost:8901/images/ \
    --release-dir ~/Documents/GitHub/m500/mikuos/out/web-release --link
```

`--repo` points at the tree the images were built in, which is not this one. `--link` hard-links
rather than copying, so a 5 GB super image costs nothing; both directories have to be on the
same filesystem for that. The manifest records a SHA-256 per image and a second one per 63 MiB
chunk, and the installer checks each chunk as it goes, so a corrupted download fails on the
chunk that is wrong instead of after ten minutes.

## Why it is signed

This channel can brick a device. It is authenticated in both directions and refuses to exist
by default.

**Every request carries an HMAC-SHA256** over a canonical string of the method, the path, a
timestamp, a nonce, and the SHA-256 of the body. A replayed nonce is refused; a timestamp more
than five minutes out is refused. The server signs its replies too, and both the page and
`mikuctl` verify that signature, because both act on what comes back.

**A command is signed by whoever issued it**, over the exact bytes it will be delivered as, and
the browser verifies that inner signature itself. The server never re-serializes a command. A
compromised control server therefore cannot make the page flash anything; it can only withhold
or reorder commands, and reordering fails the monotonic sequence check.

**The secret never travels to a server.** `control_server.py` mints 32 bytes on first run,
stores them `0600` in `.control-secret` (gitignored), and puts them in the URL *fragment*,
which browsers do not send in a request or a `Referer`. The page scrubs it out of the address
bar immediately, because this gets driven on a screen that is often being watched.

**The public site cannot be put into control mode.** The agent refuses unless the page is
served from localhost, so the copy of `control.js` on mikuos.falcontechnix.com is inert for
everybody, with or without a crafted link. Without a `#control=` fragment it returns before
it touches the network at all.

**Destroying data takes a second signature field.** `install_clean` and `rollback_stock` are
refused unless the signed envelope also carries `confirm=WIPE` - checked by the server when the
action is chosen and again by the page when the run starts, so neither one is load-bearing
alone. Pass it with `--confirm WIPE`.

**Unlocking the bootloader is not a command.** It wipes the device and usually wants a button
pressed on it. It stays a thing a person does on the page.

A fresh or reloaded tab starts from the server's current command head rather than from zero.
Replaying history would otherwise re-run a `start` against a device that is already mid-write.

## What the guard rails are for

`mikuctl flash` stops if the guard rails are blocking, and does not offer to override them.
The checks are: `getvar product` is `khaje`, the super partition is exactly 5371461632 bytes,
the bootloader is unlocked, the device is in the bootloader rather than fastbootd, and the
battery is above roughly 50% - fastboot does not charge the M500 and a full install is about
ten minutes of sustained USB traffic. Each of those is there because of something that went
wrong once. `./mikuctl override --dev on` exists for when you know which one you are bypassing
and why; reaching for it to make an error message go away is how a device gets bricked.

## When the USB gadget wedges

It will, eventually: the M500's gadget stops responding mid-`super` and needs a physical power
cycle, which is why the image goes up in 63 MiB chunks in the first place. The installer records
the step and chunk it died on. Power-cycle the device by holding POWER for about ten seconds,
get it back into fastboot, then `./mikuctl resume` - it reconnects, re-checks the guard rails,
and continues from that chunk rather than starting the 5 GB over. Do not boot Android with a
half-written `super`.
