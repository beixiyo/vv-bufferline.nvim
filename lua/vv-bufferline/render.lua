-- 把窗口局部的 buffer 标签渲染成 winbar statusline 字符串

local State = require('vv-bufferline.state')
local Icons = require('vv-bufferline.icons')
local Diagnostics = require('vv-bufferline.diagnostics')

local M = {}

local function stl(text)
  return tostring(text or ''):gsub('%%', '%%%%'):gsub('[\r\n]', ' ')
end

local function click(func, buf, text)
  return ('%%%d@v:lua.%s@%s%%X'):format(buf, func, stl(text))
end

local function buf_name(buf, counts)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return '[No Name]' end

  local base = vim.fn.fnamemodify(name, ':t')
  if counts[base] and counts[base] > 1 then
    local parent = vim.fn.fnamemodify(name, ':h:t')
    if parent ~= '' then return parent .. '/' .. base end
  end

  return base ~= '' and base or name
end

local function truncate_name(name, max_width)
  if vim.fn.strdisplaywidth(name) <= max_width then return name end

  local chars = vim.fn.strcharpart(name, 0, max_width - 1)
  return chars .. '…'
end

local function item_for(buf, current, counts, diag_snapshot, config)
  local modified = vim.bo[buf].modified
  local label = truncate_name(buf_name(buf, counts), config.max_name_width)
  local mark = modified and '● ' or ''
  local icon, icon_hl = Icons.get(buf, current)
  local icon_text = icon ~= '' and (' ' .. icon .. ' ') or ' '
  local close = config.show_close and '× ' or ''
  local diag = Diagnostics.component(buf, diag_snapshot, current, config.diagnostics or {})

  local tab_hl = current and 'VVBufferlineCurrent' or 'VVBufferlineTab'
  local mod_hl = current and 'VVBufferlineCurrentModified' or 'VVBufferlineTabModified'
  local close_hl = current and 'VVBufferlineCloseCurrent' or 'VVBufferlineClose'

  local rendered = '%#' .. tab_hl .. '#'
    .. click('__vv_bufferline_select', buf, ' ')
    .. '%#' .. icon_hl .. '#'
    .. click('__vv_bufferline_select', buf, icon ~= '' and (icon .. ' ') or '')
    .. '%#' .. mod_hl .. '#'
    .. click('__vv_bufferline_select', buf, mark)
    .. '%#' .. tab_hl .. '#'
    .. click('__vv_bufferline_select', buf, label)

  local text = icon_text .. mark .. label

  if diag then
    rendered = rendered
      .. '%#' .. diag.hl .. '#'
      .. click('__vv_bufferline_select', buf, diag.text)
    text = text .. diag.text
  end

  rendered = rendered .. '%#' .. tab_hl .. '#' .. click('__vv_bufferline_select', buf, ' ')
  text = text .. ' '

  if close ~= '' then
    rendered = rendered
      .. '%#' .. close_hl .. '#'
      .. click('__vv_bufferline_close', buf, close)
  end

  return {
    buf = buf,
    current = current,
    width = vim.fn.strdisplaywidth(text .. close),
    rendered = rendered,
  }
end

local function visible_items(items, max_width)
  if #items == 0 then return {} end

  local cur = 1
  for i, item in ipairs(items) do
    if item.current then
      cur = i
      break
    end
  end

  local used = items[cur].width
  local keep = { [cur] = true }
  local left = cur - 1
  local right = cur + 1
  local ellipsis_width = 2

  while left >= 1 or right <= #items do
    local changed = false

    if left >= 1 and used + items[left].width + ellipsis_width <= max_width then
      keep[left] = true
      used = used + items[left].width
      left = left - 1
      changed = true
    else
      left = 0
    end

    if right <= #items and used + items[right].width + ellipsis_width <= max_width then
      keep[right] = true
      used = used + items[right].width
      right = right + 1
      changed = true
    else
      right = #items + 1
    end

    if not changed then break end
  end

  local visible = {}
  for i, item in ipairs(items) do
    if keep[i] then table.insert(visible, item) end
  end

  visible.leading_trunc = not keep[1]
  visible.trailing_trunc = not keep[#items]

  return visible
end

---@param win integer
---@param config VVBufferlineConfig
function M.render(win, config)
  if not State.should_show(win) then return '' end

  local buf = vim.api.nvim_win_get_buf(win)
  -- 当前 buffer 不纳入分组的两种情况：
  --   • is_preview：临时预览 buf，渲染既有标签但不把它加进分组（保持预览不污染 bufferline）；
  --   • is_removed：用户显式删过，周期 refresh 不得复原（复原只留给 select/commit/replacement 的直接 add）。
  if not State.is_preview(win, buf) and not State.is_removed(win, buf) then
    State.add(win, buf)
  end
  State.prune(win)

  local s = State.win_state(win)
  local counts = {}
  for _, b in ipairs(s.bufs) do
    local base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t')
    counts[base] = (counts[base] or 0) + 1
  end

  local diag_snapshot = Diagnostics.snapshot()
  local items = {}
  for _, b in ipairs(s.bufs) do
    table.insert(items, item_for(b, b == buf, counts, diag_snapshot, config))
  end

  local max_width = math.max(8, vim.api.nvim_win_get_width(win) - 1)
  local visible = visible_items(items, max_width)
  -- 外框用 WINBAR_MARKER 前缀：它必然出现在每次渲染里，state 的 orphan/继承识别即据此 sniff
  local parts = { '%#' .. State.WINBAR_MARKER .. 'Fill#' }

  if visible.leading_trunc then
    table.insert(parts, '%#VVBufferlineTrunc# … ')
  end

  for _, item in ipairs(visible) do
    table.insert(parts, item.rendered)
  end

  if visible.trailing_trunc then
    table.insert(parts, '%#VVBufferlineTrunc# … ')
  end

  table.insert(parts, '%#' .. State.WINBAR_MARKER .. 'Fill#%=')

  return table.concat(parts)
end

return M
