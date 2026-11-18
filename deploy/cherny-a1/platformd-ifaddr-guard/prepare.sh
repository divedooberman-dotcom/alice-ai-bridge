#!/bin/sh
set -eu
umask 077
base=/data/opt/platformd-ifaddr-guard
target=/system/vendor/quasar/launch.json
[ "$(sha256sum /system/vendor/quasar/maind | cut -d ' ' -f1)" = ae53daaf1d1867744017bb6939d7fa2c95f0d76468f8472a273ab041a895642b ]
[ "$(sha256sum "$target" | cut -d ' ' -f1)" = 37142beec68773b425865aa7dd889ede513734630d9f43f4658d9b7284b03129 ]
[ "$(sha256sum "$base/guard.candidate.so" | cut -d ' ' -f1)" = 4a4a05f51813739470d7be7bea9807e54d2d2829989c1eec7c83eb4224078e12 ]
test ! -e "$base/launch.original.json"
cp -p "$target" "$base/launch.original.json"
chmod 600 "$base/launch.original.json"
jq -e '[..|objects|select(.name? == "maind" and .path? == "/system/vendor/quasar/maind" and ((.arg|tostring)|contains("platformd")))]|length==1' "$target" >/dev/null
jq 'walk(if type=="object" and .name?=="maind" and .path?=="/system/vendor/quasar/maind" and ((.arg|tostring)|contains("platformd")) then .envs=((.envs//[])+["LD_PRELOAD=/data/opt/platformd-ifaddr-guard/guard.so"]) else . end)' "$target" > "$base/launch.guarded.json"
# Removing exactly our field must recover the entire original JSON value.
jq -S . "$target" > "$base/original.canonical"
jq -S 'walk(if type=="object" and .name?=="maind" and .path?=="/system/vendor/quasar/maind" and ((.arg|tostring)|contains("platformd")) then del(.envs) else . end)' "$base/launch.guarded.json" > "$base/reverted.canonical"
cmp -s "$base/original.canonical" "$base/reverted.canonical"
mv "$base/guard.candidate.so" "$base/guard.so"
sync
echo 'prepared: original preserved; only platformd environment changed'
