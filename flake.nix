{
  description = "Dev shell for building and testing tt-metal from source on NixOS (single card)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      llvm = pkgs.llvmPackages_20;

      clang20-aliases = pkgs.runCommand "clang20-aliases" { } ''
        mkdir -p $out/bin
        ln -s ${llvm.clang}/bin/clang   $out/bin/clang-20
        ln -s ${llvm.clang}/bin/clang++ $out/bin/clang++-20
        ln -s ${llvm.lld}/bin/ld.lld    $out/bin/ld.lld-20
      '';

      sfpi = pkgs.callPackage ./sfpi.nix { };

      sfpi-link = pkgs.writeShellApplication {
        name = "tt-sfpi-link";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          sudo mkdir -p /opt/tenstorrent
          sudo ln -sfn ${sfpi} /opt/tenstorrent/sfpi
          ls -l /opt/tenstorrent/sfpi
        '';
      };

      runtimeLibs = with pkgs; [ stdenv.cc.cc.lib zlib libffi openssl hwloc numactl tbb capstone ];

      python = pkgs.python312;

      tt-venv = pkgs.writeShellApplication {
        name = "tt-venv";
        runtimeInputs = [ pkgs.uv python pkgs.git ];
        text = ''
          cd "''${TT_METAL_HOME:?run inside the tt-metal checkout (direnv)}"
          env_dir="''${PYTHON_ENV_DIR:-$PWD/python_env}"
          uv venv --python ${python}/bin/python --clear "$env_dir"
          # shellcheck disable=SC1091
          . "$env_dir/bin/activate"
          idx=https://download.pytorch.org/whl/cpu
          uv pip install --upgrade wheel "setuptools==80"
          uv pip install --extra-index-url "$idx" --index-strategy unsafe-best-match \
            -r tt_metal/python_env/requirements-dev.txt
          [ -f tools/triage/requirements.txt ] && uv pip install --index-strategy unsafe-best-match -r tools/triage/requirements.txt
          uv pip install -e .
          echo "venv ready: $env_dir"
        '';
      };

      tt-build = pkgs.writeShellApplication {
        name = "tt-build";
        runtimeInputs = [ ];
        text = ''
          cd "''${TT_METAL_HOME:?}"
          [ -e /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-g++ ] || { echo "run tt-sfpi-link first"; exit 1; }
          exec bash ./build_metal.sh --use-system-sfpi --enable-ccache --disable-profiler --build-tests "$@"
        '';
      };

      tt-doctor = pkgs.writeShellApplication {
        name = "tt-doctor";
        runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
        text = ''
          set +e
          rc=0
          report() {
            if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2  -> $3"; rc=1; fi
          }
          hp=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo 0)
          home="''${TT_METAL_HOME:-.}"

          [ -d /sys/module/tenstorrent ];                       report $? "tt-kmd loaded" "hardware.tenstorrent.enable = true; reboot"
          ls /dev/tenstorrent/[0-9]* >/dev/null 2>&1;           report $? "card visible" "check PCIe / firmware"
          [ "$hp" -ge 1 ];                                      report $? "1G hugepages allocated ($hp)" "boot.kernelParams = [ \"default_hugepagesz=1G\" \"hugepagesz=1G\" \"hugepages=4\" ]; reboot"
          [ -x /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-g++ ]; report $? "SFPI at /opt/tenstorrent/sfpi" "tt-sfpi-link"
          grep -q "^sfpi_version=.${sfpi.version}.$" "$home/tt_metal/sfpi-version"; report $? "SFPI ${sfpi.version} matches checkout" "bump sfpi.nix to the checkout's tt_metal/sfpi-version"
          [ -d "$home/build" ];                                 report $? "build dir present" "tt-build"
          [ -x "$home/python_env/bin/python" ];                 report $? "venv present" "tt-venv"
          exit $rc
        '';
      };

      tt-test = pkgs.writeShellApplication {
        name = "tt-test";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          cd "''${TT_METAL_HOME:?}"
          # shellcheck disable=SC1091
          . python_env/bin/activate
          case "''${1:-}" in
            smoke) shift; exec pytest tests/ttnn/unit_tests/base_functionality -x "$@" ;;
            cpp)   shift; exec ./build/test/tt_metal/unit_tests_api "$@" ;;
            *)     exec pytest tests/ttnn/unit_tests -m "not frequently_hangs" "$@" ;;
          esac
        '';
      };
    in
    {
      packages.${system} = { inherit sfpi tt-venv tt-build tt-doctor tt-test; };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          clang20-aliases llvm.clang llvm.lld llvm.clang-tools
          pkgs.mold pkgs.cmake pkgs.ninja pkgs.pkg-config pkgs.ccache pkgs.gnumake
          pkgs.git pkgs.git-lfs pkgs.pandoc pkgs.xz pkgs.xxd pkgs.patchelf pkgs.wget pkgs.curl
          pkgs.openssl pkgs.hwloc pkgs.numactl pkgs.tbb pkgs.capstone pkgs.openmpi
          pkgs.uv python pkgs.pciutils
          sfpi-link tt-venv tt-build tt-doctor tt-test
        ];

        shellHook = ''
          export TT_METAL_HOME="$PWD"
          export PYTHONPATH="$PWD''${PYTHONPATH:+:$PYTHONPATH}"
          export ARCH_NAME=''${ARCH_NAME:-blackhole}
          export LD_LIBRARY_PATH="$PWD/build/lib64:${pkgs.lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export UV_PYTHON_DOWNLOADS=never
          export CXXFLAGS="-include cstdint -Wno-macro-redefined''${CXXFLAGS:+ $CXXFLAGS}"
          export CCACHE_DIR="''${CCACHE_DIR:-$HOME/.cache/ccache}"
          [ -f "$PWD/python_env/bin/activate" ] && . "$PWD/python_env/bin/activate"
          echo "tt-metal dev shell (clang $(clang --version | head -1 | grep -o '[0-9.]*$'), sfpi ${sfpi.version}, ARCH_NAME=$ARCH_NAME)"
          echo "  first time:  tt-doctor ; tt-sfpi-link ; tt-venv ; tt-build ; tt-test smoke"
        '';
      };
    };
}
