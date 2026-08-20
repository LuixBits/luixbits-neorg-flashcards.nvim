-- Editable add-card form: a floating scratch buffer with one line per schema
-- field. Replaces sequential vim.ui.input prompts with a normal buffer you
-- can edit with full Neovim motions.

local schema = require("neorg_flashcards.schema")
local util = require("neorg_flashcards.util")

local M = {}

local state = {
  buf = nil,
  win = nil,
  kind = nil,
  fields = {},
  on_save = nil,
}

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function render_fields()
  local lines = {}
  for _, field in ipairs(state.fields) do
    table.insert(lines, field.label .. field.default)
  end
  return lines
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
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

  -- Stay open for the next card, with cleared fields.
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, render_fields())
  local first = 1
  vim.api.nvim_win_set_cursor(state.win, { first, #(state.fields[first] and state.fields[first].label or "") })
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
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " Add flashcard (" .. (language.label or kind) .. ") ",
    title_pos = "center",
    footer = " Ctrl-S save · add another · Esc/q cancel ",
    footer_pos = "center",
    style = "minimal",
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_fields())

  vim.keymap.set({ "n", "i" }, "<C-s>", M.save, { buffer = buf, silent = true, desc = "Save card" })
  vim.keymap.set("n", "<CR>", M.save, { buffer = buf, silent = true, desc = "Save card" })
  vim.keymap.set("n", "q", M.close, { buffer = buf, silent = true, desc = "Cancel" })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, silent = true, desc = "Cancel" })

  local first_label = state.fields[1] and state.fields[1].label or ""
  vim.api.nvim_win_set_cursor(state.win, { 1, #first_label })
  vim.cmd("startinsert!")

  return true
end

return M
