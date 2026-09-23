{
  description = "VRCX-0";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      pkgsFor = lib.genAttrs systems (
        system:
        import nixpkgs {
          localSystem.system = system;
          overlays = [ (import rust-overlay) ];
        }
      );
      srcCargoToml = lib.importTOML ./src-tauri/Cargo.toml;
      rust-version = "1.98.0";
    in
    {
      packages = lib.mapAttrs (system: pkgs: {
        vrcx-0 =
          let
            rust = pkgs.rust-bin.stable.${rust-version}.default;

            rustPlatform = pkgs.makeRustPlatform {
              cargo = rust;
              rustc = rust;
            };
          in
          rustPlatform.buildRustPackage (finalAttrs: {
            pname = "vrcx-0";

            src = pkgs.nix-gitignore.gitignoreSource [ ] ./.;
            inherit (srcCargoToml.package) version;

            cargoLock.lockFile = ./Cargo.lock;

            npmDeps = pkgs.fetchNpmDeps {
              name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
              inherit (finalAttrs) src;
              hash = "sha256-h9YihimQoWMBqgZOIdUtXJNQvb+06MRbLf4cHpiVxwY=";
            };

            nativeBuildInputs =
              with pkgs;
              [
                # Pull in our main hook
                cargo-tauri.hook

                # Setup npm
                nodejs
                npmHooks.npmConfigHook

                # Make sure we can find our libraries
                pkg-config
                rustPlatform.bindgenHook
                cmake
                wrapGAppsHook4
              ]
              ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapGAppsHook4 ];

            buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux (
              with pkgs;
              [
                glib-networking
                openssl
                webkitgtk_4_1
                libayatana-appindicator
              ]
            );

            postPatch = ''
              node <<'NODE'
                                const fs = require('node:fs');

                                const tauriConfigPath = 'src-tauri/tauri.conf.json';
                                const linuxConfigPath = 'src-tauri/tauri.linux.conf.json';

                                const tauriConfig = JSON.parse(fs.readFileSync(tauriConfigPath, 'utf8'));
                                let config = structuredClone(tauriConfig);

                                const linuxConfig = JSON.parse(fs.readFileSync(linuxConfigPath, 'utf8'));
                                config = {
                                    bundle: {
                                        ...(linuxConfig.bundle ?? {}),
                                        targets: ['appimage'],
                                        createUpdaterArtifacts: false
                                    }
                                };

                                fs.writeFileSync(linuxConfigPath, JSON.stringify(config, null, 4));'';

            preFixup = ''
              gappsWrapperArgs+=(
                --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ pkgs.libayatana-appindicator ]}"
              )
            '';

            # Set our Tauri source directory
            cargoRoot = "";
            # And make sure we build there too
            buildAndTestSubdir = "src-tauri";

            doCheck = false;

            passthru.updateScript = pkgs.nix-update-script { };

            meta = {
              description = "The fast, lightweight VRCX built with Tauri and Rust.";
              license = lib.licenses.gpl3;
              platforms = lib.platforms.linux;
              mainProgram = "vrcx-0";
            };
          });

        default = self.packages.${system}.vrcx-0;
      }) pkgsFor;

      devShells = lib.mapAttrs (system: pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.vrcx-0 ];

          packages = [ pkgs.rust-bin.stable.${rust-version}.default ];
        };
      }) pkgsFor;

      overlays.default = final: prev: { inherit (self.packages.${prev.system}) vrcx-0; };
    };
}
