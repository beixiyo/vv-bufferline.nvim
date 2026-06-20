-- vv-bufferline.nvim smoke tests
-- Usage:
--   cd ~/.config/nvim/vendors/vv-bufferline.nvim
--   nvim --headless -u NONE -l tests/test_smoke.lua

local this = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local plugin_root = vim.fn.fnamemodify(this, ':h:h')
local vendors_root = vim.fn.fnamemodify(plugin_root, ':h')
local utils_root = vendors_root .. '/vv-utils.nvim'

package.path = table.concat({
  plugin_root .. '/lua/?.lua',
  plugin_root .. '/lua/?/init.lua',
  utils_root .. '/lua/?.lua',
  utils_root .. '/lua/?/init.lua',
  package.path,
}, ';')

vim.api.nvim_set_hl(0, 'MiniIconsBlue', { fg = '#4aa5f0' })
vim.api.nvim_set_hl(0, 'VVDiagError', { fg = '#f7768e' })
package.loaded['nvim-web-devicons'] = {
  get_icon = function()
    return 'T', 'MiniIconsBlue'
  end,
}

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    failed = failed + 1
    print('FAIL: ' .. name .. ' -> ' .. tostring(err))
  end
end

local function setup()
  pcall(vim.cmd, 'silent! only')
  require('vv-bufferline.state').reset()
  require('vv-bufferline').setup({
    colors = {
      fill_bg = '#111111',
      inactive_bg = '#222222',
      active_bg = '#333333',
      inactive_fg = '#888888',
      active_fg = '#ffffff',
      muted_fg = '#777777',
      modified_fg = '#ffaa00',
    },
  })
end

test('renders one tab per split-local current buffer', function()
  setup()
  vim.cmd('edit /tmp/vv-bufferline-left.ts')
  vim.cmd('vsplit')
  vim.cmd('edit /tmp/vv-bufferline-right.ts')
  vim.wait(100)

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local tail = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ':t')
    assert(vim.wo[win].winbar:find(tail, 1, true), 'winbar does not contain ' .. tail)
  end
end)

test('uses icon highlight derived from devicons', function()
  vim.cmd('edit /tmp/vv-bufferline-icon.ts')
  vim.wait(100)

  local bar = vim.wo.winbar
  assert(bar:find('VVBufferlineIconCurrentMiniIconsBlue', 1, true), 'icon highlight missing')
end)

test('renders highest diagnostic severity and count', function()
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

  assert(vim.wo.winbar:find('E1', 1, true), 'diagnostic badge missing')
  assert(vim.wo.winbar:find('VVBufferlineDiagCurrentVVDiagError', 1, true), 'diagnostic highlight missing')
end)

test('registers split-local close commands', function()
  assert(vim.fn.exists(':VVBufferlineCloseLeft') == 2, 'VVBufferlineCloseLeft missing')
  assert(vim.fn.exists(':VVBufferlineCloseRight') == 2, 'VVBufferlineCloseRight missing')
  assert(vim.fn.exists(':VVBufferlineCloseCurrent') == 2, 'VVBufferlineCloseCurrent missing')
  assert(vim.fn.exists(':VVBufferlineCloseAll') == 2, 'VVBufferlineCloseAll missing')
end)

test('close_current keeps sibling split that shares the same buffer', function()
  setup()
  vim.cmd('edit /tmp/vv-bufferline-shared.ts')
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

  assert(#vim.api.nvim_tabpage_list_wins(0) == before_count, 'close_current closed a split window')
  assert(vim.api.nvim_win_is_valid(sibling_win), 'sibling split was invalidated')
  assert(vim.api.nvim_win_get_buf(sibling_win) == shared, 'sibling split stopped showing shared buffer')
  assert(vim.api.nvim_win_get_buf(close_win) ~= shared, 'closed split did not switch away from shared buffer')
end)

test('close_all deletes buffers from all split groups', function()
  setup()
  vim.cmd('edit /tmp/vv-bufferline-all-a.ts')
  local a = vim.api.nvim_get_current_buf()
  vim.cmd('split')
  vim.cmd('edit /tmp/vv-bufferline-all-b.ts')
  local b = vim.api.nvim_get_current_buf()

  require('vv-bufferline').close_all({ force = true })
  vim.wait(100)

  assert(not vim.bo[a].buflisted, 'first split buffer is still listed')
  assert(not vim.bo[b].buflisted, 'second split buffer is still listed')
end)

test('close_all can collapse split layout', function()
  setup()
  vim.cmd('edit /tmp/vv-bufferline-layout-a.ts')
  local a = vim.api.nvim_get_current_buf()
  vim.cmd('split')
  vim.cmd('edit /tmp/vv-bufferline-layout-b.ts')
  local b = vim.api.nvim_get_current_buf()

  require('vv-bufferline').close_all({ force = true, close_windows = true })
  vim.wait(100)

  assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'split layout was not collapsed')
  assert(vim.wo.winbar == '', 'bufferline winbar was left behind')
  assert(not vim.bo[a].buflisted, 'first layout buffer is still listed')
  assert(not vim.bo[b].buflisted, 'second layout buffer is still listed')
end)

