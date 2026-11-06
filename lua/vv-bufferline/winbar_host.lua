-- 管理 winbar 的宿主状态，仅本模块负责写入和还原用户原有的 winbar

local M = {
  marker = 'VVBufferline',
  owned = {},
  previous = {},
  applied = {},
}

---@type table<integer, integer> 窗口当前接管的 buffer；不维护隐藏 buffer 历史
local owned_buffers = {}

---@param win integer
function M.remember(win)
  local buf = vim.api.nvim_win_get_buf(win)
  if M.owned[win] and owned_buffers[win] == buf then return end
  -- 保留 raw local 的空值，释放后仍跟随当时的 global，而非固定旧 effective 值
  local value = vim.api.nvim_get_option_value('winbar', { win = win, scope = 'local' })
  if value and value:find(M.marker, 1, true) then value = '' end
  M.previous[win] = value
  M.applied[win] = nil
  owned_buffers[win] = buf
  M.owned[win] = true
end

---@param win integer
---@param value string
function M.apply(win, value)
  M.remember(win)
  vim.api.nvim_set_option_value('winbar', value, { win = win, scope = 'local' })
  M.applied[win] = value
end

---@param win integer
function M.restore(win)
  if not M.owned[win] then return end
  if vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_buf(win) == owned_buffers[win]
    and vim.api.nvim_get_option_value('winbar', { win = win, scope = 'local' }) == M.applied[win] then
    vim.api.nvim_set_option_value('winbar', M.previous[win] or '', { win = win, scope = 'local' })
  end
  M.remove(win)
end

---@param win integer
function M.clear_orphan(win)
  if M.owned[win] or not vim.api.nvim_win_is_valid(win) then return end
  local value = vim.api.nvim_get_option_value('winbar', { win = win, scope = 'local' })
  if value and value ~= '' and value:find(M.marker, 1, true) then vim.wo[win].winbar = '' end
end

---@return integer[]
function M.owned_wins()
  local wins = {}
  for win in pairs(M.owned) do wins[#wins + 1] = win end
  return wins
end

---@param win integer
function M.remove(win)
  M.owned[win] = nil
  M.previous[win] = nil
  M.applied[win] = nil
  owned_buffers[win] = nil
end

function M.reset()
  for win in pairs(M.owned) do M.owned[win] = nil end
  for win in pairs(M.previous) do M.previous[win] = nil end
  for win in pairs(M.applied) do M.applied[win] = nil end
  for win in pairs(owned_buffers) do owned_buffers[win] = nil end
end

return M
