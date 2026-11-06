-- 审计回归：验证异步生命周期、窗口归属、预览隔离与键位所有权的真实副作用
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua', icons = true })

T['已排队的修改不能越过 disable 或重新 setup'] = function()
  child.lua_func(function()
    for _, transition in ipairs({ 'disable', 'setup', 'reenable' }) do
      Smoke.setup()
      local bl = require('vv-bufferline')
      local buf = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/' .. transition .. '.txt')
      vim.fn.bufload(buf)
      -- 本 autocmd 晚于生产监听器：生产回调已排队，但尚未执行
      local transitioned = false
      vim.api.nvim_create_autocmd('OptionSet', {
        pattern = 'modified', once = true,
        callback = function()
          if transition == 'setup' then
            bl.setup({ track_modified = false })
          else
            bl.disable()
            if transition == 'reenable' then bl.enable() end
          end
          transitioned = true
        end,
      })
      vim.bo[buf].modified = true
      vim.wait(50)
      assert(transitioned, '测试未进入 modified 事件')
      assert(not vim.bo[buf].buflisted, transition .. ' 后旧回调仍将 buffer 转正')
    end
  end)
end

T['后台修改不能顶替 nofile 面板而应归属编辑窗口'] = function()
  child.lua_func(function()
    Smoke.setup()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/editor.txt')
    local editor = vim.api.nvim_get_current_win()
    vim.cmd.vsplit()
    local panel_win = vim.api.nvim_get_current_win()
    local panel = vim.api.nvim_create_buf(false, true)
    vim.bo[panel].bufhidden = 'wipe'
    vim.bo[panel].filetype = 'custom-panel'
    vim.api.nvim_win_set_buf(panel_win, panel)
    local buf = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/background.txt')
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'unsaved' })
    vim.wait(100)
    assert(vim.api.nvim_win_get_buf(panel_win) == panel, '后台修改顶替并销毁了 nofile 面板')
    assert(require('vv-bufferline').has(editor, buf), '后台修改未归属正常编辑窗口')
  end)
end

T['未命名空窗口可被修改文件顶替但命名的 unlisted 内容不可被顶替'] = function()
  child.lua_func(function()
    Smoke.setup()
    local win = vim.api.nvim_get_current_win()
    local blank = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(win, blank)
    local changed = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/from-lsp.txt')
    vim.fn.bufload(changed)
    vim.api.nvim_buf_set_lines(changed, 0, -1, false, { 'unsaved' })
    vim.wait(100)
    assert(vim.api.nvim_win_get_buf(win) == changed, 'listed 未命名空窗口没有显示修改文件')
    assert(not vim.api.nvim_buf_is_valid(blank), '顶替后留下无引用的空白标签')
    local named = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/unlisted.txt')
    vim.fn.bufload(named)
    vim.api.nvim_win_set_buf(win, named)
    local another = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/another.txt')
    vim.fn.bufload(another)
    vim.api.nvim_buf_set_lines(another, 0, -1, false, { 'unsaved' })
    vim.wait(100)
    assert(vim.api.nvim_win_get_buf(win) == named, '命名 unlisted 文件被误当成空占位')
  end)
end

T['其他窗口的预览不得因后台修改加入当前分组'] = function()
  child.lua_func(function()
    Smoke.setup()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/main.txt')
    local main = vim.api.nvim_get_current_win()
    vim.cmd.vsplit()
    local preview_win = vim.api.nvim_get_current_win()
    local buf = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/preview.txt')
    vim.fn.bufload(buf)
    local bl = require('vv-bufferline')
    bl.mark_preview(preview_win, buf)
    vim.api.nvim_win_set_buf(preview_win, buf)
    vim.api.nvim_set_current_win(main)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'unsaved preview' })
    vim.wait(100)
    assert(not bl.has(main, buf), '其他窗口的预览被加入当前分组')
    assert(not vim.bo[buf].buflisted, 'bufferline 越权转正了预览')
    vim.bo[buf].buflisted = true
    bl.clear_preview(preview_win, buf, { promote = true })
    assert(bl.has(preview_win, buf) and not bl.has(main, buf), 'promote 后出现重复归属')
  end)
end

T['重复 setup 按旧 leader 清理且保留外部重绑'] = function()
  child.lua_func(function()
    vim.g.mapleader = ','
    Smoke.setup()
    local external = function() end
    vim.keymap.set('n', ']b', external)
    vim.g.mapleader = ' '
    require('vv-bufferline').setup({ keys = false })
    assert(vim.fn.maparg(',bd', 'n') == '', 'leader 改变后旧键位残留')
    assert(vim.fn.maparg(']b', 'n', false, true).callback == external, '卸载误删外部重绑')
  end)
end

