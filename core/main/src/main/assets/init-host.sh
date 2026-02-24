ALPINE_DIR=$PREFIX/local/alpine

mkdir -p $ALPINE_DIR

if [ -z "$(ls -A "$ALPINE_DIR" | grep -vE '^(root|tmp)$')" ]; then
    tar -xf "$PREFIX/files/alpine.tar.gz" -C "$ALPINE_DIR"
fi

[ ! -e "$PREFIX/local/bin/proot" ] && cp "$PREFIX/files/proot" "$PREFIX/local/bin"

for sofile in "$PREFIX/files/"*.so.2; do
    dest="$PREFIX/local/lib/$(basename "$sofile")"
    [ ! -e "$dest" ] && cp "$sofile" "$dest"
done


# ── SFTP setup: configure Alpine rootfs before proot starts ──────
mkdir -p "$ALPINE_DIR/etc/ssh"
mkdir -p "$ALPINE_DIR/run/sshd"
mkdir -p "$ALPINE_DIR/var/empty"
chmod 755 "$ALPINE_DIR/run/sshd" "$ALPINE_DIR/var/empty"

# Write hosts file if missing
if [ ! -f "$ALPINE_DIR/etc/hosts" ]; then
    printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n' > "$ALPINE_DIR/etc/hosts"
fi

# Write resolv.conf if empty
if [ ! -s "$ALPINE_DIR/etc/resolv.conf" ]; then
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$ALPINE_DIR/etc/resolv.conf"
fi

# Write sshd_config (always overwrite so fixes apply on update)
# internal-sftp: SFTP runs inside sshd itself — no fork, no priv-sep needed
# UsePrivilegeSeparation no: proot cannot do real kernel privilege separation
# UsePAM no: proot has no PAM stack; with it enabled auth silently fails
cat > "$ALPINE_DIR/etc/ssh/sshd_config" << 'SSHD_CFG'
Port 8022
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp internal-sftp
UsePrivilegeSeparation no
UsePAM no
StrictModes no
PrintLastLog no
PrintMotd no
UseDNS no
X11Forwarding no
SSHD_CFG
# ─────────────────────────────────────────────────────────────────

ARGS="--kill-on-exit"
ARGS="$ARGS -w /"

for system_mnt in /apex /odm /product /system /system_ext /vendor \
 /linkerconfig/ld.config.txt \
 /linkerconfig/com.android.art/ld.config.txt \
 /plat_property_contexts /property_contexts; do

 if [ -e "$system_mnt" ]; then
  system_mnt=$(realpath "$system_mnt")
  ARGS="$ARGS -b ${system_mnt}"
 fi
done
unset system_mnt

ARGS="$ARGS -b /sdcard"
ARGS="$ARGS -b /storage"
ARGS="$ARGS -b /dev"
ARGS="$ARGS -b /data"
ARGS="$ARGS -b /dev/urandom:/dev/random"
ARGS="$ARGS -b /proc"
ARGS="$ARGS -b $PREFIX"
ARGS="$ARGS -b $PREFIX/local/stat:/proc/stat"
ARGS="$ARGS -b $PREFIX/local/vmstat:/proc/vmstat"

if [ -d "/proc/net" ]; then
  ARGS="$ARGS -b /proc/net"
fi

if [ -e "/proc/self/fd" ]; then
  ARGS="$ARGS -b /proc/self/fd:/dev/fd"
fi

if [ -e "/proc/self/fd/0" ]; then
  ARGS="$ARGS -b /proc/self/fd/0:/dev/stdin"
fi

if [ -e "/proc/self/fd/1" ]; then
  ARGS="$ARGS -b /proc/self/fd/1:/dev/stdout"
fi

if [ -e "/proc/self/fd/2" ]; then
  ARGS="$ARGS -b /proc/self/fd/2:/dev/stderr"
fi


ARGS="$ARGS -b $PREFIX"
ARGS="$ARGS -b /sys"

if [ ! -d "$PREFIX/local/alpine/tmp" ]; then
 mkdir -p "$PREFIX/local/alpine/tmp"
 chmod 1777 "$PREFIX/local/alpine/tmp"
fi
ARGS="$ARGS -b $PREFIX/local/alpine/tmp:/dev/shm"

ARGS="$ARGS -r $PREFIX/local/alpine"
ARGS="$ARGS -0"
ARGS="$ARGS --link2symlink"
ARGS="$ARGS --sysvipc"
ARGS="$ARGS -L"

$LINKER $PREFIX/local/bin/proot $ARGS sh $PREFIX/local/bin/init "$@"
