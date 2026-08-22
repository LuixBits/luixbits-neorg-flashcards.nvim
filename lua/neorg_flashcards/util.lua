local M = {}

function M.notify(message, level)
  if message and message ~= "" then
    vim.notify(message, level or vim.log.levels.INFO, { title = "Neorg flashcards" })
  end
end

function M.trim(value)
  local result = tostring(value or "")
  result = result:gsub("^%s+", "")
  result = result:gsub("%s+$", "")
  return result
end

function M.isempty(value)
  return M.trim(value) == ""
end

function M.fname(path)
  return vim.fn.fnameescape(path)
end

function M.canonical_path(path)
  if M.isempty(path) then
    return ""
  end

  local normalized = vim.fs.normalize(path)
  return vim.fs.normalize(vim.fn.resolve(normalized))
end

function M.pin_directory(path)
  local lexical = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  local canonical = M.canonical_path(lexical)
  local stat = (vim.uv or vim.loop).fs_stat(canonical)
  if not stat or stat.type ~= "directory" then
    return nil, "configured flashcards_dir is not a directory"
  end
  return {
    lexical = lexical,
    canonical = canonical,
    dev = stat.dev,
    ino = stat.ino,
  }
end

function M.resolve_pinned_directory(root)
  if type(root) == "string" then
    return M.canonical_path(vim.fn.fnamemodify(vim.fn.expand(root), ":p"))
  end
  if type(root) ~= "table" or M.isempty(root.lexical) or M.isempty(root.canonical) then
    return nil, "configured flashcards_dir identity is missing"
  end

  local current = M.canonical_path(root.lexical)
  if current ~= root.canonical then
    return nil, "configured flashcards_dir changed since setup; run setup again"
  end
  local stat = (vim.uv or vim.loop).fs_stat(current)
  if not stat or stat.type ~= "directory" then
    return nil, "configured flashcards_dir is no longer the setup directory"
  end
  if
    root.dev ~= nil
    and root.ino ~= nil
    and stat.dev ~= nil
    and stat.ino ~= nil
    and (root.dev ~= stat.dev or root.ino ~= stat.ino)
  then
    return nil, "configured flashcards_dir was replaced since setup; run setup again"
  end
  return root.canonical
end

local function without_trailing_slash(path)
  if path == "/" or path:match("^%a:/$") then
    return path
  end

  return path:gsub("/+$", "")
end

function M.resolved_path_is_within(path, root)
  path = without_trailing_slash(vim.fs.normalize(path))
  root = without_trailing_slash(vim.fs.normalize(root))
  if path == "" or root == "" then
    return false
  end
  if path == root then
    return true
  end
  local prefix = root:sub(-1) == "/" and root or (root .. "/")
  return path:sub(1, #prefix) == prefix
end

function M.loaded_buffer(path)
  local target = M.canonical_path(path)
  if target == "" then
    return nil
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local buffer_path = vim.api.nvim_buf_get_name(bufnr)
    if vim.api.nvim_buf_is_loaded(bufnr) and M.canonical_path(buffer_path) == target then
      return bufnr
    end
  end

  return nil
end

function M.path_is_within(path, root)
  path = without_trailing_slash(M.canonical_path(path))
  root = without_trailing_slash(M.canonical_path(root))

  if path == "" or root == "" then
    return false
  end

  if path == root then
    return true
  end

  local prefix = root:sub(-1) == "/" and root or (root .. "/")
  return path:sub(1, #prefix) == prefix
end

function M.path_label(path, root)
  path = without_trailing_slash(M.canonical_path(path))
  root = without_trailing_slash(M.canonical_path(root))

  if path == "" then
    return "[No Name]"
  end

  if M.path_is_within(path, root) and path ~= root then
    local prefix = root:sub(-1) == "/" and root or (root .. "/")
    return path:sub(#prefix + 1)
  end

  return vim.fn.fnamemodify(path, ":~")
end

function M.lines_fingerprint(lines)
  return vim.fn.sha256(table.concat(lines, "\n"))
end

local random_seeded = false

local function ensure_random_seeded()
  if random_seeded then
    return
  end

  local seed = os.time()
  local uv = vim.uv or vim.loop
  if uv and uv.hrtime then
    seed = seed + (uv.hrtime() % 1000000)
  end

  math.randomseed(seed)
  math.random()
  math.random()
  random_seeded = true
end

function M.shuffled(items)
  ensure_random_seeded()

  local result = vim.deepcopy(items)
  for index = #result, 2, -1 do
    local swap = math.random(index)
    result[index], result[swap] = result[swap], result[index]
  end

  return result
end

function M.utf8_chars(text)
  local chars = {}
  -- Decimal escapes: LuaJIT (5.1) has no \x string escapes.
  for char in tostring(text or ""):gmatch("[\1-\127\194-\244][\128-\191]*") do
    table.insert(chars, char)
  end
  return chars
end

-- Levenshtein distance over UTF-8 characters, not bytes, so multi-byte
-- answers (e.g. Japanese readings) compare fairly.
function M.levenshtein(left, right)
  local a = M.utf8_chars(left)
  local b = M.utf8_chars(right)
  local previous = {}
  for column = 0, #b do
    previous[column] = column
  end

  for i = 1, #a do
    local current = { [0] = i }
    for j = 1, #b do
      local cost = a[i] == b[j] and 0 or 1
      current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
    end
    previous = current
  end

  return previous[#b]
end

-- Split a field value into buffer-safe lines (values may embed newlines).
function M.value_lines(value)
  local lines = {}
  for line in (tostring(value or "") .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  if #lines == 0 then
    return { "" }
  end
  return lines
end

return M
