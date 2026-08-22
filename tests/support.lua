local M = {}

function M.assert_true(value, message)
  if not value then
    error(message or "expected truthy value", 2)
  end
end

function M.assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      string.format(
        "%s\nexpected: %s\nactual: %s",
        message or "values differ",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

function M.assert_contains(value, pattern, message)
  if not tostring(value):find(pattern, 1, true) then
    error(string.format("%s\nmissing: %s\nvalue: %s", message or "pattern not found", pattern, tostring(value)), 2)
  end
end

function M.canonical_path(path)
  return vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
end

function M.current_popup()
  local bufnr = vim.api.nvim_get_current_buf()
  M.assert_equal(vim.bo[bufnr].buftype, "nofile", "plugin opens a nofile popup")
  M.assert_equal(vim.bo[bufnr].filetype, "norg", "plugin popup uses the norg filetype")
  return bufnr, table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

function M.current_tab_text()
  local panes = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    table.insert(panes, table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
  end
  return table.concat(panes, "\n")
end

function M.assert_buffer_maps(bufnr, expected)
  local maps = {}
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    maps[map.lhs] = true
  end

  for _, lhs in ipairs(expected) do
    M.assert_true(maps[lhs], "missing popup-local mapping: " .. lhs)
  end
end

function M.window_footer(win)
  local chunks = vim.api.nvim_win_get_config(win or 0).footer or {}
  local values = {}
  for _, chunk in ipairs(chunks) do
    if type(chunk) == "table" then
      table.insert(values, tostring(chunk[1] or ""))
    else
      table.insert(values, tostring(chunk))
    end
  end
  return table.concat(values)
end

function M.decoration_text(bufnr)
  local values = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    local details = mark[4] or {}
    for _, chunk in ipairs(details.virt_text or {}) do
      table.insert(values, tostring(chunk[1] or ""))
    end
    for _, line in ipairs(details.virt_lines or {}) do
      for _, chunk in ipairs(line) do
        table.insert(values, tostring(chunk[1] or ""))
      end
    end
  end
  return table.concat(values, "\n")
end

return M
