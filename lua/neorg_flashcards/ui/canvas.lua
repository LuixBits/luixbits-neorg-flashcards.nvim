-- Display-cell layout, with byte-indexed highlight spans at the API boundary.
local M = {}
local ASCII_GLYPHS = { ["█"] = "#", ["░"] = ".", ["▒"] = ":", ["▓"] = "#", ["●"] = "*" }

function M.fit(value, width)
  width = math.max(0, width)
  local result, used = {}, 0
  for _, char in ipairs(vim.fn.split(tostring(value or ""), "\\zs")) do
    local size = vim.fn.strdisplaywidth(char, used)
    if used + size > width then
      break
    end
    table.insert(result, char)
    used = used + size
  end
  return table.concat(result), used
end

function M.pad(value, width)
  local text, used = M.fit(value, width)
  return text .. string.rep(" ", math.max(0, width - used))
end

function M.wrap(value, width)
  width = math.max(1, width)
  local lines = {}
  for _, original in ipairs(vim.split(tostring(value or ""), "\n", { plain = true })) do
    local rest = original:gsub("\t", "    ")
    repeat
      local part = M.fit(rest, width)
      if #part < #rest then
        local boundary = part:match("^.*()%s")
        if boundary and boundary > #part / 2 then
          part = part:sub(1, boundary)
        end
      end
      if part == "" and rest ~= "" then
        -- A single wide glyph cannot fit a one-cell viewport.
        part = vim.fn.strcharpart(rest, 0, 1)
        rest = rest:sub(#part + 1)
        part = "?"
      else
        rest = rest:sub(#part + 1)
      end
      table.insert(lines, part)
    until rest == ""
  end
  return lines
end

function M.new(viewport_width, ascii)
  local c = { width = math.max(1, viewport_width), rows = {}, height = 0, ascii = ascii }

  function c:put(row, col, text, hl)
    if row < 1 then
      return
    end
    self.height = math.max(self.height, row)
    self.rows[row] = self.rows[row] or {}
    local cells = self.rows[row]
    for _, char in ipairs(vim.fn.split(tostring(text), "\\zs")) do
      if self.ascii then
        char = ASCII_GLYPHS[char] or char
      end
      local size = vim.fn.strdisplaywidth(char, math.max(0, col - 1))
      if size == 0 and cells[col - 1] then
        cells[col - 1].text = cells[col - 1].text .. char
      elseif col >= 1 and col + size - 1 <= self.width then
        cells[col] = { text = char, hl = hl }
        for offset = 1, size - 1 do
          cells[col + offset] = { text = "", hl = hl }
        end
      end
      col = col + size
      if col > self.width then
        break
      end
    end
  end

  function c:box(row, col, width_, height, hl, title)
    local width = math.min(width_, self.width - col + 1)
    if width < 2 or height < 2 then
      return
    end
    local g = self.ascii and { "+", "-", "+", "|", "+", "+" } or { "╭", "─", "╮", "│", "╰", "╯" }
    self:put(row, col, g[1] .. string.rep(g[2], width - 2) .. g[3], hl)
    for y = row + 1, row + height - 2 do
      self:put(y, col, g[4], hl)
      self:put(y, col + width - 1, g[4], hl)
    end
    self:put(row + height - 1, col, g[5] .. string.rep(g[2], width - 2) .. g[6], hl)
    if title then
      self:put(row, col + 2, M.fit(" " .. title .. " ", width - 4), hl)
    end
  end

  function c:finish()
    local lines, spans = {}, {}
    for row = 1, self.height do
      local cells, chunks, byte = self.rows[row] or {}, {}, 0
      local active
      for col = 1, self.width do
        local cell = cells[col] or { text = " " }
        if not active or active.hl ~= cell.hl then
          if active and active.hl and active.end_col > active.start_col then
            table.insert(spans, active)
          end
          active = { line = row, start_col = byte, end_col = byte, hl = cell.hl }
        end
        table.insert(chunks, cell.text)
        byte = byte + #cell.text
        active.end_col = byte
      end
      if active and active.hl and active.end_col > active.start_col then
        table.insert(spans, active)
      end
      lines[row] = table.concat(chunks)
    end
    return lines, spans
  end
  return c
end

return M
