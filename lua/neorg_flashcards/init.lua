local form = require("neorg_flashcards.form")
local help = require("neorg_flashcards.help")
local overview = require("neorg_flashcards.overview")
local parser = require("neorg_flashcards.parser")
local presets = require("neorg_flashcards.presets")
local review = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")

local M = {}
M.presets = presets

local defaults = {
  flashcards_dir = vim.fn.expand("~/notes/flashcards"),
  default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
  default_kind = nil,
  languages = vim.deepcopy(schema.default_languages),
  scheduling = vim.deepcopy(schedule.DEFAULTS),
}

local config = vim.deepcopy(defaults)

local function ensure_flashcards_dir()
  vim.fn.mkdir(config.flashcards_dir, "p")
end

local function ensure_default_file_dir()
  vim.fn.mkdir(vim.fn.fnamemodify(config.default_file, ":h"), "p")
end

local function current_buffer_is_norg()
  local path = vim.api.nvim_buf_get_name(0)
  return path ~= "" and path:match("%.norg$")
end

local function ensure_editable_flashcard_buffer()
  if current_buffer_is_norg() then
    return false
  end

  M.open_flashcards()
  return true
end

---Insert a card into a .norg buffer and persist it.
---@param kind string
---@param values table<string, string>
---@param append boolean append at the end instead of above the cursor
---@param target_buf number|nil
local function insert_card(kind, values, append, target_buf)
  target_buf = target_buf or vim.api.nvim_get_current_buf()

  local row
  local win = vim.fn.bufwinid(target_buf)
  if append or win == -1 then
    row = vim.api.nvim_buf_line_count(target_buf)
  else
    row = vim.api.nvim_win_get_cursor(win)[1] - 1
  end

  vim.api.nvim_buf_set_lines(target_buf, row, row, false, schema.card_lines(config, kind, values))
  vim.api.nvim_buf_call(target_buf, function()
    vim.cmd("silent write")
  end)
  util.notify("Flashcard saved")
  overview.refresh()
end

---Append a card to the default file, creating it when missing.
---@return boolean ok
local function append_to_default(kind, values)
  ensure_default_file_dir()

  local path = config.default_file
  if vim.fn.filereadable(path) == 0 and not util.loaded_buffer(path) then
    vim.fn.writefile({ "* Flashcards", "" }, path)
  end

  local lines, bufnr, err = store.read_lines(path)
  if not lines then
    util.notify(err, vim.log.levels.ERROR)
    return false
  end

  local card_lines = schema.card_lines(config, kind, values)
  if #lines > 0 and lines[#lines] == "" and card_lines[1] == "" then
    table.remove(card_lines, 1)
  end
  vim.list_extend(lines, card_lines)

  local ok, write_err = store.write_lines(path, bufnr, lines)
  if not ok then
    util.notify(tostring(write_err), vim.log.levels.ERROR)
    return false
  end

  util.notify("Flashcard saved to " .. vim.fn.fnamemodify(path, ":t"))
  overview.refresh()
  return true
end

local function add_card(kind)
  if not schema.for_kind(config, kind) then
    util.notify("Unsupported flashcard kind: " .. kind, vim.log.levels.ERROR)
    return
  end

  local append = ensure_editable_flashcard_buffer()
  local target_buf = vim.api.nvim_get_current_buf()

  form.open(config, kind, {
    on_save = function(values)
      insert_card(kind, values, append, target_buf)
    end,
  })
end

function M.open_flashcards()
  ensure_flashcards_dir()
  ensure_default_file_dir()
  local existed = vim.fn.filereadable(config.default_file) == 1
  vim.cmd.edit(util.fname(config.default_file))

  if not existed and vim.api.nvim_buf_line_count(0) == 1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "" then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "* Flashcards",
      "",
    })
    vim.cmd.write()
  end

  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
end

function M.add_kind(kind)
  kind = util.trim(kind)
  if kind == "" then
    kind = util.trim(config.default_kind)
  end

  if kind == "" then
    util.notify("No flashcard kind given and default_kind is not configured", vim.log.levels.ERROR)
    return
  end

  add_card(kind)
end

function M.add_japanese()
  M.add_kind("japanese")
end

---Add a card straight to the default file, no matter which buffer is current.
---Used by the overview's `a` key. Falls back to default_kind.
---@param kind string|nil
function M.add_to_default(kind)
  kind = util.trim(kind or "")
  if kind == "" then
    kind = util.trim(config.default_kind or "")
  end

  if kind == "" then
    util.notify("No flashcard kind given and default_kind is not configured", vim.log.levels.ERROR)
    return
  end

  if not schema.for_kind(config, kind) then
    util.notify("Unsupported flashcard kind: " .. kind, vim.log.levels.ERROR)
    return
  end

  form.open(config, kind, {
    on_save = function(values)
      return append_to_default(kind, values)
    end,
  })
end

function M.insert_japanese()
  M.add_japanese()
end

