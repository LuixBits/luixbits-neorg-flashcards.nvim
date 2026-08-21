{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
    filterAttrs
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;

  cfg = config.programs.nvf.neorg-flashcards;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.luixbits-neorg-flashcards-nvim;

  toLua =
    value:
    let
      valueType = builtins.typeOf value;
      renderSet =
        attrs:
        "{"
        + concatMapStringsSep ",\n" (
          name:
          let
            renderedName = builtins.toJSON name;
          in
          "[${renderedName}] = ${toLua attrs.${name}}"
        ) (builtins.attrNames (filterAttrs (_: v: v != null) attrs))
        + "}";
    in
    if lib.isDerivation value then
      builtins.toJSON "${value}"
    else if valueType == "int" || valueType == "float" then
      toString value
    else if valueType == "bool" then
      lib.boolToString value
    else if valueType == "string" || valueType == "path" then
      builtins.toJSON value
    else if valueType == "null" then
      "nil"
    else if valueType == "list" then
      "{" + concatMapStringsSep ",\n" toLua value + "}"
    else if valueType == "set" then
      renderSet value
    else
      throw "Cannot render ${valueType} as Lua";

  presetArgs = concatMapStringsSep ", " builtins.toJSON cfg.languagePresets;

  setupLua = ''
    local opts = ${toLua cfg.setupOpts}
    ${optionalString (cfg.languagePresets != [ ]) ''
      local presets = require("neorg_flashcards.presets")
      opts.languages = vim.tbl_deep_extend("force", presets.only(${presetArgs}), opts.languages or {})
    ''}
    require("neorg_flashcards").setup(opts)
  '';

  key = suffix: "${cfg.keymaps.prefix}${suffix}";

  hubKeymaps = [
    {
      mode = "n";
      key = cfg.keymaps.prefix;
      action = "<cmd>Flashcards<CR>";
      desc = "Open flashcards";
    }
  ];

  legacyKeymaps = [
    {
      mode = "n";
      key = key "o";
      action = "<cmd>NeorgFlashcardOpen<CR>";
      desc = "Open flashcards";
    }
    {
      mode = "n";
      key = key "i";
      action = "<cmd>NeorgFlashcardAdd<CR>";
      desc = "Add flashcard";
    }
    {
      mode = "n";
      key = key "h";
      action = "<cmd>NeorgFlashcardHelp<CR>";
      desc = "Flashcard help";
    }
    {
      mode = "n";
      key = key "r";
      action = "<cmd>NeorgFlashcardReview<CR>";
      desc = "Review flashcards";
    }
    {
      mode = "n";
      key = key "f";
      action = "<cmd>NeorgFlashcardReviewFile<CR>";
      desc = "Review file flashcards";
    }
    {
      mode = "n";
      key = key "t";
      action = "<cmd>NeorgFlashcardReviewTag<CR>";
      desc = "Review flashcards by tag";
    }
    {
      mode = "n";
      key = key "s";
      action = "<cmd>NeorgFlashcardReviewScore<CR>";
      desc = "Review flashcards by score";
    }
    {
      mode = "n";
      key = key "v";
      action = "<cmd>NeorgFlashcardValidate<CR>";
      desc = "Validate flashcards";
    }
  ];

  keymaps = if cfg.keymaps.mode == "legacy" then legacyKeymaps else hubKeymaps;
in
{
  options.programs.nvf.neorg-flashcards = {
    enable = mkEnableOption "luixbits-neorg-flashcards.nvim";

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      defaultText = "inputs.luixbits-neorg-flashcards.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "Vim plugin package to add to NVF.";
    };

    setupOpts = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = {
        flashcards_dir = "~/notes/flashcards";
        default_file = "~/notes/flashcards/cards.norg";
        default_kind = "japanese";
      };
      description = ''
        Options passed to `require("neorg_flashcards").setup(...)`.
        Use `languagePresets` for bundled Lua presets, or set `languages`
        directly for custom schemas.
      '';
    };

    languagePresets = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "japanese"
        "chinese"
      ];
      description = ''
        Bundled language presets to merge into `setupOpts.languages` via
        `require("neorg_flashcards.presets").only(...)`.
      '';
    };

    keymaps = {
      enable = mkEnableOption "default luixbits-neorg-flashcards.nvim keymaps";

      mode = mkOption {
        type = types.enum [
          "hub"
          "legacy"
        ];
        default = "hub";
        description = ''
          Keymap layout. `hub` maps the prefix itself to the unified
          `:Flashcards` dashboard. `legacy` keeps the older command-per-key
          group below the prefix.
        '';
      };

      prefix = mkOption {
        type = types.str;
        default = "<leader>nc";
        description = ''
          Exact dashboard key in hub mode, or the group prefix in legacy mode.
        '';
      };

      registerWhichKey = mkOption {
        type = types.bool;
        default = true;
        description = "Register the keymap prefix with NVF's which-key bindings.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.nvf.settings.vim = {
      startPlugins = [ cfg.package ];
      luaConfigRC.neorg-flashcards = setupLua;
      keymaps = mkIf cfg.keymaps.enable keymaps;
      binds.whichKey.register = mkIf (
        cfg.keymaps.enable && cfg.keymaps.registerWhichKey && cfg.keymaps.mode == "legacy"
      ) {
        ${cfg.keymaps.prefix} = "+Cards";
      };
    };
  };
}
