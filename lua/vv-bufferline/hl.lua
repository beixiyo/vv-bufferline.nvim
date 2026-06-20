-- vv-bufferline 的高亮组定义

local hl_util = require('vv-utils.hl')

local M = {
  colors = {},
  derived_cache = {},
}

local function read_color(group, attr, fallback)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if ok and h and h[attr] then return string.format('#%06x', h[attr]) end
  return fallback
end

local function default_colors()
  return {
    fill_bg = read_color('TabLineFill', 'bg', '#16161e'),
    inactive_bg = read_color('Normal', 'bg', '#1a1b26'),
    active_bg = read_color('TabLineSel', 'bg', '#3d59a1'),
    inactive_fg = read_color('Comment', 'fg', '#7c7f93'),
    active_fg = read_color('Normal', 'fg', '#ffffff'),
    muted_fg = read_color('Comment', 'fg', '#565f89'),
    modified_fg = read_color('DiagnosticWarn', 'fg', '#e0af68'),
  }
end

---@param config VVBufferlineConfig
function M.setup(config)
  M.colors = vim.tbl_deep_extend('force', default_colors(), config.colors or {})
  M.derived_cache = {}

  hl_util.register('vv-bufferline.hl', {
    VVBufferlineFill = { bg = M.colors.fill_bg, fg = M.colors.inactive_fg },
    VVBufferlineTab = { bg = M.colors.inactive_bg, fg = M.colors.inactive_fg },
    VVBufferlineTabModified = { bg = M.colors.inactive_bg, fg = M.colors.modified_fg },
    VVBufferlineCurrent = { bg = M.colors.active_bg, fg = M.colors.active_fg, bold = true },
    VVBufferlineCurrentModified = { bg = M.colors.active_bg, fg = M.colors.modified_fg, bold = true },
    VVBufferlineClose = { bg = M.colors.inactive_bg, fg = M.colors.muted_fg },
    VVBufferlineCloseCurrent = { bg = M.colors.active_bg, fg = M.colors.active_fg },
    VVBufferlineTrunc = { bg = M.colors.fill_bg, fg = M.colors.muted_fg },
  }, { default = false })
end

---@param source_hl string?
---@param current boolean
---@param prefix string
---@return string
function M.derived(source_hl, current, prefix)
  local fallback = current and 'VVBufferlineCurrent' or 'VVBufferlineTab'
  if not source_hl or source_hl == '' then return fallback end

  local suffix = source_hl:gsub('[^%w_]', '_')
  local name = prefix .. (current and 'Current' or 'Inactive') .. suffix
  if M.derived_cache[name] then return name end

  local fg = hl_util.get_fg(source_hl, nil)
  if not fg then return fallback end

  vim.api.nvim_set_hl(0, name, {
    fg = fg,
    bg = current and M.colors.active_bg or M.colors.inactive_bg,
    bold = current,
  })

  M.derived_cache[name] = true
  return name
end

return M
