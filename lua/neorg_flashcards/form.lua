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
    footer = " Enter next field · Ctrl-S save · q cancel ",
    footer_pos = "center",
    style = "minimal",
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_fields())

  vim.keymap.set({ "n", "i" }, "<C-s>", M.save, { buffer = buf, silent = true, desc = "Save card" })
  vim.keymap.set("n", "<CR>", M.save, { buffer = buf, silent = true, desc = "Save card" })
  vim.keymap.set("i", "<CR>", M.next_field, { buffer = buf, silent = true, desc = "Next field (save from the last)" })
  vim.keymap.set("i", "<Tab>", function()
    M.cycle_field(1)
  end, { buffer = buf, silent = true, desc = "Next field" })
  vim.keymap.set("i", "<S-Tab>", function()
    M.cycle_field(-1)
  end, { buffer = buf, silent = true, desc = "Previous field" })
  vim.keymap.set("n", "q", M.close, { buffer = buf, silent = true, desc = "Cancel" })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, silent = true, desc = "Cancel" })

  M.goto_field(1)
  vim.cmd("startinsert!")

  return true
end

return M
