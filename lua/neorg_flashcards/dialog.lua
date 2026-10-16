-- Small workspace dialogs. These never replace the user's global vim.ui hooks.
local canvas = require("neorg_flashcards.ui.canvas")
local highlights = require("neorg_flashcards.highlights")
local popup = require("neorg_flashcards.popup")
local M = {}
local H = highlights.groups.desk
local ns = vim.api.nvim_create_namespace("neorg_flashcards_dialog")
local active
local config = {}

local function text(value)
  return (tostring(value or ""):gsub("[%c]", " "))
end

local function dimensions(s, height)
  local width = math.max(1, math.min(56, vim.o.columns - 4))
  height = math.max(1, math.min(height, vim.o.lines - 6))
  local separator = config.ui and config.ui.ascii and " | " or " · "
  local footer = s.input and ("Enter confirm" .. separator .. "Esc normal / q cancel")
    or ("j/k move" .. separator .. "Enter choose" .. separator .. (s.opts.back and "h back" or "q cancel"))
  if vim.fn.strdisplaywidth(footer) > width - 2 then
    footer = s.input and "Enter confirm | Esc, q cancel" or "j/k | Enter | q cancel"
  end
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = config.ui and config.ui.ascii and { "+", "-", "+", "|", "+", "-", "+", "|" } or "rounded",
    title = { { " " .. canvas.fit(text(s.opts.prompt):gsub(":%s*$", ""), width - 4) .. " ", H.title } },
    title_pos = "left",
    footer = { { " " .. canvas.fit(footer, width - 2) .. " ", H.muted } },
    footer_pos = "center",
    zindex = 80,
  }
end

local function finish(s, value, index, restore)
  if s.done then
    return
  end
  s.done = true
  if active == s then
    active = nil
  end
  pcall(vim.api.nvim_del_augroup_by_id, s.group)
  local owns_window = popup.is_open(s)
  if owns_window and vim.api.nvim_get_current_win() == s.win then
    vim.cmd.stopinsert()
  end
  if not owns_window then
    s.win = nil
  end
  popup.close(s)
  if restore ~= false and vim.api.nvim_get_current_tabpage() == s.tab and vim.api.nvim_win_is_valid(s.parent) then
    vim.api.nvim_set_current_win(s.parent)
  end
  s.callback(value, index)
end

function M.close()
  if active then
    finish(active, nil)
  end
end

function M.close_for_parent(win)
  if active and active.parent == win then
    finish(active, nil)
  end
end

function M.setup(opts)
  M.close()
  config = opts or {}
end

local function description(s, width)
  local result = { "" }
  local paragraphs = s.opts.description or {}
  if type(paragraphs) == "string" then
    paragraphs = { paragraphs }
  end
  for _, paragraph in ipairs(paragraphs) do
    for _, line in ipairs(canvas.wrap(text(paragraph), math.max(1, width - 4))) do
      table.insert(result, "  " .. line)
    end
  end
  if #result > 1 then
    table.insert(result, "")
  end
  return result
end

