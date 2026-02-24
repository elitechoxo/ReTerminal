set -e

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/system/bin:/system/xbin
export HOME=/root

# DNS safety net
if [ ! -s /etc/resolv.conf ]; then
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
fi

export PS1="\[\e[38;5;46m\]\u\[\033[39m\]@reterm \[\033[39m\]\w \[\033[0m\]\$ "
export PIP_BREAK_SYSTEM_PACKAGES=1

# Auto-install required packages (openssh is critical for SFTP)
required_packages="bash gcompat glib nano openssh"
missing_packages=""
for pkg in $required_packages; do
    if ! apk info -e $pkg >/dev/null 2>&1; then
        missing_packages="$missing_packages $pkg"
    fi
done
if [ -n "$missing_packages" ]; then
    echo -e "\e[34;1m[*]\e[0m Installing:$missing_packages"
    apk update -q && apk add -q $missing_packages
    echo -e "\e[32;1m[+]\e[0m Done"
fi

# Generate host keys (required for sshd to start)
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A -q 2>/dev/null
fi

# Set root password if locked (* or ! in shadow = locked = SFTP auth fails)
if ! grep -q "^root:[^*!]" /etc/shadow 2>/dev/null; then
    echo "root:root" | chpasswd 2>/dev/null || true
fi

# Runtime dirs (race-condition safety, init-host.sh already creates them)
mkdir -p /run/sshd /var/empty

# Fix linker warning
if [ ! -f /linkerconfig/ld.config.txt ]; then
    mkdir -p /linkerconfig && touch /linkerconfig/ld.config.txt
fi

if [ "$#" -eq 0 ]; then
    source /etc/profile 2>/dev/null || true
    export PS1="\[\e[38;5;46m\]\u\[\033[39m\]@reterm \[\033[39m\]\w \[\033[0m\]\$ "
    cd $HOME
    exec /bin/bash 2>/dev/null || exec /bin/ash
else
    exec "$@"
fi
