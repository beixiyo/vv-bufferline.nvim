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

local function is_tabline_target()
  return config.render_target == 'tabline'
end

---@param c VVBufferlineConfig
function M.set_config(c)
  config = c
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
  if not is_tabline_target() then return vim.api.nvim_get_current_win() end

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
  if is_tabline_target() then
    previous_tabline = vim.o.tabline
    previous_showtabline = vim.o.showtabline
  end
  M.reload_hl()
end

function M.disable()
  M.enabled = false

  if is_tabline_target() then
    vim.o.tabline = previous_tabline or ''
    vim.o.showtabline = previous_showtabline or 0
  end

  for win in pairs(State.owned_winbars) do
    State.restore_winbar(win)
  end
end

return M
