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

# FIX 1: /run/sshd - sshd REQUIRES this for privilege separation
# Without it: SSH terminal works, SFTP subsystem silently crashes
mkdir -p "$ALPINE_DIR/run/sshd"
chmod 755 "$ALPINE_DIR/run/sshd"

# FIX 2: Real /tmp (separate from /dev/shm)
# SFTP buffers temp files here during transfers
mkdir -p "$ALPINE_DIR/tmp"
chmod 1777 "$ALPINE_DIR/tmp"

# FIX 3: Real /etc/hosts inside Alpine rootfs
mkdir -p "$ALPINE_DIR/etc"
cat > "$ALPINE_DIR/etc/hosts" << 'HOSTS'
127.0.0.1   localhost.localdomain localhost
::1         localhost.localdomain localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS

# FIX 4: resolv.conf pre-written (race condition fix)
if [ ! -s "$ALPINE_DIR/etc/resolv.conf" ]; then
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\n' > "$ALPINE_DIR/etc/resolv.conf"
fi

# FIX 5: sshd_config - THE MAIN SFTP FIX
# UsePrivilegeSeparation no  -> lets SFTP subsystem spawn correctly in proot
# UsePAM no                  -> proot has no real PAM stack
# Correct Subsystem path     -> Alpine uses /usr/lib/ssh/sftp-server
mkdir -p "$ALPINE_DIR/etc/ssh"
cat > "$ALPINE_DIR/etc/ssh/sshd_config" << 'SSHD'
Port 8022
ListenAddress 0.0.0.0
UsePrivilegeSeparation no
UsePAM no
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp /usr/lib/ssh/sftp-server
PrintLastLog no
PrintMotd no
UseDNS no
X11Forwarding no
SSHD

# FIX 6: /var/empty for sshd compatibility
mkdir -p "$ALPINE_DIR/var/empty"
chmod 755 "$ALPINE_DIR/var/empty"

# ─── Build proot ARGS ───────────────────────────────────────

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

# FIX 7: /proc/net for network tools (nmap, netstat, ss, ifconfig)
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

# FIX 8: Bind Alpine /tmp as /dev/shm AND keep real /tmp
if [ ! -d "$ALPINE_DIR/tmp" ]; then
  mkdir -p "$ALPINE_DIR/tmp"
  chmod 1777 "$ALPINE_DIR/tmp"
fi
ARGS="$ARGS -b $ALPINE_DIR/tmp:/dev/shm"

# FIX 9: Android tools inside proot
[ -d "/system/bin" ] && ARGS="$ARGS -b /system/bin:/system/bin"
[ -d "/system/xbin" ] && ARGS="$ARGS -b /system/xbin:/system/xbin"

ARGS="$ARGS -r $PREFIX/local/alpine"
ARGS="$ARGS -0"
ARGS="$ARGS --link2symlink"
ARGS="$ARGS --sysvipc"
ARGS="$ARGS -L"

$LINKER $PREFIX/local/bin/proot $ARGS sh $PREFIX/local/bin/init "$@"
