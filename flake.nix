{
  description = "redroid over Mesa Venus for NVIDIA GPUs (nvidia-open)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      vendor = self + "/vendor";

      cpuinfo = builtins.tryEval (builtins.readFile /proc/cpuinfo);
      is9950X = cpuinfo.success && lib.hasInfix "9950X" cpuinfo.value;
      tuneFlags = if is9950X then "-O3 -march=znver5 -mtune=znver5" else "-O3 -march=native";

      virglrenderer-nvidia = pkgs.stdenv.mkDerivation {
        pname = "virglrenderer-nvidia";
        version = "0.1.1";
        src = builtins.fetchGit {
          url = "https://gitlab.freedesktop.org/virgl/virglrenderer.git";
          rev = "dc35e4db03144f81637c5ad061f61d3334b078fe";
        };
        patches = map (f: vendor + "/patches/virglrenderer/" + f) [
          "0001-vtest-support-exporting-sync_file-fds-for-venus-sync.patch"
          "0002-vtest-support-importing-dmabufs-as-blob-resources-fo.patch"
          "0003-vtest-raise-listen-backlog-to-128.patch"
          "0004-wip-gpu-alloc-and-global-priority.patch"
        ];
        postPatch = ''
          cp ${vendor}/src/virglrenderer-vtest/vtest_gpu_alloc.c vtest/
          cp ${vendor}/src/virglrenderer-vtest/vtest_gpu_alloc.h vtest/
        '';
        nativeBuildInputs = with pkgs; [ meson ninja pkg-config python3 python3Packages.pyyaml ];
        buildInputs = with pkgs; [ libepoxy libdrm libgbm libX11 expat vulkan-headers vulkan-loader wayland ];
        mesonFlags = [ "-Dvenus=true" "-Drender-server-worker=auto" "-Db_lto=true" ];
        env.NIX_CFLAGS_COMPILE = tuneFlags;
        postInstall = ''
          mkdir -p $out/lib/redroid-over-venus
          mv $out/bin/virgl_test_server $out/lib/redroid-over-venus/
          mv $out/libexec/virgl_render_server $out/lib/redroid-over-venus/ 2>/dev/null || \
            mv $out/bin/virgl_render_server $out/lib/redroid-over-venus/
          cp -L $out/lib/libvirglrenderer.so.1 $out/lib/redroid-over-venus/
          rm -rf $out/bin $out/libexec
        '';
      };

      guest-nvidia = pkgs.stdenv.mkDerivation {
        pname = "guest-nvidia";
        version = "0.1.2";
        src = vendor + "/guest/guest.tar.zst";
        dontUnpack = true;
        nativeBuildInputs = [ pkgs.zstd ];
        installPhase = ''
          mkdir -p $out/lib/redroid-over-venus/guest
          tar --zstd -xf "$src" -C $out/lib/redroid-over-venus/guest --strip-components=1
        '';
      };

      guest-prebuilts = pkgs.stdenv.mkDerivation {
        pname = "guest-prebuilts";
        version = "0.1.2";
        src = vendor + "/guest/prebuilts.tar.zst";
        dontUnpack = true;
        nativeBuildInputs = [ pkgs.zstd ];
        installPhase = ''
          mkdir -p $out/lib/redroid-over-venus/guest
          tar --zstd -xf "$src" -C $out/lib/redroid-over-venus/guest --strip-components=1
        '';
      };

      houdini-src = vendor + "/libhoudini/brya";
      houdini-hack-src = vendor + "/libhoudini/hack";

      withMicroG = false;
      minmicrog = vendor + "/microg";

      houdiniRc = pkgs.writeText "houdini.rc" ''
        on early-init
            mount binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc

        on property:ro.enable.native.bridge.exec=1
            copy /system/etc/binfmt_misc/arm_exe /proc/sys/fs/binfmt_misc/register
            copy /system/etc/binfmt_misc/arm_dyn /proc/sys/fs/binfmt_misc/register

        on property:ro.enable.native.bridge.exec64=1
            copy /system/etc/binfmt_misc/arm64_exe /proc/sys/fs/binfmt_misc/register
            copy /system/etc/binfmt_misc/arm64_dyn /proc/sys/fs/binfmt_misc/register
      '';

      venusPropsRc = pkgs.writeText "redroid-over-venus.rc" ''
        on early-boot
            setprop debug.hwui.renderer skiavk
            setprop debug.renderengine.backend skiaglthreaded
            setprop debug.sf.nobootanimation 1
            setprop mesa.vn.debug vtest
            setprop mesa.vtest.socket.name /dev/venus/venus.sock
      '';

      redroid-overlay = pkgs.runCommand "redroid-over-venus-overlay" { } (''
        mkdir -p $out/overlay
        cp -r ${guest-nvidia}/lib/redroid-over-venus/guest/. $out/overlay/
        (cd ${guest-prebuilts}/lib/redroid-over-venus/guest && \
          find . -type f ! -iname '*hwcomposer*' ! -iname '*surfaceflinger*' -print0 \
          | tar --null -cf - --files-from -) | tar -xf - -C $out/overlay/
        mkdir -p $out/overlay/system/etc/init
        cp -r ${houdini-src}/{bin,lib,lib64} $out/overlay/system/
        cp -r ${houdini-src}/etc/binfmt_misc $out/overlay/system/etc/
        cp ${houdiniRc} $out/overlay/system/etc/init/houdini.rc
        cp -r ${houdini-hack-src}/13.0.0/. $out/overlay/system/
        chmod 0644 $out/overlay/system/etc/init/hw/init.rc
      '') + lib.optionalString withMicroG (''
        cp -r ${minmicrog}/system/. $out/overlay/system/
        find $out/overlay/system -depth -type d -name '-*-*' | while read -r d; do
          toks="$(basename "$d" | tr '-' ' ')"; hasarch=0; archok=0; hassdk=0; sdkok=0
          for t in $toks; do
            case "$t" in
              x86_64|x86) hasarch=1; archok=1 ;;
              arm|arm64|mips|mips64) hasarch=1 ;;
              *[!0-9]*) ;;
              *) hassdk=1; [ "$t" = "33" ] && sdkok=1 ;;
            esac
          done
          if { [ "$hasarch" = 1 ] && [ "$archok" = 0 ]; } || { [ "$hassdk" = 1 ] && [ "$sdkok" = 0 ]; }; then
            rm -rf "$d"
          else
            cp -r "$d/." "$(dirname "$d")/" && rm -rf "$d"
          fi
        done
        grep -rl FAKE_PACKAGE_SIGNATURE $out/overlay/system/etc/ 2>/dev/null \
          | xargs -r sed -i '/FAKE_PACKAGE_SIGNATURE/d' || true
      '') + ''
        mkdir -p $out/overlay/vendor/etc/init
        cp ${venusPropsRc} $out/overlay/vendor/etc/init/redroid-over-venus.rc
        find $out/overlay -type d -exec chmod 0755 {} +
        find $out/overlay -type f -exec chmod 0644 {} +
        find $out/overlay -type f -path '*/bin/*' -exec chmod 0755 {} +
        find $out/overlay -name '*.so' -exec chmod 0755 {} +
        (cd $out/overlay && find . -type f | sort) > $out/MANIFEST.txt
      '');

      build-image = pkgs.writeShellApplication {
        name = "build-redroid-over-venus-image";
        runtimeInputs = [ pkgs.docker ];
        text = ''
          BASE="''${1:-redroid/redroid:13.0.0_64only-latest}"
          TAG="''${2:-redroid-over-venus:13.0.0_64only}"
          CTX="$(mktemp -d)"
          trap 'rm -rf "$CTX"' EXIT
          cp -r ${redroid-overlay}/overlay "$CTX/overlay"
          printf 'FROM %s\nADD overlay /\n' "$BASE" > "$CTX/Dockerfile"
          docker build -t "$TAG" "$CTX"
          echo "Done: $TAG (base: $BASE). MANIFEST: ${redroid-overlay}/MANIFEST.txt"
        '';
      };

    in
    {
      packages.${system} = {
        inherit virglrenderer-nvidia guest-nvidia guest-prebuilts redroid-overlay build-image;
      };

      apps.${system}.default = {
        type = "app";
        program = "${build-image}/bin/build-redroid-over-venus-image";
      };

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.redroid-over-venus;
          ids = lib.genList (i: i) cfg.instances;
          cpusetOf = i: builtins.elemAt cfg.cpusets (lib.mod i (builtins.length cfg.cpusets));
          adbPortOf = i: cfg.baseAdbPort + i;
          venusPkg = self.packages.${pkgs.system}.virglrenderer-nvidia;

          preflight = pkgs.writeShellScript "redroid-over-venus-preflight" ''
            set -euo pipefail
            fail() { echo "PREFLIGHT FAIL: $*" >&2; exit 1; }
            [ -d /sys/module/nvidia_drm ] || fail "nvidia_drm not loaded"
            grep -q "^Y" /sys/module/nvidia_drm/parameters/modeset \
              || fail "modeset disabled"
            [ -c /dev/udmabuf ] || fail "no /dev/udmabuf"
            NVSMI="${config.hardware.nvidia.package}/bin/nvidia-smi"
            [ -x "$NVSMI" ] || NVSMI=nvidia-smi
            VER="$("$NVSMI" --query-gpu=driver_version --format=csv,noheader | head -1)" \
              || fail "nvidia-smi unavailable"
            [ "''${VER%%.*}" -ge 595 ] || fail "driver $VER too old"
            [ -e /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json ] \
              || fail "no NVIDIA vulkan ICD"
          '';

          venusUnit = lib.nameValuePair "venus" {
            description = "Venus render server for redroid instances";
            wantedBy = [ "multi-user.target" ];
            preStart = "${preflight}";
            serviceConfig = {
              Type = "simple";
              RuntimeDirectory = "redroid-over-venus";
              ExecStart = "${venusPkg}/lib/redroid-over-venus/virgl_test_server --venus --multi-clients --socket-path /run/redroid-over-venus/venus.sock";
              Environment = [
                "RENDER_SERVER_EXEC_PATH=${venusPkg}/lib/redroid-over-venus/virgl_render_server"
                "LD_LIBRARY_PATH=${venusPkg}/lib/redroid-over-venus:${pkgs.vulkan-loader}/lib"
                "VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
              ];
              Restart = "on-failure";
              RestartSec = 1;
            };
          };

          redroidBootArgs = [
            "androidboot.hardware=redroid"
            "androidboot.redroid_gpu_mode=guest"
            "androidboot.redroid_width=${toString cfg.width}"
            "androidboot.redroid_height=${toString cfg.height}"
            "androidboot.redroid_dpi=${toString cfg.dpi}"
            "androidboot.redroid_fps=${toString cfg.fps}"
            "androidboot.use_memfd=1"
            "ro.hardware.egl=angle"
            "ro.hardware.vulkan=virtio"
            "ro.hardware.gralloc=cros"
          ] ++ lib.optional cfg.useOverlayfs "androidboot.use_redroid_overlayfs=1"
            ++ lib.optional cfg.enableInputSubsys "androidboot.redroid_enable_input_subsys=1"
            ++ lib.optionals cfg.houdini [
              "ro.dalvik.vm.native.bridge=libhoudini.so"
              "ro.enable.native.bridge.exec=1"
              "ro.enable.native.bridge.exec64=1"
              "ro.vendor.enable.native.bridge.exec=1"
              "ro.dalvik.vm.isa.arm=x86"
              "ro.dalvik.vm.isa.arm64=x86_64"
              "ro.product.cpu.abilist=x86_64,arm64-v8a"
              "ro.product.cpu.abilist64=x86_64,arm64-v8a"
              "ro.product.cpu.abilist32=x86"
            ]
            ++ cfg.extraBootArgs;

          redroidUnit = i: lib.nameValuePair "redroid${toString i}" {
            description = "redroid ${toString i} (Android 13, Venus/NVIDIA)";
            after = [ "docker.service" "venus.service" "dev-binderfs.mount" ];
            requires = [ "docker.service" "venus.service" "dev-binderfs.mount" ];
            wantedBy = [ "multi-user.target" ];
            preStart = ''
              mkdir -p ${cfg.dataDir}/data-base ${cfg.dataDir}/data-diff${toString i} ${cfg.dataDir}/data${toString i}
              ${pkgs.docker}/bin/docker rm -f redroid${toString i} >/dev/null 2>&1 || true
            '';
            serviceConfig = {
              Type = "simple";
              TimeoutStartSec = 300;
              ExecStart =
                let
                  docker = "${pkgs.docker}/bin/docker";
                  volumes = if cfg.useOverlayfs then
                    "-v ${cfg.dataDir}/data-base:/data-base -v ${cfg.dataDir}/data-diff${toString i}:/data-diff"
                  else
                    "-v ${cfg.dataDir}/data${toString i}:/data";
                in
                lib.concatStringsSep " " [
                  "${docker} run --rm --name redroid${toString i}"
                  "--privileged"
                  "--cpuset-cpus=${cpusetOf i}"
                  "--memory=${cfg.memoryMax}"
                  "-v /dev/binderfs:/dev/binderfs"
                  "--device /dev/udmabuf"
                  "-v /run/redroid-over-venus:/dev/venus"
                  volumes
                  "-p 127.0.0.1:${toString (adbPortOf i)}:5555"
                  cfg.image
                  (lib.concatStringsSep " " redroidBootArgs)
                ];
              ExecStop = "${pkgs.docker}/bin/docker stop -t 10 redroid${toString i}";
              Restart = "on-failure";
              RestartSec = 5;
            };
          };
        in
        {
          options.services.redroid-over-venus = {
            enable = lib.mkEnableOption "redroid & Venus";
            image = lib.mkOption {
              type = lib.types.str;
              default = "redroid-over-venus:13.0.0_64only";
              description = "Image tag built by `nix run .#build-image`.";
            };
            instances = lib.mkOption { type = lib.types.int; default = 6; };
            dataDir = lib.mkOption { type = lib.types.str; default = "/var/lib/redroid"; };
            baseAdbPort = lib.mkOption {
              type = lib.types.port;
              default = 5555;
              description = "Localhost adb base port; instance i uses baseAdbPort+i.";
            };
            width = lib.mkOption { type = lib.types.int; default = 720; };
            height = lib.mkOption { type = lib.types.int; default = 1280; };
            dpi = lib.mkOption { type = lib.types.int; default = 320; };
            fps = lib.mkOption {
              type = lib.types.int;
              default = 15;
              description = "Primary load knob.";
            };
            memoryMax = lib.mkOption {
              type = lib.types.str;
              default = "4G";
              description = "Per-instance cgroup memory limit (requires psi=1).";
            };
            cpusets = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Per-instance CPU pinning.";
            };
            useOverlayfs = lib.mkOption { type = lib.types.bool; default = true; };
            enableInputSubsys = lib.mkOption { type = lib.types.bool; default = true; };
            houdini = lib.mkOption { type = lib.types.bool; default = true; };
            extraBootArgs = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
          };

          config = lib.mkIf cfg.enable {
            virtualisation.docker.enable = true;
            boot.kernelModules = [ "binder_linux" "udmabuf" ];
            boot.kernelParams = [ "psi=1" ];
            hardware.nvidia.modesetting.enable = lib.mkDefault true;
            systemd.mounts = [{
              what = "binder";
              type = "binder";
              where = "/dev/binderfs";
              options = "nosuid,nodev,noexec";
              wantedBy = [ "multi-user.target" ];
            }];
            environment.systemPackages = [ pkgs.android-tools ];
            systemd.services = lib.listToAttrs ([ venusUnit ] ++ map redroidUnit ids);
          };
        };
    };
}
