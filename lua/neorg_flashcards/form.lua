local dialog = require("neorg_flashcards.dialog")
-- Safe add-card composer. The buffer contains field values only; labels,
-- validation, target context, and guidance are UI decorations rendered with
-- extmarks so they cannot accidentally become part of a saved card.

local popup = require("neorg_flashcards.popup")
local schema = require("neorg_flashcards.schema")
local actions = require("neorg_flashcards.ui.actions")
local highlights = require("neorg_flashcards.highlights")
local util = require("neorg_flashcards.util")
local canvas = require("neorg_flashcards.ui.canvas")

local M = {}

local namespace = vim.api.nvim_create_namespace("neorg_flashcards_form")
local FORM_HIGHLIGHTS = highlights.groups.form

local generation_counter = 0

local function fresh_state(generation)
  return {
    generation = generation,
    buf = nil,
    win = nil,
    return_win = nil,
    augroup = nil,
    kind = nil,
    kind_label = nil,
    title = nil,
    fields = {},
    roles = {},
    on_save = nil,
    on_close = nil,
    config = {},
    target = {},
    initial_lines = {},
    initial_field_lengths = {},
    initial_values = {},
    field_lengths = {},
    undo_layouts = {},
    change_sequence = nil,
    insertion_field = nil,
    last_lines = {},
    last_field_lengths = {},
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
    change_revision = 0,
    allow_save_new = true,
    edit_mode = false,
  }
end

local state = fresh_state()
local key_help = { buf = nil, win = nil }

local function show_shortcuts()
  return type(state.config.ui) ~= "table" or state.config.ui.show_shortcuts ~= false
end

local function form_capabilities()
  return {
    save_new = state.allow_save_new,
    edit = state.edit_mode,
  }
end

local function valid_buffer()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
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
  state.field_lengths = {}
  for index, field in ipairs(state.fields) do
    local initial = state.initial_values[field.key]
    local value = initial ~= nil and initial or field.default
    local field_lines = field.multiline and util.value_lines(value) or { one_line(value) }
    state.field_lengths[index] = #field_lines
    vim.list_extend(lines, field_lines)
  end
  state.initial_field_lengths = vim.deepcopy(state.field_lengths)
  return lines
end

-- Field ranges are zero-based and end-exclusive, like the buffer API.
local function field_range(index)
  local first = 0
  for preceding = 1, index - 1 do
    first = first + state.field_lengths[preceding]
  end
  return first, first + (state.field_lengths[index] or 1)
end

local function field_at(row)
  for index = 1, #state.fields do
    local _, last = field_range(index)
    if row < last then
      return index
    end
  end
  return #state.fields
end

local function current_lines()
  if not valid_buffer() then
    return {}
  end
  return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
end

local function draft_field_value(index, lines)
  local first, last = field_range(index)
  return table.concat(lines or current_lines(), "\n", first + 1, last)
end

local function refresh_dirty(lines)
  state.dirty = not vim.deep_equal(lines or current_lines(), state.initial_lines)
    or not vim.deep_equal(state.field_lengths, state.initial_field_lengths)
end

local function remember_layout(lines)
  local sequence = vim.fn.undotree().seq_cur
  state.undo_layouts[sequence] = state.undo_layouts[sequence] or {}
  local key = vim.fn.sha256(table.concat(lines, "\n"))
  state.undo_layouts[sequence][key] = vim.deepcopy(state.field_lengths)
  state.change_sequence = sequence
end

local function sync_undo_layout()
  local sequence = vim.fn.undotree().seq_cur
  if sequence == state.change_sequence then
    return
  end
  -- on_lines runs before Neovim finishes moving through the undo tree. Once
  -- it has finished, restore the field boundaries belonging to that text.
  local lines = current_lines()
  local layouts = state.undo_layouts[sequence]
  local lengths = layouts and layouts[vim.fn.sha256(table.concat(lines, "\n"))]
  if lengths then
    state.field_lengths = vim.deepcopy(lengths)
    state.last_lines = copy_lines(lines)
    state.last_field_lengths = vim.deepcopy(lengths)
    state.structure_invalid = false
  end
  state.change_sequence = sequence
