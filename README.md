# EasyConnect for Nix / NixOS

[Sangfor EasyConnect](https://www.sangfor.com.cn/) VPN client, packaged as a Nix flake.

**One command, any Linux distro.** Works on NixOS, Ubuntu, Debian, Arch, Fedora — anywhere Nix is installed.

## Quick Start

### Any Linux Distribution (with Nix)

```bash
curl -L -O https://raw.githubusercontent.com/x12w/SCUT_easyconnect_nix/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh install
```

Then launch:

```bash
easyconnect
```

Uninstall:

```bash
sudo ./setup.sh uninstall
```

### NixOS (with flakes enabled)

Add to your system flake (`/etc/nixos/flake.nix`):

```nix
{
  inputs.easyconnect.url = "github:x12w/SCUT_easyconnect_nix/main";

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

Enable in configuration:

```nix
programs.easyconnect.enable = true;
```

Rebuild (reboot recommended):

```bash
sudo nixos-rebuild switch --flake /etc/nixos#your-host
sudo reboot
```

## What It Does

The installer / NixOS module handles everything needed to make EasyConnect work:

| Task | NixOS (`nixosModules`) | Other distros (`setup.sh`) |
|------|------------------------|----------------------------|
| Package build | `nix build` | `nix build` |
| Kernel modules (`tun`, `ip_tables`, ...) | `boot.kernelModules` | `modprobe` |
| SUID for VPN services | `security.wrappers` | Compiled SUID wrappers |
| SUID for iptables (with `setuid(0)`) | Custom compiled wrapper | Custom compiled wrapper |
| Shell/asar path fixes | Post-install patching | Bundled in package |
| Desktop entry | N/A | `/usr/local/share/applications/` |
| PATH entry point | Nix store link | `/usr/local/bin/easyconnect` |

## Requirements

- **Nix** ([install](https://nixos.org/download)) with flakes enabled
- **x86_64-linux** — EasyConnect is x86_64 only
- **Kernel modules**: `tun`, `ip_tables`, `iptable_nat`, `iptable_filter`
- **Display server**: X11 or Wayland (for GUI)
- **Desktop environment**: KDE, GNOME, or any with `xdg-open`

### Enable Nix Flakes

If you haven't enabled flakes yet, add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

## Project Structure

```
├── flake.nix                # Package derivation + NixOS module
├── flake.lock               # Pinned nixpkgs
├── setup.sh                 # Cross-distro one-command installer
├── wrappers/
│   └── suid-wrapper.c       # Generic SUID wrapper (setuid(0) + exec)
├── iptables-wrapper.c       # Legacy standalone wrapper (used by NixOS module)
├── EasyConnect_x64_7_6_7_3.deb  # Upstream Debian package (60MB)
├── legacy-libs/             # 84 precompiled .so files for ABI compat
├── conf/                    # Default configuration
├── deb_control/             # Original DEB control files (reference)
└── README.md
```

## How the SUID Wrapper Works

EasyConnect's VPN services (ECAgent, svpnservice, CSClient) need root to:
- Create TUN network devices
- Modify routing tables
- Manipulate iptables NAT rules

`iptables` in particular checks `getuid() != 0` and refuses to run via plain SUID
(where `geteuid() = 0` but `getuid() = 1000`). Our wrapper calls `setuid(0)` first,
setting both real and effective UID to root, bypassing the check.

The wrapper is also used for `ip`, `ifconfig`, and `route` for compatibility.

## Troubleshooting

### "Permission denied" when accessing NAT table

```bash
# NixOS: verify wrappers are SUID
ls -la /run/wrappers/bin/iptables-legacy   # should show r-s--s--x

# Test
/run/wrappers/bin/iptables-legacy -t nat -L OUTPUT
```

### VPN connects but drops after 1-2 minutes

Kernel module `ip_tables` not loaded:

```bash
lsmod | grep ip_tables
sudo modprobe ip_tables iptable_nat iptable_filter
```

### Browser doesn't open when clicking resource URLs

Ensure `xdg-open` works:

```bash
xdg-open http://example.com
```

### Internet inaccessible after VPN login

This is expected — EasyConnect uses split-tunnel routing. Only VPN resources
are routed through the tunnel (tun0). If you need full-tunnel mode,
configure it server-side.

## License

This packaging code is MIT. The EasyConnect software itself is proprietary,
owned by Sangfor Technologies. See `deb_control/readme` for upstream info.
