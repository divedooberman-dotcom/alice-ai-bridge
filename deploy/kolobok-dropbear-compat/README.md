# Kolobok Dropbear Linux 4.9 compatibility

Installed 2026-11-13 on Yandex Station Micro v1.2, Linux 4.9.68.
Scope: existing ARM32 static Dropbear v2026.94, not firmware or global logging.

The linked musl clock wrapper tries ARM syscall403 (clock_gettime64) on every
clock read, then falls back to syscall263 on ENOSYS. This vendor kernel dumps
registers for the unsupported syscall. Its stat wrapper similarly probes
syscall397 (statx), then uses the existing legacy stat fallback. The binary
includes debug symbols; both fallback paths were verified by disassembly.
Context7 had no musl-specific coverage; upstream source was checked at
https://git.musl-libc.org/cgit/musl/tree/src/time/clock_gettime.c . Exact embedded
musl release is not recorded in the binary; this patch relies on the exact hash
and disassembled instructions, not an assumed library version.

`patch.py` replaces precisely two ARM SVC instructions with `mvn r0,#37`
(-ENOSYS), so the already-used fallback runs without the unsupported probe.
All other bytes, timespec conversion, authentication and cryptography remain
unchanged. This is specifically for this old kernel: it preserves its existing
time32 limitations and is not a general fix for dates past 2038. Re-evaluate
after changing firmware, kernel or Dropbear; unknown builds are refused.

Original SHA256:
`374be9f85dabfab4d1f649d553f45e6238973e272b447fd2d81c2ab24a654db2`

Patched SHA256:
`bcdcba94f3269b5ba2065cee2b9d10e53abcea708c2ecd0fcb0bc77776cb7283`

Source: Marker284/yandex-station-extended commit
`db3539ea915c2388ba5075be2294ea45bdadb603`, contrib/bin/dropbear.
Local original: local-dashboard/private/kolobok-root-lab/ssh-setup/dropbear.

Installation uses a separate verified RAM candidate on LAN port2223 with the
same host key, public-key-only login, and forwarding disabled. `install.sh`
backs up the original, atomically replaces /bkupgrade/owner-ssh/dropbear and
restarts only the main SSH listener through the existing init script.
Init, authorized_keys, host_key, rootfs and logging configuration are unchanged.

Rollback (through a verified SSH session, preserving another recovery session):
copy /bkupgrade/owner-ssh/dropbear.before-compat-20261113 to a temporary filename,
verify the original SHA256, stop S99zz-owner-ssh, atomically rename the copy to
/bkupgrade/owner-ssh/dropbear, then start S99zz-owner-ssh. Do not overwrite the
running executable in place. The backup itself must remain intact.

Validation: exact original/live hash match; changed/truncated/already-patched
inputs rejected; output differs only at the two guarded instruction sites;
disassembly verifies fallback control flow; sh -n and git diff --check pass.
Separate candidate key-auth sessions and data transfer passed. Main installation
passed twelve new key-auth sessions, stat checks and twelve 1MiB checksum checks.
Password-only access was rejected without sending a password. Receiver HTTP200,
syslog and Family AI relay services active. No firmware reboot or sound test.

Live regression: the preceding 60 seconds contained 80 syscall dumps. The first
49.36 seconds after installation, including twelve fresh connections, contained
zero new syscall dumps of any process. On A1, from 04:27:03 to 04:27:53 UTC, the
active log grew by only 203 bytes (7,430,269 to 7,430,472), compared with the
previous approximately 16MiB/32min. Central journal received three normal records
since 04:27:00, zero syscall dumps. This is a short measured window, not a daily
storage forecast. Temporary LAN port2223 was stopped after main-port validation.

Final observation: uptime2674.93–2798.37 (123.44sec), zero new syscall lines
including suppression notices; primary port2222 listening, temporary2223 closed;
rootfs remained ro and maind/shairport/report processes present. A1 active log
grew917bytes over98sec (04:27:03–04:28:41UTC); receiver remained HTTP200.
