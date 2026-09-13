-- Small, UTF-8-aware answer comparisons for the review UI. This module only
-- describes the comparison; callers decide how to render or highlight it.

local util = require("neorg_flashcards.util")

local M = {}

local GAP = "·"
local MAX_COMPARE_CHARS = 512
local MAX_DISPLAY_CHARS = 160

M.MAX_COMPARE_CHARS = MAX_COMPARE_CHARS

local function join(chars, first, last)
  if first > last then
    return ""
  end
  return table.concat(chars, "", first, last)
end

function M.normalize(value)
  return util.trim(value):lower():gsub("%s+", " ")
end

local function aligned_change(actual, expected)
  local actual_chars = util.utf8_chars(actual)
  local expected_chars = util.utf8_chars(expected)
  local prefix = 0
  local shared = math.min(#actual_chars, #expected_chars)
  while prefix < shared and actual_chars[prefix + 1] == expected_chars[prefix + 1] do
    prefix = prefix + 1
  end

  local suffix = 0
  while
    suffix < #actual_chars - prefix
    and suffix < #expected_chars - prefix
    and actual_chars[#actual_chars - suffix] == expected_chars[#expected_chars - suffix]
  do
    suffix = suffix + 1
  end

  local prefix_text = join(actual_chars, 1, prefix)
  local suffix_text = join(actual_chars, #actual_chars - suffix + 1, #actual_chars)
  local actual_middle = join(actual_chars, prefix + 1, #actual_chars - suffix)
  local expected_middle = join(expected_chars, prefix + 1, #expected_chars - suffix)
  if actual_middle == "" then
    actual_middle = GAP
  end
  if expected_middle == "" then
    expected_middle = GAP
  end

  local start_col = #prefix_text
  return {
    actual = {
      text = prefix_text .. actual_middle .. suffix_text,
      start_col = start_col,
      end_col = start_col + #actual_middle,
    },
    expected = {
      text = prefix_text .. expected_middle .. suffix_text,
      start_col = start_col,
      end_col = start_col + #expected_middle,
    },
  }
end

local function clipped(text)
  local chars = util.utf8_chars(text)
  if #chars <= MAX_DISPLAY_CHARS then
    return text
  end
  return join(chars, 1, MAX_DISPLAY_CHARS) .. "…"
end

---Compare two answers after the same case and whitespace normalization used by
---review matching. Changed columns are zero-based byte offsets suitable for
---Neovim extmarks. A middle dot represents text missing from one side.
---@param actual any
---@param expected any
---@return table comparison
function M.compare(actual, expected)
  local raw_actual = tostring(actual or "")
  local raw_expected = tostring(expected or "")
  local normalized_actual = M.normalize(raw_actual)
  local normalized_expected = M.normalize(raw_expected)
  local actual_length = #util.utf8_chars(normalized_actual)
  local expected_length = #util.utf8_chars(normalized_expected)
  local exact = normalized_actual == normalized_expected
  local truncated = actual_length > MAX_COMPARE_CHARS or expected_length > MAX_COMPARE_CHARS
  local distance = exact and 0 or (truncated and math.huge or util.levenshtein(normalized_actual, normalized_expected))
  local threshold = math.max(1, math.floor(expected_length * 0.2))
  local close = actual_length > 0 and distance <= threshold and distance < math.max(actual_length, expected_length)
  local status = exact and "exact" or (close and "close" or "miss")
  local aligned
  if truncated then
    local actual_text = clipped(normalized_actual)
    local expected_text = clipped(normalized_expected)
    aligned = {
      actual = { text = actual_text, start_col = 0, end_col = #actual_text },
      expected = { text = expected_text, start_col = 0, end_col = #expected_text },
    }
  elseif distance == 0 then
    aligned = {
      actual = { text = normalized_actual },
      expected = { text = normalized_expected },
    }
  else
    aligned = aligned_change(normalized_actual, normalized_expected)
  end

  return {
    status = status,
    distance = distance,
    threshold = threshold,
    truncated = truncated,
    raw_actual = raw_actual,
    raw_expected = raw_expected,
    actual = aligned.actual,
    expected = aligned.expected,
  }
end

---Return the closest non-empty expected answer. Ties preserve candidate order.
---@param actual any
---@param candidates any[]
---@return table? comparison
---@return integer? candidate_index
function M.best(actual, candidates)
  local best, best_index
  for index, expected in ipairs(candidates or {}) do
    if M.normalize(expected) ~= "" then
      local comparison = M.compare(actual, expected)
      if not best or comparison.distance < best.distance then
        best, best_index = comparison, index
      end
    end
  end
  return best, best_index
end

return M
