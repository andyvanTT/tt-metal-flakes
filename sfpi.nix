{ stdenv, fetchurl, runCommand, autoPatchelfHook, ncurses, mpfr, libmpc, xz, zstd, expat }:
let
  version = "7.95.0";
  hash = "sha256-90ux9KVSX2ecySwtCjuG8ys++gj5J5YjEj3VmPWb9q0=";
in
runCommand "sfpi-${version}"
  {
    inherit version;
    nativeBuildInputs = [ autoPatchelfHook ];
    patchelfFlags = [ "--page-size" "65536" ];
    buildInputs = [ ncurses mpfr libmpc xz zstd expat ];
    src = fetchurl {
      url = "https://github.com/tenstorrent/sfpi/releases/download/${version}/sfpi_${version}_x86_64_debian.txz";
      inherit hash;
    };
  }
  ''
    runPhase unpackPhase
    cp -r ../"$sourceRoot" "$out"
    runPhase fixupPhase
  ''
