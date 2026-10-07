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

return T
