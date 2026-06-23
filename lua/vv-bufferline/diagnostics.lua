-- 诊断徽标渲染。聚合逻辑委托给 vv-utils

local HL = require('vv-bufferline.hl')
local D = require('vv-utils.diagnostics')

local M = {}

---@return table<string, table<integer, integer>>
function M.snapshot()
  return D.collect_by_path()
end

local function count_total(counts)
  local total = 0
  for _, count in pairs(counts or {}) do
    total = total + count
  end
  return total
end

---@param buf integer
---@param snapshot table<string, table<integer, integer>>
---@param current boolean
---@param opts VVBufferlineDiagnosticsConfig
---@return {text:string, hl:string, width:integer}?
function M.component(buf, snapshot, current, opts)
  if opts and opts.enabled == false then return nil end

  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' then return nil end

  local counts = snapshot[vim.fs.normalize(path)]
  local symbol = D.symbol_for(counts)
  if not symbol then return nil end

  local total = count_total(counts)
  local text = ' ' .. symbol.glyph .. ' ' .. total

  return {
    text = text,
    hl = HL.derived(symbol.hl, current, 'VVBufferlineDiag'),
    width = vim.fn.strdisplaywidth(text),
  }
end

return M
