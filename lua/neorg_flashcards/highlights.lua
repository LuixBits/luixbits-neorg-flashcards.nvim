local util = require("neorg_flashcards.util")

local M = {}

M.groups = {
  hub = {
    due = "NeorgFlashcardsDue",
    overdue = "NeorgFlashcardsOverdue",
    soon = "NeorgFlashcardsSoon",
    scheduled = "NeorgFlashcardsScheduled",
    new = "NeorgFlashcardsNew",
    learning = "NeorgFlashcardsLearning",
    review = "NeorgFlashcardsReview",
    relearning = "NeorgFlashcardsLearning",
    suspended = "NeorgFlashcardsSuspended",
    buried = "NeorgFlashcardsBuried",
    invalid = "NeorgFlashcardsInvalid",
    active = "NeorgFlashcardsActive",
    title = "NeorgFlashcardsGroupTitle",
    muted = "NeorgFlashcardsMuted",
    selected = "NeorgFlashcardsSelected",
    heading = "NeorgFlashcardsHeading",
    accent = "NeorgFlashcardsAccent",
    action = "NeorgFlashcardsPrimaryAction",
    table_header = "NeorgFlashcardsTableHeader",
    tab_active = "NeorgFlashcardsTabActive",
    tab_inactive = "NeorgFlashcardsTabInactive",
    footer = "NeorgFlashcardsFooter",
  },
  rating = {
    again = "NeorgFlashcardsAgain",
    hard = "NeorgFlashcardsHard",
    good = "NeorgFlashcardsGood",
  },
  heatmap = {
    [0] = "NeorgFlashcardsHeat0",
    "NeorgFlashcardsHeat1",
    "NeorgFlashcardsHeat2",
    "NeorgFlashcardsHeat3",
    "NeorgFlashcardsHeat4",
  },
  form = {
    active = "NeorgFlashcardsFormActive",
    error = "NeorgFlashcardsFormError",
    hint = "NeorgFlashcardsFormHint",
    label = "NeorgFlashcardsFormLabel",
    muted = "NeorgFlashcardsFormMuted",
    required = "NeorgFlashcardsFormRequired",
    status_ok = "NeorgFlashcardsFormStatusOk",
    status_warn = "NeorgFlashcardsFormStatusWarn",
    target = "NeorgFlashcardsFormTarget",
  },
}

M.defaults = {
  rating_highlights = {
    again = { link = "DiagnosticError" },
    hard = { link = "DiagnosticWarn" },
    good = { link = "DiagnosticOk" },
  },
  heatmap_highlights = {
    [0] = { link = "NonText" },
    { link = "Comment" },
    { link = "DiagnosticHint" },
    { link = "DiagnosticInfo" },
    { link = "DiagnosticOk" },
  },
}

local DEFAULT_LINKS = {
  [M.groups.hub.due] = "DiagnosticWarn",
  [M.groups.hub.overdue] = "DiagnosticError",
  [M.groups.hub.soon] = "DiagnosticWarn",
  [M.groups.hub.scheduled] = "DiagnosticOk",
  [M.groups.hub.new] = "DiagnosticInfo",
  [M.groups.hub.learning] = "Special",
  [M.groups.hub.review] = "Type",
  [M.groups.hub.suspended] = "Comment",
  [M.groups.hub.buried] = "NonText",
  [M.groups.hub.invalid] = "DiagnosticError",
  [M.groups.hub.active] = "DiagnosticOk",
  [M.groups.hub.title] = "Title",
  [M.groups.hub.muted] = "Comment",
  [M.groups.hub.selected] = "Visual",
  [M.groups.hub.heading] = "Title",
  [M.groups.hub.accent] = "Special",
  [M.groups.hub.action] = "IncSearch",
  [M.groups.hub.table_header] = "Identifier",
  [M.groups.hub.tab_active] = "TabLineSel",
  [M.groups.hub.tab_inactive] = "TabLine",
  [M.groups.hub.footer] = "StatusLine",
  [M.groups.form.active] = "CursorLine",
  [M.groups.form.error] = "DiagnosticError",
  [M.groups.form.hint] = "Comment",
  [M.groups.form.label] = "Identifier",
  [M.groups.form.muted] = "Comment",
  [M.groups.form.required] = "DiagnosticWarn",
  [M.groups.form.status_ok] = "DiagnosticOk",
  [M.groups.form.status_warn] = "DiagnosticWarn",
  [M.groups.form.target] = "Directory",
}

local DEFAULT_BOLD = {
  [M.groups.hub.invalid] = true,
  [M.groups.hub.selected] = true,
  [M.groups.hub.heading] = true,
  [M.groups.hub.accent] = true,
  [M.groups.hub.action] = true,
  [M.groups.hub.table_header] = true,
  [M.groups.hub.tab_active] = true,
}

local config = {}

local function configured_highlight(section, key)
  local ui = type(config.ui) == "table" and config.ui or nil
  local values = ui and type(ui[section]) == "table" and ui[section] or nil
  if not values then
    return nil
  end
  return values[key] or values[tostring(key)]
end

local function define_configured(section, key, group, fallback)
  local configured = configured_highlight(section, key)
  local value = type(configured) == "table" and vim.deepcopy(configured) or { link = fallback }
  if vim.tbl_isempty(value) then
    value = { link = fallback }
  end

  local ok, err = pcall(vim.api.nvim_set_hl, 0, group, value)
  if ok then
    return
  end

  local path = section == "heatmap_highlights" and string.format("ui.%s[%d]", section, key)
    or string.format("ui.%s.%s", section, key)
  util.notify(string.format("Invalid %s (%s); using %s", path, tostring(err), fallback), vim.log.levels.WARN)
  vim.api.nvim_set_hl(0, group, { link = fallback })
end

function M.apply()
  for group, link in pairs(DEFAULT_LINKS) do
    vim.api.nvim_set_hl(0, group, { bold = DEFAULT_BOLD[group] or nil, default = true, link = link })
  end
  for name, definition in pairs(M.defaults.rating_highlights) do
    define_configured("rating_highlights", name, M.groups.rating[name], definition.link)
  end
  for level = 0, 4 do
    define_configured("heatmap_highlights", level, M.groups.heatmap[level], M.defaults.heatmap_highlights[level].link)
  end
end

function M.setup(opts)
  config = { ui = vim.deepcopy(type(opts) == "table" and opts.ui or {}) }
  M.apply()

  local group = vim.api.nvim_create_augroup("neorg_flashcards_highlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = M.apply,
  })
end

return M
