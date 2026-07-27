-- 管理 winbar/tabline 字符串使用的 v:lua 点击回调
-- Neovim 在全局解析这些名称，因此安装过程必须能够完整还原

---@class VVBufferlineClickOwner
---@field install fun(select: VVBufferlineClickCallback, close: VVBufferlineClickCallback)
---@field restore fun()
---@type VVBufferlineClickOwner
local M = {}

local previous = {}
local owned = {}
local installed = false

local names = {
  '__vv_bufferline_select',
  '__vv_bufferline_close',
}

---@param select VVBufferlineClickCallback
---@param close VVBufferlineClickCallback
function M.install(select, close)
  if installed then return end

  for _, name in ipairs(names) do
    previous[name] = rawget(_G, name)
  end

  -- 这些名称属于 Neovim 的全局 v:lua 边界，仅由本模块负责安装
  -- 还原时只处理仍由本模块持有的名称，并恢复安装前已有的回调
  _G.__vv_bufferline_select = select
  _G.__vv_bufferline_close = close
  owned.__vv_bufferline_select = select
  owned.__vv_bufferline_close = close
  installed = true
end

function M.restore()
  if not installed then return end

  for _, name in ipairs(names) do
    if _G[name] == owned[name] then _G[name] = previous[name] end
    previous[name] = nil
    owned[name] = nil
  end

  installed = false
end

return M
