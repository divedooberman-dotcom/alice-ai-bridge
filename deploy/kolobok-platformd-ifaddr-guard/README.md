# Kolobok platformd addressless-interface guard

Port of `deploy/cherny-a1/platformd-ifaddr-guard` to Kolobok, installed
16 November 2026 with the owner's approval. Same source (`guard.c` there),
built with `-DGUARD_CALLSITE=0x10017be`.

## Why

Kolobok left the network at the 05:00 Asia/Dubai router reboot on 12, 13, 14,
15 and 16 November and returned only after a power cycle. Evidence:

- Kolobok's maind (SHA256 `69f4f147fe50c435de5a37f1d8397a91e338c7ab762100c9f2757e010c13df49`,
  firmware `0.374.1.25.4850990437.20261112.302`, ELF32 ARM) contains the same
  function as Cherny: getifaddrs call returning to `0x10017be`, then
  `ldr r0,[r4,#0xc]` / `ldrh r0,[r0]` at `0x10017d4` with no NULL check.
  The 14-byte sequence occurs exactly once. File offset equals image-relative
  address (first PT_LOAD maps offset 0 at 0).
- `/data/quasar/minidump` holds 272-byte dump stubs written at 01:00:17–01:02:32
  UTC on 8, 9, 11, 12 and 14 November and repeatedly during the following
  offline hours. The system therefore keeps running; a maind task crash-loops.
  The stubs carry no fault address, and 13 and 16 November have no stubs.
- No fault address was captured on Kolobok itself. Logs produced while offline
  stay in RAM and are lost at the power cycle.

So the same defect is present and the timing fits, but the guard fixing the
nightly outage is NOT proven until a real router reboot passes.

## What is installed

`/data/opt/platformd-ifaddr-guard/` (0700): `guard.so`
(`fdcd4736622600ae8acfb5f60ae813764cc5aa2c9371752751981fd756c8c996`) and two
guarded launcher profiles. `/etc/init.d/S98platformd-ifaddr-guard`
(`34651264c5c947b588b083beb08b0998537a6b962971065ea314e15d5e76fc9b`) runs
before S99quasar and bind-mounts them over:

- `/system/vendor/quasar/launch.json` (stock profile, original `0861c4c1…`);
- `/bkupgrade/data/opt/alisa-standalone/launch.bridge.json` (voice-agent
  profile, original `baf97568…`; `/data` is a symlink, so the hook names the
  resolved path that /proc/mounts shows).

No existing file is modified. Only the `maind --platformd` task gains the
guard in LD_PRELOAD (after `vqe_tap.so` in the bridge profile). Every step is
gated on exact hashes of maind, guard and both originals; a firmware update or
a reinstalled voice agent leaves that profile unguarded and logs one syslog
line tagged `platformd-ifaddr-guard`. Replacing `launch.bridge.json` by rename
while it is mounted fails with EBUSY: run the hook's `stop` first.

## Difference from the Cherny build

platformd's children inherit LD_PRELOAD. On Kolobok (glibc 2.30) the Cherny
link recipe made `/bin/sh`, busybox and `ip` fail at startup with
`undefined symbol: pthread_once`, because the library named no dependencies.
The Kolobok library adds DT_NEEDED `libdl.so.2` and `libpthread.so.0` through
empty stub libraries at link time; the object code is unchanged. Whether the
installed Cherny library has the same problem was NOT checked.

## Build

```
clang --target=armv7-linux-gnueabihf -march=armv7-a -mfloat-abi=hard -ffreestanding -fPIC -O2 -Wall -Wextra -Werror -DGUARD_CALLSITE=0x10017be -c guard.c -o kolobok.o
echo '' | clang --target=armv7-linux-gnueabihf -march=armv7-a -mfloat-abi=hard -ffreestanding -fPIC -c -x c - -o empty.o
ld.lld -shared -soname libdl.so.2 empty.o -o stub/libdl.so.2
ld.lld -shared -soname libpthread.so.0 empty.o -o stub/libpthread.so.0
ld.lld -shared --hash-style=both -z relro -z now -soname platformd-ifaddr-guard.so kolobok.o --no-as-needed stub/libdl.so.2 stub/libpthread.so.0 -o guard.so
```
Clang 22.1.6 locally, LLD 21.1.8 on A1 (`/tmp/cherny-ifaddr-build`, not
installed). The default build still reproduces Cherny's object and library
hashes. `make_profiles.py` derives the guarded profiles off-device (Kolobok
has no jq) and verifies that removing the guard restores each original.
`install.sh <hook-sha256>` runs on the speaker from `/tmp/ifaddr-guard-stage`.

## Verification on 16 November 2026 (UTC)

- Native tests with ASan/UBSan pass for both callsite values.
- Children with the guard preloaded start normally: busybox, sh, ip, wpa_cli,
  aplay, also combined with `vqe_tap.so`.
- Hook start/stop/start: stop restores both original hashes; root stays ro.
- 18:52 Alice restarted through `run.sh stop` and `boot.sh launch`; voice agent
  connected on attempt 1 after 15 s. New platformd has the guard in its maps;
  mediad, telemetry and fluent-bitd do not. Syslog: `matched target callsite`,
  `filtering 1 addressless entries`. SIP supervisor running.
- 18:52:53–18:53:18 `reconnect-test.sh` (Cherny's script): Wi-Fi disconnected
  20 s and reconnected, same platformd PID and boot, no new minidump.

Not verified: a real router reboot (next one 05:00 Dubai, 17 November), boot
persistence of the hook (no reboot was done), an unguarded baseline for the
reconnect test, physical voice response.

## Rollback

`/etc/init.d/S98platformd-ifaddr-guard stop`, then restart Alice the same way
(`/data/opt/alisa-standalone/run.sh stop`, `/data/opt/alisa-cli/boot.sh launch`).
To remove permanently: remount root rw, delete the hook, remount ro, delete
`/data/opt/platformd-ifaddr-guard`.
