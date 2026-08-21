-- Editable add-card form: a floating scratch buffer with one line per schema
-- field. Replaces sequential vim.ui.input prompts with a normal buffer you
-- can edit with full Neovim motions.

local popup = require("neorg_flashcards.popup")
local schema = require("neorg_flashcards.schema")
local actions = require("neorg_flashcards.ui.actions")
local util = require("neorg_flashcards.util")

local M = {}

local state = {
  buf = nil,
  win = nil,
  kind = nil,
  fields = {},
  on_save = nil,
  config = {},
}

local key_help = { buf = nil, win = nil }

local function show_shortcuts()
  return type(state.config.ui) ~= "table" or state.config.ui.show_shortcuts ~= false
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---Move the cursor to a field, landing after its label.
function M.goto_field(index)
  if not M.is_open() or #state.fields == 0 then
    return
  end
  index = math.max(1, math.min(#state.fields, index))
  vim.api.nvim_win_set_cursor(state.win, { index, #state.fields[index].label })
end

---<CR> in insert mode: hop to the next field, save from the last one.
function M.next_field()
  if not M.is_open() then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  if line >= #state.fields then
    M.save()
    return
  end
  M.goto_field(line + 1)
end

---<Tab>/<S-Tab> in insert mode: cycle fields without saving.
function M.cycle_field(delta)
  if not M.is_open() or #state.fields == 0 then
    return
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  M.goto_field(((line - 1 + delta) % #state.fields) + 1)
end

local function render_fields()
  local lines = {}
  for _, field in ipairs(state.fields) do
    table.insert(lines, field.label .. field.default)
  end
  return lines
end

function M.close()
  popup.close(key_help)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

function M.context_help()
  popup.open(key_help, {
    title = " " .. actions.title("form") .. " ",
    footer = " q/Esc/? close ",
    min_width = 56,
    max_width = 76,
    min_height = 12,
    max_height = 22,
    maps = {
      { "q", M.help_close, "Close form key help" },
      { "<Esc>", M.help_close, "Close form key help" },
      { "?", M.help_close, "Close form key help" },
    },
  })
  popup.set_lines(key_help, actions.help_lines("form"))
end

function M.help_close()
  popup.close(key_help)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

local function dispatch(action_name)
  if action_name == "close" then
    M.close()
  elseif action_name == "context_help" then
    M.context_help()
  elseif action_name == "save" then
    M.save()
  elseif action_name == "next_field" then
    M.next_field()
  elseif action_name == "next_form_field" then
    M.cycle_field(1)
  elseif action_name == "previous_form_field" then
    M.cycle_field(-1)
  end
end

function M.save()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local values = {}
  for index, field in ipairs(state.fields) do
    local line = lines[index] or ""
    if line:sub(1, #field.label) ~= field.label then
      util.notify(
        string.format("Line %d lost its %q prefix; restore it or press q to cancel", index, field.label),
        vim.log.levels.ERROR
      )
      return
    end

    local value = util.trim(line:sub(#field.label + 1))
    if field.required and value == "" then
      util.notify(field.label .. " is required", vim.log.levels.ERROR)
      return
    end
    values[field.key] = value
  end

  local on_save = state.on_save
  if on_save and on_save(values) == false then
    return
  end

  -- Stay open for the next card, with cleared fields, ready to type.
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, render_fields())
  M.goto_field(1)
  vim.cmd("startinsert!")
end

function M.open(config, kind, opts)
  local language = schema.for_kind(config, kind)
  if not language then
    util.notify("Unsupported flashcard kind: " .. kind, vim.log.levels.ERROR)
    return false
  end

  M.close()

  state.kind = kind
  state.on_save = opts and opts.on_save
  state.config = config
  state.fields = {}
  for _, field in ipairs(schema.prompt_fields(config, kind)) do
    table.insert(state.fields, field)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "norg"
  vim.bo[buf].swapfile = false

  state.buf = buf

  local width = math.min(72, math.max(48, math.floor(vim.o.columns * 0.6)))
  local height = #state.fields + 2
  local window_config = {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " Add flashcard (" .. (language.label or kind) .. ") ",
    title_pos = "center",
    style = "minimal",
  }
  if show_shortcuts() then
    window_config.footer = actions.footer("form", width)
    window_config.footer_pos = "center"
  end
  state.win = vim.api.nvim_open_win(buf, true, window_config)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_fields())

  for _, binding in ipairs(actions.available_bindings("form")) do
    local action_name = binding.action
    vim.keymap.set(binding.mode, binding.key, function()
      dispatch(action_name)
    end, { buffer = buf, silent = true, nowait = true, desc = binding.description })
  end

  M.goto_field(1)
  vim.cmd("startinsert!")

  return true
end

return M
