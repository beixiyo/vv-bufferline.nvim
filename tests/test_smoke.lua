-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua', icons = true })

T["对每个分割窗口当前缓冲区渲染独立标签项"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-left.ts'))
      vim.cmd('vsplit')
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-right.ts'))
      vim.wait(100)

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local tail = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ':t')
        assert(vim.wo[win].winbar:find(tail, 1, true), 'winbar 未包含 ' .. tail)
      end
  end)
end

T["图标高亮来自 devicons"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
    setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-icon.ts'))
      vim.wait(100)

      local bar = vim.wo.winbar
      assert(bar:find('VVBufferlineIconCurrentMiniIconsBlue', 1, true), '图标高亮缺失')
  end)
end

T["渲染最高级别诊断与数量"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
    setup()
    vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/diagnostic.ts'))
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'const x: number = "bad"' })

      local ns = vim.api.nvim_create_namespace('vv-bufferline-test')
      vim.diagnostic.set(ns, buf, {
        {
          lnum = 0,
          col = 0,
          message = 'bad type',
          severity = vim.diagnostic.severity.ERROR,
        },
      })
      vim.wait(100)

      local diag_error = require('vv-icons').diagnostics_error
      assert(vim.wo.winbar:find(diag_error .. ' 1', 1, true), '诊断徽标缺失')
      assert(vim.wo.winbar:find('VVBufferlineDiagCurrentDiagnosticError', 1, true), '诊断高亮缺失')
  end)
end

T["悬停时显示关闭按钮且不改变项宽"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-hover-a.ts'))
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-hover-b.ts'))
      vim.wait(100)

      local State = require('vv-bufferline.state')
      local View = require('vv-bufferline.view')
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      local before = vim.wo[win].winbar
      local before_width
      for _, item in ipairs(State.layouts[win] or {}) do
        if item.buf == buf then
          before_width = item.end_col - item.start_col + 1
          break
        end
      end

      assert(before_width, '悬停缓冲区未记录在布局中')
      assert(not before:find('×', 1, true), '悬停前应隐藏关闭按钮')

      State.set_hovered(win, buf)
      View.refresh()
      vim.wait(50)

      local after = vim.wo[win].winbar
      local after_width
      for _, item in ipairs(State.layouts[win] or {}) do
        if item.buf == buf then
          after_width = item.end_col - item.start_col + 1
          break
        end
      end

      assert(after:find('×', 1, true), '悬停时应显示关闭按钮')
      assert(after_width == before_width, '悬停关闭按钮不应改变项宽')

      State.clear_hovered()
      View.refresh()
      assert(not vim.wo[win].winbar:find('×', 1, true), '清除悬停后应隐藏关闭按钮')
  end)
end

T["注册分割窗口级关闭命令"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
    setup()
      assert(vim.fn.exists(':VVBufferlineCloseLeft') == 2, '缺少 VVBufferlineCloseLeft 命令')
      assert(vim.fn.exists(':VVBufferlineCloseRight') == 2, '缺少 VVBufferlineCloseRight 命令')
      assert(vim.fn.exists(':VVBufferlineCloseCurrent') == 2, '缺少 VVBufferlineCloseCurrent 命令')
      assert(vim.fn.exists(':VVBufferlineCloseAll') == 2, '缺少 VVBufferlineCloseAll 命令')
  end)
end

