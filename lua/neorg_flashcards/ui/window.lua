local M = {}

-- App drawings are display cells, not editable Neorg source. Apply only local
-- options: the user's whitespace and conceal settings still belong to notes.
function M.configure(win)
  for name, value in pairs({
    list = false,
    conceallevel = 0,
    concealcursor = "",
    spell = false,
    foldenable = false,
    colorcolumn = "",
    cursorcolumn = false,
  }) do
    vim.wo[win][name] = value
  end
end

return M
