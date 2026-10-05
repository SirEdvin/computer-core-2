-- Pure sizing/state rules shared by the GUI and engine regressions.
local M = {}
function M.dimensions(resolution, scale)
  local available_width = math.max(1, math.floor(resolution.width / scale) - 32)
  local available_height = math.max(1, math.floor(resolution.height / scale) - 64)
  local width, height = math.min(980, available_width), math.min(760, available_height)
  return {width = width, height = height, content_width = math.max(1, width - 64),
    content_height = math.max(1, height - 210), compact = width < 640}
end
function M.status(c, powered)
  if not powered then return c.process and 'Paused — no power' or 'No power' end
  if c.process then return 'Running — ' .. (c.process.path or 'program') end
  return 'Idle — no program running'
end
function M.feedback(session, text, kind, tick)
  session.notice, session.notice_kind = text, kind or 'info'
  session.notice_until = tick + 600
end
function M.notice(session, tick)
  if session.notice_until and tick >= session.notice_until then
    session.notice, session.notice_kind, session.notice_until = nil, nil, nil
  end
  return session.notice
end
return M