T["close_current 在保留共享缓冲区的同窗后关闭空分割"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-shared.ts'))
      local shared = vim.api.nvim_get_current_buf()
      vim.cmd('split')
      local close_win = vim.api.nvim_get_current_win()
      local sibling_win
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= close_win then
          sibling_win = win
          break
        end
      end

      local before_count = #vim.api.nvim_tabpage_list_wins(0)
      require('vv-bufferline').close_current()
      vim.wait(100)

      assert(#vim.api.nvim_tabpage_list_wins(0) == before_count - 1, 'close_current 未关闭已清空分割窗口')
      assert(vim.api.nvim_win_is_valid(sibling_win), '同窗口分割失效')
      assert(vim.api.nvim_win_get_buf(sibling_win) == shared, '同窗不再显示共享缓冲区')
      assert(not vim.api.nvim_win_is_valid(close_win), '已清空分割仍保留在布局中')
      assert(vim.bo[shared].buflisted, '尽管同窗仍占有，仍删除了共享缓冲区')
  end)
end

T["局部分组清空时 close_current 关闭分割窗口"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-layout-left.ts'))
      local left = vim.api.nvim_get_current_win()
      vim.cmd('vsplit')
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-layout-right.ts'))
      local right = vim.api.nvim_get_current_win()
      local right_buf = vim.api.nvim_get_current_buf()
      vim.wait(80)

      require('vv-bufferline').close_left()
      vim.wait(80)
      require('vv-bufferline').close_current()
      vim.wait(100)

      assert(vim.api.nvim_win_is_valid(left), '左侧分割被关闭')
      assert(not vim.api.nvim_win_is_valid(right), '空的右侧分割仍保留在布局中')
      assert(not vim.bo[right_buf].buflisted, '右侧缓冲区仍在列表中')
      assert(#vim.api.nvim_tabpage_list_wins(0) == 1, '布局应折叠为一个编辑器分割')
  end)
end

T["关闭已修改缓冲区时按确认结果决定是否强制删除"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-modified.ts'))
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'modified' })

      local original_confirm = vim.fn.confirm
      local confirm_calls = 0
      vim.fn.confirm = function()
        confirm_calls = confirm_calls + 1
        return 2
      end

      require('vv-bufferline').close_current()
      vim.fn.confirm = original_confirm
      vim.wait(100)

      assert(confirm_calls == 1, '非强制关闭已修改缓冲区时应请求确认')
      assert(not vim.bo[buf].buflisted, '选择不保存后应强制删除已修改缓冲区')
  end)
end

T["强制关闭已修改缓冲区时跳过确认"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-force.ts'))
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'modified' })

      local original_confirm = vim.fn.confirm
      vim.fn.confirm = function() error('强制关闭不应请求确认') end
      local ok, err = pcall(require('vv-bufferline').close_current, { force = true })
      vim.fn.confirm = original_confirm
      if not ok then error(err) end
      vim.wait(100)

      assert(not vim.bo[buf].buflisted, '强制关闭应删除已修改缓冲区')
  end)
end

