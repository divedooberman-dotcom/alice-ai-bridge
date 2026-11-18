# Cherny platformd addressless-interface guard

## Confirmed defect

15 November 2026: the owner's Archer C64 screenshot confirms a daily05:00
router reboot. Cherny's driver subsequently reports missed beacons and disconnects.
Nineteen native faults share relative PC0x14a767a and FAR0. The exact device
executable SHA256 is
`ae53daaf1d1867744017bb6939d7fa2c95f0d76468f8472a273ab041a895642b`,
ELF32 ARM PIE, build ID28f5077683c648303e7ed932fc1ffcba57b8152f.

Disassembly shows a getifaddrs call at0x14a765e, followed by interface-name
matching, then a load of ifa_addr at offset12 and an unchecked read of its
sa_family at0x14a767a. This matches the recorded null fault exactly. The Linux
API explicitly permits NULL ifa_addr:
https://man7.org/linux/man-pages/man3/getifaddrs.3.html
The disassembler's nearest `malloc_usable_size` label is NOT the function name;
the binary is stripped and source-level function attribution is unavailable.

## Correction and scope

guard.c interposes getifaddrs/freeifaddrs ONLY in platformd via its existing
launcher environment. Only the confirmed callsite (return0x14a7662, ignoring
Thumb bit, in the main maind image) receives a filtered list. Other callers
receive the exact original list. No static vendor instruction is patched.

When necessary, allocate shallow copies of entries with non-NULL ifa_addr,
retaining libc's complete original list unchanged until freeifaddrs. A locked
ownership list distinguishes copies from original allocations. All-null input
becomes an empty list. Allocation failures release the original and return
ENOMEM. Diagnostic messages contain only callsite confirmation and counts.

The init-hook checks exact vendor and guard hashes before binding a derived
launch.json over the stock file. A firmware change therefore requires a new
review; this is not a general fix for arbitrary maind versions. The original
vendor binary and config remain on disk. Only the maind/platformd task receives
LD_PRELOAD; mediad, telemetry, fluent-bitd and bulbik are unchanged.

## Evidence so far

- Mac and Linux A1 synthetic tests with AddressSanitizer/UBSan pass: NULL at
  beginning/middle/end, all-null and empty release, valid ordering/pointers,
  original ownership, allocation and libc errors, unrelated caller unchanged,
  exact callsite matching,40000 multithreaded allocate/free lifecycles.
- ARM hard-float shared object built with Clang and LLD21.1.8. LLD was unpacked
  in `/tmp/cherny-ifaddr-build` on A1, not installed. A Homebrew installation
  attempt was cancelled before dependency upgrades; downloaded files remain.
- Candidate hash4a4a05f51813739470d7be7bea9807e54d2d2829989c1eec7c83eb4224078e12.
- On-device LD_BIND_NOW loading through jq passed. Runtime maps confirm guard
  present only in platformd. Native logs confirm the target callsite matched
  and addressless entries were filtered during startup and reconnection.
- Actual station-only Wi-Fi test: disconnect07:27:32UTC, observed DISCONNECTED,
  reconnect completed07:28:02UTC. PID17868 and boot ID unchanged. A1 independently
  saw SSH and Glagol TCP ports unavailable then available again. This is an
  administrative Wi-Fi disconnect/reconnect, not a physical router reboot.
- Derived JSON was reversed and compared canonically to original. Init start,
  stop and repeated start passed on the device; root filesystem restored ro.
  BusyBox mountpoint rejects file mounts; use /proc/mounts. Launcher holds the
  config open, so rollback detaches the file bind mount with umount -l.
- Own-speaker reboot passed: new boot525fb1ef-9602-4c9d-b193-b6d689f0b034,
  platformd1068 loads the guard automatically.07:30:38UTC target-callsite and
  filtering markers present,07:30:44 both TCP ports reachable.07:31:23 Wi-Fi
  COMPLETED, root ro, expected config overlay mounted. Original maind unchanged.

The owner's router schedule and Kolobok were not changed. Physical voice
response and a real router-reboot cycle still require confirmation.

## Operations / rollback

Files on speaker are under `/data/opt/platformd-ifaddr-guard`, mode0700. The
boot hook is `/etc/init.d/S96platformd-ifaddr-guard`, before S97quasar. Original
config backup is launch.original.json; do not print it into public reports.

To roll back under existing operational authorization: stop the guard hook to
detach its config overlay, disable the boot hook (brief root remount required),
then restart the native launcher and platformd gracefully using VERIFIED PIDs.
The factory S97quasar stop invokes missing `pkill`; it does not actually stop
the launcher. Do not assume its exit means Alice stopped. Wait for native
children before running `/system/vendor/quasar/run.sh`; never start duplicates.
The initial rollback timer was explicitly cancelled before manual activation;
no periodic reboot or recovery watchdog was installed.

## Build / checks

Native synthetic tests:
```
cc -Wall -Wextra -Werror -fsanitize=address,undefined -g -pthread test_guard.c -o test_guard
./test_guard
```
Linux needs `-ldl`. ARM object (Clang builtin freestanding headers only):
```
clang --target=armv7-linux-gnueabihf -march=armv7-a -mfloat-abi=hard -ffreestanding -fPIC -O2 -Wall -Wextra -Werror -c guard.c -o guard.o
ld.lld -shared --hash-style=both -z relro -z now -soname platformd-ifaddr-guard.so guard.o -o platformd-ifaddr-guard.so
```
Changing guard.c requires rebuilding, rerunning checks, and updating both
deployment checksum gates. The callsite is a build parameter (GUARD_CALLSITE,
default = Cherny); the default build still reproduces the hashes above.
Kolobok's port, approved and installed 16 November 2026, is documented in
`deploy/kolobok-platformd-ifaddr-guard/README.md`. It found that this link
recipe names no library dependencies, so children inheriting LD_PRELOAD can
fail to start on glibc 2.30; whether Cherny is affected is not yet checked.
