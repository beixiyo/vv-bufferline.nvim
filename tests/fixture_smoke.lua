-- 每个子进程的场景辅助，不参与测试收集。
vim.api.nvim_set_hl(0, 'MiniIconsBlue', { fg = '#4aa5f0' })
vim.api.nvim_set_hl(0, 'DiagnosticError', { fg = '#f7768e' })
package.loaded['nvim-web-devicons'] = {
  get_icon = function()
    return 'T', 'MiniIconsBlue'
  end,
}

local function setup(extra)
  pcall(vim.cmd, 'silent! only')
  pcall(function() require('vv-bufferline').disable() end)
  require('vv-bufferline.state').reset()
  require('vv-bufferline.winbar_host').reset()
  local opts = {
    colors = {
      fill_bg = '#111111',
      inactive_bg = '#222222',
      active_bg = '#333333',
      inactive_fg = '#888888',
      active_fg = '#ffffff',
      muted_fg = '#777777',
      modified_fg = '#ffaa00',
    },
  }
  require('vv-bufferline').setup(vim.tbl_deep_extend('force', opts, extra or {}))
end

local function assert_clicks_work_after_reenable(transition, suffix)
  setup({ show_close = true })
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-reenable-a-' .. suffix .. '.ts'))
  local a = vim.api.nvim_get_current_buf()
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-reenable-b-' .. suffix .. '.ts'))
  local b = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.wait(80)

  transition()
  require('vv-bufferline.view').refresh()

  local bar = vim.wo[win].winbar
  assert(bar:find('@v:lua.__vv_bufferline_select@', 1, true), '渲染的 bar 缺少 select 点击目标')
  assert(bar:find('@v:lua.__vv_bufferline_close@', 1, true), '渲染的 bar 缺少 close 点击目标')
  assert(type(_G.__vv_bufferline_select) == 'function', 'select 点击处理器未重装')
  assert(type(_G.__vv_bufferline_close) == 'function', 'close 点击处理器未重装')

  local View = require('vv-bufferline.view')
  local mouse_interaction_win = View.mouse_interaction_win
  View.mouse_interaction_win = function() return win end
  local ok, err = pcall(function()
    _G.__vv_bufferline_select(a)
  assert(vim.api.nvim_win_get_buf(win) == a, '重装后的 select 处理器未切换缓冲区')

    _G.__vv_bufferline_close(b)
    vim.wait(80)
    assert(not vim.bo[b].buflisted, '重装后的 close 处理器未关闭目标缓冲区')
  end)
  View.mouse_interaction_win = mouse_interaction_win
  if not ok then error(err) end
end

-- 构造「b 已从 top 分组删除、但仍存活（bottom 分屏持有）」的状态
local function split_with_removed_buffer()
  setup()
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-rm-a.ts'))
  vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-rm-b.ts'))
  local b = vim.api.nvim_get_current_buf()
  vim.cmd('split') -- 新窗口与原窗口都显示 b，焦点在新窗口
  local bottom = vim.api.nvim_get_current_win()
  local top
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= bottom then
      top = w
      break
    end
  end
  vim.api.nvim_set_current_win(top)
  require('vv-bufferline').close_current() -- 从 top 删除 b；b 因 bottom 持有而存活
  vim.wait(50)
  return top, bottom, b
end

Smoke = { setup = setup, assert_clicks_work_after_reenable = assert_clicks_work_after_reenable, split_with_removed_buffer = split_with_removed_buffer }
