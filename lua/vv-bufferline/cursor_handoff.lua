-- 自动顶替占位窗口时的一次性光标交接：源窗口离开时采样，目标首次进入时应用
-- 不同步普通 split，不依赖具体 diff 插件，也不复制 diff/scrollbind 等窗口选项
local Window = require('vv-bufferline.window')
local M = {}
local pending = {}
local group

---仅从仍显示同一 buffer 的源窗口采样；切文件/关窗后保留最后有效位置
local function sample(entry)
  if vim.api.nvim_win_is_valid(entry.source) and vim.api.nvim_win_get_buf(entry.source) == entry.buf then
    entry.cursor = vim.api.nvim_win_get_cursor(entry.source)
  end
end

---为成功顶替占位的目标记录源窗口；无真实可见源（如纯 LSP 隐藏编辑）则不交接
---@param opts { win: integer, buf: integer }
function M.watch(opts)
  if not group then return end

  ---@type integer?
  local source = vim.api.nvim_get_current_win()
  local function matches(win)
    return win ~= opts.win and Window.is_editor_win(win) and vim.api.nvim_win_get_buf(win) == opts.buf
  end

  if not matches(source) then
    source = nil
    for _, win in ipairs(vim.fn.win_findbuf(opts.buf)) do
      if matches(win) then
        source = win
        break
      end
    end
  end
  if not source then return end

  local entry = { source = source, buf = opts.buf }
  sample(entry)
  pending[opts.win] = entry
end

---安装事件；只在确有待交接记录时处理，重复启用不重复注册
function M.enable()
  if group then return end
  group = vim.api.nvim_create_augroup('vv_bufferline_cursor_handoff', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
    group = group,
    callback = function()
      local source = vim.api.nvim_get_current_win()
      for _, entry in pairs(pending) do
        if entry.source == source then sample(entry) end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local entry = pending[win]
      if not entry then return end
      -- 消费后不再跟随源窗口，保留目标从此独立的光标；换了 buffer 则直接取消
      pending[win] = nil
      if vim.api.nvim_win_get_buf(win) ~= entry.buf then return end
      sample(entry)
      if entry.cursor then
        local line = math.min(entry.cursor[1], vim.api.nvim_buf_line_count(entry.buf))
        vim.api.nvim_win_set_cursor(win, { line, entry.cursor[2] })
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win then pending[win] = nil end
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      for win, entry in pairs(pending) do
        if entry.buf == args.buf then pending[win] = nil end
      end
    end,
  })
end

---取消全部待交接记录并清理事件，disable/setup 后旧位置不得再次写回
function M.disable()
  pending = {}
  if group then vim.api.nvim_del_augroup_by_id(group) end
  group = nil
end

return M