local function render(s)
  if s.done or not popup.is_open(s) then
    return
  end
  local width = dimensions(s, 1).width
  local lines = description(s, width)
  vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  if s.input then
    local above = {}
    for _, line in ipairs(lines) do
      table.insert(above, { { line, H.ink } })
    end
    local values = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
    local errors = {}
    if s.error then
      for _, line in ipairs(canvas.wrap(s.error, math.max(1, width - 4))) do
        table.insert(errors, { { "  " .. line, H.again } })
      end
    end
    local height = #lines + #values + 2 + #errors
    for _, value in ipairs(values) do
      height = height + math.floor(vim.fn.strdisplaywidth(value) / math.max(1, width - 4))
    end
    vim.api.nvim_win_set_config(s.win, dimensions(s, height))
    vim.api.nvim_buf_set_extmark(s.buf, ns, 0, 0, {
      virt_lines = above,
      virt_lines_above = true,
      virt_text = { { "  > ", H.accent } },
      virt_text_pos = "inline",
      right_gravity = false,
      line_hl_group = highlights.groups.form.active,
    })
    if #errors > 0 then
      vim.api.nvim_buf_set_extmark(s.buf, ns, #values - 1, 0, {
        virt_lines = errors,
      })
    end
    vim.api.nvim_win_call(s.win, function()
      local view = vim.fn.winsaveview()
      view.topfill = view.topline == 1 and #above or 0
      vim.fn.winrestview(view)
    end)
    return
  end

  s.rows, s.ends = {}, {}
  local first_item = #lines + 1
  for index, item in ipairs(s.items) do
    s.rows[index] = #lines + 1
    local label = s.opts.format_item and s.opts.format_item(item) or tostring(item)
    for offset, line in ipairs(canvas.wrap(text(label), math.max(1, width - 5))) do
      table.insert(lines, (offset == 1 and index == s.selected and " > " or "   ") .. line)
    end
    s.ends[index] = #lines
  end
  if #s.items == 0 then
    table.insert(lines, "  No items")
  end
  table.insert(lines, "")
  vim.api.nvim_win_set_config(s.win, dimensions(s, #lines))
  popup.set_lines(s, lines)
  for row = 1, first_item - 1 do
    vim.api.nvim_buf_add_highlight(s.buf, ns, H.ink, row - 1, 0, -1)
  end
  for index, row in ipairs(s.rows) do
    local hl = index == s.selected and H.selected or (s.opts.danger == s.items[index] and H.again or H.ink)
    for line = row, s.ends[index] do
      vim.api.nvim_buf_add_highlight(s.buf, ns, hl, line - 1, 1, -1)
    end
  end
  s.moving = true
  vim.api.nvim_win_set_cursor(s.win, { s.rows[s.selected] or first_item, math.min(1, #lines[first_item]) })
  s.moving = false
end

local function open(opts, callback, input, items)
  M.close()
  vim.cmd.stopinsert()
  local s = {
    opts = opts or {},
    callback = callback,
    input = input,
    items = items,
    selected = 1,
    parent = vim.api.nvim_get_current_win(),
    tab = vim.api.nvim_get_current_tabpage(),
  }
  active = s
  s.group = vim.api.nvim_create_augroup("neorg_flashcards_dialog", { clear = true })
  local size = dimensions(s, 3)
  popup.open(s, {
    width = size.width,
    height = size.height,
    border = size.border,
    title = size.title,
    footer = size.footer,
    title_pos = "left",
    zindex = size.zindex,
    completion = false,
    filetype = "neorg_flashcards_dialog",
  })
  vim.wo[s.win].winhighlight = "Normal:" .. H.ink .. ",FloatBorder:" .. H.edge
  vim.wo[s.win].scrolloff = 0
  vim.wo[s.win].sidescrolloff = 0
  vim.wo[s.win].cursorline = false
  vim.wo[s.win].wrap = input == true
  vim.bo[s.buf].textwidth = 0
  vim.bo[s.buf].undofile = false
  vim.bo[s.buf].modeline = false
  local function map(mode, keys, fn)
    for _, key in ipairs(keys) do
      vim.keymap.set(mode, key, fn, { buffer = s.buf, silent = true, nowait = true })
    end
  end
  local function cancel()
    finish(s, nil)
  end
  local function submit()
    if input then
      local values = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
      s.error_value = table.concat(values, "\n")
      if #values ~= 1 then
        s.error = "Use a single line."
        render(s)
        return
      end
      s.error = s.opts.validate and s.opts.validate(values[1]) or nil
      if s.error then
        render(s)
        return
      end
      finish(s, values[1])
    elseif s.items[s.selected] ~= nil then
      finish(s, s.items[s.selected], s.selected)
    end
  end
  map("n", { "q", "<Esc>" }, cancel)
  map("n", { "<CR>" }, submit)
  map({ "n", "i" }, { "<C-c>" }, cancel)
  if input then
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, { text(s.opts.default) })
    map("i", { "<CR>" }, submit)
    map("i", { "<Esc>" }, function()
      vim.cmd.stopinsert()
    end)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = s.group,
      buffer = s.buf,
      callback = function()
        local value = table.concat(vim.api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
        if value ~= s.error_value then
          s.error = nil
        end
        render(s)
      end,
    })
  else
    local function move(delta)
      s.selected = math.max(1, math.min(#s.items, s.selected + delta * vim.v.count1))
      render(s)
    end
    map("n", { "j", "<Down>", "<C-j>" }, function()
      move(1)
    end)
    map("n", { "k", "<Up>", "<C-k>" }, function()
      move(-1)
    end)
    map("n", { "<C-d>", "<PageDown>" }, function()
      move(math.max(1, math.floor(vim.api.nvim_win_get_height(s.win) / 2)))
    end)
    map("n", { "<C-u>", "<PageUp>" }, function()
      move(-math.max(1, math.floor(vim.api.nvim_win_get_height(s.win) / 2)))
    end)
    map("n", { "gg" }, function()
      s.selected = 1
      render(s)
    end)
    map("n", { "G" }, function()
      s.selected = math.max(1, #s.items)
      render(s)
    end)
    map("n", { "l", "<Right>" }, submit)
    map("n", { "h", "<Left>", "<BS>" }, function()
      finish(s, nil)
      if s.opts.back then
        s.opts.back()
      end
    end)
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = s.group,
      buffer = s.buf,
      callback = function()
        if s.done or s.moving or not popup.is_open(s) then
          return
        end
        local row = vim.api.nvim_win_get_cursor(s.win)[1]
        for index, start in ipairs(s.rows) do
          if row >= start and row <= s.ends[index] and s.selected ~= index then
            s.selected = index
            render(s)
            break
          end
        end
      end,
    })
  end
  vim.api.nvim_create_autocmd("VimResized", {
    group = s.group,
    callback = function()
      render(s)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave", "BufWipeout" }, {
    group = s.group,
    buffer = s.buf,
    callback = function()
      vim.schedule(function()
        if not s.done and (not popup.is_open(s) or vim.api.nvim_get_current_win() ~= s.win) then
          finish(s, nil, nil, false)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = s.group,
    callback = function(event)
      if tonumber(event.match) == s.parent or tonumber(event.match) == s.win then
        vim.schedule(function()
          finish(s, nil, nil, false)
        end)
      end
    end,
  })
  render(s)
  if input then
    vim.api.nvim_win_set_cursor(s.win, { 1, #text(s.opts.default) })
    vim.cmd.startinsert({ bang = true })
  end
end

function M.select(items, opts, callback)
  open(opts, callback, false, items)
end

function M.input(opts, callback)
  open(opts, callback, true)
end

return M