test('tracks rapid edit sequence before scheduled redraw', function()
  local State = require('vv-bufferline.state')

  vim.cmd('edit /tmp/vv-bufferline-a.ts')
  vim.cmd('edit /tmp/vv-bufferline-b.ts')
  local b = vim.api.nvim_get_current_buf()
  vim.cmd('edit /tmp/vv-bufferline-c.ts')
  require('vv-bufferline').select(b)
  vim.wait(100)

  local seen = {}
  for _, buf in ipairs(State.win_state(vim.api.nvim_get_current_win()).bufs) do
    seen[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')] = true
  end

  assert(seen['vv-bufferline-a.ts'], 'left rapid edit buffer missing')
  assert(seen['vv-bufferline-b.ts'], 'current rapid edit buffer missing')
  assert(seen['vv-bufferline-c.ts'], 'right rapid edit buffer missing')
end)

test('keeps the bufferline visible while previewing a new file (and does not pollute the group)', function()
  setup()
  vim.cmd('edit /tmp/vv-bl-pv-a.ts')
  local a = vim.api.nvim_get_current_buf()
  vim.cmd('edit /tmp/vv-bl-pv-b.ts')
  vim.wait(50)
  local win = vim.api.nvim_get_current_win()
  assert(vim.wo[win].winbar ~= '', 'precondition: bufferline visible with fixed buffers')

  -- 模拟 explorer 在树里 j/k 预览一个「新文件」：unlisted buffer 标记为预览后换入窗口
  local State = require('vv-bufferline.state')
  local pv = vim.fn.bufadd('/tmp/vv-bl-pv-preview.ts')
  vim.fn.bufload(pv)
  vim.bo[pv].buflisted = false
  require('vv-bufferline').mark_preview(win, pv)
  vim.api.nvim_win_set_buf(win, pv)
  vim.wait(80)

  assert(vim.wo[win].winbar ~= '', 'bufferline disappeared while previewing a new file (the reported bug)')
  assert(not State.has_in_win(win, pv), 'preview buffer must not be added to the group')
  local tail = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(a), ':t')
  assert(vim.wo[win].winbar:find(tail, 1, true), 'existing fixed tab missing from winbar during preview')
end)

test('ignores diff windows + vv-git tab, and clears the winbar inherited via tab split', function()
  setup()
  vim.cmd('edit /tmp/vv-bl-ign-a.ts')
  local win = vim.api.nvim_get_current_win()
  vim.wait(50)
  local State = require('vv-bufferline.state')
  assert(vim.wo[win].winbar ~= '', 'precondition: normal editor window shows bufferline')

  -- diff 模式窗口被忽略（vv-git 的 diff 视图就是这种窗口）
  vim.wo[win].diff = true
  assert(State.ignored_win(win) and not State.should_show(win), 'diff window must be ignored')
  vim.wo[win].diff = false
  assert(State.should_show(win), 'window renders again once diff is off')

  -- 模拟 vv-git：tab split（新窗口会「继承」源窗口的 bufferline winbar）+ 同步标记 ignore
  vim.cmd('tab split')
  local gwin = vim.api.nvim_get_current_win()
  assert(vim.wo[gwin].winbar:find('VVBufferline', 1, true), 'precondition: tab split inherited the bufferline winbar')
  vim.api.nvim_tabpage_set_var(vim.api.nvim_get_current_tabpage(), 'vv_bufferline_ignore', true)
  assert(State.ignored_win(gwin), 'window in an ignored tab must be ignored')

  -- 一次刷新后，继承来的 bufferline 残留应被清掉
  vim.api.nvim_exec_autocmds('WinResized', {})
  vim.wait(80)
  assert(vim.wo[gwin].winbar == '', 'inherited bufferline winbar must be cleared on an ignored (vv-git) tab')

  vim.cmd('tabclose')
end)

