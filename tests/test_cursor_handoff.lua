-- 自动顶替占位窗口后，应交接源编辑窗口最后的光标，而不是第一次修改时的位置
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua', icons = true })

for _, via_panel in ipairs({ false, true }) do
  T[via_panel and '修改后先回面板再关闭 tab 仍恢复最后光标' or '连续修改后关闭 tab 恢复最后光标且仅恢复一次'] = function()
    child.lua_func(function(panel_first)
      Smoke.setup()
      local main = vim.api.nvim_get_current_win()
      local dash = vim.api.nvim_create_buf(false, true)
      vim.bo[dash].filetype = 'dashboard'
      vim.bo[dash].bufhidden = 'wipe'
      vim.api.nvim_win_set_buf(main, dash)
      local lines = {}
      for i = 1, 100 do lines[i] = ('line %03d original content'):format(i) end
      local path = vim.env.VV_TEST_TMP .. '/edited.txt'
      vim.fn.writefile(lines, path)

      vim.cmd('tab split')
      vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
      vim.cmd.edit(path)
      local source = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      vim.wo[source].diff = true
      vim.api.nvim_win_set_cursor(source, { 20, 4 })
      vim.api.nvim_buf_set_text(buf, 19, 4, 19, 4, { 'first' })
      vim.wait(100)
      assert(vim.api.nvim_win_get_buf(main) == buf, '修改文件没有自动顶替 dashboard')

      -- modified 已经是 true，第二次编辑不会再次触发 false→true；退出时必须取最新位置
      vim.api.nvim_win_set_cursor(source, { 70, 9 })
      vim.api.nvim_buf_set_text(buf, 69, 9, 69, 9, { 'last' })
      vim.api.nvim_win_set_cursor(source, { 70, 13 })
      vim.wait(80)
      local expected = vim.api.nvim_win_get_cursor(source)
      local before = vim.api.nvim_win_get_cursor(main)
      if panel_first then
        vim.cmd.vnew()
        local panel = vim.api.nvim_get_current_buf()
        vim.bo[panel].buftype = 'nofile'
        vim.bo[panel].filetype = 'vv-git'
      end
      vim.cmd.tabclose()
      vim.wait(80)
      local actual = vim.api.nvim_win_get_cursor(main)
      assert(vim.deep_equal(actual, expected), vim.inspect({
        expected_source = expected, target_before_close = before, target_after_close = actual,
      }))
      assert(vim.api.nvim_get_current_win() == main, '返回窗口不正确')

      -- 交接是一次性的；之后使用主窗口不能被旧位置覆盖
      vim.api.nvim_win_set_cursor(main, { 8, 2 })
      vim.cmd('tab split')
      vim.cmd.tabclose()
      vim.wait(50)
      assert(vim.deep_equal(vim.api.nvim_win_get_cursor(main), { 8, 2 }), '重复进入覆盖了主窗口的新光标')
    end, via_panel)
  end
end

T['已有编辑窗口不会继承 ignored tab 的光标'] = function()
  child.lua_func(function()
    Smoke.setup()
    local path = vim.env.VV_TEST_TMP .. '/existing.txt'
    vim.fn.writefile({ 'first existing line', 'second existing line', 'third existing line' }, path)
    vim.cmd.edit(path)
    local main = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(main, { 1, 2 })
    vim.cmd('tab split')
    vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_text(buf, 2, 5, 2, 5, { 'edit' })
    vim.api.nvim_win_set_cursor(0, { 3, 9 })
    vim.wait(100)
    vim.cmd.tabclose()
    vim.wait(50)
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(main), { 1, 2 }), '已有窗口独立光标被覆盖')
  end)
end

T['禁用重启与目标换文件会取消旧光标交接'] = function()
  child.lua_func(function()
    for _, transition in ipairs({ 'disable', 'setup', 'replace' }) do
      Smoke.setup()
      local bl = require('vv-bufferline')
      local main = vim.api.nvim_get_current_win()
      local blank = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(main, blank)
      vim.cmd('tab split')
      vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
      vim.cmd.edit(vim.env.VV_TEST_TMP .. '/' .. transition .. '.txt')
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first line', 'second line', 'third line' })
      vim.api.nvim_win_set_cursor(0, { 3, 5 })
      vim.wait(100)
      assert(vim.api.nvim_win_get_buf(main) == buf, '光标交接前置条件未建立')
      if transition == 'disable' then
        bl.disable()
        bl.enable()
      elseif transition == 'setup' then
        bl.setup()
      else
        local other = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(other, vim.env.VV_TEST_TMP .. '/replacement.txt')
        vim.api.nvim_buf_set_lines(other, 0, -1, false, { 'replacement line', 'keep cursor here' })
        vim.api.nvim_win_set_buf(main, other)
      end
      vim.api.nvim_win_set_cursor(main, { 2, 1 })
      vim.cmd.tabclose()
      vim.wait(50)
      assert(vim.deep_equal(vim.api.nvim_win_get_cursor(main), { 2, 1 }), transition .. ' 后旧光标仍写回')
    end
  end)
end

return T