T['取消 close_all 时 hook 不得报告成功'] = function()
  child.lua_func(function()
    local ctx
    Smoke.setup({ hooks = { after_close = function(value) ctx = value end } })
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/cancel.txt')
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'keep me' })
    local confirm = vim.fn.confirm
    vim.fn.confirm = function() return 3 end
    local ok, err = pcall(require('vv-bufferline').close_all, { close_windows = true })
    vim.fn.confirm = confirm
    assert(ok, err)
    assert(ctx and ctx.completed == false, '取消关闭仍报告成功，调用方会错误关闭 explorer')
    assert(vim.api.nvim_get_current_buf() == buf and vim.bo[buf].modified, '取消后编辑内容丢失')
  end)
end

-- 不替换生产渲染或诊断结果，只包裹真实聚合入口计数，并读回实际展示宿主
T['一次刷新在多分屏共享诊断且后续刷新读取最新诊断'] = function()
  child.lua_func(function()
    Smoke.setup()
    local wins, bufs = {}, {}
    for i = 1, 3 do
      if i > 1 then vim.cmd.split() end
      vim.cmd.edit(vim.env.VV_TEST_TMP .. '/diag-' .. i .. '.txt')
      wins[i], bufs[i] = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    end
    local ns = vim.api.nvim_create_namespace('刷新诊断')
    local severity = vim.diagnostic.severity
    for i, buf in ipairs(bufs) do
      local diagnostics = {}
      for _ = 1, i do
        diagnostics[#diagnostics + 1] = { lnum = 0, col = 0, message = '问题', severity = severity.ERROR }
      end
      vim.diagnostic.set(ns, buf, diagnostics)
    end
    vim.wait(50)
    local D = require('vv-utils.diagnostics')
    local collect, calls = D.collect_by_path, 0
    D.collect_by_path = function()
      calls = calls + 1
      return collect()
    end
    local View = require('vv-bufferline.view')
    View.refresh()
    for i, win in ipairs(wins) do
      local text = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
      local symbol = D.symbol_for({ [severity.ERROR] = i })
      assert(text:find('diag-' .. i .. '.txt', 1, true), '分屏未显示自己的文件')
      assert(text:find(symbol.glyph .. ' ' .. i, 1, true), '分屏诊断数量或级别错误')
    end
    assert(calls == 1, '一次多分屏刷新应只聚合一次，实际 ' .. calls)

    vim.diagnostic.reset(ns, bufs[1])
    vim.diagnostic.set(ns, bufs[2], { { lnum = 0, col = 0, message = '新警告', severity = severity.WARN } })
    calls = 0
    View.refresh()
    assert(not vim.wo[wins[1]].winbar:find('VVBufferlineDiag', 1, true), '清除诊断后残留旧徽标')
    local text = vim.api.nvim_eval_statusline(vim.wo[wins[2]].winbar, { winid = wins[2], use_winbar = true }).str
    assert(text:find(D.symbol_for({ [severity.WARN] = 1 }).glyph .. ' 1', 1, true), '下一刷新未读取最新诊断')
    assert(calls == 1, '下一刷新应重新聚合且只聚合一次')
  end)
end

T['诊断关闭或无渲染目标时不聚合且清理展示'] = function()
  child.lua_func(function()
    Smoke.setup()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/disabled.txt')
    vim.cmd.split()
    local ns = vim.api.nvim_create_namespace('关闭诊断')
    vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = '问题', severity = 1 } })
    vim.wait(50)
    local D = require('vv-utils.diagnostics')
    local collect, calls = D.collect_by_path, 0
    D.collect_by_path = function()
      calls = calls + 1
      return collect()
    end
    local bl, View = require('vv-bufferline'), require('vv-bufferline.view')
    for _, target in ipairs({ 'winbar', 'tabline' }) do
      bl.setup({ diagnostics = { enabled = false }, render_target = target })
      calls = 0
      View.refresh()
      local bar = target == 'winbar' and vim.wo.winbar or vim.o.tabline
      assert(bar:find('disabled.txt', 1, true), '关闭诊断不应隐藏文件标签')
      assert(not bar:find('VVBufferlineDiag', 1, true), '关闭诊断后徽标残留')
      assert(calls == 0, '诊断关闭时仍进行聚合')

      bl.setup({ render_target = target })
      vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
      calls = 0
      View.refresh()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        assert(vim.wo[win].winbar == '', '无目标时仍残留 winbar')
      end
      if target == 'tabline' then assert(vim.o.tabline == '', '无目标时仍残留 tabline') end
      assert(calls == 0, '无渲染目标时仍进行聚合')
      vim.api.nvim_tabpage_del_var(0, 'vv_bufferline_ignore')
    end
  end)
end

