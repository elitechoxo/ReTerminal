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

# ── Pre-configure Alpine rootfs BEFORE proot starts ──────────────

mkdir -p "$ALPINE_DIR/etc"
mkdir -p "$ALPINE_DIR/etc/ssh"
mkdir -p "$ALPINE_DIR/run/sshd"
mkdir -p "$ALPINE_DIR/var/empty"
mkdir -p "$ALPINE_DIR/tmp"
chmod 755 "$ALPINE_DIR/run/sshd"
chmod 755 "$ALPINE_DIR/var/empty"
chmod 1777 "$ALPINE_DIR/tmp"

# /etc/hosts
cat > "$ALPINE_DIR/etc/hosts" << 'HOSTS'
127.0.0.1   localhost.localdomain localhost
::1         localhost.localdomain localhost ip6-localhost ip6-loopback
HOSTS

# /etc/resolv.conf
if [ ! -s "$ALPINE_DIR/etc/resolv.conf" ]; then
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$ALPINE_DIR/etc/resolv.conf"
fi

# sshd_config — written unconditionally so updates always apply
# KEY: internal-sftp = sftp runs INSIDE sshd process, no fork/priv-sep needed
# KEY: UsePrivilegeSeparation no = proot cannot do real kernel priv-sep
# KEY: UsePAM no = proot has no PAM stack
cat > "$ALPINE_DIR/etc/ssh/sshd_config" << 'SSHD'
Port 8022
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
Subsystem sftp internal-sftp
UsePrivilegeSeparation no
UsePAM no
StrictModes no
PrintLastLog no
PrintMotd no
UseDNS no
X11Forwarding no
SSHD

# ── proot ARGS ─────────────────────────────────────────────────

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
ARGS="$ARGS -b /sys"
ARGS="$ARGS -b $PREFIX"
ARGS="$ARGS -b $PREFIX/local/stat:/proc/stat"
ARGS="$ARGS -b $PREFIX/local/vmstat:/proc/vmstat"

[ -d "/proc/net" ] && ARGS="$ARGS -b /proc/net"

[ -e "/proc/self/fd"   ] && ARGS="$ARGS -b /proc/self/fd:/dev/fd"
[ -e "/proc/self/fd/0" ] && ARGS="$ARGS -b /proc/self/fd/0:/dev/stdin"
[ -e "/proc/self/fd/1" ] && ARGS="$ARGS -b /proc/self/fd/1:/dev/stdout"
[ -e "/proc/self/fd/2" ] && ARGS="$ARGS -b /proc/self/fd/2:/dev/stderr"

ARGS="$ARGS -b $ALPINE_DIR/tmp:/dev/shm"

[ -d "/system/bin"  ] && ARGS="$ARGS -b /system/bin:/system/bin"
[ -d "/system/xbin" ] && ARGS="$ARGS -b /system/xbin:/system/xbin"

ARGS="$ARGS -r $PREFIX/local/alpine"
ARGS="$ARGS -0"
ARGS="$ARGS --link2symlink"
ARGS="$ARGS --sysvipc"
ARGS="$ARGS -L"

$LINKER $PREFIX/local/bin/proot $ARGS sh $PREFIX/local/bin/init "$@"
