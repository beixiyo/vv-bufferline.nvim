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
local CursorHandoff = require('vv-bufferline.cursor_handoff')
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
  track_modified = true,
  placeholder_filetypes = { alpha = true, dashboard = true, ministarter = true },
  keys = {
    prev = '[b',
    next = ']b',
    first = '[B',
    last = ']B',
    close = '<leader>bd',
    close_force = '<leader>bD',
    close_left = '<leader>bh',
    close_right = '<leader>bl',
    close_others = '<leader>bo',
    close_all = '<leader>ba',
  },
  hooks = {},
}

---@type VVBufferlineConfig
local config = vim.deepcopy(defaults)
local tracking_generation = 0

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

---跳到当前窗口标签列表的端点标签
---@param side 'first'|'last' 最左侧或最右侧
function M.jump_to_end(side)
  local win = View.interaction_win()
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  State.prune(win)
  local bufs = State.win_state(win).bufs
  if #bufs == 0 then return end

  local target_index = side == 'first' and 1 or #bufs
  if State.index_of(win, vim.api.nvim_win_get_buf(win)) == target_index then return end

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

-- 记录安装时展开的 lhs 和 callback；卸载不删除用户后来的重绑，也不受 leader 变化影响
local registered_keys = {}

---@param lhs string
local function global_mapping(lhs)
  local raw = vim.keycode(lhs)
  for _, mapping in ipairs(vim.api.nvim_get_keymap('n')) do
    if mapping.lhsraw == raw or mapping.lhs == lhs then return mapping end
  end
end

local function uninstall_default_keys()
  for i = #registered_keys, 1, -1 do
    local owned = registered_keys[i]
    local current = global_mapping(owned.lhs)
    if current and current.callback == owned.callback then
      vim.keymap.del('n', owned.lhs)
      if owned.previous then vim.fn.mapset('n', false, owned.previous) end
    end
  end
  registered_keys = {}
end

-- 默认键位接管 Neovim 内置的 [b/]b/[B/]B（内置走全局 bufnr 序的 :bnext 等，
-- 与窗口分组顺序不一致）；keys = false 可完全不注册
local function install_default_keys()
  uninstall_default_keys()

  local keys = config.keys
  if not keys then return end

  local actions = {
    { lhs = keys.prev, fn = function() M.cycle(-vim.v.count1) end, desc = 'Previous buffer' },
    { lhs = keys.next, fn = function() M.cycle(vim.v.count1) end, desc = 'Next buffer' },
    { lhs = keys.first, fn = function() M.jump_to_end('first') end, desc = 'First buffer' },
    { lhs = keys.last, fn = function() M.jump_to_end('last') end, desc = 'Last buffer' },
    { lhs = keys.close, fn = function() M.close_current() end, desc = 'Close buffer' },
    { lhs = keys.close_force, fn = function() M.close_current({ force = true }) end, desc = 'Force close buffer' },
    { lhs = keys.close_left, fn = function() M.close_left() end, desc = 'Close buffers left' },
    { lhs = keys.close_right, fn = function() M.close_right() end, desc = 'Close buffers right' },
    { lhs = keys.close_others, fn = function() M.close_others() end, desc = 'Close other buffers' },
    { lhs = keys.close_all, fn = function() M.close_all({ close_windows = true }) end, desc = 'Close all buffers' },
  }

  for _, action in ipairs(actions) do
    if action.lhs then
      local lhs = action.lhs:gsub('<[Ll][Ee][Aa][Dd][Ee][Rr]>', function() return vim.g.mapleader or '\\' end)
        :gsub('<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>', function() return vim.g.maplocalleader or '\\' end)
      local previous = global_mapping(lhs)
      vim.keymap.set('n', lhs, action.fn, { desc = 'vv-bufferline: ' .. action.desc, silent = true })
      local installed = assert(global_mapping(lhs))
      table.insert(registered_keys, { lhs = installed.lhs, callback = action.fn, previous = previous })
    end
  end
end

local function install_click_handlers()
  -- Neovim resolves winbar click handlers through these v:lua names.
  Click.install(function(buf) M.select(buf, { mouse = true }) end, function(buf)
    local win = View.mouse_interaction_win()
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      M.close_current({ mouse = true })
      return
    end

    M.close(buf, { mouse = true })
  end)
end

function M.enable()
  if View.enabled then return end
  install_click_handlers()
  CursorHandoff.enable()
  View.enable()
end

function M.disable()
  tracking_generation = tracking_generation + 1
  CursorHandoff.disable()
  View.disable()
  Click.restore()
end

function M.toggle()
  if View.enabled then
    M.disable()
  else
    M.enable()
  end
end

