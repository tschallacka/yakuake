{
  description = "Yakuake local checkout - build and dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      kpkgs = pkgs.kdePackages;

      qtDeps = [
        pkgs.qt6.qtbase
        pkgs.qt6.qtsvg
        pkgs.qt6.qtwayland
      ];

      kdeDeps = [
        kpkgs.karchive
        kpkgs.kconfig
        kpkgs.kcoreaddons
        kpkgs.kcrash
        kpkgs.kdbusaddons
        kpkgs.kglobalaccel
        kpkgs.ki18n
        kpkgs.kiconthemes
        kpkgs.kio
        kpkgs.knewstuff
        kpkgs.knotifications
        kpkgs.knotifyconfig
        kpkgs.kparts
        kpkgs.konsole
        kpkgs.kstatusnotifieritem
        kpkgs.kwayland
        kpkgs.kwidgetsaddons
        kpkgs.kwindowsystem
        kpkgs.kcolorscheme
        kpkgs.plasma-wayland-protocols
      ];

      x11Deps = [
        pkgs.libxcb
        pkgs.xcbutil
      ];

      buildDeps = qtDeps ++ kdeDeps ++ x11Deps;

      # The checkout holds things the build must not see: CodeGraph's index directory
      # (which contains a unix socket nix cannot copy at all), the result symlink and
      # .git. Filter them out so a plain `nix build` works while the daemon is running.
      filteredSrc = pkgs.lib.cleanSourceWith {
        name = "yakuake-source";
        src = self;
        filter =
          path: _type:
          let
            base = baseNameOf (toString path);
          in
          !(builtins.elem base [
            ".codegraph"
            ".direnv"
            "result"
          ]);
      };
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "yakuake";
        version = "26.11.70";

        src = filteredSrc;

        nativeBuildInputs = [
          pkgs.cmake
          pkgs.ninja
          pkgs.pkg-config
          pkgs.gettext
          kpkgs.extra-cmake-modules
          pkgs.qt6.wrapQtAppsHook
        ];

        buildInputs = buildDeps;

        cmakeFlags = [ "-DWITH_X11=ON" ];

        env.LANG = "C.UTF-8";
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ kpkgs.yakuake ];
        packages = [ pkgs.git ];
      };
    };
}