test('should_show in preview state counts only valid members (no empty winbar)', function()
  setup()
  local State = require('vv-bufferline.state')
  local win = vim.api.nvim_get_current_win()

  local stale = vim.fn.bufadd('/tmp/vv-bl-pe-stale.ts') -- 未 load/未 list → normal_buf=false
  local pv = vim.fn.bufadd('/tmp/vv-bl-pe-prev.ts')
  vim.fn.bufload(pv)
  vim.bo[pv].buflisted = false

  -- 确定性构造：先进入预览态，再把分组注入为「只有一个已失效成员」
  -- （注入须在 set_preview 之后——set_preview 内部 remove_from_win 会顺手 prune 掉非 normal_buf）
  State.set_preview(win, pv)
  vim.api.nvim_win_set_buf(win, pv)
  State.wins[win] = { bufs = { stale } }
  assert(not State.should_show(win), 'preview window whose only member is invalid must not should_show')

  -- 对照：补一个有效成员 → 预览态应保留既有标签栏
  local valid = vim.fn.bufadd('/tmp/vv-bl-pe-valid.ts')
  vim.fn.bufload(valid)
  vim.bo[valid].buflisted = true
  State.wins[win].bufs = { stale, valid }
  assert(State.should_show(win), 'preview window with a valid member should should_show')
end)

test('disable() does not write back a bufferline winbar inherited via split', function()
  setup()
  vim.cmd('edit /tmp/vv-bl-rem-a.ts')
  vim.wait(50)
  local State = require('vv-bufferline.state')

  vim.cmd('vsplit') -- 新窗口继承源窗口的 bufferline winbar 串
  local nw = vim.api.nvim_get_current_win()
  vim.wait(50)

  -- remember_winbar 不应把「继承来的我方串」存为 previous
  assert(not (State.previous_winbars[nw] or ''):find('VVBufferline', 1, true),
    'remember_winbar stored an inherited bufferline string as the previous value')

  require('vv-bufferline').disable()
  vim.wait(50)
  assert(not (vim.wo[nw].winbar or ''):find('VVBufferline', 1, true),
    'disable() wrote a stale bufferline winbar back into the split window')
end)

-- 构造「b 已从 top 分组删除、但仍存活（bottom 分屏持有）」的状态
local function split_with_removed_buffer()
  setup()
  vim.cmd('edit /tmp/vv-bl-rm-a.ts')
  vim.cmd('edit /tmp/vv-bl-rm-b.ts')
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

test('does not auto-readd a removed buffer after a transient visit', function()
  local State = require('vv-bufferline.state')
  local top, _, b = split_with_removed_buffer()

  assert(not State.has_in_win(top, b), 'precondition: b should be removed from top group')
  assert(State.is_removed(top, b), 'precondition: top should remember it rejected b')
  assert(vim.bo[b].buflisted, 'precondition: b should stay listed because bottom owns it')

  -- 模拟「打开其他 buffer」过程中短暂进入 b，随后落定到另一个 buffer c
  vim.api.nvim_set_current_win(top)
  vim.cmd('buffer ' .. b) -- 短暂显示 b：track_current 必须因 removed 跳过
  vim.cmd('edit /tmp/vv-bl-rm-c.ts') -- 落定到 c
  vim.wait(100)

  assert(not State.has_in_win(top, b), 'removed buffer b was resurrected after a transient visit')
  local c = vim.fn.bufnr('/tmp/vv-bl-rm-c.ts')
  assert(State.has_in_win(top, c), 'the settled buffer c should be tracked')
end)

test('does not resurrect a removed buffer the window dwells on across an event-loop tick', function()
  local State = require('vv-bufferline.state')
  local top, _, b = split_with_removed_buffer()

  assert(State.is_removed(top, b), 'precondition: top rejected b')

  -- 用户把 TOP 切到已删除的 b（:bprevious / 跳转定义 / 选择器），并停留至少一个事件循环 tick：
  -- 此时一次 scheduled refresh 会在 b 仍是当前 buffer 时跑起来。render 必须尊重 removed。
  vim.api.nvim_set_current_win(top)
  vim.cmd('buffer ' .. b)
  vim.wait(30)

  assert(not State.has_in_win(top, b), 'a periodic refresh resurrected a removed buffer the window dwelled on')
  assert(State.is_removed(top, b), 'the removed flag was cleared by a periodic refresh')

  -- 之后落定到别的 buffer，b 仍不应回到分组
  vim.cmd('edit /tmp/vv-bl-dwell-c.ts')
  vim.wait(50)
  assert(not State.has_in_win(top, b), 'removed buffer reappeared after settling elsewhere')
end)

test('explicit reopen (select) restores a buffer removed from a split', function()
  local State = require('vv-bufferline.state')
  local top, _, b = split_with_removed_buffer()

  assert(not State.has_in_win(top, b), 'precondition: b removed from top')

  vim.api.nvim_set_current_win(top)
  require('vv-bufferline').select(b)
  vim.wait(50)

  assert(State.has_in_win(top, b), 'select did not restore the removed buffer')
  assert(not State.is_removed(top, b), 'removed flag should be cleared after an explicit reopen')
end)

print(string.format('vv-bufferline smoke: %d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
