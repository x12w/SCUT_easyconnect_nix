#!/usr/bin/env bash
# EasyConnect cross-distro one-command installer
# Supports: NixOS, Ubuntu, Debian, Arch, Fedora, and any distro with Nix installed.
#
# Usage:
#   ./setup.sh install     # Install EasyConnect
#   ./setup.sh uninstall   # Remove EasyConnect

set -euo pipefail

FLAKE_URL="github:x12w/SCUT_easyconnect_nix"
INSTALL_DIR="/usr/local/lib/easyconnect"
BIN_DIR="/usr/local/bin"
WRAPPERS_DIR="${INSTALL_DIR}/wrappers"
NIX_BUILD_RESULT=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; exit 1; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "This step requires root. Please run with sudo."
    fi
}

check_deps() {
    log "Checking dependencies..."
    if ! command -v nix &>/dev/null; then
        err "Nix is required but not installed.\n"\
            "Install it: curl -L https://nixos.org/nix/install | sh"
    fi
    if ! command -v gcc &>/dev/null; then
        warn "gcc not found, will use nix-shell for compilation"
    fi
}

build_package() {
    log "Building EasyConnect package (this may take a while on first run)..."
    NIX_BUILD_RESULT=$(nix build "${FLAKE_URL}#easyconnect" --no-link --print-out-paths 2>&1)
    log "Built: ${NIX_BUILD_RESULT}"
}

compile_suid_wrappers() {
    local wrapper_src
    wrapper_src="$(dirname "$0")/wrappers/suid-wrapper.c"
    local cc=gcc

    if ! command -v "$cc" &>/dev/null; then
        cc="nix-shell -p gcc --run gcc"
    fi

    log "Compiling SUID wrappers..."
    mkdir -p "${WRAPPERS_DIR}"

    # iptables wrappers (need nat table access)
    local ipt_bin ipt_name
    local IPTABLES_BASE="${NIX_BUILD_RESULT}/share/sangfor/EasyConnect/resources"
    # Use system iptables if available, otherwise the one from the nix build
    local REAL_IPTABLES=""
    if command -v iptables-legacy &>/dev/null; then
        REAL_IPTABLES=$(readlink -f "$(which iptables-legacy)")
    else
        REAL_IPTABLES=$(find /nix/store -path "*/iptables*/bin/iptables-legacy" -type l 2>/dev/null | head -1)
        [ -z "$REAL_IPTABLES" ] && REAL_IPTABLES=$(find /nix/store -path "*/iptables*/bin/xtables-legacy-multi" -type f 2>/dev/null | head -1)
    fi

    for name in iptables iptables-legacy iptables-legacy-save iptables-legacy-restore; do
        local target="${REAL_IPTABLES}"
        [ ! -f "$target" ] && warn "Real iptables not found at $target, skipping ${name}" && continue
        $cc -DTARGET="\"${target}\"" -o "${WRAPPERS_DIR}/${name}" "${wrapper_src}"
        chown root:root "${WRAPPERS_DIR}/${name}" 2>/dev/null || warn "Could not chown ${name} (run as root?)"
        chmod u+s "${WRAPPERS_DIR}/${name}" 2>/dev/null || warn "Could not set SUID on ${name} (run as root?)"
        log "  ${name} -> ${target}"
    done

    # VPN service wrappers
    local EC_BIN="${NIX_BUILD_RESULT}/share/sangfor/EasyConnect/resources/bin"
    for svc in ECAgent svpnservice CSClient; do
        local target="${EC_BIN}/${svc}"
        [ ! -f "$target" ] && warn "${target} not found, skipping" && continue
        $cc -DTARGET="\"${target}\"" -o "${WRAPPERS_DIR}/${svc}" "${wrapper_src}"
        chown root:root "${WRAPPERS_DIR}/${svc}" 2>/dev/null || warn "Could not chown ${svc}"
        chmod u+s "${WRAPPERS_DIR}/${svc}" 2>/dev/null || warn "Could not set SUID on ${svc}"
        log "  ${svc} -> ${target}"
    done

    # Network tool wrappers (ip, ifconfig, route)
    for tool in ip ifconfig route; do
        local target
        target=$(which "$tool" 2>/dev/null || true)
        [ -z "$target" ] && warn "${tool} not found in PATH, skipping" && continue
        target=$(readlink -f "$target")
        $cc -DTARGET="\"${target}\"" -o "${WRAPPERS_DIR}/${tool}" "${wrapper_src}"
        chown root:root "${WRAPPERS_DIR}/${tool}" 2>/dev/null || warn "Could not chown ${tool}"
        chmod u+s "${WRAPPERS_DIR}/${tool}" 2>/dev/null || warn "Could not set SUID on ${tool}"
        log "  ${tool} -> ${target}"
    done
}

