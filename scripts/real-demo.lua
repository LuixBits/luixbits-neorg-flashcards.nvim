local clock = 900

local function later(delay, callback)
  clock = clock + delay
  vim.defer_fn(callback, clock)
end

local function input(keys)
  vim.api.nvim_input(vim.api.nvim_replace_termcodes(keys, true, false, true))
end

local function paste(value)
  vim.api.nvim_paste(value, false, -1)
end

local function command(value)
  later(0, function()
    vim.cmd(value)
  end)
end

local function press(keys)
  later(0, function()
    input(keys)
  end)
end

local function type_text(value)
  for index = 0, vim.fn.strchars(value) - 1 do
    local char = vim.fn.strcharpart(value, index, 1)
    later(105, function()
      paste(char)
    end)
  end
end

local function answer(value)
  type_text(value)
  later(320, function()
    input("<CR>")
  end)
  later(520, function() end)
end

vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.wrap = true

later(800, function()
  pcall(vim.cmd, "NvimTreeClose")
end)

command("NeorgFlashcardAdd")
later(950, function() end)
answer("言語")
answer("げんご")
answer("languages")
answer("noun")
answer("demo vocab")

later(700, function() end)
command("NeorgFlashcardAdd")
later(950, function() end)
answer("リナックス")
answer("")
answer("linux")
answer("katakana loanword")
answer("demo tech")

later(1000, function() end)
command("NeorgFlashcardReviewFile")
later(350, function()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].swapfile = false
      vim.api.nvim_win_set_buf(win, buf)
      break
    end
  end
end)
later(1300, function() end)
press("<Space>")
later(1300, function() end)
press("2")
later(1200, function() end)
press("<Space>")
later(1300, function() end)
press("3")
later(1000, function() end)
press("q")

later(700, function() end)
command("NeorgFlashcardReviewScore good")
later(1200, function() end)
press("<Space>")
later(1300, function() end)
press("q")

later(800, function()
  vim.cmd("qa!")
end)
