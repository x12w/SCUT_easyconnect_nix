{
  description = "EasyConnect for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      lib = pkgs.lib;

      runtimeDeps = with pkgs; [
        coreutils
        findutils
        gawk
        gnugrep
        gnused
        iproute2
        iptables
        lsb-release
        nettools
        procps
        systemd
        which
        xdg-utils
      ];

      easyConnectLibs = with pkgs; [
        alsa-lib
        atk
        cairo
        cups
        dbus
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk2
        libX11
        libXScrnSaver
        libXcomposite
        libXcursor
        libXdamage
        libXext
        libXfixes
        libXi
        libXinerama
        libXrandr
        libXrender
        libXtst
        libdrm
        libxcb
        nspr
        nss
        pango
        stdenv.cc.cc
        systemd
      ];

      runtimeBinPath = lib.makeBinPath runtimeDeps;

      easyconnect = pkgs.stdenv.mkDerivation rec {
        pname = "easyconnect";
        version = "7.6.7.7";

        src = ./EasyConnect_x64_7_6_7_3.deb;

        nativeBuildInputs = with pkgs; [
          binutils
          dpkg
          file
          gnutar
          makeWrapper
          nodePackages.asar
          patchelf
          perl
        ];

        dontConfigure = true;
        dontBuild = true;
        dontStrip = true;

        unpackPhase = ''
          runHook preUnpack

          ar x "$src"
          tar -xzf data.tar.gz

          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out"
          cp -r usr/* "$out/"

          mkdir -p "$out/opt/easyconnect/legacy-libs"
          cp -r ${./legacy-libs}/. "$out/opt/easyconnect/legacy-libs/"

          mkdir -p "$out/opt/easyconnect/defaults"
          cp -r ${./conf}/. "$out/opt/easyconnect/defaults/"

          chmod +x "$out/share/sangfor/EasyConnect/EasyConnect"
          chmod +x "$out/share/sangfor/EasyConnect/resources/bin/"*
          chmod +x "$out/share/sangfor/EasyConnect/resources/shell/"*.sh

          sed -i 's|^Exec=.*|Exec=easyconnect|' \
            "$out/share/applications/EasyConnect.desktop"

          runHook postInstall
        '';

        postFixup =
          let
            appDir = "$out/share/sangfor/EasyConnect";
            resourceDir = "${appDir}/resources";
            bundledLibPath =
              lib.concatStringsSep ":" [
                appDir
                "${resourceDir}/lib64"
                "$out/opt/easyconnect/legacy-libs"
                (lib.makeLibraryPath easyConnectLibs)
              ];
          in
          ''
            ln -sf ${pkgs.systemd}/lib/libudev.so.1 \
              "$out/opt/easyconnect/legacy-libs/libudev.so.0"

            asarWorkDir="$(mktemp -d)"
            asar extract "${resourceDir}/app.asar" "$asarWorkDir/app"
            substituteInPlace "$asarWorkDir/app/src/main.js" \
              --replace-quiet 'const App=require("electron").app;const Util=require("util");const OS=require("os");' \
                'const App=require("electron").app;const Util=require("util");const OS=require("os");const FS=require("fs");' \
              --replace-quiet 'if(process.resourcesPath.startsWith("/Applications")||process.resourcesPath.startsWith("/usr/share/sangfor")){global.gDevelopMode=false;global.gWorkPath=process.resourcesPath;global.gAppPath=process.resourcesPath+"/app.asar"}' \
                'if(FS.existsSync(process.resourcesPath+"/app.asar")||process.resourcesPath.startsWith("/Applications")||process.resourcesPath.startsWith("/usr/share/sangfor")){global.gDevelopMode=false;global.gWorkPath=process.cwd();global.gAppPath=process.resourcesPath+"/app.asar"}'

            # Fix OPEN_BROWSER_SHELL: __dirname resolves inside asar, but open_browser.sh
            # is outside at resources/script/. Use process.resourcesPath instead.
            substituteInPlace "$asarWorkDir/app/src/service/util/common.js" \
              --replace-quiet 'Path.join(__dirname,"../script/open_browser.sh")' \
                'Path.join(process.resourcesPath,"script/open_browser.sh")'

            rm -f "${resourceDir}/app.asar"
            asar pack "$asarWorkDir/app" "${resourceDir}/app.asar"
            rm -rf "$asarWorkDir"

            for script in "$out"/share/sangfor/EasyConnect/resources/shell/*.sh; do
              substituteInPlace "$script" \
                --replace-quiet 'PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/X11/bin:$PATH' 'PATH=/run/wrappers/bin:${runtimeBinPath}:$PATH' \
                --replace-quiet 'PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$PATH' 'PATH=/run/wrappers/bin:${runtimeBinPath}:$PATH' \
                --replace-quiet '/usr/bin/lsb_release' '${pkgs.lsb-release}/bin/lsb_release'
            done

            substituteInPlace "$out/share/sangfor/EasyConnect/resources/shell/EasyConnect.sh" \
              --replace-quiet 'cd `dirname $0`' \
                ':' \
              --replace-quiet 'ECHOME=/usr/share/sangfor/EasyConnect' \
                'ECHOME="''${EASYCONNECT_HOME:-$(cd "$(dirname "$0")/../.." && pwd)}"' \
              --replace-quiet '$EASYCONNECT  $params --enable-transparent-visuals --disable-gpu &' \
                '$EASYCONNECT $params &'

            substituteInPlace "$out/share/sangfor/EasyConnect/resources/shell/sslservice.sh" \
              --replace-quiet 'ECHOME=/usr/share/sangfor/EasyConnect/resources/' \
                'ECHOME="''${EASYCONNECT_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"/resources' \
              --replace-quiet '/bin/bash $ECHOME/shell/envcheck.sh none' \
                '${pkgs.bash}/bin/bash $ECHOME/shell/envcheck.sh none'

            substituteInPlace "$out/share/sangfor/EasyConnect/resources/shell/EasyMonitor.sh" \
              --replace-quiet 'ECHOME="/usr/share/sangfor/EasyConnect/resources"' \
                'ECHOME="''${EASYCONNECT_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"/resources'

            substituteInPlace "$out/share/sangfor/EasyConnect/resources/Web/jssdk/business/connect.js" \
              --replace-quiet 'if(!SFConfig.isExistEC||!is.Win())return s.debug(u,"EC not need check update in login page "),r=SFConfig.IS_UPDATE.NEED_UPDATE,void n();' \
                'if(!SFConfig.isExistEC||!is.Win())return s.debug(u,"EC not need check update in login page "),r=SFConfig.IS_UPDATE.NOT_UPDATE,void n();'

            # EasyConnect expects open_browser.sh at resources/script/ but it's at resources/shell/
            # Create a symlink so FS.existsSync(OPEN_BROWSER_SHELL) succeeds
            mkdir -p "$out/share/sangfor/EasyConnect/resources/script"
            ln -sf ../shell/open_browser.sh "$out/share/sangfor/EasyConnect/resources/script/open_browser.sh"
            ln -sf ../shell/find_browser_path.sh "$out/share/sangfor/EasyConnect/resources/script/find_browser_path.sh"

            while IFS= read -r -d "" elf; do
              if file -N -b "$elf" | grep -q '^ELF'; then
                perl -0pi -e 's#/usr/share/sangfor/EasyConnect#/tmp/sangfor/EasyConnectNixOSX#g' "$elf"
                patchelf --set-rpath "${bundledLibPath}" "$elf" || true
                if patchelf --print-interpreter "$elf" >/dev/null 2>&1; then
                  patchelf --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" "$elf" || true
                fi
              fi
            done < <(find "$out/share/sangfor/EasyConnect" "$out/opt/easyconnect/legacy-libs" -type f -print0)

            mkdir -p "$out/bin"
            cat > "$out/bin/easyconnect" <<EOF
#!${pkgs.runtimeShell}
export LD_LIBRARY_PATH="${bundledLibPath}:''${LD_LIBRARY_PATH:-}"
export PATH="/run/wrappers/bin:${runtimeBinPath}:\$PATH"
export QT_X11_NO_MITSHM=1
export XDG_DATA_DIRS="${lib.makeSearchPath "share" [ pkgs.glib pkgs.gtk2 pkgs.hicolor-icon-theme ]}:''${XDG_DATA_DIRS:-}"

set -e

appdir="\$HOME/.easyconnect"
bindir="\$appdir/resources/bin"
mkdir -p "\$appdir" "\$appdir/resources" "\$bindir" "\$appdir/logs"
mkdir -p /tmp/sangfor

unset ELECTRON_RUN_AS_NODE
export EASYCONNECT_HOME="\$appdir"
runtime_appdir="/tmp/sangfor/EasyConnectNixOSX"
if [ -e "\$runtime_appdir" ] && [ ! -d "\$runtime_appdir" ]; then
  rm -f "\$runtime_appdir"
fi
mkdir -p "\$runtime_appdir"

for src in ${appDir}/*; do
  name="\$(basename "\$src")"
  if [ "\$name" != "resources" ]; then
    ln -sfn "\$src" "\$appdir/\$name"
  fi
done

find "\$appdir/resources" -mindepth 1 -maxdepth 1 \
  ! -name bin ! -name conf ! -name logs ! -name user_cert -exec rm -rf {} +

for src in ${resourceDir}/*; do
  name="\$(basename "\$src")"
  case "\$name" in
    bin|conf|logs|user_cert)
      ;;
    *)
      ln -sfn "\$src" "\$appdir/resources/\$name"
      ;;
  esac
done

rm -rf "\$appdir/resources/conf" "\$appdir/resources/logs" "\$appdir/resources/user_cert" "\$appdir/resources/bin"
mkdir -p "\$appdir/resources/conf" "\$appdir/resources/logs" "\$appdir/resources/user_cert" "\$appdir/resources/bin"
cp -n ${resourceDir}/conf/* "\$appdir/resources/conf/" 2>/dev/null || true
cp -n $out/opt/easyconnect/defaults/* "\$appdir/" 2>/dev/null || true
mkdir -p "\$appdir/resourceslogs" "\$appdir/logs"
touch "\$appdir/resources/logs/ECAgent.log" "\$appdir/resources/logs/ECAgent.bootstrap.log" 2>/dev/null || true
chmod -R a+rwX "\$appdir/resources/logs" "\$appdir/resourceslogs" "\$appdir/logs" 2>/dev/null || true

if [ -x /run/wrappers/bin/easyconnect-ecagent ]; then
  ln -sfn /run/wrappers/bin/easyconnect-ecagent "\$bindir/ECAgent"
else
  ln -sfn ${resourceDir}/bin/ECAgent "\$bindir/ECAgent"
fi

if [ -x /run/wrappers/bin/easyconnect-svpnservice ]; then
  ln -sfn /run/wrappers/bin/easyconnect-svpnservice "\$bindir/svpnservice"
else
  ln -sfn ${resourceDir}/bin/svpnservice "\$bindir/svpnservice"
fi

if [ -x /run/wrappers/bin/easyconnect-csclient ]; then
  ln -sfn /run/wrappers/bin/easyconnect-csclient "\$bindir/CSClient"
else
  ln -sfn ${resourceDir}/bin/CSClient "\$bindir/CSClient"
fi

if [ ! -x /run/wrappers/bin/easyconnect-ecagent ] || [ ! -x /run/wrappers/bin/easyconnect-svpnservice ] || [ ! -x /run/wrappers/bin/easyconnect-csclient ]; then
  echo "warning: EasyConnect helper wrappers are not installed; VPN TCP/L3 services may fail." >&2
  echo "warning: enable the flake NixOS module with programs.easyconnect.enable = true." >&2
fi

ln -sfn ${resourceDir}/bin/EasyMonitor "\$bindir/EasyMonitor"
ln -sfn ${resourceDir}/bin/ca.crt "\$bindir/ca.crt"
ln -sfn ${resourceDir}/bin/cert.crt "\$bindir/cert.crt"

find "\$runtime_appdir" -mindepth 1 -maxdepth 1 \
  ! -name resources -exec rm -rf {} +

for src in "\$appdir"/*; do
  name="\$(basename "\$src")"
  if [ "\$name" != "resources" ]; then
    ln -sfn "\$src" "\$runtime_appdir/\$name"
  fi
done

rm -rf "\$runtime_appdir/resources"
mkdir -p "\$runtime_appdir/resources"
for src in "\$appdir/resources"/*; do
  ln -sfn "\$src" "\$runtime_appdir/resources/\$(basename "\$src")"
done

chmod -R a+rwX "\$appdir/resources/logs" "\$appdir/resourceslogs" "\$appdir/logs" 2>/dev/null || true

if ! ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:54530'; then
  "\$bindir/ECAgent" --resume >> "\$appdir/resources/logs/ECAgent.bootstrap.log" 2>&1 &
  for _ in 1 2 3 4 5; do
    ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:54530' && break
    sleep 0.2
  done
fi

cd "\$appdir"
exec ${pkgs.bash}/bin/bash "\$appdir/resources/shell/EasyConnect.sh" "\$@"
EOF
            chmod +x "$out/bin/easyconnect"

            ln -s easyconnect "$out/bin/EasyConnect"
          '';

        meta = with lib; {
          description = "Sangfor EasyConnect packaged for NixOS";
          homepage = "https://www.sangfor.com.cn/";
          sourceProvenance = [ sourceTypes.binaryNativeCode ];
          license = licenses.unfree;
          platforms = [ "x86_64-linux" ];
          mainProgram = "easyconnect";
        };
      };
    in
    {
      packages.${system} = {
        inherit easyconnect;
        default = easyconnect;
      };

      apps.${system}.default = {
        type = "app";
        program = "${easyconnect}/bin/easyconnect";
      };

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.easyconnect;
          pkg = self.packages.${pkgs.system}.easyconnect;
          helperBin = "${pkg}/share/sangfor/EasyConnect/resources/bin";

          # Compile a custom SUID wrapper for an iptables variant.
          # The NixOS SUID wrapper grants euid=0 but iptables refuses to run
          # when getuid() != geteuid(). Our wrapper calls setuid(0) first.
          mkIptablesWrapper = name: realBin: pkgs.runCommandCC "iptables-suid-${name}" {} ''
            mkdir -p "$out/bin"
            gcc ${./iptables-wrapper.c} \
              -DREAL_IPTABLES='"${realBin}"' \
              -o "$out/bin/${name}"
          '';
        in
        {
          options.programs.easyconnect.enable =
            lib.mkEnableOption "Sangfor EasyConnect";

          config = lib.mkIf cfg.enable {
            boot.kernelModules = [
              "tun"
              "ip_tables"
              "iptable_nat"
              "iptable_filter"
            ];

            environment.systemPackages = [ pkg ];

            security.wrappers = {
              easyconnect-ecagent = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${helperBin}/ECAgent";
              };

              easyconnect-svpnservice = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${helperBin}/svpnservice";
              };

              easyconnect-csclient = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${helperBin}/CSClient";
              };

              ip = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${pkgs.iproute2}/bin/ip";
              };

              ifconfig = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${pkgs.nettools}/bin/ifconfig";
              };

              route = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${pkgs.nettools}/bin/route";
              };

              iptables = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${mkIptablesWrapper "iptables" "${pkgs.iptables}/bin/iptables-legacy"}/bin/iptables";
              };

              iptables-save = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${mkIptablesWrapper "iptables-save" "${pkgs.iptables}/bin/iptables-legacy-save"}/bin/iptables-save";
              };

              iptables-restore = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${mkIptablesWrapper "iptables-restore" "${pkgs.iptables}/bin/iptables-legacy-restore"}/bin/iptables-restore";
              };

              iptables-legacy = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${mkIptablesWrapper "iptables-legacy" "${pkgs.iptables}/bin/iptables-legacy"}/bin/iptables-legacy";
              };

              iptables-legacy-save = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${mkIptablesWrapper "iptables-legacy-save" "${pkgs.iptables}/bin/iptables-legacy-save"}/bin/iptables-legacy-save";
              };

              iptables-legacy-restore = {
                owner = "root";
                group = "root";
                setuid = true;
                setgid = true;
                source = "${mkIptablesWrapper "iptables-legacy-restore" "${pkgs.iptables}/bin/iptables-legacy-restore"}/bin/iptables-legacy-restore";
              };
            };
          };
        };
    };
}