create_entrypoint() {
    log "Creating entrypoint at ${BIN_DIR}/easyconnect..."

    local app_dir="${INSTALL_DIR}/share/sangfor/EasyConnect"
    local res_dir="${app_dir}/resources"
    local lib_path="${app_dir}:${res_dir}/lib64:${INSTALL_DIR}/opt/easyconnect/legacy-libs"

    # Build PATH with wrappers first, then system paths
    local ec_path="${WRAPPERS_DIR}:${BIN_DIR}:/usr/bin:/usr/sbin:/bin:/sbin"

    cat > "${BIN_DIR}/easyconnect" <<SCRIPT
#!/usr/bin/env bash
export LD_LIBRARY_PATH="${lib_path}:\${LD_LIBRARY_PATH:-}"
export PATH="${ec_path}:\$PATH"
export QT_X11_NO_MITSHM=1
export XDG_DATA_DIRS="\${XDG_DATA_DIRS:-/usr/share:/usr/local/share}"

set -e

appdir="\$HOME/.easyconnect"
bindir="\${appdir}/resources/bin"
mkdir -p "\${appdir}" "\${appdir}/resources" "\${bindir}" "\${appdir}/logs"
mkdir -p /tmp/sangfor

unset ELECTRON_RUN_AS_NODE
export EASYCONNECT_HOME="\${appdir}"
runtime_appdir="/tmp/sangfor/EasyConnectNixOSX"
[ -e "\${runtime_appdir}" ] && [ ! -d "\${runtime_appdir}" ] && rm -f "\${runtime_appdir}"
mkdir -p "\${runtime_appdir}"

# Set up symlink farm
for src in ${app_dir}/*; do
    name="\$(basename "\${src}")"
    [ "\${name}" = "resources" ] && continue
    ln -sfn "\${src}" "\${appdir}/\${name}"
done

find "\${appdir}/resources" -mindepth 1 -maxdepth 1 \\
    ! -name bin ! -name conf ! -name logs ! -name user_cert -exec rm -rf {} +

for src in ${res_dir}/*; do
    name="\$(basename "\${src}")"
    case "\${name}" in bin|conf|logs|user_cert) ;; *)
        ln -sfn "\${src}" "\${appdir}/resources/\${name}"
    esac
done

rm -rf "\${appdir}/resources/conf" "\${appdir}/resources/logs" "\${appdir}/resources/user_cert" "\${appdir}/resources/bin"
mkdir -p "\${appdir}/resources/conf" "\${appdir}/resources/logs" "\${appdir}/resources/user_cert" "\${appdir}/resources/bin"
cp -n ${res_dir}/conf/* "\${appdir}/resources/conf/" 2>/dev/null || true
mkdir -p "\${appdir}/resourceslogs" "\${appdir}/logs"
touch "\${appdir}/resources/logs/ECAgent.log" "\${appdir}/resources/logs/ECAgent.bootstrap.log" 2>/dev/null || true
chmod -R a+rwX "\${appdir}/resources/logs" "\${appdir}/resourceslogs" "\${appdir}/logs" 2>/dev/null || true

# Link SUID wrappers for VPN services
for svc in ECAgent svpnservice CSClient; do
    if [ -x "${WRAPPERS_DIR}/\${svc}" ]; then
        ln -sfn "${WRAPPERS_DIR}/\${svc}" "\${bindir}/\${svc}"
    else
        ln -sfn "${res_dir}/bin/\${svc}" "\${bindir}/\${svc}"
    fi
done

ln -sfn "${res_dir}/bin/EasyMonitor" "\${bindir}/EasyMonitor" 2>/dev/null || true
ln -sfn "${res_dir}/bin/ca.crt" "\${bindir}/ca.crt" 2>/dev/null || true
ln -sfn "${res_dir}/bin/cert.crt" "\${bindir}/cert.crt" 2>/dev/null || true

# Runtime app dir symlinks
find "\${runtime_appdir}" -mindepth 1 -maxdepth 1 ! -name resources -exec rm -rf {} +
for src in "\${appdir}"/*; do
    name="\$(basename "\${src}")"
    [ "\${name}" = "resources" ] && continue
    ln -sfn "\${src}" "\${runtime_appdir}/\${name}"
done
rm -rf "\${runtime_appdir}/resources"
mkdir -p "\${runtime_appdir}/resources"
for src in "\${appdir}/resources"/*; do
    ln -sfn "\${src}" "\${runtime_appdir}/resources/\$(basename "\${src}")"
done

chmod -R a+rwX "\${appdir}/resources/logs" "\${appdir}/resourceslogs" "\${appdir}/logs" 2>/dev/null || true

# Start ECAgent if needed
if ! ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:54530'; then
    "\${bindir}/ECAgent" --resume >> "\${appdir}/resources/logs/ECAgent.bootstrap.log" 2>&1 &
    for _ in 1 2 3 4 5; do
        ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:54530' && break
        sleep 0.2
    done
fi

cd "\${appdir}"
exec /usr/bin/env bash "\${appdir}/resources/shell/EasyConnect.sh" "\$@"
SCRIPT
    chmod +x "${BIN_DIR}/easyconnect"
    log "Created ${BIN_DIR}/easyconnect"
}

load_kernel_modules() {
    log "Loading kernel modules..."
    for mod in tun ip_tables iptable_nat iptable_filter; do
        if lsmod 2>/dev/null | grep -q "^${mod} "; then
            log "  ${mod} already loaded"
        else
            modprobe "$mod" 2>/dev/null || warn "Could not load ${mod} (may need kernel config)"
        fi
    done
}

create_desktop_entry() {
    log "Creating desktop entry..."
    mkdir -p /usr/local/share/applications
    cat > /usr/local/share/applications/easyconnect.desktop <<EOF
[Desktop Entry]
Name=EasyConnect
Comment=Sangfor EasyConnect VPN Client
Exec=${BIN_DIR}/easyconnect
Icon=${INSTALL_DIR}/share/sangfor/EasyConnect/resources/assets/EasyConnect.png
Terminal=false
Type=Application
Categories=Network;
EOF
    log "Created desktop entry"
}

do_install() {
    echo ""
    echo "  EasyConnect Cross-Distro Installer"
    echo "  ==================================="
    echo ""

    check_deps
    require_root
    build_package

    log "Installing to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    cp -r "${NIX_BUILD_RESULT}/." "${INSTALL_DIR}/"
    chmod -R a+rX "${INSTALL_DIR}"

    compile_suid_wrappers
    create_entrypoint
    load_kernel_modules
    create_desktop_entry

    echo ""
    log "Installation complete!"
    echo ""
    echo "  Run:   easyconnect"
    echo "  Or:    launch 'EasyConnect' from your app menu"
    echo ""
}

do_uninstall() {
    require_root
    log "Removing EasyConnect..."
    rm -rf "${INSTALL_DIR}"
    rm -f "${BIN_DIR}/easyconnect"
    rm -f /usr/local/share/applications/easyconnect.desktop
    log "Uninstall complete"
}

case "${1:-}" in
    install)  do_install ;;
    uninstall) do_uninstall ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        echo ""
        echo "  install    Build and install EasyConnect"
        echo "  uninstall  Remove EasyConnect"
        exit 1
        ;;
esac
