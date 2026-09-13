-- Small cross-process token locks shared by source and history writes.
-- Callers remain responsible for resolving and validating their destinations.

local M = {}

local function lock_token(path)
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or #lines ~= 1 then
    return nil
  end
  return lines[1]
end

local function create_lock(path)
  local uv = vim.uv or vim.loop
  local fd, open_err, open_code = uv.fs_open(path, "wx", 384)
  if not fd then
    return nil, open_err, open_code
  end

  local token = string.format("%s:%s", vim.fn.getpid(), uv.hrtime())
  local written, write_err = uv.fs_write(fd, token, 0)
  if not written then
    pcall(uv.fs_close, fd)
    pcall(uv.fs_unlink, path)
    return nil, write_err
  end
  pcall(uv.fs_fsync, fd)
  return { fd = fd, path = path, token = token }
end

function M.release(lock)
  if not lock then
    return
  end

  local uv = vim.uv or vim.loop
  if lock.fd then
    pcall(uv.fs_close, lock.fd)
  end
  if lock_token(lock.path) == lock.token then
    pcall(uv.fs_unlink, lock.path)
  end
end

local function remove_dead_owner_lock(path)
  local uv = vim.uv or vim.loop
  local token = lock_token(path)
  local owner = token and tonumber(token:match("^(%d+):")) or nil
  if not owner then
    return false
  end

  local _, _, kill_code = uv.kill(owner, 0)
  if kill_code ~= "ESRCH" or lock_token(path) ~= token then
    return false
  end
  local removed = uv.fs_unlink(path)
  return removed ~= nil or lock_token(path) == nil
end

-- A reaper token ensures that only one process checks and removes a dead
-- owner's lock. Re-reading the original token prevents an old holder from
-- unlinking a successor's lock.
local function recover_dead_lock(lock_path)
  local reaper_path = lock_path .. ".reap"
  local reaper, _, reaper_code = create_lock(reaper_path)
  if not reaper and reaper_code == "EEXIST" and remove_dead_owner_lock(reaper_path) then
    reaper = create_lock(reaper_path)
  end
  if not reaper then
    return false
  end

  local recovered = remove_dead_owner_lock(lock_path)
  M.release(reaper)
  return recovered
end

---Acquire a token lock, recovering one whose owning process no longer exists.
---@param path string
---@param opts? { wait_ms?: number, sleep_ms?: number }
---@return table|nil lock
---@return string|nil error
---@return "open"|"timeout"|nil reason
function M.acquire(path, opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  local wait_ms = opts.wait_ms or 2000
  local sleep_ms = opts.sleep_ms or 2
  local deadline = uv.hrtime() + wait_ms * 1000000

  while true do
    local lock, open_err, open_code = create_lock(path)
    if lock then
      return lock
    end
    if open_code ~= "EEXIST" then
      return nil, open_err, "open"
    end

    local recovered = recover_dead_lock(path)
    if not recovered and uv.hrtime() >= deadline then
      return nil, nil, "timeout"
    elseif not recovered then
      uv.sleep(sleep_ms)
    end
  end
end

return M