T["winbar 关闭按钮行为与 close_current 一致关闭当前空分割"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-mouse-left.ts'))
      local left = vim.api.nvim_get_current_win()
      vim.cmd('vsplit')
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-mouse-right.ts'))
      local right = vim.api.nvim_get_current_win()
      local right_buf = vim.api.nvim_get_current_buf()
      vim.wait(80)

      require('vv-bufferline').close_left()
      vim.wait(80)

      local View = require('vv-bufferline.view')
      local mouse_interaction_win = View.mouse_interaction_win
      View.mouse_interaction_win = function() return right end
      local ok, err = pcall(function() _G.__vv_bufferline_close(right_buf) end)
      View.mouse_interaction_win = mouse_interaction_win
      if not ok then error(err) end
      vim.wait(100)

      assert(vim.api.nvim_win_is_valid(left), '左侧分割被关闭')
      assert(not vim.api.nvim_win_is_valid(right), '鼠标关闭后空的右侧分割仍留在布局')
      assert(not vim.bo[right_buf].buflisted, '鼠标关闭后右侧缓冲区仍在列表中')
      assert(#vim.api.nvim_tabpage_list_wins(0) == 1, '鼠标关闭应折叠为单一编辑器分割')
  end)
end

T["close_all 清理所有分割组中的缓冲区"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-all-a.ts'))
      local a = vim.api.nvim_get_current_buf()
      vim.cmd('split')
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-all-b.ts'))
      local b = vim.api.nvim_get_current_buf()

      require('vv-bufferline').close_all({ force = true })
      vim.wait(100)

      assert(not vim.bo[a].buflisted, '第一个分割窗缓冲区仍在列表中')
      assert(not vim.bo[b].buflisted, '第二个分割窗缓冲区仍在列表中')
  end)
end

T["close_all 可折叠分割布局"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-layout-a.ts'))
      local a = vim.api.nvim_get_current_buf()
      vim.cmd('split')
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-layout-b.ts'))
      local b = vim.api.nvim_get_current_buf()

      require('vv-bufferline').close_all({ force = true, close_windows = true })
      vim.wait(100)

      assert(#vim.api.nvim_tabpage_list_wins(0) == 1, '分割布局未折叠')
      assert(vim.wo.winbar == '', 'bufferline winbar 残留')
      assert(not vim.bo[a].buflisted, '第一布局缓冲区仍在列表中')
      assert(not vim.bo[b].buflisted, '第二布局缓冲区仍在列表中')
  end)
end

T["在计划重绘前跟踪快速编辑序列"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
    setup()
      local State = require('vv-bufferline.state')

      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-a.ts'))
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-b.ts'))
      local b = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bufferline-c.ts'))
      require('vv-bufferline').select(b)
      vim.wait(100)

      local seen = {}
      for _, buf in ipairs(State.win_state(vim.api.nvim_get_current_win()).bufs) do
        seen[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')] = true
      end

      assert(seen['vv-bufferline-a.ts'], '左侧快速编辑缓冲区丢失')
      assert(seen['vv-bufferline-b.ts'], '当前快速编辑缓冲区丢失')
      assert(seen['vv-bufferline-c.ts'], '右侧快速编辑缓冲区丢失')
  end)
end

T["只在当前分割组内循环切换"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      local State = require('vv-bufferline.state')

      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-cycle-a.ts'))
      local a = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-cycle-b.ts'))
      local b = vim.api.nvim_get_current_buf()
      vim.cmd('split')
      local current = vim.api.nvim_get_current_win()
      local other

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= current then
          other = win
          break
        end
      end

      vim.api.nvim_win_set_buf(current, a)
      State.wins[current] = { bufs = { a } }
      State.wins[other] = { bufs = { b } }
      State.removed[current] = { [b] = true }

      assert(not State.has_in_win(current, b), '前提: b 不应属于当前分割')
      assert(vim.bo[b].buflisted, '前提: b 应在另一分割中保持全局列出')

      require('vv-bufferline').cycle(1)
      assert(
        vim.api.nvim_win_get_buf(current) == a,
        ('选择了缓冲区 %d 而不是当前组内缓冲区 %d'):format(vim.api.nvim_win_get_buf(current), a)
      )

      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-cycle-c.ts'))
      local c = vim.api.nvim_get_current_buf()
      require('vv-bufferline').cycle(-1)
      assert(vim.api.nvim_win_get_buf(current) == a, '向后循环未按当前分割顺序执行')

      require('vv-bufferline').cycle(3)
      assert(vim.api.nvim_win_get_buf(current) == c, '循环计数未在当前分割内回绕')
  end)
end

T["预览新文件时保持 bufferline 可见且不污染分组"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-pv-a.ts'))
      local a = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-pv-b.ts'))
      vim.wait(50)
      local win = vim.api.nvim_get_current_win()
      assert(vim.wo[win].winbar ~= '', '前提: 固定缓冲区时 bufferline 应可见')

      -- 模拟资源管理器在树里 j/k 预览一个「新文件」：未列入 bufferline 的缓冲区标记为预览后换入窗口
      local State = require('vv-bufferline.state')
      local pv = vim.fn.bufadd((vim.env.VV_TEST_TMP .. '/vv-bl-pv-preview.ts'))
      vim.fn.bufload(pv)
      vim.bo[pv].buflisted = false
      require('vv-bufferline').mark_preview(win, pv)
      vim.api.nvim_win_set_buf(win, pv)
      vim.wait(80)

      assert(vim.wo[win].winbar ~= '', '预览新文件时 bufferline 消失（复现该缺陷）')
      assert(not State.has_in_win(win, pv), '预览缓冲区不应加入分组')
      local tail = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(a), ':t')
      assert(vim.wo[win].winbar:find(tail, 1, true), '预览期间固定 tab 在 winbar 中丢失')
  end)
end

T["忽略 diff 窗口与 vv-git tab，并清理 tab split 继承的 winbar"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-ign-a.ts'))
      local win = vim.api.nvim_get_current_win()
      vim.wait(50)
      local Window = require('vv-bufferline.window')
      assert(vim.wo[win].winbar ~= '', '前提: 普通编辑窗口应显示 bufferline')

      -- diff 模式窗口被忽略（vv-git 的 diff 视图就是这种窗口）
      vim.wo[win].diff = true
      assert(Window.ignored_win(win) and not Window.should_show(win), '应忽略 diff 窗口')
      vim.wo[win].diff = false
      assert(Window.should_show(win), 'diff 关闭后窗口应重新渲染')

      -- 模拟 vv-git：tab split（新窗口会「继承」源窗口的 bufferline winbar）+ 同步标记忽略
      vim.cmd('tab split')
      local gwin = vim.api.nvim_get_current_win()
      assert(vim.wo[gwin].winbar:find('VVBufferline', 1, true), '前提: tab split 已继承 bufferline 的 winbar')
      vim.api.nvim_tabpage_set_var(vim.api.nvim_get_current_tabpage(), 'vv_bufferline_ignore', true)
      assert(Window.ignored_win(gwin), '在忽略 tab 的窗口必须被忽略')

      -- 一次刷新后，继承来的 bufferline 残留应被清掉
      vim.api.nvim_exec_autocmds('WinResized', {})
      vim.wait(80)
      assert(vim.wo[gwin].winbar == '', '忽略的（vv-git）tab 上应清除继承的 bufferline winbar')

      vim.cmd('tabclose')
  end)
end

T["预览状态下应显示判断仅统计有效成员（无空 winbar）"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      local State = require('vv-bufferline.state')
      local Window = require('vv-bufferline.window')
      local win = vim.api.nvim_get_current_win()

      local stale = vim.fn.bufadd((vim.env.VV_TEST_TMP .. '/vv-bl-pe-stale.ts')) -- 未 load/未 list → normal_buf=false
      local pv = vim.fn.bufadd((vim.env.VV_TEST_TMP .. '/vv-bl-pe-prev.ts'))
      vim.fn.bufload(pv)
      vim.bo[pv].buflisted = false

      -- 确定性构造：先进入预览态，再把分组注入为「只有一个已失效成员」
      -- （注入须在 set_preview 之后——set_preview 内部 remove_from_win 会顺手 prune 掉非 normal_buf）
      State.set_preview(win, pv)
      vim.api.nvim_win_set_buf(win, pv)
      State.wins[win] = { bufs = { stale } }
      assert(not Window.should_show(win), '仅含无效成员的预览窗口应不显示')

      -- 对照：补一个有效成员 → 预览态应保留既有标签栏
      local valid = vim.fn.bufadd((vim.env.VV_TEST_TMP .. '/vv-bl-pe-valid.ts'))
      vim.fn.bufload(valid)
      vim.bo[valid].buflisted = true
      State.wins[win].bufs = { stale, valid }
      assert(Window.should_show(win), '含有效成员的预览窗口应显示')
  end)
end

T["disable() 不应回写通过 split 继承的 bufferline winbar"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-rem-a.ts'))
      vim.wait(50)
      local WinbarHost = require('vv-bufferline.winbar_host')

      vim.cmd('vsplit') -- 新窗口继承源窗口的 bufferline winbar 串
      local nw = vim.api.nvim_get_current_win()
      vim.wait(50)

      -- remember_winbar 不应把「继承来的我方串」存为 previous
      assert(not (WinbarHost.previous[nw] or ''):find('VVBufferline', 1, true),
        '前提: 旧有 bufferline winbar 应保存在 previous')

      require('vv-bufferline').disable()
      vim.wait(50)
      assert(not (vim.wo[nw].winbar or ''):find('VVBufferline', 1, true),
        'disable() 不应回写 split 窗口过期的 bufferline winbar')
  end)
end

T["disable() 恢复已有的 v:lua 点击回调"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      require('vv-bufferline').disable()
      local old_select = function() return 'old select' end
      local old_close = function() return 'old close' end
      _G.__vv_bufferline_select = old_select
      _G.__vv_bufferline_close = old_close

      setup()
      assert(_G.__vv_bufferline_select ~= old_select, 'setup 未安装 select 桥接')
      require('vv-bufferline').disable()
      assert(_G.__vv_bufferline_select == old_select, 'select 桥接未恢复')
      assert(_G.__vv_bufferline_close == old_close, 'close 桥接未恢复')
  end)
end

T["disable() 保持 bufferline 安装后替换的 v:lua 点击回调"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      require('vv-bufferline').disable()
      setup()

      local external_select = function() return 'external select' end
      local external_close = function() return 'external close' end
      _G.__vv_bufferline_select = external_select
      _G.__vv_bufferline_close = external_close

      require('vv-bufferline').disable()
      assert(_G.__vv_bufferline_select == external_select, 'disable 覆盖了外部 select 桥接')
      assert(_G.__vv_bufferline_close == external_close, 'disable 覆盖了外部 close 桥接')
  end)
end

T["enable() 在 disable() 后重装有效的 v:lua 点击处理器"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      assert_clicks_work_after_reenable(function()
        require('vv-bufferline').disable()
        require('vv-bufferline').enable()
      end, 'enable')
  end)
end

T["toggle() 重新启用后重装有效的 v:lua 点击处理器"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      assert_clicks_work_after_reenable(function()
        require('vv-bufferline').toggle()
        require('vv-bufferline').toggle()
      end, 'toggle')
  end)
end

T["重复 enable 不会回收被其他所有者替换的点击处理器"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      local external_select = function() end
      local external_close = function() end
      _G.__vv_bufferline_select = external_select
      _G.__vv_bufferline_close = external_close

      require('vv-bufferline').enable()

      assert(_G.__vv_bufferline_select == external_select, 'enable 重复开启未回收外部 select 处理器')
      assert(_G.__vv_bufferline_close == external_close, 'enable 重复开启未回收外部 close 处理器')
  end)
end

T["短暂访问后不应自动重加已移除缓冲区"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      local State = require('vv-bufferline.state')
      local top, _, b = split_with_removed_buffer()

      assert(not State.has_in_win(top, b), '前提: b 已从 top 分组移除')
      assert(State.is_removed(top, b), '前提: top 应记住拒绝了 b')
      assert(vim.bo[b].buflisted, '前提: 因 bottom 持有，b 应继续列出')

      -- 模拟「打开其他缓冲区」过程中短暂进入 b，随后落定到另一个缓冲区 c
      vim.api.nvim_set_current_win(top)
      vim.cmd('buffer ' .. b) -- 短暂显示 b：track_current 必须因 removed 跳过
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-rm-c.ts')) -- 落定到 c
      vim.wait(100)

      assert(not State.has_in_win(top, b), '短暂访问后已移除的缓冲区 b 被复活')
      local c = vim.fn.bufnr((vim.env.VV_TEST_TMP .. '/vv-bl-rm-c.ts'))
      assert(State.has_in_win(top, c), '已落定的缓冲区 c 应被跟踪')
  end)
end

T["窗口停留期间跨事件循环周期不应复活移除的缓冲区"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      local State = require('vv-bufferline.state')
      local top, _, b = split_with_removed_buffer()

      assert(State.is_removed(top, b), '前提: top 已拒绝 b')

      -- 用户把 TOP 切到已删除的 b（:bprevious / 跳转定义 / 选择器），并停留至少一个事件循环周期：
      -- 此时一次定时重绘会在 b 仍是当前缓冲区时跑起来，必须尊重已移除标记
      vim.api.nvim_set_current_win(top)
      vim.cmd('buffer ' .. b)
      vim.wait(30)

      assert(not State.has_in_win(top, b), '窗口停留时已移除的缓冲区 b 被复活')
      assert(State.is_removed(top, b), '周期刷新不应清除移除标记')

      -- 之后落定到别的缓冲区，b 仍不应回到分组
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-dwell-c.ts'))
      vim.wait(50)
      assert(not State.has_in_win(top, b), '其他地方落定后已移除缓冲区又出现')
  end)
end

T["明确 reopen(select) 应恢复已从分组移除的缓冲区"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      local State = require('vv-bufferline.state')
      local top, _, b = split_with_removed_buffer()

      assert(not State.has_in_win(top, b), '前提: b 已从 top 移除')

      vim.api.nvim_set_current_win(top)
      require('vv-bufferline').select(b)
      vim.wait(50)

      assert(State.has_in_win(top, b), 'select 未恢复已移除的缓冲区')
      assert(not State.is_removed(top, b), '显式 reopen 后移除标记应清除')
  end)
end

T["select 忽略 winfixbuf 窗口而非抛错"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-fixed-a.ts'))
      local a = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-fixed-b.ts'))
      local b = vim.api.nvim_get_current_buf()

      vim.wo.winfixbuf = true
      local ok, err = pcall(function() require('vv-bufferline').select(a) end)
      local click_ok, click_err = pcall(function() _G.__vv_bufferline_select(a) end)
      vim.wo.winfixbuf = false

      assert(ok, 'winfixbuf 窗口中的 select 抛错: ' .. tostring(err))
      assert(click_ok, 'winbar click select 在 winfixbuf 窗口中抛错: ' .. tostring(click_err))
      assert(vim.api.nvim_get_current_buf() == b, 'select 切换到了 winfixbuf 窗口')
  end)
end

T["tabline 渲染目标在无 winbar 下保持 bufferline 可见"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup({ render_target = 'tabline' })
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-tabline-a.ts'))
      vim.wait(100)

      assert(vim.o.showtabline == 2, 'tabline 渲染目标应强制显示 tabline')
      assert(vim.wo.winbar == '', 'tabline 渲染目标不应写入 winbar')
      assert(vim.o.tabline:find('vv-bl-tabline-a.ts', 1, true), 'tabline 未包含当前缓冲区')
      assert(vim.fn.exists(':VVBufferlineCloseLeft') == 2, 'tabline 模式下缺少 close-left 命令')

      require('vv-bufferline').disable()
      assert(vim.o.tabline == '', 'disable 应恢复 tabline 值')
  end)
end

T["winbar hide_tabline 仅恢复其拥有的全局选项值"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      require('vv-bufferline').disable()
      vim.o.showtabline = 2

      setup()
      assert(vim.o.showtabline == 0, 'winbar setup 应隐藏内置 tabline')
      require('vv-bufferline').disable()
      assert(vim.o.showtabline == 2, 'disable 应恢复预设的 showtabline 值')

      setup()
      require('vv-bufferline').setup({ hide_tabline = false })
      assert(vim.o.showtabline == 2, '重配 hide_tabline=false 后应恢复先前值')

      setup()
      vim.o.showtabline = 1
      require('vv-bufferline').disable()
      assert(vim.o.showtabline == 1, 'disable 应保留随后外部修改的 showtabline')
  end)
end

T["窗口外修改的隐藏 buffer 自动纳入当前分组"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      -- track_modified 默认开启，验证默认行为
      setup()
      assert(require('vv-bufferline.state').get_config().track_modified == true, 'track_modified 默认值应为 true')
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-mod-a.ts'))
      local a = vim.api.nvim_get_current_buf()

      -- 模拟 LSP 跨文件编辑：修改从未进入任何窗口的隐藏 buffer
      local b = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/vv-bl-mod-hidden.ts')
      vim.fn.bufload(b)
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'changed by lsp' })
      vim.wait(200)

      local State = require('vv-bufferline.state')
      local win = vim.api.nvim_get_current_win()
      assert(State.has_in_win(win, b), '隐藏修改 buffer 未自动纳入当前窗口分组')
      assert(vim.bo[b].buflisted, '纳入分组的 buffer 应转正 buflisted')
      assert(vim.wo[win].winbar:find('vv-bl-mod-hidden', 1, true), 'winbar 未渲染隐藏修改 buffer')
      assert(vim.api.nvim_get_current_buf() == a, '自动入列不得切换当前 buffer')
  end)
