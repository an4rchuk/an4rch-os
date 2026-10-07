# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# an4rch OS: start the installer on the first console.
if [[ "$(tty)" == /dev/tty1 && -z "${LUMEN_INSTALLER_STARTED:-}" ]]; then
    export LUMEN_INSTALLER_STARTED=1
    lumen-os-install
fi
