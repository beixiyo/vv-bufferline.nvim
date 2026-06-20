-- 文件图标查询。本配置里 nvim-web-devicons 被 mini.icons 接管，
-- 所以高亮组取自 vv-icons 的数据

local HL = require('vv-bufferline.hl')

local M = {}

---@param buf integer
---@param current boolean
---@return string icon
---@return string hl
function M.get(buf, current)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if not ok then return '', current and 'VVBufferlineCurrent' or 'VVBufferlineTab' end

  local name = vim.api.nvim_buf_get_name(buf)
  local icon, source_hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ':e'), { default = true })

  return icon or '', HL.derived(source_hl, current, 'VVBufferlineIcon')
end

return M
