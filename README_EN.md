# EasyConnect for Nix

[Sangfor EasyConnect](https://www.sangfor.com.cn/) VPN client packaged as a Nix flake for x86_64-linux. Works on any Linux distribution with Nix installed.

## Usage

### Local Build (recommended: avoids network issues)

If GitHub access is unstable or downloads are slow, clone the repo and build locally:

```bash
# Option A: git clone
git clone https://github.com/x12w/SCUT_easyconnect_nix.git
cd SCUT_easyconnect_nix

# Option B: download zip (no git needed)
curl -L -O https://github.com/x12w/SCUT_easyconnect_nix/archive/refs/heads/main.zip
unzip main.zip && cd SCUT_easyconnect_nix-main
```

Then choose your system:

```bash
# NixOS — reference the local path in your system flake:
# inputs.easyconnect.url = "path:/path/to/SCUT_easyconnect_nix"

# Other distros — build and install from local source:
nix profile add .#easyconnect
nix run .#setup
```

To update: `git pull` in the repo (or re-download the zip), then re-run the commands above.

### NixOS

Add to `/etc/nixos/flake.nix`:

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

Enable and rebuild:

```nix
programs.easyconnect.enable = true;
```

```bash
sudo nixos-rebuild switch --flake /etc/nixos#your-host
sudo reboot
```

Done. SUID wrappers, kernel modules, iptables — all configured automatically.

### Other Linux Distributions

```bash
# 0. Enable Nix flakes (one-time only)
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf

# 1. Install
nix profile add github:x12w/SCUT_easyconnect_nix#easyconnect

# 2. One-time root setup (compile SUID wrappers + load kernel modules)
nix run github:x12w/SCUT_easyconnect_nix#setup

# 3. Add to PATH (in ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/share/easyconnect/wrappers:$PATH"

# 4. Launch
easyconnect
```

`#setup` only needed once. All builds are Nix-controlled, version synced with the flake.

### Run without installing

```bash
nix run github:x12w/SCUT_easyconnect_nix
```

## What the Module Configures

| Feature | NixOS (`programs.easyconnect`) | Other distros (`nix run ...#setup`) |
|---------|-------------------------------|-------------------------------------|
| Kernel modules | `boot.kernelModules` | `sudo modprobe` |
| SUID for VPN services | `security.wrappers` | — |
| SUID for iptables | Custom wrapper via `security.wrappers` | Compiled SUID wrapper |
| SUID for ip/ifconfig/route | `security.wrappers` | — |
| Shell/asar path patches | Build-time patching | Built into package |
| Desktop entry | N/A | Manual |

## Project Structure

```
├── flake.nix                # Package derivation + NixOS module + setup app
├── flake.lock
├── wrappers/
│   └── suid-wrapper.c       # Generic SUID wrapper (setgid(0) + setuid(0) + exec)
├── EasyConnect_x64_7_6_7_3.deb
├── legacy-libs/             # 84 precompiled .so for ABI compat
├── conf/                    # Default configuration
├── deb_control/             # Original DEB control files (reference)
├── README.md                # Chinese readme (default)
└── README_EN.md             # This file (English)
```

## Requirements

- **Nix** with [flakes enabled](https://nixos.wiki/wiki/Flakes)
- **x86_64-linux** (EasyConnect is x86_64 only)
- **Kernel modules**: `tun`, `ip_tables`, `iptable_nat`, `iptable_filter`
- **Display server**: X11 or Wayland
- **Desktop environment**: KDE, GNOME, or any with `xdg-open`

## Troubleshooting

### VPN connects but drops after 1-2 minutes

`ip_tables` module not loaded:

```bash
lsmod | grep ip_tables
sudo modprobe ip_tables iptable_nat iptable_filter
```

### "Permission denied" in iptables

```bash
# NixOS
ls -la /run/wrappers/bin/iptables-legacy  # shows r-s--s--x ?
/run/wrappers/bin/iptables-legacy -t nat -L OUTPUT

# Other distros
ls -la ~/.local/share/easyconnect/wrappers/iptables-legacy  # shows rws ?
```

### Browser doesn't open resource URLs

```bash
xdg-open http://example.com  # test URL opening
```

### Internet blocked after VPN login

Expected behavior — split-tunnel routing. Only VPN resources go through tun0.

## License

Packaging code: MIT. EasyConnect software: proprietary, Sangfor Technologies.
