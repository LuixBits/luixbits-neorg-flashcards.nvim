local M = {}

local counter = 0

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function digest(value)
  if vim and vim.fn and vim.fn.sha256 then
    return vim.fn.sha256(value)
  end

  -- Neovim always provides sha256, but keeping a dependency-free fallback
  -- makes the helper usable by lightweight Lua tooling too.
  local left = tostring(os.time()):gsub("[^%da-fA-F]", "")
  local right = tostring(value):gsub("[^%da-fA-F]", "")
  return (left .. right .. string.rep("0", 32)):sub(1, 32)
end

function M.card_id(card)
  local values = (card and card.values) or {}
  local value = trim(values.id)
  if value == "" then
    value = trim(card and card.id)
  end
  return value ~= "" and value or nil
end

function M.is_valid(id)
  id = trim(id)
  return #id > 0 and #id <= 128 and id:match("^[%w][%w_.:-]*$") ~= nil
end

-- IDs are deliberately opaque. Their only contract is collection-wide
-- uniqueness and stability once written into a card block.
function M.generate(used)
  used = used or {}

  while true do
    counter = counter + 1
    local uv = vim and (vim.uv or vim.loop) or nil
    local clock = uv and uv.hrtime and uv.hrtime() or 0
    local entropy = table.concat({ os.time(), clock, counter, tostring({}) }, ":")
    local id = "fc_" .. digest(entropy):sub(1, 24)
    if not used[id] then
      return id
    end
  end
end

return M
