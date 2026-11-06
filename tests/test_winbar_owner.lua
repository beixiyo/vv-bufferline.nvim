local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua', icons = true })

local function run(case)
  child.lua_func(function()
    Owner = {}
    function Owner.read()
      return vim.api.nvim_get_option_value('winbar', { win = 0, scope = 'local' })
    end
    function Owner.write(value)
      vim.api.nvim_set_option_value('winbar', value, { win = 0, scope = 'local' })
    end
    function Owner.start(value)
      vim.cmd.edit(vim.env.VV_TEST_TMP .. '/owner.txt')
      Owner.write(value)
      Smoke.setup({ diagnostics = { enabled = false }, hover_close = false, keys = false })
      Owner.assert_rendered('owner.txt')
      return require('vv-bufferline')
    end
    function Owner.assert_rendered(name)
      local text = vim.api.nvim_eval_statusline(Owner.read(), { winid = 0, use_winbar = true }).str
      assert(text:find(name, 1, true), '真实 winbar 未显示文件：' .. name)
    end
  end)
  child.lua_func(case)
end

T['disable 保留后来 owner 且重复关闭和排队刷新不再覆盖'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    vim.api.nvim_exec_autocmds('WinResized', {})
    Owner.write('LATEROWNER')
    bl.disable()
    assert(Owner.read() == 'LATEROWNER', 'disable 覆盖了后来 owner')
    bl.disable()
    vim.wait(50)
    assert(Owner.read() == 'LATEROWNER', '重复关闭或旧刷新覆盖了后来 owner')
  end)
end

T['无人接管时按最后一次渲染值恢复初始局部值'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    local first = Owner.read()
    vim.api.nvim_buf_set_name(0, vim.env.VV_TEST_TMP .. '/renamed.txt')
    require('vv-bufferline.view').refresh()
    Owner.assert_rendered('renamed.txt')
    assert(Owner.read() ~= first, '前置条件：第二次渲染没有改变 winbar')
    bl.disable()
    assert(Owner.read() == 'USERBAR', '最后一次 applied 未被识别或原始值未恢复')
  end)
end

T['空局部值在重配和关闭后继续跟随新的 global'] = function()
  run(function()
    vim.api.nvim_set_option_value('winbar', 'GLOBAL_BEFORE', { scope = 'global' })
    local bl = Owner.start('')
    vim.api.nvim_set_option_value('winbar', 'GLOBAL_AFTER', { scope = 'global' })
    bl.setup({ diagnostics = { enabled = false }, hover_close = false, keys = false })
    Owner.assert_rendered('owner.txt')
    bl.disable()
    assert(Owner.read() == '', '恢复将 effective 值固化成了局部值')
    assert(vim.wo.winbar == 'GLOBAL_AFTER', '空局部值没有跟随新 global')
    vim.api.nvim_set_option_value('winbar', 'GLOBAL_LATEST', { scope = 'global' })
    assert(vim.wo.winbar == 'GLOBAL_LATEST', '关闭后 global fallback 被冻结')
  end)
end

T['后来 owner 清空局部值时保留 global fallback'] = function()
  run(function()
    vim.api.nvim_set_option_value('winbar', 'GLOBAL', { scope = 'global' })
    local bl = Owner.start('USERBAR')
    Owner.write('')
    bl.disable()
    assert(Owner.read() == '' and vim.wo.winbar == 'GLOBAL', '后来 owner 的空局部值被覆盖')
  end)
end

T['关闭重开以后来 owner 为新基线而非复用旧记录'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    Owner.write('LATEROWNER')
    bl.disable()
    bl.enable()
    Owner.assert_rendered('owner.txt')
    bl.disable()
    assert(Owner.read() == 'LATEROWNER', '重开仍恢复到上一轮 USERBAR')
  end)
end

T['启用期间刷新仍接管但关闭恢复本轮初始基线'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    Owner.write('LATEROWNER')
    vim.api.nvim_exec_autocmds('WinResized', {})
    vim.wait(50)
    Owner.assert_rendered('owner.txt')
    bl.disable()
    assert(Owner.read() == 'USERBAR', '本批不应改变启用期间持续接管的基线策略')
  end)
end

T['同窗切 buffer 并刷新后关闭不覆盖后来 owner'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    local win = vim.api.nvim_get_current_win()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/second.txt')
    vim.wait(50)
    assert(vim.api.nvim_get_current_win() == win, '前置条件：必须在同一窗口切换')
    Owner.assert_rendered('second.txt')
    Owner.write('SECOND_OWNER')
    bl.disable()
    assert(Owner.read() == 'SECOND_OWNER', '同窗切 buffer 后错误恢复旧 buffer 的基线')
  end)
end

T['同窗切 buffer 尚未刷新时关闭不改写新 buffer 局部值'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/pending.txt')
    assert(Owner.read() == '', '前置条件：新 buffer 应有空局部值')
    bl.disable()
    vim.wait(50)
    assert(Owner.read() == '', '关闭把旧 buffer 的基线写到了尚未渲染的新 buffer')
  end)
end

T['窗口失去展示资格时不把后来 owner 当成本插件孤儿串清除'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    local later = 'LATEROWNER VVBufferline'
    Owner.write(later)
    vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
    require('vv-bufferline.view').refresh()
    assert(Owner.read() == later, 'restore 后的 marker 清扫绕过了 exact applied 守卫')
    bl.disable()
    assert(Owner.read() == later, '释放后的 disable 再次覆盖了后来 owner')
  end)
end

T['重配到 tabline 不清除后来 owner 的 winbar'] = function()
  run(function()
    local bl = Owner.start('USERBAR')
    Owner.write('LATEROWNER')
    bl.setup({ render_target = 'tabline', diagnostics = { enabled = false }, hover_close = false, keys = false })
    assert(Owner.read() == 'LATEROWNER', '重配释放 winbar 时覆盖了后来 owner')
    local text = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
    assert(text:find('owner.txt', 1, true), '重配后未真实渲染到 tabline')
    bl.disable()
    assert(Owner.read() == 'LATEROWNER', 'tabline 关闭误改 winbar')
  end)
end

T['关闭窗口后新窗口独立保存并恢复自己的基线'] = function()
  run(function()
    local bl = Owner.start('CLOSED_USERBAR')
    local closed = vim.api.nvim_get_current_win()
    vim.cmd.vnew()
    vim.api.nvim_win_close(closed, true)
    vim.cmd.vnew()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/reopened.txt')
    Owner.write('NEW_USERBAR')
    vim.wait(50)
    Owner.assert_rendered('reopened.txt')
    bl.disable()
    assert(Owner.read() == 'NEW_USERBAR', '新窗口复用了已关闭窗口的基线或 applied')
  end)
end

return T
