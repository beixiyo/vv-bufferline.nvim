-- Owns the v:lua click callbacks used by winbar/tabline strings.
-- Neovim resolves these names globally, so installation must be reversible.

local M = {}

local previous = {}
local owned = {}
local installed = false

local names = {
  '__vv_bufferline_select',
  '__vv_bufferline_close',
}

function M.install(select, close)
  if installed then return end

  for _, name in ipairs(names) do
    previous[name] = rawget(_G, name)
  end

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
