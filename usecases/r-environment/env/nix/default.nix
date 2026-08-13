# GENERATED FILE — do not edit by hand.
#
# Source of truth: env/nix/generate_env.R
# Regenerate with:  Rscript env/nix/generate_env.R <YYYY-MM-DD>
#
# Editing this file directly violates AGENTS.md §1.4 and will be rejected in
# review, because the generator would silently overwrite your change on the next
# run and the environment would stop matching its declared source.
#
# The fetchTarball URL below is the immutable pin. Nix hashes the entire
# downloaded content, so this single line fixes the OS, system libraries, R
# itself, and every R package simultaneously — a strictly stronger guarantee
# than a lockfile, which cannot see below the R layer.

let
  pkgs = import (fetchTarball {
    url = "https://github.com/rstats-on-nix/nixpkgs/archive/refs/heads/2025-01-15.tar.gz";
  }) { };

  rpkgs = builtins.attrValues {
    inherit (pkgs.rPackages)
      admiral
      digest
      dplyr
      jsonlite
      lubridate
      pharmaversesdtm
      sessioninfo
      stringr
      testthat
      tidyr
      xml2;
  };

  system_packages = builtins.attrValues {
    inherit (pkgs)
      R
      git
      glibcLocalesUtf8
      jq
      pandoc;
  };

in
pkgs.mkShell {
  LOCALE_ARCHIVE =
    if pkgs.stdenv.isLinux
    then "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive"
    else "";

  LANG = "en_US.UTF-8";
  LC_ALL = "en_US.UTF-8";

  buildInputs = [ rpkgs system_packages ];

  shellHook = ''
    echo "r-env-harness Track B (Nix, nixpkgs pinned 2025-01-15)"
  '';
}