T['突发事件合并刷新但同步记录访问与删除并显示最终诊断'] = function()
  child.lua_func(function()
    Smoke.setup()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/start.txt')
    vim.wait(50)
    local View = require('vv-bufferline.view')
    local refresh, calls = View.refresh, 0
    View.refresh = function()
      calls = calls + 1
      return refresh()
    end
    local State = require('vv-bufferline.state')
    local win = vim.api.nvim_get_current_win()
    local bufs = {}
    for _, name in ipairs({ 'first', 'deleted', 'last' }) do
      vim.cmd.edit(vim.env.VV_TEST_TMP .. '/' .. name .. '.txt')
      bufs[#bufs + 1] = vim.api.nvim_get_current_buf()
      assert(State.has_in_win(win, bufs[#bufs]), '计划刷新前丢失同步访问记录')
    end
    vim.api.nvim_buf_delete(bufs[2], { force = true })
    assert(not State.has_in_win(win, bufs[2]), '删除归属被延迟到刷新')
    local ns = vim.api.nvim_create_namespace('突发诊断')
    for _ = 1, 5 do
      vim.diagnostic.set(ns, bufs[3], { { lnum = 0, col = 0, message = '最终问题', severity = 1 } })
      vim.api.nvim_exec_autocmds('WinResized', {})
      vim.api.nvim_exec_autocmds('BufWritePost', { buffer = bufs[3] })
    end
    assert(calls == 0, '事件刷新应保持计划调度而非同步渲染')
    vim.wait(50)
    local text = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
    assert(text:find('first.txt', 1, true) and text:find('last.txt', 1, true), '合并刷新丢失访问过的标签')
    assert(not text:find('deleted.txt', 1, true), '最终展示残留已删除标签')
    local symbol = require('vv-utils.diagnostics').symbol_for({ [1] = 1 })
    assert(text:find(symbol.glyph .. ' 1', 1, true), '合并后未显示最终诊断')
    assert(calls == 1, '同批突发事件应只刷新一次，实际 ' .. calls)
  end)
end

for _, transition in ipairs({ 'disable', 'reenable', 'setup' }) do
  T['排队刷新不能越过 owner 生命周期：' .. transition] = function()
    child.lua_func(function(transition)
      Smoke.setup()
      vim.cmd.edit(vim.env.VV_TEST_TMP .. '/owner-' .. transition .. '.txt')
      vim.wait(50)
      local bl = require('vv-bufferline')
      local ns = vim.api.nvim_create_namespace('owner-' .. transition)
      vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = '待刷新', severity = 1 } })
      if transition == 'setup' then
        bl.setup({ keys = false })
      else
        bl.disable()
        if transition == 'reenable' then bl.enable() end
      end
      -- 新 owner 完成同步 enable 渲染后，外部写入不能被旧队列覆盖
      vim.wo.winbar = '外部宿主'
      vim.wait(50)
      assert(vim.wo.winbar == '外部宿主', transition .. ' 后旧回调写回了展示')
      if transition == 'disable' then
        vim.api.nvim_exec_autocmds('WinResized', {})
        bl.enable()
        vim.wo.winbar = '禁用期哨兵'
        vim.wait(50)
        assert(vim.wo.winbar == '禁用期哨兵', '禁用期间的事件不能排队写入新 owner')
      end
      vim.api.nvim_exec_autocmds('WinResized', {})
      vim.wait(50)
      assert(vim.wo.winbar:find('owner-' .. transition .. '.txt', 1, true), '新 owner 的刷新请求失效')
      assert(vim.wo.winbar:find('VVBufferlineDiag', 1, true), '新 owner 未显示真实诊断')
    end, transition)
  end
end

T['tabline 合并诊断刷新并跟随当前分组保留修改标记'] = function()
  child.lua_func(function()
    Smoke.setup({ render_target = 'tabline' })
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/tab-left.txt')
    local left = vim.api.nvim_get_current_win()
    vim.cmd.split()
    vim.cmd.edit(vim.env.VV_TEST_TMP .. '/tab-right.txt')
    local right = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '未保存内容' })
    vim.wait(50)
    local D = require('vv-utils.diagnostics')
    local collect, calls = D.collect_by_path, 0
    D.collect_by_path = function()
      calls = calls + 1
      return collect()
    end
    local ns = vim.api.nvim_create_namespace('tabline诊断')
    for _ = 1, 5 do
      vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = '问题', severity = 1 } })
    end
    vim.wait(50)
    local text = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
    assert(text:find('tab-right.txt', 1, true) and text:find('●', 1, true), 'tabline 丢失当前文件或修改标记')
    assert(text:find(D.symbol_for({ [1] = 1 }).glyph .. ' 1', 1, true), 'tabline 未显示真实诊断')
    assert(calls == 1, 'tabline 突发诊断应合并为一次聚合，实际 ' .. calls)
    assert(vim.wo[left].winbar == '' and vim.wo[right].winbar == '', 'tabline 模式污染了 winbar')
    vim.api.nvim_set_current_win(left)
    vim.wait(50)
    assert(vim.o.tabline:find('tab-left.txt', 1, true), '切窗后未切换 tabline 分组')
    assert(not vim.o.tabline:find('tab-right.txt', 1, true), '不同窗口分组混入同一 tabline')
  end)
end

return T