end

T["track_modified 不覆盖显式删除与其他窗口的分组"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-rmmod-a.ts'))
      local win = vim.api.nvim_get_current_win()

      -- 用户显式删除过（removed 标记）的 buffer 不得因窗口外修改复活
      local r = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/vv-bl-rmmod-removed.ts')
      vim.fn.bufload(r)
      require('vv-bufferline.state').detach(win, r)
      vim.api.nvim_buf_set_lines(r, 0, -1, false, { 'changed' })

      -- 用真实 split 建立分组，再回到原窗口修改该 buffer
      vim.cmd.vsplit()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-rmmod-other.ts'))
      local other = vim.api.nvim_get_current_buf()
      local other_win = vim.api.nvim_get_current_win()
      assert(require('vv-bufferline').has(other_win, other), '其他窗口分组前置条件未建立')
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_buf_set_lines(other, 0, -1, false, { 'changed in another group' })

      -- 未修改的隐藏 buffer 不纳入
      local clean = vim.fn.bufadd(vim.env.VV_TEST_TMP .. '/vv-bl-rmmod-clean.ts')
      vim.fn.bufload(clean)

      vim.wait(200)

      local State = require('vv-bufferline.state')
      assert(not State.has_in_win(win, r), '显式删除过的 buffer 因窗口外修改复活')
      assert(not vim.bo[r].buflisted, '被拒绝纳入的 buffer 不应被转正 buflisted')
      assert(not State.has_in_win(win, other), '已在其他窗口分组的 buffer 被重复纳入')
      assert(not State.has_in_win(win, clean), '未修改的隐藏 buffer 被纳入')
      assert(not vim.wo[win].winbar:find('vv-bl-rmmod-removed', 1, true), 'removed buffer 出现在 winbar')
  end)
