# EasyConnect for Nix

[深信服 EasyConnect](https://www.sangfor.com.cn/) VPN 客户端 Nix flake，支持 x86_64-linux。任何安装了 Nix 的 Linux 发行版均可使用。

## 使用方式

### NixOS

在系统 flake 中引入（`/etc/nixos/flake.nix`）：

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

启用模块并重建：

```nix
programs.easyconnect.enable = true;
```

```bash
sudo nixos-rebuild switch --flake /etc/nixos#your-host
sudo reboot
```

完成。SUID wrappers、内核模块、iptables 全部自动配置。

### 其他 Linux 发行版

```bash
# 1. 安装
nix profile install github:x12w/SCUT_easyconnect_nix#easyconnect

# 2. 一次性 root 配置（编译 SUID wrapper + 加载内核模块）
nix run github:x12w/SCUT_easyconnect_nix#setup

# 3. 添加 PATH（写入 ~/.bashrc 或 ~/.zshrc）
export PATH="$HOME/.local/share/easyconnect/wrappers:$PATH"

# 4. 启动
easyconnect
```

`#setup` 只需执行一次。所有构建由 Nix 控制，版本与 flake 同步。

### 不安装直接运行

```bash
nix run github:x12w/SCUT_easyconnect_nix
```

## 模块配置详情

| 功能 | NixOS（`programs.easyconnect`） | 其他发行版（`nix run ...#setup`） |
|------|-------------------------------|-----------------------------------|
| 内核模块 | `boot.kernelModules` | `sudo modprobe` |
| VPN 服务 SUID | `security.wrappers` | — |
| iptables SUID | 自定义 wrapper via `security.wrappers` | 编译安装 SUID wrapper |
| ip/ifconfig/route SUID | `security.wrappers` | — |
| Shell/asar 路径修复 | 构建时 patch | 内置于包 |
| 桌面入口 | 无需 | 手动 |

## 项目结构

```
├── flake.nix                # 包构建 + NixOS 模块 + setup app
├── flake.lock
├── wrappers/
│   └── suid-wrapper.c       # 通用 SUID wrapper (setuid(0) + exec)
├── EasyConnect_x64_7_6_7_3.deb
├── legacy-libs/             # 84 个预编译 .so（ABI 兼容）
├── conf/                    # 默认配置
├── deb_control/             # 原始 DEB 控制文件（参考）
├── README.md                # 本文件（中文）
└── README_EN.md             # English version
```

## 常见问题

### VPN 连接后 1-2 分钟断开

`ip_tables` 内核模块未加载：

```bash
lsmod | grep ip_tables
sudo modprobe ip_tables iptable_nat iptable_filter
```

### iptables 报 "Permission denied"

```bash
# NixOS：检查 wrapper 是否有 SUID 位
ls -la /run/wrappers/bin/iptables-legacy  # 应显示 r-s--s--x
/run/wrappers/bin/iptables-legacy -t nat -L OUTPUT

# 其他发行版：检查自定义 wrapper
ls -la ~/.local/share/easyconnect/wrappers/iptables-legacy  # 应显示 rws
```

### 点击资源卡片浏览器不打开

```bash
xdg-open http://example.com  # 测试 URL 打开是否正常
```

### 登录 VPN 后无法访问外网

预期行为 — EasyConnect 使用分离隧道模式，仅 VPN 资源走 tun0 隧道。如需全隧道模式请在服务端配置。

## 依赖

- **Nix** 并[启用 flakes](https://nixos.wiki/wiki/Flakes)
- **x86_64-linux**（EasyConnect 仅支持 x86_64）
- **内核模块**：`tun`、`ip_tables`、`iptable_nat`、`iptable_filter`
- **显示服务**：X11 或 Wayland
- **桌面环境**：KDE、GNOME 或任何支持 `xdg-open` 的桌面

## License

打包代码：MIT。EasyConnect 软件本身为深信服 proprietary 软件，见 `deb_control/readme`。
