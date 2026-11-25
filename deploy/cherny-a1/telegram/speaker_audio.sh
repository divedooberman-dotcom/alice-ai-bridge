#!/bin/sh
# Forced SSH command on the Cherny only. Never evaluate SSH_ORIGINAL_COMMAND.
set -eu
tr '\000' '\n' </proc/device-tree/compatible | grep -qx 'yandex,cucumber-dvt2'
umask 077
tmp=$(mktemp -d /tmp/cherny-telegram-audio.XXXXXX)
pid=
display_worker=
alarm_clock_worker=
alarm_reader=
alarm_volume=
call_display_owned=
speaker_volume() {
    amixer -c 0 cget 'name=Master Playback Volume' |
        awk '/^[[:space:]]*: values=/ {sub(/.*values=/,""); print; exit}'
}
cleanup() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    if [ -n "$alarm_volume" ] && [ "$(speaker_volume)" = 255,255 ]; then
        amixer -q -c 0 cset 'name=Master Playback Volume' "$alarm_volume" || true
    fi
    if [ -n "$alarm_reader" ]; then
        kill "$alarm_reader" 2>/dev/null || true
        wait "$alarm_reader" 2>/dev/null || true
    fi
    if [ -n "$alarm_clock_worker" ]; then
        kill "$alarm_clock_worker" 2>/dev/null || true
        wait "$alarm_clock_worker" 2>/dev/null || true
    fi
    if [ -n "$display_worker" ]; then
        kill "$display_worker" 2>/dev/null || true
        wait "$display_worker" 2>/dev/null || true
    fi
    if [ -n "$call_display_owned" ]; then
        clock_ok=0; ring_ok=0
        if [ "$call_display_owned" = ring ]; then
            clock_ok=1
        else
            luna_post clock/off '{}' >/dev/null 2>&1 && clock_ok=1
        fi
        if [ "$call_display_owned" = clock ]; then
            ring_ok=1
        else
            luna_post led/off/ring '{}' >/dev/null 2>&1 && ring_ok=1
        fi
        if [ "$clock_ok" = 1 ] && [ "$ring_ok" = 1 ]; then printf 'released\n'; fi
    fi
    rm -f "$tmp/pcm" "$tmp/gateway" "$tmp/dns" "$tmp/telegram"
    rmdir "$tmp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mic_enabled() {
    grep -Eq '\|mute-switch +\).* in +hi ACTIVE LOW' /sys/kernel/debug/gpio
}

luna_get() {
    wget -T 4 -qO- "http://127.0.0.1:8099/api/$1"
}

luna_post() {
    wget -T 4 -qO- --header 'Content-Type: application/json' --post-data "$2" \
        "http://127.0.0.1:8099/api/$1"
}

read_clock_brightness() {
    level=50
    if IFS= read -r requested; then
        case "$requested" in 10|50|100) level=$requested ;; *) return 2 ;; esac
    fi
}

ring_frame() {
    awk -v mode="$1" -v step="$2" 'BEGIN {
        split("#200000 #201000 #202000 #002000 #002020 #000020 #200020 #200810", p, " ")
        split("#040004 #080008 #100010 #180018 #200020 #180018 #100010 #080008", b, " ")
        printf "{\"colors\":["
        for (i=0; i<24; i++) {
            if (mode=="rainbow") c=p[(int(i/3)+step)%8+1]
            else if (mode=="breathe") c=b[step%8+1]
            else if (mode=="spin") c=((i-step+24)%24<3)?"#002020":"#000000"
            else if (mode=="police") c=((int(i/12)+step)%2)?"#200000":"#000020"
            else c=(step%2)?"#202020":"#000000"
            printf "%s\"%s\"", i ? "," : "", c
        }
        print "]}"
    }'
}

