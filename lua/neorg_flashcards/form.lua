-- Safe add-card composer. The buffer contains field values only; labels,
-- validation, target context, and guidance are UI decorations rendered with
-- extmarks so they cannot accidentally become part of a saved card.

local popup = require("neorg_flashcards.popup")
local schema = require("neorg_flashcards.schema")
local actions = require("neorg_flashcards.ui.actions")
local util = require("neorg_flashcards.util")

local M = {}

local namespace = vim.api.nvim_create_namespace("neorg_flashcards_form")

local function fresh_state()
  return {
    buf = nil,
    win = nil,
    return_win = nil,
    augroup = nil,
    kind = nil,
    language_label = nil,
    fields = {},
    on_save = nil,
    on_close = nil,
    config = {},
    target = {},
    initial_lines = {},
    last_lines = {},
    errors = {},
    validation_attempted = false,
    dirty = false,
    saved_count = 0,
    status = nil,
    selected = 1,
    rendering = false,
    structure_invalid = false,
    valid_change = false,
    change_scheduled = false,
    closing_prompt = false,
  }
end

local state = fresh_state()
local key_help = { buf = nil, win = nil }

local function show_shortcuts()
  return type(state.config.ui) ~= "table" or state.config.ui.show_shortcuts ~= false
end

local function valid_buffer()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function ensure_highlights()
  local links = {
    NeorgFlashcardsFormActive = "CursorLine",
    NeorgFlashcardsFormError = "DiagnosticError",
    NeorgFlashcardsFormHint = "Comment",
    NeorgFlashcardsFormLabel = "Identifier",
    NeorgFlashcardsFormMuted = "Comment",
    NeorgFlashcardsFormRequired = "DiagnosticWarn",
    NeorgFlashcardsFormStatusOk = "DiagnosticOk",
    NeorgFlashcardsFormStatusWarn = "DiagnosticWarn",
    NeorgFlashcardsFormTarget = "Directory",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

local function copy_lines(lines)
  local result = {}
  for index, line in ipairs(lines or {}) do
    result[index] = tostring(line or "")
  end
  return result
end

local function one_line(value)
  local result = tostring(value or ""):gsub("[\r\n]+", " ")
  return result
end

local function default_lines()
  local lines = {}
  for _, field in ipairs(state.fields) do
    table.insert(lines, one_line(field.default))
  end
  return lines
end

local function current_lines()
  if not valid_buffer() then
    return {}
  end
  return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
end

local function refresh_dirty(lines)
  state.dirty = not vim.deep_equal(lines or current_lines(), state.initial_lines)
end

local function field_title(field)
  return one_line(field.title or field.key or "Field")
end

local function label_width()
  local width = 0
  for _, field in ipairs(state.fields) do
    local marker = field.required and " *" or ""
    width = math.max(width, vim.fn.strdisplaywidth(field_title(field) .. marker))
  end
  return width
end

local function window_config()
  local available_width = math.max(1, vim.o.columns - 4)
  local minimum_width = math.max(54, label_width() + 28)
  local width = math.min(92, math.max(minimum_width, math.floor(vim.o.columns * 0.64)))
  width = math.max(1, math.min(width, available_width))

  local available_height = math.max(1, vim.o.lines - 4)
  local height = math.max(8, #state.fields + 4)
  height = math.max(1, math.min(height, available_height))

  local config = {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    title = " Add " .. (state.language_label or state.kind or "flashcard") .. " card ",
    title_pos = "center",
    style = "minimal",
  }
  if show_shortcuts() then
    config.footer = actions.footer("form", width)
    config.footer_pos = "center"
  end
  return config
end

local function resize()
  if M.is_open() then
    pcall(vim.api.nvim_win_set_config, state.win, window_config())
  end
end

local function selected_row()
  if not M.is_open() or #state.fields == 0 then
    return 1
  end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  return math.max(1, math.min(#state.fields, row))
end

local function status_chunks()
  if state.status then
    local prefix = "  "
    local highlight = "NeorgFlashcardsFormHint"
    if state.status.kind == "saved" then
      prefix = "  ✓ "
      highlight = "NeorgFlashcardsFormStatusOk"
    elseif state.status.kind == "warning" then
      prefix = "  ! "
      highlight = "NeorgFlashcardsFormStatusWarn"
    elseif state.status.kind == "error" then
      prefix = "  ! "
      highlight = "NeorgFlashcardsFormError"
    end
    return { { prefix .. state.status.text, highlight } }
  end

  local field = state.fields[state.selected]
  if field and state.errors[state.selected] then
    return { { "  ! " .. state.errors[state.selected], "NeorgFlashcardsFormError" } }
  end
  if field and not util.isempty(field.help) then
    return {
      { "  Hint  ", "NeorgFlashcardsFormMuted" },
      { one_line(field.help), "NeorgFlashcardsFormHint" },
    }
  end

  local remaining = 0
  local lines = current_lines()
  for index, item in ipairs(state.fields) do
    if item.required and util.isempty(lines[index]) then
      remaining = remaining + 1
    end
  end
  if remaining > 0 then
    local suffix = remaining == 1 and "field" or "fields"
    return { { string.format("  %d required %s remaining", remaining, suffix), "NeorgFlashcardsFormMuted" } }
  end
  return { { "  Ready to save", "NeorgFlashcardsFormStatusOk" } }
end

local function render()
  if not valid_buffer() or #state.fields == 0 then
    return
  end

  ensure_highlights()
  state.selected = selected_row()
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)

  local lines = current_lines()
  local widest = label_width()
  for index, field in ipairs(state.fields) do
    local title = field_title(field)
    local marker = field.required and " *" or ""
    local padding = string.rep(" ", math.max(0, widest - vim.fn.strdisplaywidth(title .. marker)))
    local options = {
      priority = 100,
      right_gravity = false,
      virt_text = {
        { "  " .. title, "NeorgFlashcardsFormLabel" },
        { marker, "NeorgFlashcardsFormRequired" },
        { padding .. "  │ ", "NeorgFlashcardsFormMuted" },
      },
      virt_text_pos = "inline",
    }
    if index == state.selected then
      options.line_hl_group = "NeorgFlashcardsFormActive"
    end
    vim.api.nvim_buf_set_extmark(state.buf, namespace, index - 1, 0, options)

    local value = lines[index] or ""
    local decoration
    if state.errors[index] then
      decoration = { "  " .. state.errors[index], "NeorgFlashcardsFormError" }
    elseif util.isempty(value) and not util.isempty(field.placeholder) then
      decoration = { "  " .. one_line(field.placeholder), "NeorgFlashcardsFormMuted" }
    end
    if decoration then
      vim.api.nvim_buf_set_extmark(state.buf, namespace, index - 1, #value, {
        priority = 110,
        right_gravity = false,
        virt_text = { decoration },
        virt_text_pos = "eol",
      })
    end
  end

  local target_label = one_line(state.target.label or state.target.path or "[No target]")
  vim.api.nvim_buf_set_extmark(state.buf, namespace, 0, 0, {
    priority = 90,
    virt_lines = {
      {
        { "  Target  ", "NeorgFlashcardsFormMuted" },
        { target_label, "NeorgFlashcardsFormTarget" },
      },
    },
    virt_lines_above = true,
  })

  local last_line = lines[#state.fields] or ""
  vim.api.nvim_buf_set_extmark(state.buf, namespace, #state.fields - 1, #last_line, {
    priority = 90,
    virt_lines = { status_chunks() },
  })
end

local function replace_lines(lines)
  if not valid_buffer() then
    return
  end
  state.rendering = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  state.rendering = false
  state.last_lines = copy_lines(lines)
end

local function focus_form()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
  end
end

---Move the cursor to a field. Because labels are virtual, column zero is the
---start of the value and the end column is simply the raw line length.
function M.goto_field(index)
  if not M.is_open() or #state.fields == 0 then
    return
  end
  index = math.max(1, math.min(#state.fields, tonumber(index) or 1))
  local line = current_lines()[index] or ""
  vim.api.nvim_win_set_cursor(state.win, { index, #line })
  state.selected = index
  render()
end

function M.edit_field()
  if not M.is_open() then
    return
  end
  focus_form()
  M.goto_field(selected_row())
  vim.cmd("startinsert!")
end

-- Keep Insert-mode deletion inside the raw value on the current row. Labels
-- are virtual text, but an unguarded Backspace/Delete at a line boundary can
-- still join two field rows before the structural repair runs. Returning an
-- empty expression makes the boundary a hard edge, like an input mask.
local function masked_delete(key, direction)
  if not M.is_open() then
    return key
  end

  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local line = current_lines()[cursor[1]] or ""
  local column = cursor[2]
  if direction == "backward" and column == 0 then
    return ""
  end
  if direction == "forward" and column >= #line then
    return ""
  end
  return key
end

function M.masked_backspace()
  return masked_delete("<BS>", "backward")
end

function M.masked_delete()
  return masked_delete("<Del>", "forward")
end

function M.masked_word_backspace()
  return masked_delete("<C-w>", "backward")
end

---<CR> in insert mode: hop to the next field, save and return from the last.
function M.next_field()
  if not M.is_open() then
    return
  end
  local line = selected_row()
  if line >= #state.fields then
    M.save("close")
    return
  end
  M.goto_field(line + 1)
end

M.next_or_save = M.next_field

---Cycle fields without changing editing mode.
function M.cycle_field(delta)
  if not M.is_open() or #state.fields == 0 then
    return
  end
  local line = selected_row()
  M.goto_field(((line - 1 + delta) % #state.fields) + 1)
end

local function close_now()
  local return_win = state.return_win
  local augroup = state.augroup
  local on_close = state.on_close
  local form_buf = state.buf
  local form_win = state.win
  local errors = {}

  -- Clear the live state before closing windows. WinClosed callbacks and
  -- user autocmds may re-enter this module; they must observe an already
  -- completed close and must not run on_close twice.
  state = fresh_state()

  local popup_ok, popup_err = pcall(popup.close, key_help)
  if not popup_ok then
    table.insert(errors, popup_err)
  end
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  if form_win and vim.api.nvim_win_is_valid(form_win) then
    local close_ok, close_err = pcall(vim.api.nvim_win_close, form_win, true)
    if not close_ok then
      table.insert(errors, close_err)
    end
  end
  if form_buf and vim.api.nvim_buf_is_valid(form_buf) then
    local delete_ok, delete_err = pcall(vim.api.nvim_buf_delete, form_buf, { force = true })
    if not delete_ok then
      table.insert(errors, delete_err)
    end
  end
  if return_win and vim.api.nvim_win_is_valid(return_win) then
    local focus_ok, focus_err = pcall(vim.api.nvim_set_current_win, return_win)
    if not focus_ok then
      table.insert(errors, focus_err)
    end
  end
  if on_close then
    local callback_ok, callback_err = pcall(on_close)
    if not callback_ok then
      table.insert(errors, callback_err)
    end
  end
  if #errors > 0 then
    pcall(
      util.notify,
      "Flashcard form closed, but a UI cleanup hook failed: " .. one_line(errors[1]),
      vim.log.levels.WARN
    )
  end
  return true
end

---Close the composer. Dirty interactive closes ask before discarding values;
---internal callers may pass { force = true } after a completed save.
function M.close(opts)
  opts = opts or {}
  pcall(popup.close, key_help)
  if not M.is_open() then
    if state.buf or state.on_close then
      return close_now()
    end
    state = fresh_state()
    return true
  end
  local lines = current_lines()
  refresh_dirty(lines)
  if state.structure_invalid or #lines ~= #state.fields then
    state.dirty = true
  end
  if opts.force == true or not state.dirty then
    return close_now()
  end
  if state.closing_prompt then
    return false
  end

  state.closing_prompt = true
  vim.ui.select({ "Keep editing", "Discard draft" }, {
    prompt = "Discard this unsaved flashcard?",
  }, function(choice)
    if not M.is_open() then
      return
    end
    state.closing_prompt = false
    if choice == "Discard draft" then
      close_now()
      return
    end
    focus_form()
  end)
  return false
end

function M.context_help()
  if not M.is_open() then
    return
  end
  popup.open(key_help, {
    title = " " .. actions.title("form") .. " ",
    footer = " q/Esc/? close ",
    min_width = 56,
    max_width = 76,
    min_height = 12,
    max_height = 24,
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
  focus_form()
end

local function set_error(message, source)
  state.status = {
    kind = "error",
    source = source,
    text = one_line(message),
  }
  render()
end

local function validate()
  local lines = current_lines()
  if #lines ~= #state.fields then
    return nil, 1, "Fields are single-line; use one row per field"
  end

  local values = {}
  local errors = {}
  local first_invalid
  for index, field in ipairs(state.fields) do
    local value = util.trim(lines[index])
    values[field.key] = value
    if field.required and value == "" then
      errors[index] = field_title(field) .. " is required"
      first_invalid = first_invalid or index
    end
  end

  state.validation_attempted = true
  state.errors = errors
  if first_invalid then
    return nil, first_invalid, errors[first_invalid]
  end
  return values
end

local function normalize_save_result(callback_ok, result, detail)
  if not callback_ok then
    return {
      ok = false,
      persisted = false,
      message = "Could not save flashcard: " .. tostring(result),
    }
  end

  if result == false then
    local message = type(detail) == "table" and detail.message or detail
    return {
      ok = false,
      persisted = false,
      message = one_line(message or "Could not save flashcard"),
    }
  end

  if type(result) == "table" then
    return {
      ok = result.ok ~= false,
      persisted = result.persisted ~= false,
      path = result.path,
      message = result.message,
    }
  end

  return {
    ok = true,
    persisted = true,
    message = type(result) == "string" and result or (type(detail) == "string" and detail or nil),
  }
end

local function invoke_save(values, mode)
  if not state.on_save then
    return { ok = true, persisted = true }
  end
  local callback_ok, result, detail = pcall(state.on_save, values, {
    kind = state.kind,
    mode = mode,
    target = vim.deepcopy(state.target),
  })
  return normalize_save_result(callback_ok, result, detail)
end

local function save_message(result)
  if not util.isempty(result.message) then
    return one_line(result.message)
  end
  if result.persisted == false then
    return "Saved in the target buffer; write it to persist the card"
  end

  local path = result.path or state.target.path
  local label = state.target.label
  if not util.isempty(path) then
    label = util.path_label(path, state.config.flashcards_dir)
  end
  if not util.isempty(label) then
    return "Flashcard saved to " .. one_line(label)
  end
  return "Flashcard saved"
end

---Validate and save the composer. mode is close (the default) or new.
---Callbacks may return nil/true/false for compatibility, or a structured
---{ ok, persisted, path, message } result.
function M.save(mode)
  mode = mode == "new" and "new" or "close"
  if not valid_buffer() then
    return false
  end

  if state.structure_invalid or #current_lines() ~= #state.fields then
    replace_lines(state.last_lines)
    state.structure_invalid = false
    state.valid_change = false
    refresh_dirty(state.last_lines)
    state.errors = {}
    state.validation_attempted = false
    set_error("Fields are single-line; use one row per field", "structure")
    M.goto_field(math.min(state.selected, #state.fields))
    vim.cmd("startinsert!")
    return false
  end

  local values, first_invalid, message = validate()
  if not values then
    set_error(message, "validation")
    M.goto_field(first_invalid)
    vim.cmd("startinsert!")
    return false
  end

  local result = invoke_save(values, mode)
  if not result.ok then
    set_error(result.message or "Could not save flashcard", "callback")
    focus_form()
    return false
  end

  local message_text = save_message(result)
  if mode == "close" then
    close_now()
    return true
  end

  state.saved_count = state.saved_count + 1
  state.errors = {}
  state.validation_attempted = false
  state.status = {
    kind = result.persisted == false and "warning" or "saved",
    source = "save",
    text = string.format("Saved %d · %s", state.saved_count, message_text),
  }
  state.initial_lines = default_lines()
  replace_lines(state.initial_lines)
  state.dirty = false
  M.goto_field(1)
  vim.cmd("startinsert!")
  return true
end

function M.save_new()
  return M.save("new")
end

local function restore_structure()
  if not valid_buffer() then
    return
  end
  local row = selected_row()
  replace_lines(state.last_lines)
  state.structure_invalid = false
  state.valid_change = false
  refresh_dirty(state.last_lines)
  state.errors = {}
  state.validation_attempted = false
  state.status = {
    kind = "error",
    source = "structure",
    text = "Fields are single-line; use one row per field",
  }
  M.goto_field(math.min(row, #state.fields))
end

local function refresh_after_change()
  if not valid_buffer() then
    return
  end
  if state.structure_invalid or #current_lines() ~= #state.fields then
    restore_structure()
    return
  end

  local lines = current_lines()
  local valid_change = state.valid_change
  state.valid_change = false
  state.last_lines = copy_lines(lines)
  refresh_dirty(lines)
  if valid_change and state.status and state.status.kind == "error" then
    state.status = nil
  end
  if state.validation_attempted then
    local _, first_invalid = validate()
    if first_invalid then
      state.status = {
        kind = "error",
        source = "validation",
        text = state.errors[first_invalid],
      }
    else
      state.status = nil
    end
  end
  render()
end

local function schedule_refresh()
  if state.change_scheduled then
    return
  end
  state.change_scheduled = true
  local expected_buffer = state.buf
  vim.schedule(function()
    if state.buf ~= expected_buffer then
      return
    end
    state.change_scheduled = false
    refresh_after_change()
  end)
end

local function attach_guard(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, _, first_line, old_last_line, new_last_line)
      if changed_buf ~= state.buf or state.rendering then
        return
      end
      if old_last_line - first_line ~= new_last_line - first_line then
        state.structure_invalid = true
      else
        state.valid_change = true
      end
      schedule_refresh()
    end,
  })
end

local function dispatch(action_name)
  if action_name == "close" then
    M.close()
  elseif action_name == "context_help" then
    M.context_help()
  elseif action_name == "save_close" then
    M.save("close")
  elseif action_name == "save_new" then
    M.save("new")
  elseif action_name == "next_or_save" then
    M.next_field()
  elseif action_name == "next_form_field" then
    M.cycle_field(1)
  elseif action_name == "previous_form_field" then
    M.cycle_field(-1)
  elseif action_name == "edit_field" then
    M.edit_field()
  elseif action_name == "leave_insert" then
    vim.cmd("stopinsert")
  end
end

local function infer_target(config, opts, source_buf)
  local path = util.trim(opts.target_path)
  if path == "" and source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    local source_path = vim.api.nvim_buf_get_name(source_buf)
    if source_path:match("%.norg$") then
      path = source_path
    end
  end
  if path == "" then
    path = util.trim(config.default_file)
  end
  if path ~= "" then
    path = vim.fs.normalize(vim.fn.expand(path))
  end

  local label = util.trim(opts.target_label)
  if label == "" then
    label = util.path_label(path, config.flashcards_dir)
  end
  return {
    path = path,
    label = label,
  }
end

local function configure_window(buf)
  state.win = vim.api.nvim_open_win(buf, true, window_config())
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].spell = false
  vim.wo[state.win].wrap = false
end

local handle_native_close

local function watch_form_window(group, form_win)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(form_win),
    callback = function()
      handle_native_close(form_win)
    end,
  })
end

handle_native_close = function(form_win)
  if state.win ~= form_win then
    return
  end

  local lines = current_lines()
  refresh_dirty(lines)
  local has_draft = state.dirty or state.structure_invalid or #lines ~= #state.fields
  if not has_draft then
    close_now()
    return
  end

  local selected = state.selected
  state.win = nil
  local reopened, reopen_err = pcall(configure_window, state.buf)
  if not reopened then
    pcall(util.notify, "Could not reopen the unsaved flashcard draft: " .. tostring(reopen_err), vim.log.levels.ERROR)
    return
  end

  watch_form_window(state.augroup, state.win)
  state.selected = selected
  render()
  M.goto_field(selected)

  local expected_buf = state.buf
  vim.schedule(function()
    if state.buf == expected_buf and M.is_open() then
      M.close()
    end
  end)
end

local function configure_autocmds(buf)
  state.augroup = vim.api.nvim_create_augroup("NeorgFlashcardsForm" .. buf, { clear = true })
  watch_form_window(state.augroup, state.win)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = state.augroup,
    buffer = buf,
    callback = function()
      if M.is_open() then
        state.selected = selected_row()
        render()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      vim.schedule(resize)
    end,
  })
end

function M.open(config, kind, opts)
  opts = opts or {}
  local language = schema.for_kind(config, kind)
  if not language then
    util.notify("Unsupported flashcard kind: " .. kind, vim.log.levels.ERROR)
    return false
  end

  if M.is_open() then
    focus_form()
    util.notify("Finish or discard the open flashcard first", vim.log.levels.WARN)
    return false
  end
  if state.buf then
    close_now()
  end

  local fields = schema.prompt_fields(config, kind)
  if #fields == 0 then
    util.notify("Flashcard kind has no editable fields: " .. kind, vim.log.levels.ERROR)
    return false
  end

  local source_buf = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  state = fresh_state()
  state.kind = kind
  state.language_label = language.label or kind
  state.on_save = opts.on_save
  state.on_close = opts.on_close
  state.config = config
  state.fields = vim.deepcopy(fields)
  state.return_win = source_win
  state.target = infer_target(config, opts, source_buf)
  state.initial_lines = default_lines()
  state.last_lines = copy_lines(state.initial_lines)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  -- Keep the draft alive long enough for WinClosed to recover native :q or
  -- <C-w>c closes. close_now() deletes it after an intentional final close.
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "neorg_flashcards_form"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  state.buf = buf

  replace_lines(state.initial_lines)
  attach_guard(buf)
  configure_window(buf)
  configure_autocmds(buf)

  for _, binding in ipairs(actions.available_bindings("form")) do
    local action_name = binding.action
    vim.keymap.set(binding.mode, binding.key, function()
      dispatch(action_name)
    end, { buffer = buf, silent = true, nowait = true, desc = binding.description })
  end

  local mask_options = { buffer = buf, expr = true, silent = true, nowait = true }
  vim.keymap.set(
    "i",
    "<BS>",
    M.masked_backspace,
    vim.tbl_extend("force", mask_options, {
      desc = "Delete only inside the current flashcard value",
    })
  )
  vim.keymap.set(
    "i",
    "<C-h>",
    M.masked_backspace,
    vim.tbl_extend("force", mask_options, {
      desc = "Delete only inside the current flashcard value",
    })
  )
  vim.keymap.set(
    "i",
    "<Del>",
    M.masked_delete,
    vim.tbl_extend("force", mask_options, {
      desc = "Delete only inside the current flashcard value",
    })
  )
  vim.keymap.set(
    "i",
    "<C-w>",
    M.masked_word_backspace,
    vim.tbl_extend("force", mask_options, {
      desc = "Delete a word only inside the current flashcard value",
    })
  )

  render()
  M.goto_field(1)
  vim.cmd("startinsert!")
  return true
end

return M
