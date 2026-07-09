# EasyConnect for NixOS

[Sangfor EasyConnect](https://www.sangfor.com.cn/) VPN client packaged as a Nix flake for NixOS (x86_64-linux).

## Overview

This flake packages the official EasyConnect 7.6.7.3 Debian package into a Nix derivation, providing a NixOS module that handles:

- SUID wrappers for VPN services (ECAgent, svpnservice, CSClient)
- Custom iptables SUID wrapper (works around `getuid() != geteuid()` rejection)
- Kernel module loading (`tun`, `ip_tables`, `iptable_nat`, `iptable_filter`)
- ASAR patching for NixOS path compatibility
- Legacy library bundling for ABI compatibility
- Browser URL opening fix (KDE/NixOS compatible)

## Quick Start

### 1. Add the flake input

In your system flake (`/etc/nixos/flake.nix`):

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    easyconnect.url = "github:your-username/easyconnect-nix";
  };

  outputs = { nixpkgs, easyconnect, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      modules = [
        easyconnect.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Enable the module

In your NixOS configuration:

```nix
programs.easyconnect.enable = true;
```

### 3. Rebuild and reboot

```bash
sudo nixos-rebuild switch --flake /etc/nixos#your-host
sudo reboot
```

The reboot is required to load the `ip_tables` kernel modules.

### 4. Launch

```bash
easyconnect
```

## What the Module Does

### Kernel Modules
Loads at boot:
- `tun` — TUN/TAP virtual network device
- `ip_tables`, `iptable_nat`, `iptable_filter` — legacy iptables NAT support (required even on nftables-based NixOS)

### SUID Wrappers (`/run/wrappers/bin/`)
| Wrapper | Purpose |
|---------|---------|
| `easyconnect-ecagent` | Agent service (localhost:54530) |
| `easyconnect-svpnservice` | VPN tunnel (TUN device, routes, iptables) |
| `easyconnect-csclient` | Client service manager |
| `ip` | Network interface management |
| `ifconfig` | Legacy network config |
| `route` | Legacy routing table |
| `iptables*` (6 wrappers) | Custom wrapper with `setuid(0)` for NAT table access |

### ASAR Patches
- **Work path**: Uses `process.cwd()` instead of `process.resourcesPath`
- **Browser opening**: Fixes `OPEN_BROWSER_SHELL` to use `process.resourcesPath` (outside asar) so `open_browser.sh` can be found
- **Update check**: Disabled (not applicable on NixOS)

### Shell Script Patches
- PATH updated to include `/run/wrappers/bin` and Nix store binaries
- `lsb_release` redirected to NixOS-compatible version
- Hardcoded `/usr/share/sangfor` paths replaced with `/tmp/sangfor/EasyConnectNixOSX`

## Requirements

- NixOS (x86_64-linux)
- Linux kernel with `ip_tables` module available
- X11 or Wayland display server (for GUI)
- KDE or GNOME desktop (for `xdg-open` URL handling)

## Files

```
├── flake.nix              # Package derivation + NixOS module
├── flake.lock             # Pinned nixpkgs revision
├── iptables-wrapper.c     # Custom SUID iptables wrapper source
├── EasyConnect_x64_7_6_7_3.deb  # Upstream Debian package
├── legacy-libs/           # 84 precompiled .so files for ABI compat
├── conf/                  # Default configuration files
├── deb_control/           # Original DEB control files (reference)
└── README.md
```

## Troubleshooting

### VPN connects but drops after 1-2 minutes
Check `dmesg | grep ip_tables`. If modules aren't loaded, reboot is required after first install.

### "Permission denied" in DNS.log / TCP.log
Verify iptables SUID wrappers exist:
```bash
ls -la /run/wrappers/bin/iptables-legacy  # Should show r-s--s--x
```
And can access the nat table:
```bash
/run/wrappers/bin/iptables-legacy -t nat -L OUTPUT
```

### Browser doesn't open when clicking resource URLs
Ensure your desktop environment has `xdg-open` properly configured:
```bash
xdg-open http://example.com
```

### Internet inaccessible after VPN login
This is expected — EasyConnect sets up split-tunnel routing. Only VPN resources are routed through the tunnel (tun0). If you need full-tunnel mode, configure it in the EasyConnect server settings.

## License

This packaging code is provided as-is. The EasyConnect software itself is proprietary, owned by Sangfor Technologies. See `deb_control/readme` for upstream license information.
