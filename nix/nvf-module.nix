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

  presetArgs = concatMapStringsSep ", " builtins.toJSON cfg.schemaPresets;

  setupLua = ''
    local opts = ${toLua cfg.setupOpts}
    ${optionalString (cfg.schemaPresets != [ ]) ''
      local presets = require("neorg_flashcards.presets")
      opts.schemas = vim.tbl_deep_extend("force", presets.only(${presetArgs}), opts.schemas or {})
    ''}
    require("neorg_flashcards").setup(opts)
  '';

  keymaps = [
    {
      mode = "n";
      key = cfg.keymaps.prefix;
      action = "<cmd>Flashcards<CR>";
      desc = "Open flashcards";
    }
  ];
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
      default = {
        default_kind = "japanese";
      };
      example = {
        flashcards_dir = "~/notes/flashcards";
        default_file = "~/notes/flashcards/cards.norg";
        default_kind = "japanese";
      };
      description = ''
        Options passed to `require("neorg_flashcards").setup(...)`.
        The default selects the bundled Japanese schema so enabling the module
        is immediately usable. Use `schemaPresets` for other bundled Lua
        presets, or set `schemas` directly for custom schemas.
      '';
    };

    schemaPresets = mkOption {
      type = types.listOf types.str;
      default = [ "japanese" ];
      example = [
        "japanese"
        "chinese"
      ];
      description = ''
        Bundled schema presets to merge into `setupOpts.schemas` via
        `require("neorg_flashcards.presets").only(...)`. Japanese is enabled
        by default; set this to an empty list when supplying only custom
        schemas.
      '';
    };

    keymaps = {
      enable = mkEnableOption "default luixbits-neorg-flashcards.nvim keymaps";

      prefix = mkOption {
        type = types.str;
        default = "<leader>nc";
        description = "Exact key used to open the flashcard hub.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.nvf.settings.vim = {
      startPlugins = [ cfg.package ];
      luaConfigRC.neorg-flashcards = setupLua;
      keymaps = mkIf cfg.keymaps.enable keymaps;
    };
  };
}
