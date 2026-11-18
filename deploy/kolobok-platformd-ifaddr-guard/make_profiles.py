#!/usr/bin/env python3
"""Derive guarded launcher profiles for Kolobok off-device (it has no jq).

Usage: make_profiles.py STOCK_JSON BRIDGE_JSON OUT_DIR
Both inputs must hash to the audited originals. The only change is the
LD_PRELOAD of the single maind --platformd task. Each output is reversed and
compared with its original before it is written.
"""
import copy, hashlib, json, pathlib, sys

GUARD = "/data/opt/platformd-ifaddr-guard/guard.so"
ORIGINALS = {
    "stock": "0861c4c1b12792c2fece90ad8367fcfd4326bd0d6ea8275ffb752af7d4366703",
    "bridge": "baf97568435c2828fc1f9ff80814fc9c308ab71884ab51499084f8f4a71addc1",
}


def platformd(doc):
    found = [t for n in doc["nodes"] for t in n["tasks"]
             if t.get("name") == "maind"
             and t.get("path") == "/system/vendor/quasar/maind"
             and t.get("arg") == ["--platformd"]]
    if len(found) != 1:
        raise SystemExit("expected exactly one platformd task")
    return found[0]


def guard(doc):
    out = copy.deepcopy(doc)
    envs = platformd(out).setdefault("envs", [])
    preload = [i for i, e in enumerate(envs) if e.startswith("LD_PRELOAD=")]
    if len(preload) > 1 or any(GUARD in e for e in envs):
        raise SystemExit("unexpected LD_PRELOAD state")
    if preload:
        envs[preload[0]] += ":" + GUARD      # keep the existing library first
    else:
        envs.append("LD_PRELOAD=" + GUARD)
    return out


def unguard(doc):
    out = copy.deepcopy(doc)
    envs = platformd(out)["envs"]
    for i, e in enumerate(envs):
        if e == "LD_PRELOAD=" + GUARD:
            del envs[i]
            break
        if e.startswith("LD_PRELOAD=") and e.endswith(":" + GUARD):
            envs[i] = e[: -len(":" + GUARD)]
            break
    else:
        raise SystemExit("guard not present")
    return out


def main(stock, bridge, out_dir):
    out_dir = pathlib.Path(out_dir)
    for name, path, dump in (
        ("stock", stock, lambda d: json.dumps(d, indent=2) + "\n"),
        ("bridge", bridge, lambda d: json.dumps(d)),
    ):
        raw = pathlib.Path(path).read_bytes()
        if hashlib.sha256(raw).hexdigest() != ORIGINALS[name]:
            raise SystemExit(f"{name}: not the audited original")
        doc = json.loads(raw)
        guarded = guard(doc)
        if unguard(guarded) != doc:
            raise SystemExit(f"{name}: reversal mismatch")
        text = dump(guarded).encode()
        if json.loads(text) != guarded:
            raise SystemExit(f"{name}: serialisation mismatch")
        target = out_dir / f"launch.{name}.guarded.json"
        target.write_bytes(text)
        print(hashlib.sha256(text).hexdigest(), target.name)


if __name__ == "__main__":
    main(*sys.argv[1:4])
