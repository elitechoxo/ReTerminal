set -e

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/share/bin:/usr/share/sbin:/usr/local/bin:/usr/local/sbin:/system/bin:/system/xbin
export HOME=/root

# FIX: resolv.conf already written by init-host.sh but double-check
if [ ! -s /etc/resolv.conf ]; then
    printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
fi

export PS1="\[\e[38;5;46m\]\u\[\033[39m\]@reterm \[\033[39m\]\w \[\033[0m\]\$ "
export PIP_BREAK_SYSTEM_PACKAGES=1

required_packages="bash gcompat glib nano openssh"
missing_packages=""
for pkg in $required_packages; do
    if ! apk info -e $pkg >/dev/null 2>&1; then
        missing_packages="$missing_packages $pkg"
    fi
done
if [ -n "$missing_packages" ]; then
    echo -e "\e[34;1m[*] \e[0mInstalling packages\e[0m"
    apk update && apk upgrade
    apk add $missing_packages
    if [ $? -eq 0 ]; then
        echo -e "\e[32;1m[+] \e[0mDone\e[0m"
    fi
fi

# FIX: Generate SSH host keys if missing (needed for sshd to start)
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A 2>/dev/null
fi

# FIX: Set root password if not set (needed for SFTP password auth)
if ! grep -q "^root:[^*!]" /etc/shadow 2>/dev/null; then
    echo "root:root" | chpasswd 2>/dev/null || true
fi

# FIX: Ensure /run/sshd exists (critical for sshd privilege separation)
mkdir -p /run/sshd

# fix linker warning
if [ ! -f /linkerconfig/ld.config.txt ]; then
    mkdir -p /linkerconfig
    touch /linkerconfig/ld.config.txt
fi

if [ "$#" -eq 0 ]; then
    source /etc/profile 2>/dev/null || true
    export PS1="\[\e[38;5;46m\]\u\[\033[39m\]@reterm \[\033[39m\]\w \[\033[0m\]\$ "
    cd $HOME
    /bin/ash
else
    exec "$@"
fi