case "${SSH_ORIGINAL_COMMAND:-}" in
    alarm_full|alarm_siren)
        alarm=/data/opt/cherny-telegram-audio/alarm
        test -s "$alarm/siren.wav"
        if [ "$SSH_ORIGINAL_COMMAND" = alarm_full ]; then test -s "$alarm/warning.wav"; fi
        exec 9>/tmp/cherny-telegram-alarm.lock
        flock -n 9
        saved=$(speaker_volume)
        printf '%s\n' "$saved" | grep -Eq '^[0-9]{1,3},[0-9]{1,3}$'
        alarm_volume=$saved
        amixer -q -c 0 cset 'name=Master Playback Volume' 255,255
        call_display_owned=1
        luna_post led/ring "$(ring_frame police 0)" >/dev/null
        (
            trap - EXIT
            trap 'exit 0' HUP INT TERM
            step=1
            while :; do
                sleep 0.25
                luna_post led/ring "$(ring_frame police "$step")" >/dev/null
                step=$((1 - step))
            done
        ) </dev/null &
        display_worker=$!
        (
            trap - EXIT
            trap 'exit 0' HUP INT TERM
            while :; do
                luna_post clock/text '{"text":"HELP","brightness":100,"duration_ms":15000}' >/dev/null 2>&1 || true
                sleep 5
            done
        ) </dev/null &
        alarm_clock_worker=$!
        parent=$$
        trap 'exit 0' USR1
        exec 8<&0
        (
            trap - EXIT
            IFS= read -r ignored || true
            kill -USR1 "$parent" 2>/dev/null || true
        ) <&8 &
        alarm_reader=$!
        printf 'ready\n'
        if [ "$SSH_ORIGINAL_COMMAND" = alarm_full ]; then
            aplay -q -D speakers "$alarm/warning.wav" </dev/null &
            pid=$!
            wait "$pid"
            pid=
        fi
        while :; do
            aplay -q -D speakers "$alarm/siren.wav" </dev/null &
            pid=$!
            wait "$pid"
            pid=
        done
        ;;
    speech_capture)
        capture=/data/opt/cherny-telegram-audio/dmix
        stock=f75be865339127d81e6a24724a271381c9cb0d548c3a42bc7d93840bc6bae4e3
        exec 9>/tmp/cherny-native-speech.lock
        flock -n 9
        [ "$(sha256sum /etc/asound.conf | cut -d' ' -f1)" = "$stock" ]
        [ "$(cat /proc/asound/card0/pcm0p/sub0/hw_params)" = closed ]
        exec 8<&0
        "$capture/ld-linux-aarch64.so.1" --library-path "$capture" "$capture/dmix-capture" <&8 &
        pid=$!
        wait "$pid"
        pid=
        ;;
    timer_display)
        IFS= read -r seconds
        case "$seconds" in ''|*[!0-9]*) exit 2 ;; esac
        [ "${#seconds}" -le 4 ] && [ "$seconds" -ge 1 ] && [ "$seconds" -le 1800 ]
        now=$(cut -d. -f1 /proc/uptime)
        until=$((now + seconds))
        call_display_owned=clock
        (
            trap - EXIT
            trap 'exit 0' HUP INT TERM
            first=1
            while :; do
                now=$(cut -d. -f1 /proc/uptime)
                remaining=$((until - now))
                [ "$remaining" -gt 0 ] || break
                frame=$(printf '%02d%02d' "$((remaining / 60))" "$((remaining % 60))")
                luna_post clock/text "$(printf '{"text":"%s","brightness":50,"duration_ms":1000}' "$frame")" >/dev/null
                if [ "$first" = 1 ]; then printf 'ready\n'; first=0; fi
            done
        ) </dev/null &
        display_worker=$!
        read -r -t "$seconds" ignored || true
        ;;
    effect_rainbow|effect_breathe|effect_spin|effect_police|effect_flash)
        mode=${SSH_ORIGINAL_COMMAND#effect_}
        seconds=1800
        if [ "$mode" = flash ]; then seconds=3; fi
        call_display_owned=ring
        luna_post led/ring "$(ring_frame "$mode" 0)" >/dev/null
        (
            trap - EXIT
            trap 'exit 0' HUP INT TERM
            step=1
            while :; do
                sleep 0.6
                luna_post led/ring "$(ring_frame "$mode" "$step")" >/dev/null
                step=$(((step + 1) % 24))
            done
        ) </dev/null &
        display_worker=$!
        printf 'ready\n'
        read -r -t "$seconds" ignored || true
        ;;
    prank_ring)
        call_display_owned=ring
        luna_post led/ring '{"colors":["#200000"]}' >/dev/null
        printf 'ready\n'
        read -r -t 16 ignored || true
        ;;
    call_display_ring|call_display_active)
        if [ "$SSH_ORIGINAL_COMMAND" = call_display_ring ]; then
            text=CALL; color='#002020'; seconds=36
        else
            text=CHAT; color='#002010'; seconds=1805
        fi
        call_display_owned=1
        luna_post led/ring "$(printf '{"colors":["%s"]}' "$color")" >/dev/null
        clock_payload=$(printf '{"text":"%s","brightness":50,"duration_ms":15000}' "$text")
        (
            trap - EXIT
            trap 'exit 0' HUP INT TERM
            while :; do
                # LUNA retains the frame if the HTTP client times out.
                luna_post clock/text "$clock_payload" >/dev/null 2>&1 || true
                sleep 6
            done
        ) </dev/null &
        display_worker=$!
        printf 'ready\n'
        # Hold only while the authenticated SSH client keeps stdin open.
        read -r -t "$seconds" ignored || true
        ;;
    sensors) luna_get sensors ;;
    hardware_info)
        printf 'uptime_seconds=%s\n' "$(cut -d. -f1 /proc/uptime)"
        awk '{print "load=" $1 " " $2 " " $3}' /proc/loadavg
        for setting in scaling_cur_freq scaling_governor; do
            file="/sys/devices/system/cpu/cpu0/cpufreq/$setting"
            if [ -r "$file" ]; then printf '%s=%s\n' "$setting" "$(cat "$file")"; fi
        done
        if command -v wpa_cli >/dev/null 2>&1; then
            wpa_cli -i wlan0 status 2>/dev/null | awk -F= '$1 == "ssid" || $1 == "freq" || $1 == "wpa_state"'
            wpa_cli -i wlan0 signal_poll 2>/dev/null | awk -F= '$1 == "RSSI" || $1 == "FREQUENCY"'
        fi
        ;;
    network_info)
        gateway=$(ip -4 route show default 2>/dev/null |
            awk '$1 == "default" && $2 == "via" && $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $3; exit}')
        probe_ping() {
            if [ -z "$1" ]; then printf 'no_route\n'; return; fi
            if ! command -v ping >/dev/null 2>&1; then printf 'unavailable\n'; return; fi
            result=$(LC_ALL=C ping -c 2 -W 2 "$1" 2>/dev/null) || true
            average=$(printf '%s\n' "$result" | awk -F' = ' '/min\/avg/ {split($2, times, "/"); print times[2]; exit}')
            if [ -n "$average" ]; then printf '%s\n' "$average"; else printf 'no_reply\n'; fi
        }
        probe_ping "$gateway" >"$tmp/gateway" &
        probe_ping 77.88.8.8 >"$tmp/dns" &
        probe_ping 149.154.167.50 >"$tmp/telegram" &
        wait
        for target in gateway dns telegram; do
            printf '%s=%s\n' "$target" "$(cat "$tmp/$target")"
            rm -f "$tmp/$target"
        done
        ;;
    flash_info)
        awk -F= '$1=="PRETTY_NAME" || $1=="BUILD_ID" {print}' /etc/os-release
        if [ -r /system/vendor/quasar/version_full ]; then
            printf 'FIRMWARE=%s\n' "$(cat /system/vendor/quasar/version_full)"
        fi
        df -k /data | awk 'NR>1 && $NF=="/data" {print "DATA_TOTAL=" $(NF-4); print "DATA_USED=" $(NF-3)}'
        ;;
    partition_info)
        awk '$4 ~ /^mmcblk[0-9]+(p[0-9]+)?$/ && $3 ~ /^[0-9]+$/ {
            printf "block\t%s:%s\t%s\t%s\n",$1,$2,$3,$4
        }' /proc/partitions
        awk '$5=="/" || $5=="/data" {printf "mount\t%s\t%s\n",$3,$5}' /proc/self/mountinfo
        ls -ln /dev | awk '$1 ~ /^b/ && $5 ~ /^[0-9]+,$/ && $6 ~ /^[0-9]+$/ && $NF ~ /^[A-Za-z0-9_.-]+$/ {
            sub(/,$/,"",$5); printf "alias\t%s:%s\t%s\n",$5,$6,$NF
        }'
        ;;
    system_info)
        uname -rm
        uptime
        awk '/^MemTotal:|^MemAvailable:/ {print}' /proc/meminfo
        ;;
    storage_info)
        df -k /data /tmp
        free -m
        ;;
    cleanup_cache)
        old_dirs=$(find /tmp -maxdepth 1 -type d -user root -perm 0700 -name 'cherny-telegram-audio.*' -mmin +60)
        printf '%s\n' "$old_dirs" |
        while IFS= read -r old; do
            case "${old#/tmp/cherny-telegram-audio.}" in
                ''|*[!a-zA-Z0-9]*) continue ;;
            esac
            rm -f "$old/pcm"
            if rmdir "$old" 2>/dev/null; then printf 'removed\n'; fi
        done
        ;;
    boot_id) cat /proc/sys/kernel/random/boot_id ;;
    call_voice_events|dialog_events)
        log_file=
        for candidate in /data/quasar/daemons_logs/maind.log /bkupgrade/quasar/daemons_logs/maind.log; do
            if [ -r "$candidate" ]; then log_file=$candidate; break; fi
        done
        [ -n "$log_file" ] || exit 5
        # Send only exact call controls and their log timestamps, never raw dialogue.
        tail -n 100 "$log_file" | awk -v mode="$SSH_ORIGINAL_COMMAND" '
            match($0, /\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9:.]+\]/) {
                stamp=substr($0,RSTART+1,RLENGTH-2)
                if (mode=="dialog_events" && match($0, /Got AliceDeferred Response message:[ ]*Text=.*,[ ]*IsLast=[0-9]+/)) {
                    reply=substr($0,RSTART,RLENGTH)
                    if (reply !~ /IsLast=1$/) next
                    sub(/^Got AliceDeferred Response message:[ ]*Text=/, "", reply)
                    sub(/,[ ]*IsLast=1$/, "", reply)
                    gsub(/[\t\r]/, " ", reply)
                    if (length(reply)>0) print stamp "\tanswer\t" substr(reply,1,2400)
                    next
                }
                if (!match($0, /recognizedPhrase=\047[^\047]*\047/)) next
                phrase=substr($0,RSTART+18,RLENGTH-19)
                if (mode=="dialog_events") {
                    gsub(/[\t\r]/, " ", phrase)
                    if (length(phrase)>0) print stamp "\tquestion\t" substr(phrase,1,800)
                    next
                }
                sub(/^(Алиса|алиса)[, ]+/, "", phrase)
                sub(/[.!?]+$/, "", phrase)
                if (phrase ~ /^(Прими|прими|Принять|принять|Ответь|ответь|Возьми трубку|возьми трубку|Соедини|соедини)$/)
                    print stamp "\taccept"
                else if (phrase ~ /^(Отбой|отбой|Отклони|отклони|Сбрось|сбрось|Положи трубку|положи трубку|Заверши звонок|заверши звонок)$/)
                    print stamp "\tend"
            }'
        ;;
    reboot_station)
        nohup /bin/sh -c 'sleep 3; exec /sbin/reboot' </dev/null >/dev/null 2>&1 &
        printf 'scheduled\n'
        ;;
    ring_red) luna_post led/ring '{"colors":["#200000"]}' ;;
    ring_green) luna_post led/ring '{"colors":["#002000"]}' ;;
    ring_blue) luna_post led/ring '{"colors":["#000020"]}' ;;
    ring_purple) luna_post led/ring '{"colors":["#200020"]}' ;;
    ring_orange) luna_post led/ring '{"colors":["#201000"]}' ;;
    ring_cyan) luna_post led/ring '{"colors":["#002020"]}' ;;
    ring_pink) luna_post led/ring '{"colors":["#200810"]}' ;;
    ring_white) luna_post led/ring '{"colors":["#202020"]}' ;;
    ring_release) luna_post led/off/ring '{}' ;;
    clock_release) luna_post clock/off '{}' ;;
    clock_text)
        IFS= read -r text
        printf '%s\n' "$text" | LC_ALL=C grep -Eq '^[A-JLN-UY0-9 _-]{1,4}$'
        read_clock_brightness
        luna_post clock/text "$(printf '{"text":"%s","brightness":%s}' "$text" "$level")"
        ;;
    clock_face)
        IFS= read -r face
        read_clock_brightness
        case "$face" in
            cat) set -- A1 B1 F1 G2 D2 D3 G3 A4 B4 F4 ;;
            happy) set -- A1 B1 F1 E2 D2 D3 C3 A4 B4 F4 ;;
            uwu) set -- C1 D1 E1 E2 D2 C2 E3 D3 C3 C4 D4 E4 ;;
            *) exit 2 ;;
        esac
        frame=$(printf '{"segments":{'
            separator=
            for segment do
                printf '%s"%s":%s' "$separator" "$segment" "$level"
                separator=,
            done
            printf '}}')
        call_display_owned=clock
        luna_post clock "$frame"
        sleep 2
        luna_post clock/off '{}'
        call_display_owned=
        ;;
    record[3-9]|record[12][0-9]|record30)
        seconds=${SSH_ORIGINAL_COMMAND#record}
        mic_enabled || exit 3
        # Alice shares the PDM clock. Refuse capture if the native format changes.
        grep -q '^rate: 96000 ' /proc/asound/card0/pcm2c/sub0/hw_params || exit 3
        ALSA_CONFIG_PATH=/data/opt/cherny-telegram-audio/room-capture.conf \
            arecord -q -D cherny_room -t raw -c 8 -r 48000 -f S16_LE -d "$seconds" "$tmp/pcm" </dev/null &
        pid=$!
        count=0
        while kill -0 "$pid" 2>/dev/null; do
            mic_enabled || exit 3
            [ "$count" -lt "$((seconds + 3))" ] || exit 4
            count=$((count + 1))
            sleep 1
        done
        wait "$pid"
        pid=
        mic_enabled || exit 3
        test "$(wc -c < "$tmp/pcm")" -eq "$((seconds * 48000 * 8 * 2))"
        cat "$tmp/pcm"
        ;;
    play|voice)
        # Accept only bounded stereo PCM at 96 kHz.
        limit=768000
        if [ "$SSH_ORIGINAL_COMMAND" = voice ]; then limit=11520000; fi
        head -c "$((limit + 1))" > "$tmp/pcm"
        bytes=$(wc -c < "$tmp/pcm")
        [ "$bytes" -gt 0 ] && [ "$bytes" -le "$limit" ] && [ "$((bytes % 4))" -eq 0 ]
        awk '$2 ~ /:1388$/ && $4 == "01" {busy=1} END {exit busy}' /proc/net/tcp /proc/net/tcp6
        aplay -q -D plughw:0,0 -t raw -c 2 -r 96000 -f S16_LE "$tmp/pcm" </dev/null &
        pid=$!
        wait "$pid"
        pid=
        ;;
    *) exit 2 ;;
esac