---统一关闭入口；捕获动作开始时的 tab，报告取消/失败，不让展示层误判成功
---@param action 'close'|'close_current'|'close_left'|'close_right'|'close_others'|'close_all'
local function run_close(action, ...)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local hook = config.hooks.after_close
  local completed = Close[action](...) == true
  if type(hook) == 'function' then
    local ok, err = pcall(hook, { action = action, completed = completed, tabpage = tabpage })
    if not ok then
      vim.schedule(function()
        vim.notify('[vv-bufferline] after_close hook error: ' .. tostring(err), vim.log.levels.ERROR)
      end)
    end
  end
  return completed
end

---关闭指定标签
function M.close(buf, opts)
  return run_close('close', buf, opts)
end

---关闭当前标签
function M.close_current(opts)
  return run_close('close_current', opts)
end

---关闭当前标签左侧的标签
function M.close_left()
  return run_close('close_left')
end

---关闭当前标签右侧的标签
function M.close_right()
  return run_close('close_right')
end

---关闭当前分组的其他标签
function M.close_others()
  return run_close('close_others')
end

---关闭所有 buffer，可选收起当前 tab 的分屏
function M.close_all(opts)
  return run_close('close_all', opts)
end

---@param opts? VVBufferlineConfig
function M.setup(opts)
  M.disable()
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  State.setup(config)
  View.set_config(config)

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

  -- 窗口外被修改的 buffer（LSP 跨文件编辑、后台格式化等）若未出现在任何窗口分组，
  -- 只能靠退出确认兜底。把它自动纳入当前编辑窗口，让未保存状态在标签上可见
  -- 预览 buffer 交给 explorer 的 promote 语义；用户显式删除过的不自动复活
  --
  -- OptionSet modified 对隐藏 buffer 的触发会延迟到事件循环，且 Neovim 会在无窗口
  -- buffer 的临时窗口上下文中执行回调（args.buf 可能为 0，当前窗口不可信）：先
  -- 捕获 bufnr，再 vim.schedule 回正常上下文解析归属窗口（ignored tab / dashboard
  -- 会话中尝试回退到最近编辑窗口；无合适目标时跳过）
  -- 0.12 的 OptionSet 不报告 modified；兼容 BufModifiedSet，但旧事件仅覆盖重绘中的
  -- 当前 buffer，完整的隐藏修改追踪需要 0.13（neovim/neovim#35610）
  local modified_event = vim.fn.exists('##BufModifiedSet') == 1 and 'BufModifiedSet' or 'OptionSet'
  -- 0.13 类型库已移除旧事件名；运行时已通过 exists 做能力检测
  ---@diagnostic disable-next-line: param-type-mismatch
  vim.api.nvim_create_autocmd(modified_event, {
    group = group,
    pattern = modified_event == 'OptionSet' and 'modified' or nil,
    callback = function(args)
      if not config.track_modified or not View.enabled then return end

      local buf = (args.buf and args.buf > 0) and args.buf or vim.api.nvim_get_current_buf()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local generation = tracking_generation

      vim.schedule(function()
        if generation ~= tracking_generation or not config.track_modified or not View.enabled then return end
        if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then return end
        if not Window.file_buf(buf) then return end
        if State.contains_buf(buf) or State.has_preview(buf) then return end

        local win = View.modification_target_win()
        if not win then return end
        if State.is_preview(win, buf) then return end
        if State.is_removed(win, buf) then return end

        -- 纳入分组时转正 buflisted：LSP 跨文件编辑加载的 buffer 是 unlisted 的，
        -- 让分组与 :ls 可见；不改变 Neovim 自身的退出保护（与预览 promote 同语义）
        vim.bo[buf].buflisted = true
        State.add(win, buf)

        -- 归属窗口停在占位内容（dashboard / 未命名空 buffer）时直接切过去显示：
        -- 用户从被忽略的 tab（如 vv-git 编辑窗）回来时第一眼看到的就是刚改的文件，
        -- 而不是仍停在 dashboard、误以为修改丢了。已在显示编辑内容或预览的窗口不打扰
        local cur = vim.api.nvim_win_get_buf(win)
        if Window.placeholder_buf(cur) and not State.is_preview(win, cur) then
          local replaced = pcall(vim.api.nvim_win_set_buf, win, buf)
          if replaced then
            CursorHandoff.watch({ win = win, buf = buf })
            State.remove_from_win(win, cur)
            -- 空白标签已被顶替；仍被其他分组/窗口引用时保留，否则清理 startup 空 buffer
            if not State.contains_buf(cur) then require('vv-utils.bufdelete').wipe_if_throwaway(cur) end
          end
        end

        View.refresh()
      end)
    end,
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
  vim.api.nvim_create_user_command('VVBufferlineFirst', function() M.jump_to_end('first') end, {})
  vim.api.nvim_create_user_command('VVBufferlineLast', function() M.jump_to_end('last') end, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseOthers', M.close_others, {})
  vim.api.nvim_create_user_command('VVBufferlineCloseAll', function() M.close_all() end, {})

  install_default_keys()

  M.enable()
end

return M
