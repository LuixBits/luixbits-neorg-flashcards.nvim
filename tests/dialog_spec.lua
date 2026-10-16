return function(T)
  local dialog = require("neorg_flashcards.dialog")
  local truth, equal, contains = T.assert_true, T.assert_equal, T.assert_contains
  local select, input = vim.ui.select, vim.ui.input
  local columns, lines = vim.o.columns, vim.o.lines
  vim.o.columns, vim.o.lines = 100, 32
  local function keys(value)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt", false)
  end
  local function text()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  end
  local function drain()
    vim.wait(30, function()
      return false
    end)
  end
  dialog.setup({ ui = { ascii = true } })
  local parent = vim.api.nvim_get_current_win()
  local choices = { { name = "Cancel" }, { name = "Remove 日本語" } }
  local called, value, index = 0
  local function chosen(item, n)
    called, value, index = called + 1, item, n
  end
  local function open()
    dialog.select(choices, {
      prompt = "Remove chapter",
      description = { "Lesson 1", "Cards and history are kept." },
      format_item = function(item)
        return item.name
      end,
    }, chosen)
  end
  open()
  equal(vim.bo.filetype, "neorg_flashcards_dialog")
  truth(not vim.wo.list and vim.wo.conceallevel == 0, "dialogs isolate whitespace and conceal settings")
  truth(vim.b.completion == false, "dialog inputs opt out of completion plugins")
  equal(vim.api.nvim_win_get_config(0).border[1], "+", "ASCII follows the existing setting")
  contains(text(), "Cards and history are kept.")
  keys("<CR>")
  equal(value, choices[1], "Enter initially chooses Cancel")
  equal(index, 1)
  equal(vim.api.nvim_get_current_win(), parent, "confirm returns to its originating pane")
  equal(called, 1)
  drain()
  equal(called, 1, "closing autocmds cannot invoke the callback twice")

  open()
  keys("<Down><CR>")
  equal(value, choices[2], "arrows choose the actual object, not its label")
  equal(index, 2)
  open()
  keys("j<C-k><CR>")
  equal(value, choices[1], "Vim and Ctrl-key navigation agree")
  open()
  keys("<Esc>")
  equal(value, nil, "Escape cancels without selecting an item")
  open()
  vim.cmd("close")
  drain()
  equal(value, nil, "native close cancels")

  dialog.select({ "Continue" }, { prompt = "First" }, function(item)
    if item then
      dialog.select({ "Next" }, { prompt = "Second" }, chosen)
    end
  end)
  keys("<CR>")
  drain()
  contains(text(), "Next", "a subsequent dialog survives the previous one's close events")
  keys("q")

  local back = 0
  dialog.select({ "Child" }, {
    prompt = "Submenu",
    back = function()
      back = back + 1
    end,
  }, chosen)
  keys("h")
  equal(back, 1, "h goes back exactly once")
  equal(value, nil)

  open()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(parent)
  drain()
  truth(not vim.api.nvim_win_is_valid(win), "leaving a dialog cancels and removes it")
  equal(vim.api.nvim_get_current_win(), parent, "cancellation never takes focus back")

  open()
  win = vim.api.nvim_get_current_win()
  local replacement = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, replacement)
  drain()
  truth(vim.api.nvim_win_is_valid(win), "cleanup does not close a window now displaying another buffer")
  equal(vim.api.nvim_win_get_buf(win), replacement)
  equal(value, nil)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(replacement, { force = true })

  local labels = {}
  for n = 1, 20 do
    labels[n] = { name = string.rep("日本語", 10) .. " " .. n }
  end
  dialog.select(labels, {
    prompt = "Long chapter names",
    format_item = function(item)
      return item.name
    end,
  }, chosen)
  keys("G")
  for _, size in ipairs({ { 40, 16 }, { 60, 20 }, { 100, 32 } }) do
    vim.o.columns, vim.o.lines = size[1], size[2]
    vim.api.nvim_exec_autocmds("VimResized", {})
    local cfg = vim.api.nvim_win_get_config(0)
    truth(cfg.width + 2 <= size[1] and cfg.height + 2 <= size[2], "dialog fits after resize")
  end
  keys("<CR>")
  equal(value, labels[20], "resize preserves the selected item")
  dialog.select({}, { prompt = "Empty" }, chosen)
  contains(text(), "No items")
  keys("<CR>q")
  equal(value, nil, "empty menus cannot confirm a nonexistent choice")

  dialog.input({ prompt = "Rename chapter", default = "Lesson 日本語", description = { "Japanese" } }, chosen)
  vim.cmd.stopinsert()
  equal(text(), "Lesson 日本語", "input holds only the editable value")
  contains(T.decoration_text(0), "Japanese", "input context is visible but cannot be edited")
  keys("gg0C新しい章<Esc><CR>")
  equal(value, "新しい章", "normal editing and Unicode survive submission")
  dialog.input({
    prompt = "Required",
    default = "",
    validate = function(v)
      return v == "" and "Enter a name." or nil
    end,
  }, chosen)
  vim.cmd.stopinsert()
  local input_win = vim.api.nvim_get_current_win()
  keys("<CR>")
  drain()
  truth(vim.api.nvim_win_is_valid(input_win), "validation leaves the input open")
  contains(T.decoration_text(0), "Enter a name.")
  keys("iLesson 3<Esc><CR>")
  equal(value, "Lesson 3", "an invalid value can be corrected in place")
  dialog.input({ prompt = "Rename", default = "Original" }, chosen)
  vim.cmd.stopinsert()
  keys("0CChanged<Esc>q")
  equal(value, nil, "q in Normal mode discards the input")

  dialog.input({ prompt = "One line" }, chosen)
  vim.cmd.stopinsert()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
  keys("<CR>")
  contains(T.decoration_text(0), "Use a single line.", "multiline paste is not silently flattened")
  keys("q")

  vim.cmd("vsplit")
  local disposable = vim.api.nvim_get_current_win()
  open()
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(disposable, true)
  drain()
  truth(not vim.api.nvim_win_is_valid(win), "closing a dialog's parent cancels it")
  equal(value, nil)
  equal(vim.ui.select, select, "the editor's global picker is unchanged")
  equal(vim.ui.input, input, "the editor's global input is unchanged")
  dialog.setup({})
  vim.o.columns, vim.o.lines = columns, lines
end
