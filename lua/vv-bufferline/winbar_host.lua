-- 管理 winbar 的宿主状态，仅本模块负责写入和还原用户原有的 winbar

local M = {
  marker = 'VVBufferline',
  owned = {},
  previous = {},
}

---@param win integer
function M.remember(win)
  if M.owned[win] then return end
  local value = vim.wo[win].winbar
  if value and value:find(M.marker, 1, true) then value = '' end
  M.previous[win] = value
  M.owned[win] = true
end

---@param win integer
function M.restore(win)
  if not M.owned[win] then return end
  if vim.api.nvim_win_is_valid(win) then vim.wo[win].winbar = M.previous[win] or '' end
  M.owned[win] = nil
  M.previous[win] = nil
end

---@param win integer
function M.clear_orphan(win)
  if M.owned[win] or not vim.api.nvim_win_is_valid(win) then return end
  local value = vim.wo[win].winbar
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
end

function M.reset()
  for win in pairs(M.owned) do M.owned[win] = nil end
  for win in pairs(M.previous) do M.previous[win] = nil end
end

return M
