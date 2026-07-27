-- 窗口与 buffer 的准入规则独立于状态存储
-- close/view 等模块由此共享同一套编辑区判定

local State = require('vv-bufferline.state')

local M = {}

---@param buf integer
---@return boolean
function M.normal_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if not vim.bo[buf].buflisted or vim.bo[buf].buftype ~= '' then return false end

  local excluded = State.get_config().exclude_filetypes or {}
  return not excluded[vim.bo[buf].filetype]
end

---@param win integer
---@return boolean
function M.is_editor_win(win)
  return vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_config(win).relative == ''
    and not vim.wo[win].winfixbuf
end

---@param win integer
---@return boolean
function M.normal_win(win)
  return M.is_editor_win(win) and M.normal_buf(vim.api.nvim_win_get_buf(win))
end

---@param win integer
---@return boolean
function M.ignored_win(win)
  if not vim.api.nvim_win_is_valid(win) or vim.wo[win].diff then return true end

  local ok_w, value = pcall(vim.api.nvim_win_get_var, win, 'vv_bufferline_ignore')
  if ok_w and value then return true end

  local ok_t, tab = pcall(vim.api.nvim_win_get_tabpage, win)
  if not ok_t then return false end
  local ok_v, tab_value = pcall(vim.api.nvim_tabpage_get_var, tab, 'vv_bufferline_ignore')
  return ok_v and not not tab_value
end

---@param win integer
---@return boolean
function M.should_show(win)
  if not M.is_editor_win(win) or M.ignored_win(win) then return false end

  local buf = vim.api.nvim_win_get_buf(win)
  if M.normal_buf(buf) then return true end
  if not State.is_preview(win, buf) then return false end

  local group = State.wins[win]
  if not group then return false end
  for _, member in ipairs(group.bufs) do
    if M.normal_buf(member) then return true end
  end
  return false
end

return M