end

local function field_title(field)
  return one_line(field.title or field.key or "Field")
end

local function layout()
  local available = math.max(1, vim.o.lines - 6)
  local spacious = available >= #state.fields * 3 + 6
  return {
    spacious = spacious,
    height = math.min(
      available,
      #state.fields * (spacious and 3 or 2) + (spacious and 6 or 5) + #state.last_lines - #state.fields
    ),
    width = math.max(1, math.min(96, vim.o.columns - 4, math.floor(vim.o.columns * 0.82))),
  }
end

local function window_config()
  local dimensions = layout()
  local width, height = dimensions.width, dimensions.height

  local config = {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = state.config.ui and state.config.ui.ascii and { "+", "-", "+", "|", "+", "-", "+", "|" } or "rounded",
    title = state.title or (state.edit_mode and " Edit card " or " New card "),
    title_pos = "left",
    style = "minimal",
  }
  if show_shortcuts() then
    config.footer = { { canvas.fit(actions.footer("form", width, form_capabilities()), width), FORM_HIGHLIGHTS.label } }
    config.footer_pos = "center"
  end
  return config
end

local render

local function resize()
  if M.is_open() then
    pcall(vim.api.nvim_win_set_config, state.win, window_config())
    render()
  end
end

local function selected_field()
  if not M.is_open() or #state.fields == 0 then
    return 1
  end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  return field_at(row - 1)
end

local function status_chunks()
  if state.status then
    local prefix = "  "
    local highlight = FORM_HIGHLIGHTS.hint
    if state.status.kind == "saved" then
      prefix = "  ✓ "
      highlight = FORM_HIGHLIGHTS.status_ok
    elseif state.status.kind == "warning" then
      prefix = "  ! "
      highlight = FORM_HIGHLIGHTS.status_warn
    elseif state.status.kind == "error" then
      prefix = "  ! "
      highlight = FORM_HIGHLIGHTS.error
    end
    return { { prefix .. state.status.text, highlight } }
  end

  local field = state.fields[state.selected]
  if field and state.errors[state.selected] then
    return { { "  ! " .. state.errors[state.selected], FORM_HIGHLIGHTS.error } }
  end
  local remaining = 0
  local lines = current_lines()
  for index, item in ipairs(state.fields) do
    if item.required and util.isempty(draft_field_value(index, lines)) then
      remaining = remaining + 1
    end
  end
  if remaining > 0 then
    local suffix = remaining == 1 and "field" or "fields"
    return { { string.format("  %d required %s remaining", remaining, suffix), FORM_HIGHLIGHTS.muted } }
  end
  return { { "  Ready to save", FORM_HIGHLIGHTS.status_ok } }
end

local function header_lines(dimensions)
  local collection = one_line(state.config.label or state.config.id or "Collection")
  local context = collection .. " / " .. one_line(state.target.chapter_label or "Unfiled")
  local lines = { { { "  " .. canvas.fit(context, dimensions.width - 4), FORM_HIGHLIGHTS.target } } }
  -- A very short terminal must leave room for the active field itself.
  if dimensions.height >= 10 then
    table.insert(lines, {
      { "  " .. canvas.fit(one_line(state.kind_label or state.kind), dimensions.width - 4), FORM_HIGHLIGHTS.muted },
    })
    table.insert(lines, {
      {
        "  Target  " .. canvas.fit(one_line(state.target.label or state.target.path), dimensions.width - 10),
        FORM_HIGHLIGHTS.muted,
      },
    })
    if dimensions.spacious then
      table.insert(lines, { { "", FORM_HIGHLIGHTS.muted } })
    end
  end
  return lines
end