end

T["jump_to_end 按窗口标签顺序跳到端点"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      -- 按访问顺序建立分组 a → b → c，当前在 c（最右）
      for _, name in ipairs({ 'a', 'b', 'c' }) do
        vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-end-' .. name .. '.ts'))
      end

      local bl = require('vv-bufferline')
      bl.jump_to_end('first')
      vim.wait(50)
      assert(vim.fn.bufname():find('vv%-bl%-end%-a%.ts$'), 'first 未跳到最左标签，当前: ' .. vim.fn.bufname())

      bl.jump_to_end('last')
      vim.wait(50)
      assert(vim.fn.bufname():find('vv%-bl%-end%-c%.ts$'), 'last 未跳到最右标签，当前: ' .. vim.fn.bufname())

      -- 已在端点时保持不变且不报错
      bl.jump_to_end('last')
      vim.wait(50)
      assert(vim.fn.bufname():find('vv%-bl%-end%-c%.ts$'), '重复跳端点应保持当前 buffer')
  end)
end

T["默认键位接管内置映射且可关闭"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      local all_keys = { '[b', ']b', '[B', ']B', '<leader>bd', '<leader>bD', '<leader>bh', '<leader>bl', '<leader>bo', '<leader>ba' }
      local previous = {}
      for _, lhs in ipairs(all_keys) do previous[lhs] = vim.fn.maparg(lhs, 'n', false, true) end
      setup()
      for _, lhs in ipairs(all_keys) do
        local m = vim.fn.maparg(lhs, 'n', false, true)
        assert(type(m) == 'table' and type(m.callback) == 'function', lhs .. ' 未注册默认键位')
        assert(m.desc and m.desc:find('vv-bufferline', 1, true), lhs .. ' desc 缺少 vv-bufferline 前缀: ' .. tostring(m.desc))
      end

      -- 按访问顺序建立分组 a → b → c，验证 ]B / [B 回调按窗口标签序跳端点
      for _, name in ipairs({ 'a', 'b', 'c' }) do
        vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-keys-' .. name .. '.ts'))
      end
      vim.fn.maparg(']B', 'n', false, true).callback()
      assert(vim.fn.bufname():find('vv%-bl%-keys%-c%.ts$'), ']B 回调未跳到最右标签')
      vim.fn.maparg('[B', 'n', false, true).callback()
      assert(vim.fn.bufname():find('vv%-bl%-keys%-a%.ts$'), '[B 回调未跳到最左标签')

      -- keys = false 撤销默认键位，不残留
      setup({ keys = false })
      for _, lhs in ipairs(all_keys) do
        local restored = vim.fn.maparg(lhs, 'n', false, true)
        assert(restored.rhs == previous[lhs].rhs and restored.callback == previous[lhs].callback,
          'keys=false 后 ' .. lhs .. ' 未恢复接管前的映射')
      end
  end)
