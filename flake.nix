{
  description = "Local flashcards for Neorg notes in Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f system (import nixpkgs {
            inherit system;
          })
        );
    in
    {
      packages = forAllSystems (
        system: pkgs:
        let
          plugin = pkgs.vimUtils.buildVimPlugin {
            pname = "luixbits-neorg-flashcards.nvim";
            version = "0.1.0";
            src = self;
          };
        in
        {
          default = plugin;
          luixbits-neorg-flashcards-nvim = plugin;
        }
      );

      homeManagerModules.nvf = import ./nix/nvf-module.nix { inherit self; };
      nixosModules.nvf = self.homeManagerModules.nvf;

      checks = forAllSystems (
        system: pkgs:
        let
          plugin = self.packages.${system}.luixbits-neorg-flashcards-nvim;

          nvimEnv = ''
            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$TMPDIR/config"
            export XDG_STATE_HOME="$TMPDIR/state"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            export XDG_DATA_HOME="$TMPDIR/data"
            mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
          '';

          nvfModuleEval =
            let
              eval = lib.evalModules {
                specialArgs = {
                  inherit pkgs;
                };
                modules = [
                  (
                    { lib, ... }:
                    {
                      options.programs.nvf.settings.vim = {
                        startPlugins = lib.mkOption {
                          type = lib.types.listOf lib.types.package;
                          default = [ ];
                        };
                        luaConfigRC = lib.mkOption {
                          type = lib.types.attrsOf lib.types.lines;
                          default = { };
                        };
                        keymaps = lib.mkOption {
                          type = lib.types.listOf lib.types.attrs;
                          default = [ ];
                        };
                        binds.whichKey.register = lib.mkOption {
                          type = lib.types.attrsOf lib.types.str;
                          default = { };
                        };
                      };
                    }
                  )
                  self.homeManagerModules.nvf
                  {
                    programs.nvf.settings.vim.notes.neorg-flashcards = {
                      enable = true;
                      languagePresets = [ "japanese" ];
                      setupOpts.default_kind = "japanese";
                      keymaps.enable = true;
                    };
                  }
                ];
              };
              cfg = eval.config.programs.nvf.settings.vim;
            in
            assert builtins.length cfg.startPlugins == 1;
            assert builtins.length cfg.keymaps == 8;
            assert lib.hasInfix "require(\"neorg_flashcards\").setup" cfg.luaConfigRC.neorg-flashcards;
            assert lib.hasInfix "presets.only(\"japanese\")" cfg.luaConfigRC.neorg-flashcards;
            pkgs.runCommand "luixbits-neorg-flashcards-nvf-module-eval" { } ''
              touch "$out"
            '';
        in
        {
          inherit nvfModuleEval;

          package = plugin;

          luaSyntax = pkgs.runCommand "luixbits-neorg-flashcards-lua-syntax" {
            nativeBuildInputs = [ pkgs.lua ];
          } ''
            cd ${self}
            while IFS= read -r -d "" file; do
              luac -p "$file"
            done < <(find lua scripts -name '*.lua' -print0)
            touch "$out"
          '';

          headlessTests = pkgs.runCommand "luixbits-neorg-flashcards-headless-tests" {
            nativeBuildInputs = [
              pkgs.lua
              pkgs.neovim
            ];
          } ''
            ${nvimEnv}
            cd ${self}
            nvim --headless -u NONE -i NONE -n \
              --cmd "set rtp^=${self}" \
              -c "luafile ${self}/tests/run.lua" \
              -c "qa!"
            touch "$out"
          '';

          packageRequire = pkgs.runCommand "luixbits-neorg-flashcards-package-require" {
            nativeBuildInputs = [ pkgs.neovim ];
          } ''
            ${nvimEnv}
            nvim --headless -u NONE -i NONE -n \
              --cmd "set rtp^=${plugin}" \
              -c "lua require('neorg_flashcards').setup({})" \
              -c "qa!"
            touch "$out"
          '';

          cleanInstall = pkgs.runCommand "luixbits-neorg-flashcards-clean-install" {
            nativeBuildInputs = [ pkgs.neovim ];
          } ''
            ${nvimEnv}
            ${pkgs.runtimeShell} ${self}/scripts/check-clean-install.sh
            touch "$out"
          '';
        }
      );
    };
}