render = function()
  if not valid_buffer() or #state.fields == 0 then
    return
  end

  sync_undo_layout()
  if state.structure_invalid then
    return
  end
  state.last_lines = current_lines()
  state.last_field_lengths = vim.deepcopy(state.field_lengths)
  local view = M.is_open() and vim.api.nvim_win_call(state.win, vim.fn.winsaveview) or nil
  local dimensions = layout()
  if M.is_open() and vim.api.nvim_win_get_height(state.win) ~= dimensions.height then
    vim.api.nvim_win_set_config(state.win, window_config())
  end
  local header = header_lines(dimensions)
  state.selected = selected_field()
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)

  local lines = current_lines()
  for index, field in ipairs(state.fields) do
    local first, last = field_range(index)
    local selected = index == state.selected
    local caption = {
      { "  " .. field_title(field), state.errors[index] and FORM_HIGHLIGHTS.error or FORM_HIGHLIGHTS.label },
      { "  " .. (state.roles[field.key] or "Details"), FORM_HIGHLIGHTS.muted },
      {
        field.required and " · required" or " · optional",
        field.required and FORM_HIGHLIGHTS.required or FORM_HIGHLIGHTS.muted,
      },
    }
    local above = index == 1 and vim.deepcopy(header) or {}
    if index > 1 and dimensions.spacious then
      table.insert(above, { { "", FORM_HIGHLIGHTS.muted } })
    end
    table.insert(above, caption)
    local options = {
      priority = 100,
      right_gravity = false,
      virt_text = {
        { selected and "  > " or "    ", selected and FORM_HIGHLIGHTS.target or FORM_HIGHLIGHTS.muted },
      },
      virt_text_pos = "inline",
      hl_mode = "combine",
      virt_lines = above,
      virt_lines_above = true,
      line_hl_group = selected and FORM_HIGHLIGHTS.active or FORM_HIGHLIGHTS.input,
    }
    vim.api.nvim_buf_set_extmark(state.buf, namespace, first, 0, options)
    for row = first + 1, last - 1 do
      vim.api.nvim_buf_set_extmark(state.buf, namespace, row, 0, {
        virt_text = { { "    ", FORM_HIGHLIGHTS.muted } },
        virt_text_pos = "inline",
        right_gravity = false,
        line_hl_group = selected and FORM_HIGHLIGHTS.active or FORM_HIGHLIGHTS.input,
      })
    end

    local value = lines[first + 1] or ""
    local decoration
    if state.errors[index] then
      decoration = { "  " .. state.errors[index], FORM_HIGHLIGHTS.error }
    elseif util.isempty(draft_field_value(index, lines)) then
      decoration = { one_line(field.placeholder ~= "" and field.placeholder or "Enter a value"), FORM_HIGHLIGHTS.muted }
    end
    if decoration then
      vim.api.nvim_buf_set_extmark(state.buf, namespace, first, #value, {
        priority = 110,
        right_gravity = false,
        virt_text = { decoration },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end
  end

  local field = state.fields[state.selected]
  local help = field and one_line(field.help) or ""
  if field and field.multiline then
    help = "Normal: o/O adds a line" .. (help ~= "" and " · " .. help or "")
  end
  local below = { status_chunks() }
  if help ~= "" then
    table.insert(below, 1, { { "  " .. canvas.fit(help, dimensions.width - 4), FORM_HIGHLIGHTS.hint } })
  end
  if dimensions.spacious then
    table.insert(below, 1, { { "", FORM_HIGHLIGHTS.muted } })
  end
  local last_line = lines[#lines] or ""
  vim.api.nvim_buf_set_extmark(state.buf, namespace, #lines - 1, #last_line, {
    priority = 90,
    virt_lines = below,
  })
  if view then
    -- Neovim otherwise hides virtual labels above the first visible value.
    -- Preserve horizontal scrolling while including that field's caption.
    local first = field_range(field_at(view.topline - 1))
    view.topfill = view.topline == 1 and (#header + 1)
      or (view.topline == first + 1 and (dimensions.spacious and 2 or 1) or 0)
    vim.api.nvim_win_call(state.win, function()
      vim.fn.winrestview(view)
    end)
  end
end

local function replace_lines(lines, reset_undo)
  if not valid_buffer() then
    return
  end
  state.rendering = true
  local undolevels = vim.bo[state.buf].undolevels
  if reset_undo then
    vim.bo[state.buf].undolevels = -1
  end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  if reset_undo then
    vim.bo[state.buf].undolevels = undolevels
  end
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
  sync_undo_layout()
  local first = field_range(index)
  local line = current_lines()[first + 1] or ""
  vim.api.nvim_win_set_cursor(state.win, { first + 1, #line })
  state.selected = index
  render()
end

function M.edit_field()
  if not M.is_open() then
    return
  end
  focus_form()
  vim.cmd("startinsert")
end

-- Allow ordinary deletion within a field, including joining its own lines,
-- while stopping Backspace/Delete at the boundary with a neighbouring field.
local function masked_delete(key, direction)
  if not M.is_open() then
    return key
  end

  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local line = current_lines()[cursor[1]] or ""
  local column = cursor[2]
  local first, last = field_range(field_at(cursor[1] - 1))
  if direction == "backward" and column == 0 and cursor[1] == first + 1 then
    return ""
  end
  if direction == "forward" and column >= #line and cursor[1] == last then
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
  local line = selected_field()
  if line >= #state.fields then
    M.save("close")
    return
  end
  M.goto_field(line + 1)
end

---Cycle fields without changing editing mode.
function M.cycle_field(delta)
  if not M.is_open() or #state.fields == 0 then
    return
  end
  local line = selected_field()
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

  dialog.close_for_parent(form_win)

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
  sync_undo_layout()
  local lines = current_lines()
  refresh_dirty(lines)
  if state.structure_invalid then
    state.dirty = true
  end
  if opts.force == true or not state.dirty then
    return close_now()
  end
  if state.closing_prompt then
    return false
  end

  state.closing_prompt = true
  local expected_generation = state.generation
  local expected_buffer = state.buf
  dialog.select({ "Keep editing", "Discard draft" }, {
    prompt = "Discard draft",
    description = { "This card has unsaved changes." },
    danger = "Discard draft",
  }, function(choice)
    if state.generation ~= expected_generation or state.buf ~= expected_buffer or not M.is_open() then
      return
    end
    state.closing_prompt = false
    if choice == "Discard draft" then
      close_now()
      return
    end
    -- The dialog restores its parent for an explicit cancel. If the user
    -- moved to another window or tab, leave their focus there.
  end)
  return false
end

function M.context_help()
  if not M.is_open() then
    return
  end
  popup.open(key_help, {
    title = " " .. actions.title("form", form_capabilities()) .. " ",
    footer = actions.help_footer(),
    wrap = true,
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
  popup.set_lines(key_help, actions.help_lines("form", form_capabilities()))
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
    revision = state.change_revision,
  }
  render()
end

local function validate()
  local lines = current_lines()

  local values = {}
  local errors = {}
  local first_invalid
  for index, field in ipairs(state.fields) do
    local raw_value = draft_field_value(index, lines)
    local value = field.multiline and tostring(raw_value or "") or util.trim(raw_value)
    values[field.key] = value
    if field.required and util.isempty(value) then
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

local function normalize_save_result(callback_ok, result)
  if not callback_ok then
    return {
      ok = false,
      persisted = false,
      message = "Could not save flashcard: " .. tostring(result),
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

  return { ok = false, persisted = false, message = "Flashcard save callback must return a result table" }
end

local function invoke_save(values, mode)
  if not state.on_save then
    return { ok = true, persisted = true }
  end
  local callback_ok, result = pcall(state.on_save, values, {
    kind = state.kind,
    mode = mode,
    target = vim.deepcopy(state.target),
  })
  return normalize_save_result(callback_ok, result)
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
    label = util.path_label(path, state.config.path)
  end
  if not util.isempty(label) then
    return "Flashcard saved to " .. one_line(label)
  end
  return "Flashcard saved"
end

---Validate and save the composer. mode is close (the default) or new.
---The callback returns a structured { ok, persisted, path, message } result.
function M.save(mode)
  mode = mode == "new" and "new" or "close"
  if not valid_buffer() then
    return false
  end

  sync_undo_layout()

  if mode == "new" and not state.allow_save_new then
    set_error("Save-and-new is not available while editing a card", "mode")
    return false
  end

  if state.structure_invalid then
    state.field_lengths = vim.deepcopy(state.last_field_lengths)
    replace_lines(state.last_lines)
    state.structure_invalid = false
    state.valid_change = false
    refresh_dirty(state.last_lines)
    state.errors = {}
    state.validation_attempted = false
    set_error("Keep edits within a field; single-line fields cannot contain line breaks", "structure")
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
  replace_lines(state.initial_lines, true)
  state.undo_layouts = {}
  remember_layout(state.initial_lines)
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
  local row = state.selected
  state.field_lengths = vim.deepcopy(state.last_field_lengths)
  replace_lines(state.last_lines)
  state.structure_invalid = false
  state.valid_change = false
  refresh_dirty(state.last_lines)
  state.errors = {}
  state.validation_attempted = false
  state.status = {
    kind = "error",
    source = "structure",
    text = "Keep edits within a field; single-line fields cannot contain line breaks",
  }
  M.goto_field(math.min(row, #state.fields))
end

local function refresh_after_change()
  if not valid_buffer() then
    return
  end
  sync_undo_layout()
  if state.structure_invalid then
    restore_structure()
    return
  end

  local lines = current_lines()
  local valid_change = state.valid_change
  state.valid_change = false
  state.last_lines = copy_lines(lines)
  refresh_dirty(lines)
  if
    valid_change
    and state.status
    and state.status.kind == "error"
    and (state.status.revision or -1) < state.change_revision
  then
    state.status = nil
  end
  local callback_error_is_current = state.status
    and state.status.kind == "error"
    and state.status.source == "callback"
    and (state.status.revision or -1) >= state.change_revision
  if state.validation_attempted and not callback_error_is_current then
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
  local expected_generation = state.generation
  vim.schedule(function()
    if state.generation ~= expected_generation or state.buf ~= expected_buffer then
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
      state.change_revision = state.change_revision + 1
      local delta = new_last_line - old_last_line
      if not state.structure_invalid and delta ~= 0 then
        local index = field_at(first_line)
        if first_line == old_last_line and M.is_open() then
          -- o/P/p may insert precisely at the boundary between fields. The
          -- cursor identifies which field owns the inserted line.
          local cursor_field = state.insertion_field or state.selected
          local first, last = field_range(cursor_field)
          if first_line >= first and first_line <= last then
            index = cursor_field
          end
        end
        local first, last = field_range(index)
        if
          state.fields[index].multiline
          and first_line >= first
          and old_last_line <= last
          and state.field_lengths[index] + delta >= 1
        then
          state.field_lengths[index] = state.field_lengths[index] + delta
        else
          state.selected = index
          state.structure_invalid = true
        end
      end
      state.insertion_field = nil
      if not state.structure_invalid then
        state.valid_change = true
        remember_layout(current_lines())
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
    label = util.path_label(path, config.path)
  end
  return {
    path = path,
    label = label,
    chapter_label = opts.chapter_label or "Unfiled",
  }
end

local function configure_window(buf)
  state.win = vim.api.nvim_open_win(buf, true, window_config())
  require("neorg_flashcards.ui.window").configure(state.win)
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].spell = false
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].breakindent = true
  vim.wo[state.win].scrolloff = 0
  vim.wo[state.win].sidescrolloff = 3
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

  sync_undo_layout()
  local lines = current_lines()
  refresh_dirty(lines)
  local has_draft = state.dirty or state.structure_invalid
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
  local expected_generation = state.generation
  vim.schedule(function()
    if state.generation == expected_generation and state.buf == expected_buf and M.is_open() then
      M.close()
    end
  end)
end

local function configure_keymaps(buf)
  for _, binding in ipairs(actions.available_bindings("form", form_capabilities())) do
    local action_name = binding.action
    vim.keymap.set(binding.mode, binding.key, function()
      dispatch(action_name)
    end, { buffer = buf, silent = true, nowait = true, desc = binding.description })
  end

  -- Preserve native o/O and linewise paste while recording which input owns
  -- an insertion exactly between two fields. Neovim may move the cursor to
  -- the new row before on_lines runs.
  for _, key in ipairs({ "o", "O", "p", "P" }) do
    vim.keymap.set("n", key, function()
      sync_undo_layout()
      state.insertion_field = selected_field()
      return key
    end, { buffer = buf, expr = true, silent = true, desc = "Edit inside the selected flashcard field" })
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
end

local function configure_autocmds(buf)
  state.augroup = vim.api.nvim_create_augroup("NeorgFlashcardsForm" .. buf, { clear = true })
  watch_form_window(state.augroup, state.win)
  vim.api.nvim_create_autocmd({ "BufEnter", "InsertEnter" }, {
    group = state.augroup,
    buffer = buf,
    callback = function()
      -- Completion and pairing plugins may attach after the form opens.
      -- Keep field navigation and deletion boundaries local to this buffer.
      if state.buf == buf then
        configure_keymaps(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = state.augroup,
    buffer = buf,
    callback = function()
      if M.is_open() and not state.structure_invalid then
        state.selected = selected_field()
        render()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      local expected_generation = state.generation
      vim.schedule(function()
        if state.generation == expected_generation then
          resize()
        end
      end)
    end,
  })
end

function M.open(config, kind, opts)
  opts = opts or {}
  local card_schema = schema.for_kind(config, kind)
  if not card_schema then
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

  local fields = schema.composer_fields(config, kind)
  if #fields == 0 then
    util.notify("Flashcard kind has no editable fields: " .. kind, vim.log.levels.ERROR)
    return false
  end

  local source_buf = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  generation_counter = generation_counter + 1
  state = fresh_state(generation_counter)
  state.kind = kind
  state.kind_label = card_schema.label or kind
  state.title = opts.title
  state.on_save = opts.on_save
  state.on_close = opts.on_close
  state.config = config
  state.fields = vim.deepcopy(fields)
  for _, field in ipairs(card_schema.fields or {}) do
    state.roles[field.key] = field.key == card_schema.front and "Front" or (field.reveal and "Answer" or "Details")
  end
  state.initial_values = vim.deepcopy(opts.initial_values or {})
  state.allow_save_new = opts.allow_save_new ~= false
  state.edit_mode = opts.edit == true
  state.return_win = source_win
  state.target = infer_target(config, opts, source_buf)
  state.initial_lines = default_lines()
  state.last_lines = copy_lines(state.initial_lines)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  -- Keep the draft alive long enough for WinClosed to recover native :q or
  -- <C-w>c closes. close_now() deletes it after an intentional final close.
  vim.bo[buf].bufhidden = "hide"
  vim.b[buf].completion = false
  vim.bo[buf].filetype = "neorg_flashcards_form"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].textwidth = 0
  vim.bo[buf].wrapmargin = 0
  state.buf = buf

  replace_lines(state.initial_lines, true)
  remember_layout(state.initial_lines)
  attach_guard(buf)
  configure_window(buf)
  configure_autocmds(buf)

  configure_keymaps(buf)

  render()
  M.goto_field(1)
  vim.cmd("startinsert!")
  return true
end

return M
