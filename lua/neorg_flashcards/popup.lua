local M = {}

function M.is_open(state)
  return state.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.win ~= nil
    and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_buf(state.win) == state.buf
end

function M.open(state, opts)
  if M.is_open(state) then
    return true
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win, state.buf = nil, nil

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = opts.filetype or "norg"
  vim.bo[state.buf].swapfile = false

  local width = opts.width
    or math.min(
      opts.max_width or 84,
      math.max(opts.min_width or 52, math.floor(vim.o.columns * (opts.width_ratio or 0.72)))
    )
  local height = opts.height
    or math.min(
      opts.max_height or 24,
      math.max(opts.min_height or 10, math.floor(vim.o.lines * (opts.height_ratio or 0.55)))
    )
  width = math.max(1, math.min(width, vim.o.columns - 4))
  height = math.max(1, math.min(height, vim.o.lines - 4))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = opts.title,
    title_pos = "center",
    footer = opts.footer,
    footer_pos = "center",
    style = "minimal",
  })

  for _, map in ipairs(opts.maps or {}) do
    vim.keymap.set("n", map[1], map[2], {
      buffer = state.buf,
      silent = true,
      nowait = true,
      desc = map[3],
    })
  end
  return true
end

function M.close(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

function M.set_lines(state, lines)
  if not M.is_open(state) then
    return false, "popup buffer is no longer displayed in its window"
  end
  local ok, err = pcall(function()
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
  end)
  return ok, err
end

return M