end

T["after_close 回调携带动作名"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      local seen = {}
      setup({ hooks = { after_close = function(ctx) table.insert(seen, ctx.action) end } })
      for _, name in ipairs({ 'a', 'b', 'c' }) do
        vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-hook-' .. name .. '.ts'))
      end

      -- 键位回调与直接 API 都触发 hook，动作名区分入口
      vim.fn.maparg('<leader>bd', 'n', false, true).callback()
      vim.wait(80)
      assert(#seen == 1 and seen[1] == 'close_current', 'close 键位未触发 after_close: ' .. vim.inspect(seen))

      vim.fn.maparg('<leader>bo', 'n', false, true).callback()
      vim.wait(80)
      assert(#seen == 2 and seen[2] == 'close_others', 'close_others 未触发: ' .. vim.inspect(seen))

      -- hook 报错被捕获并通知，关闭流程本身不受影响
      setup({ hooks = { after_close = function() error('boom') end } })
      local bl = require('vv-bufferline')
      local closing = vim.api.nvim_get_current_buf()
      local notifications = {}
      local notify = vim.notify
      vim.notify = function(message, level) notifications[#notifications + 1] = { message, level } end
      local ok, err = pcall(bl.close_current)
      vim.wait(80)
      vim.notify = notify
      assert(ok, err)
      assert(not vim.bo[closing].buflisted, 'hook 报错影响了实际关闭')
      assert(#notifications == 1 and notifications[1][2] == vim.log.levels.ERROR
        and notifications[1][1]:find('boom', 1, true), 'hook 错误未以 ERROR 通知')
  end)
end

T["被忽略 tab 中的修改归属最近编辑窗口"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-ig-a.ts'))
      local main = vim.api.nvim_get_current_win()

      -- 模拟 vv-git：独立 tab + 忽略标记，在其中打开并修改文件
      vim.cmd('tab split')
      vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-ig-b.ts'))
      local b = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'changed in ignored tab' })
      vim.wait(300)

      -- 修改发生在被忽略的 tab，也应归属到之前的编辑窗口分组
      local State = require('vv-bufferline.state')
      assert(State.has_in_win(main, b), '被忽略 tab 中的修改未归属最近编辑窗口')

      -- 回到主 tab 后标签可见
      vim.cmd('tabclose')
      vim.wait(100)
      assert(vim.api.nvim_get_current_win() == main, 'tabclose 后未回到主窗口')
      assert(vim.wo[main].winbar:find('vv%-bl%-ig%-b', 1, true) or vim.wo[main].winbar:find('vv-bl-ig-b', 1, true), '主窗口 winbar 未显示被忽略 tab 中的修改')
  end)
end

T["dashboard-only 会话的修改直接顶替占位内容显示"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      local main = vim.api.nvim_get_current_win()

      -- 不先打开编辑文件：真正的 dashboard-only 初始分组为空
      local dash = vim.api.nvim_create_buf(false, true)
      vim.bo[dash].buftype = 'nofile'
      vim.bo[dash].filetype = 'dashboard'
      vim.bo[dash].bufhidden = 'wipe'
      vim.api.nvim_win_set_buf(main, dash)
      require('vv-bufferline.view').track_current()

      vim.cmd('tab split')
      vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-dash-hidden.ts'))
      local b = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'changed' })
      vim.wait(300)

      -- 修改直接把归属窗口从占位内容切到该 buffer：q 关闭 vv-git 后第一眼就是它
      local State = require('vv-bufferline.state')
      assert(State.has_in_win(main, b), '修改未归属主窗口分组')
      assert(vim.api.nvim_win_get_buf(main) == b, '归属窗口未从占位内容切到修改的 buffer')

      vim.cmd('tabclose')
      vim.wait(100)
      assert(vim.wo[main].winbar:find('vv-bl-dash-hidden', 1, true), 'winbar 未显示修改标签')
  end)
end

T["已显示编辑内容的归属窗口只加标签不切换"] = function()
  child.lua_func(function()
    local setup, assert_clicks_work_after_reenable, split_with_removed_buffer = Smoke.setup, Smoke.assert_clicks_work_after_reenable, Smoke.split_with_removed_buffer
      setup()
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-keep-a.ts'))
      local a = vim.api.nvim_get_current_buf()
      local main = vim.api.nvim_get_current_win()

      vim.cmd('tab split')
      vim.api.nvim_tabpage_set_var(0, 'vv_bufferline_ignore', true)
      vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.VV_TEST_TMP .. '/vv-bl-keep-b.ts'))
      local b = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'changed' })
      vim.wait(300)

      local State = require('vv-bufferline.state')
      assert(State.has_in_win(main, b), '修改未归属主窗口分组')
      assert(vim.api.nvim_win_get_buf(main) == a, '正在显示编辑内容的窗口被切走')
  end)
end

return T
