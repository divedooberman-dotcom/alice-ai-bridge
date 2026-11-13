#!/bin/sh
# Run through the independently verified candidate SSH on port 2223.
set -eu
umask 077
D=/bkupgrade/owner-ssh
BACKUP=$D/dropbear.before-compat-20261113
CANDIDATE=/tmp/dropbear-compat-20261113
OLD=374be9f85dabfab4d1f649d553f45e6238973e272b447fd2d81c2ab24a654db2
NEW=bcdcba94f3269b5ba2065cee2b9d10e53abcea708c2ecd0fcb0bc77776cb7283
hash() { sha256sum "$1" | awk '{print $1}'; }
[ "$(uname -r)" = 4.9.68 ]
[ "$(hash "$D/dropbear")" = "$OLD" ]
[ "$(hash "$CANDIDATE")" = "$NEW" ]
[ ! -e "$BACKUP" ]
read TEST_PID < /run/dropbear-compat-test.pid
[ "$(readlink /proc/$TEST_PID/exe)" = "$CANDIDATE" ]
kill -0 "$TEST_PID"
cp -p "$D/dropbear" "$BACKUP"
[ "$(hash "$BACKUP")" = "$OLD" ]
cp "$CANDIDATE" "$D/dropbear.next"
chmod 700 "$D/dropbear.next"
[ "$(hash "$D/dropbear.next")" = "$NEW" ]
/etc/init.d/S99zz-owner-ssh stop
mv "$D/dropbear.next" "$D/dropbear"
if ! /etc/init.d/S99zz-owner-ssh start; then
    cp -p "$BACKUP" "$D/dropbear.rollback"
    mv "$D/dropbear.rollback" "$D/dropbear"
    /etc/init.d/S99zz-owner-ssh start
    exit 1
fi
sleep 1
read PID < /run/kolobok-dropbear.pid
kill -0 "$PID"
[ "$(readlink /proc/$PID/exe)" = "$D/dropbear" ]
sha256sum "$D/dropbear" "$BACKUP"
echo "primary_pid=$PID"
