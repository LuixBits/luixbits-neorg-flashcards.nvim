-- Each owner has at most one short animation; idle views own no timers.
local M = {}
local owners = {}

function M.cancel(owner)
  local timer = owners[owner]
  owners[owner] = nil
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end
end

function M.play(owner, enabled, callback)
  M.cancel(owner)
  if not enabled then
    callback(1)
    return
  end
  local uv = vim.uv or vim.loop
  local timer, frame = uv.new_timer(), 0
  owners[owner] = timer
  timer:start(
    0,
    35,
    vim.schedule_wrap(function()
      if owners[owner] ~= timer then
        return
      end
      frame = frame + 1
      local ok = pcall(callback, frame / 4)
      if not ok or frame >= 4 then
        M.cancel(owner)
      end
    end)
  )
end

function M.active(owner)
  return owners[owner] ~= nil
end

return M