function M.validate_file()
  local cards = parser.parse_buffer(0)
  if #cards == 0 then
    util.notify("No @flashcard blocks found", vim.log.levels.WARN)
    return
  end

  local _, errors = parser.valid_cards(config, cards)
  if #errors == 0 then
    util.notify(string.format("%d flashcard block(s) valid", #cards))
  else
    util.notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
  end
end

function M.review_all()
  local cards, errors = parser.collect_flashcards(config)
  review.start(cards, errors, "all")
end

function M.review_due()
  local cards, errors = parser.collect_flashcards(config)
  local now = os.time()
  local due = {}
  for _, card in ipairs(cards) do
    if schedule.is_due(card, now) then
      table.insert(due, card)
    end
  end

  local empty_message = "No due flashcards"
  local next_due = schedule.next_due(cards, now)
  if next_due then
    empty_message = empty_message .. " — next at " .. schedule.format_due(next_due)
  end

  review.start(due, errors, "due", empty_message, { sort = "due" })
end

function M.overview(opts)
  overview.open(function()
    return parser.collect_flashcards(config)
  end, opts)
end

function M.stats()
  M.overview({ view = "stats" })
end

function M.review_file()
  local cards, errors = parser.valid_cards(config, parser.parse_buffer(0))
  review.start(cards, errors, "file")
end

function M.review_tag(tag)
  tag = util.trim(tag)

  if tag == "" then
    vim.ui.input({ prompt = "Tag: " }, function(input)
      if input == nil then
        util.notify("Tag review cancelled", vim.log.levels.WARN)
        return
      end
      M.review_tag(input)
    end)
    return
  end

  local cards, errors = parser.collect_flashcards(config)
  local filtered = {}
  for _, card in ipairs(cards) do
    if schema.card_has_tag(card, tag) then
      table.insert(filtered, card)
    end
  end

  review.start(filtered, errors, "tag:" .. tag, "No flashcards found with tag: " .. tag)
end

function M.review_score(score)
  score = util.trim(score)

  if score == "" then
    vim.ui.input({ prompt = "Score (bad/mid/good/new): " }, function(input)
      if input == nil then
        util.notify("Score review cancelled", vim.log.levels.WARN)
        return
      end
      M.review_score(input)
    end)
    return
  end

  local filter = schema.score_filter(score)
  if not filter then
    util.notify("Unknown score: " .. score .. " (use bad, mid, good, new, or 1/2/3)", vim.log.levels.ERROR)
    return
  end

  local cards, errors = parser.collect_flashcards(config)
  local filtered = {}
  for _, card in ipairs(cards) do
    if filter.matches(card) then
      table.insert(filtered, card)
    end
  end

  review.start(filtered, errors, "score:" .. filter.label, "No flashcards found with score: " .. filter.label)
end

function M.close_review()
  review.close()
end

function M.flip_or_next()
  review.flip_or_next()
end

function M.next_card()
  review.next()
end

function M.previous_card()
  review.previous()
end

function M.rate_current(score)
  review.rate_current(score)
end

function M.edit_current_card()
  review.edit_current()
end

function M.type_answer()
  review.type_answer()
end

function M.help()
  help.open()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  config.flashcards_dir = vim.fs.normalize(vim.fn.expand(config.flashcards_dir))
  config.default_file = vim.fs.normalize(vim.fn.expand(config.default_file))

  help.setup(config)
  overview.setup(config, {
    on_add = function()
      M.add_to_default("")
    end,
  })
  review.setup(config)
  stats.setup(config)

  vim.api.nvim_create_user_command("NeorgFlashcardOpen", M.open_flashcards, {})
  vim.api.nvim_create_user_command("NeorgFlashcardAdd", function(opts_)
    M.add_kind(opts_.args)
  end, {
    nargs = "?",
    complete = function()
      return vim.tbl_keys(config.languages or {})
    end,
  })
  vim.api.nvim_create_user_command("NeorgFlashcardAddJapanese", M.add_japanese, {})
  vim.api.nvim_create_user_command("NeorgFlashcardInsertJapanese", M.insert_japanese, {})
  vim.api.nvim_create_user_command("NeorgFlashcardReview", M.review_all, {})
  vim.api.nvim_create_user_command("NeorgFlashcardReviewDue", M.review_due, {})
  vim.api.nvim_create_user_command("NeorgFlashcardReviewFile", M.review_file, {})
  vim.api.nvim_create_user_command("NeorgFlashcardReviewTag", function(opts_)
    M.review_tag(opts_.args)
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("NeorgFlashcardReviewScore", function(opts_)
    M.review_score(opts_.args)
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("NeorgFlashcardOverview", M.overview, {})
  vim.api.nvim_create_user_command("NeorgFlashcardStats", M.stats, {})
  vim.api.nvim_create_user_command("NeorgFlashcardHelp", M.help, {})
  vim.api.nvim_create_user_command("NeorgFlashcardValidate", M.validate_file, {})
end

return M
