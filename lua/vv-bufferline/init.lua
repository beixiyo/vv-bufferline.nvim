-- vv-bufferline.nvim —— 类 VSCode 的分屏局部 buffer 标签栏
--
-- 每个窗口通过 window-local winbar 渲染自己访问过的 buffer 列表
-- Neovim 的 buffer 仍是全局的，只有标签 UI 状态按窗口隔离
--
-- 本文件是该目录的统一入口（barrel）：装配 setup / 用户命令 / autocmd，并重导出
-- 公开 API。逻辑分布：state（状态模型）· render（纯渲染）· view（渲染同步引擎）·
-- close（关闭/删除编排）

local State = require('vv-bufferline.state')
local Window = require('vv-bufferline.window')
local WinbarHost = require('vv-bufferline.winbar_host')
local View = require('vv-bufferline.view')
local Close = require('vv-bufferline.close')
local Click = require('vv-bufferline.click')
require('vv-bufferline.types')

local M = {}

---@type VVBufferlineConfig
local defaults = {
  max_name_width = 28,
  show_close = false,
  hover_close = true,
  exclude_filetypes = {
    alpha = true,
    dashboard = true,
    fzf = true,
    help = true,
    ministarter = true,
    qf = true,
    trouble = true,
    ['vv-explorer'] = true,
    ['vv-git'] = true,
  },
  diagnostics = { enabled = true },
  hide_tabline = true,
  render_target = 'winbar',
}

---@type VVBufferlineConfig
local config = vim.deepcopy(defaults)

-- ===== 公开交互 API（触碰 state 并重绘，薄封装放在入口）=====

---@param buf integer
---@param opts? {mouse?:boolean}
function M.select(buf, opts)
  local win = opts and opts.mouse and View.mouse_interaction_win() or View.interaction_win()
  if not win or not Window.normal_buf(buf) or not vim.api.nvim_win_is_valid(win) then return end
  if not Window.is_editor_win(win) or Window.ignored_win(win) then return end

  State.clear_preview(win)
  local ok = pcall(vim.api.nvim_win_set_buf, win, buf)
  if not ok then return end

  State.add(win, buf)
  View.refresh()
end

---按当前窗口的标签顺序循环切换 buffer
---@param delta integer 正数向右，负数向左
function M.cycle(delta)
  if delta == 0 then return end

  local win = View.interaction_win()
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  State.prune(win)
  local bufs = State.win_state(win).bufs
  if #bufs == 0 then return end

  local current = vim.api.nvim_win_get_buf(win)
  local index = State.index_of(win, current)
  local target_index

  if index then
    target_index = (index - 1 + delta) % #bufs + 1
  elseif delta > 0 then
    target_index = (delta - 1) % #bufs + 1
  else
    target_index = delta % #bufs + 1
  end

  M.select(bufs[target_index])
end

---@param win integer
---@param buf integer
---@return boolean
function M.has(win, buf)
  return State.has_in_win(win, buf)
end

---@param win integer
---@param buf integer
function M.mark_preview(win, buf)
  if not vim.api.nvim_win_is_valid(win) then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end

  State.set_preview(win, buf)
  View.refresh()
end

---@param win integer
---@param buf? integer
---@param opts? {promote?:boolean}
function M.clear_preview(win, buf, opts)
  opts = opts or {}
  if not vim.api.nvim_win_is_valid(win) then return end

  State.clear_preview(win, buf)
  if opts.promote then
    local target = buf or vim.api.nvim_win_get_buf(win)
    if Window.normal_buf(target) then State.add(win, target) end
  end

  View.refresh()
end

-- ===== 重导出 view / close 的公开 API =====

M.enable = View.enable
function M.disable()
  View.disable()
  Click.restore()
end

function M.toggle()
  if View.enabled then
    M.disable()
  else
    View.enable()
  end
end

function M.close(buf, opts)
  Close.close(buf, opts)
end

M.close_current = Close.close_current
M.close_left = Close.close_left
M.close_right = Close.close_right
M.close_others = Close.close_others
M.close_all = Close.close_all

---@param opts? VVBufferlineConfig
function M.setup(opts)
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  State.setup(config)
  View.set_config(config)

  -- vv-bufferline 用 winbar 展示 buffer，内置 tabline 是冗余噪音：多开一个 tab（如打开 vv-git
  -- 专属 tab）时 Neovim 默认 tabline 会冒出来显示 pathshorten 的标签栏。这里默认隐藏它，
  -- 接管原 akinsho/bufferline（它当年 set showtabline=2 自管 tabline）留下的这块空缺。
  if config.hide_tabline and config.render_target ~= 'tabline' then vim.o.showtabline = 0 end

  -- Neovim resolves winbar click handlers through these v:lua names.
  Click.install(function(buf) M.select(buf, { mouse = true }) end, function(buf)
    local win = View.mouse_interaction_win()
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      M.close_current({ mouse = true })
      return
    end

    M.close(buf, { mouse = true })
  end)

  local group = vim.api.nvim_create_augroup('vv_bufferline', { clear = true })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function() View.reload_hl() end,
  })

  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'BufWinEnter', 'BufAdd', 'FileType', 'TermOpen', 'WinResized' }, {
    group = group,
    callback = function()
      View.track_current()
      vim.schedule(View.refresh)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      State.remove_buf(args.buf)
      vim.schedule(View.refresh)
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost', 'DiagnosticChanged' }, {
    group = group,
    callback = function() vim.schedule(View.refresh) end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        State.remove_win(win)
        WinbarHost.remove(win)
      end
    end,
  })

  vim.api.nvim_create_user_command('VVBufferlineEnable', M.enable, {})
  vim.api.nvim_create_user_command('VVBufferlineDisable', M.disable, {})
  vim.api.nvim_create_user_command('VVBufferlineToggle', M.toggle, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseCurrent', function() M.close_current() end, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseCurrentForce', function() M.close_current({ force = true }) end, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseLeft', M.close_left, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseRight', M.close_right, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseOthers', M.close_others, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseAll', function() M.close_all() end, {})

  M.enable()
end

return M
