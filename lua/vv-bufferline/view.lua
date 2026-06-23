-- 渲染同步引擎：把 state 渲染进各窗口的 window-local winbar，并跟踪当前窗口的
-- buffer 归属。持有 enabled 开关与 config，对外暴露 refresh / enable / disable /
-- track_current；close 等模块通过 View.refresh 触发重绘

local State = require('vv-bufferline.state')
local Render = require('vv-bufferline.render')
local HL = require('vv-bufferline.hl')

local M = { enabled = false }

local config = {}
local previous_tabline
local previous_showtabline
local last_editor_win
local saved_mousemoveevent
local mousemove_ns
local hover_scheduled = false
local hover_clear_token = 0
local mousemove_key = vim.keycode('<MouseMove>')

local function is_tabline_target()
  return config.render_target == 'tabline'
end

local function cancel_hover_clear()
  hover_clear_token = hover_clear_token + 1
end

local function clear_hover_later()
  if not State.hover then return end

  hover_clear_token = hover_clear_token + 1
  local token = hover_clear_token
  vim.defer_fn(function()
    if token ~= hover_clear_token then return end
    if State.clear_hovered() then M.refresh() end
  end, 80)
end

local function mouse_winbar_col(pos, win)
  local infos = vim.fn.getwininfo(win)
  local info = infos and infos[1]
  if not info or info.winbar ~= 1 then return nil end

  if pos.screenrow ~= info.winrow then return nil end

  local col = (pos.screencol or 0) - info.wincol + 1
  if col < 1 or col > info.width then return nil end

  return col
end

local function mouse_winbar_target(pos)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if State.should_show(win) then
      local col = mouse_winbar_col(pos, win)
      if col then return win, col end
    end
  end
end

local function mouse_tabline_col(pos)
  if not is_tabline_target() then return nil end
  if vim.o.showtabline == 0 then return nil end
  if pos.screenrow ~= 1 then return nil end

  local col = pos.screencol or 0
  return col > 0 and col or nil
end

local function update_hover()
  hover_scheduled = false

  if not M.enabled or not config.hover_close then
    if State.clear_hovered() then M.refresh() end
    return
  end

  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or not pos then return end

  local win
  local col
  if is_tabline_target() then
    win = M.interaction_win()
    col = mouse_tabline_col(pos)
  else
    win, col = mouse_winbar_target(pos)
  end

  local buf = (win and col) and State.buf_at(win, col) or nil
  if not buf then
    clear_hover_later()
    return
  end

  cancel_hover_clear()
  local changed = State.set_hovered(win, buf)
  if changed then M.refresh() end
end

local function schedule_hover_update()
  if hover_scheduled then return end

  hover_scheduled = true
  vim.schedule(update_hover)
end

local function enable_hover()
  if not config.hover_close or mousemove_ns then return end

  saved_mousemoveevent = vim.o.mousemoveevent
  vim.o.mousemoveevent = true

  mousemove_ns = vim.api.nvim_create_namespace('vv_bufferline_mousemove')
  vim.on_key(function(key, typed)
    if key == mousemove_key or typed == mousemove_key then
      schedule_hover_update()
    end
  end, mousemove_ns)
end

local function disable_hover()
  if mousemove_ns then
    pcall(vim.on_key, nil, mousemove_ns)
    mousemove_ns = nil
  end
  hover_scheduled = false
  State.clear_hovered()

  if saved_mousemoveevent ~= nil then
    local has_mousemove_map = vim.fn.maparg('<MouseMove>', 'n') ~= ''
    if saved_mousemoveevent or not has_mousemove_map then
      vim.o.mousemoveevent = saved_mousemoveevent
    end
    saved_mousemoveevent = nil
  end
end

---@param c VVBufferlineConfig
function M.set_config(c)
  config = c
end

---@return integer?
function M.mouse_interaction_win()
  if is_tabline_target() then return M.interaction_win() end

  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or not pos then return nil end

  local win = mouse_winbar_target(pos)
  return win
end

---@param win integer
local function apply_winbar(win)
  if not vim.api.nvim_win_is_valid(win) then return end

  -- 预览态下若窗口已有固定分组，should_show 仍为真 → 标签栏保留可见（不再消失）
  if not State.should_show(win) then
    State.restore_winbar(win)
    -- tab split / :split 会把 bufferline winbar 继承到新窗口；该窗口不该显示却没被
    -- 我们登记 owned 时，restore 不生效 → 主动清掉这份继承来的残留（只清我们自己的串）
    State.clear_orphan_winbar(win)
    return
  end

  State.remember_winbar(win)
  vim.wo[win].winbar = Render.render(win, config)
end

function M.refresh()
  if not M.enabled then return end

  if is_tabline_target() then
    local win = M.interaction_win()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      State.restore_winbar(w)
      State.clear_orphan_winbar(w)
    end

    if win and State.should_show(win) then
      vim.o.showtabline = 2
      vim.o.tabline = Render.render(win, config)
    else
      vim.o.tabline = ''
      if config.hide_tabline then vim.o.showtabline = 0 end
    end
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    apply_winbar(win)
  end
end

function M.restore_all_winbars()
  local wins = {}
  for win in pairs(State.owned_winbars) do
    table.insert(wins, win)
  end

  for _, win in ipairs(wins) do
    State.restore_winbar(win)
  end

  if is_tabline_target() then M.refresh() end
end

-- 当前窗口落定显示某 buffer 时把它纳入分组；尊重 ignored / preview / removed，不强行复原
function M.track_current()
  if not M.enabled then return end

  local win = vim.api.nvim_get_current_win()
  if not State.is_editor_win(win) then return end
  if State.ignored_win(win) then return end
  last_editor_win = win

  local buf = vim.api.nvim_get_current_buf()
  if State.is_preview(win, buf) then return end
  -- 用户在该窗口显式删除过此 buf → 不因一次自动 BufEnter 把它复原。
  -- 真正落定显示它时，render 的 State.add 会清掉 removed 并重新纳入分组。
  if State.is_removed(win, buf) then return end
  if State.normal_buf(buf) then State.add(win, buf) end
end

-- 重建高亮并重绘（启用时、ColorScheme 之后调用）
function M.reload_hl()
  HL.setup(config)
  M.refresh()
end

---@return integer?
function M.interaction_win()
  if not is_tabline_target() then
    local cur = vim.api.nvim_get_current_win()
    return State.should_show(cur) and cur or nil
  end

  local cur = vim.api.nvim_get_current_win()
  if State.should_show(cur) then
    last_editor_win = cur
    return cur
  end

  if last_editor_win and vim.api.nvim_win_is_valid(last_editor_win) and State.should_show(last_editor_win) then
    return last_editor_win
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if State.should_show(win) then
      last_editor_win = win
      return win
    end
  end
end

function M.enable()
  if M.enabled then return end

  M.enabled = true
  enable_hover()
  if is_tabline_target() then
    previous_tabline = vim.o.tabline
    previous_showtabline = vim.o.showtabline
  end
  M.reload_hl()
end

function M.disable()
  M.enabled = false
  disable_hover()

  if is_tabline_target() then
    vim.o.tabline = previous_tabline or ''
    vim.o.showtabline = previous_showtabline or 0
  end

  for win in pairs(State.owned_winbars) do
    State.restore_winbar(win)
  end
end

return M
