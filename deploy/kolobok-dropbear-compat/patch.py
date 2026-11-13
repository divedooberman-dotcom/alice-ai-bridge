"""Exact-build ARM32 compatibility fix for Kolobok Linux 4.9.68 only.

Use musl's existing ENOSYS fallbacks without issuing unsupported clock_gettime64
and statx probes. No syscall number substitution or timespec ABI conversion.
"""
import hashlib
from pathlib import Path
import sys

ORIGINAL_SHA256 = '374be9f85dabfab4d1f649d553f45e6238973e272b447fd2d81c2ab24a654db2'
# File offsets are VA - 0x20000 in the verified executable PT_LOAD segment.
SITES = (
    (0x51620, bytes.fromhex('937100e30410a0e1000000ef260070e3'), 8),
    (0x4c254, bytes.fromhex('8d7100e3ff3700e3000000ef0090a0e1'), 8),
)


def patch(original):
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA256:
        raise ValueError('Unsupported input SHA256; refusing to patch')
    result = bytearray(original)
    for offset, expected, svc_offset in SITES:
        if original[offset:offset + len(expected)] != expected:
            raise ValueError('Unexpected instruction context')
        # ARM mvn r0,#37: r0=-38 (-ENOSYS), preserving flags and other registers.
        result[offset + svc_offset:offset + svc_offset + 4] = bytes.fromhex('2500e0e3')
    return bytes(result)


if __name__ == '__main__':
    source, destination = map(Path, sys.argv[1:])
    result = patch(source.read_bytes())
    with destination.open('xb') as out:
        out.write(result)
    destination.chmod(0o700)
    print(hashlib.sha256(result).hexdigest())
