#!/bin/sh
# Run on Kolobok as root. Expects the audited files in /tmp/ifaddr-guard-stage.
# Installs files and the boot hook and mounts the guarded profiles. It does NOT
# restart Alice: running processes keep their old environment until restarted.
set -eu
umask 077
stage=/tmp/ifaddr-guard-stage
base=/data/opt/platformd-ifaddr-guard
hook=/etc/init.d/S98platformd-ifaddr-guard
hash() { sha256sum "$1" | cut -d ' ' -f1; }
check() { [ "$(hash "$1")" = "$2" ] || { echo "hash mismatch: $1" >&2; exit 1; }; }
check /system/vendor/quasar/maind 69f4f147fe50c435de5a37f1d8397a91e338c7ab762100c9f2757e010c13df49
check /system/vendor/quasar/launch.json 0861c4c1b12792c2fece90ad8367fcfd4326bd0d6ea8275ffb752af7d4366703
check /data/opt/alisa-standalone/launch.bridge.json baf97568435c2828fc1f9ff80814fc9c308ab71884ab51499084f8f4a71addc1
check "$stage/guard.so" fdcd4736622600ae8acfb5f60ae813764cc5aa2c9371752751981fd756c8c996
check "$stage/launch.stock.guarded.json" de2835623e9c72358c9f9be42ae8a56cd94072b547bd79af987698f3b5e8a632
check "$stage/launch.bridge.guarded.json" 1760d65946183514b029f1add6575df66000e1fd3442caea5082f8e8b3d5aaeb
check "$stage/S98platformd-ifaddr-guard" "$1"
[ ! -e "$base" ] && [ ! -e "$hook" ] || { echo 'already installed' >&2; exit 1; }
mkdir -m 700 "$base"
cp "$stage/guard.so" "$stage/launch.stock.guarded.json" "$stage/launch.bridge.guarded.json" "$base/"
chmod 700 "$base/guard.so"
# The stock profile must stay readable exactly like the file it covers.
chmod 644 "$base/launch.stock.guarded.json"
chmod 600 "$base/launch.bridge.guarded.json"
sync
restore_ro() { sync; mount -o remount,ro / || echo 'ERROR: rootfs still writable' >&2; }
trap restore_ro EXIT
mount -o remount,rw /
cp "$stage/S98platformd-ifaddr-guard" "$hook.new"
chmod 755 "$hook.new"
check "$hook.new" "$1"
mv "$hook.new" "$hook"
trap - EXIT
restore_ro
grep -q ' / ubifs ro' /proc/mounts
"$hook" start
"$hook" status
echo 'installed: profiles guarded for the next platformd start'
