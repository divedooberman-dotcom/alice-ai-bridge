#!/bin/sh
# Run detached on the speaker so the reconnect does not depend on SSH.
set -u
find_platformd() {
    for p in $(pidof maind); do
        if tr '\000' '\n' < /proc/"$p"/cmdline | grep -qx -- --platformd; then
            echo "$p"
        fi
    done
}
before=$(find_platformd)
test -n "$before" || exit 1
grep -q /data/opt/platformd-ifaddr-guard/guard.so /proc/"$before"/maps || exit 1
boot=$(cat /proc/sys/kernel/random/boot_id)
printf 'before_pid=%s boot=%s\n' "$before" "$boot"
date -u '+disconnect_utc=%Y-%m-%dT%H:%M:%SZ'
# An independent fallback reconnect remains scheduled if this shell fails.
(sleep 45; wpa_cli -i wlan0 reconnect >/dev/null 2>&1) </dev/null &
fallback=$!
wpa_cli -i wlan0 disconnect
sleep 20
wpa_cli -i wlan0 status | grep '^wpa_state='
printf 'during_pid=%s\n' "$(find_platformd)"
wpa_cli -i wlan0 reconnect
n=0
while [ "$n" -lt 18 ]; do
    sleep 5
    state=$(wpa_cli -i wlan0 status | sed -n 's/^wpa_state=//p')
    if [ "$state" = COMPLETED ]; then
        after=$(find_platformd)
        printf 'after_pid=%s wpa_state=%s\n' "$after" "$state"
        date -u '+reconnected_utc=%Y-%m-%dT%H:%M:%SZ'
        kill "$fallback" 2>/dev/null || true
        test "$before" = "$after" || exit 2
        test "$boot" = "$(cat /proc/sys/kernel/random/boot_id)" || exit 3
        echo 'PASS: same platformd process and boot after Wi-Fi reconnect'
        exit 0
    fi
    n=$((n+1))
done
echo 'FAIL: Wi-Fi did not reconnect in observation window'
exit 4
