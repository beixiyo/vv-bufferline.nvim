-- 窗口局部的 buffer 列表状态

local M = {
  wins = {},
  owned_winbars = {},
  previous_winbars = {},
  preview_bufs = {},
  -- removed[win][buf] = true：用户在该窗口「显式删除」过的 buffer
  -- 自动追踪（track_current）必须尊重它，不能因为后续某次 BufEnter 把它复原；
  -- 只有「显式打开」（select / 在该窗口落定显示该 buf → add）才会清除该标记
  removed = {},
  config = {},
}

function M.setup(config)
  M.config = config or {}
end

-- 渲染出的 winbar 必然包含此标记串（render 用它构造外框高亮组前缀）。集中一处定义：
-- render 据此生成 `%#…Fill#` 外框、本模块据此识别「split / tab split 继承来的我方 winbar 残留」。
-- 二者共用同一常量 → 改前缀只动这里，杜绝「render 改了名、这边识别静默失效」。
M.WINBAR_MARKER = 'VVBufferline'

---@param buf integer
---@return boolean
function M.normal_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if not vim.bo[buf].buflisted then return false end
  if vim.bo[buf].buftype ~= '' then return false end

  local excluded = M.config.exclude_filetypes or {}
  if excluded[vim.bo[buf].filetype] then return false end

  return true
end

---@param win integer
---@return boolean
-- 普通「编辑区」窗口：有效、非浮窗、未固定 buffer。bufferline 只作用于这类窗口；
-- 是否进一步「忽略」（diff / vv-git tab）由 ignored_win 单独判定，不并进来
function M.is_editor_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  if vim.wo[win].winfixbuf then return false end

  return true
end

---@param win integer
---@return boolean
function M.normal_win(win)
  if not M.is_editor_win(win) then return false end

  return M.normal_buf(vim.api.nvim_win_get_buf(win))
end

---@param win integer
---@return boolean
-- 显式排除的窗口：不属于「编辑区分屏」，不该叠加分屏 bufferline
--   • diff 窗口（diff 视图自带上下文，bufferline 是噪音）；
--   • 被工具显式标记忽略的窗口/标签页——约定变量 `vv_bufferline_ignore`：
--     vv-git 在自己的 tab 里（tab split）用 diff 视图展示文件并自管 winbar，
--     开 tab 时同步把该 tab 标记忽略，bufferline 整 tab 跳过（panel/diff/冲突窗都不画）
-- 纯约定、双向解耦：缺了对方插件该变量也只是 nil，无副作用
function M.ignored_win(win)
  if not vim.api.nvim_win_is_valid(win) then return true end
  if vim.wo[win].diff then return true end

  local ok_w, w = pcall(vim.api.nvim_win_get_var, win, 'vv_bufferline_ignore')
  if ok_w and w then return true end

  local ok_t, tab = pcall(vim.api.nvim_win_get_tabpage, win)
  if ok_t then
    local ok_tv, tv = pcall(vim.api.nvim_tabpage_get_var, tab, 'vv_bufferline_ignore')
    if ok_tv and tv then return true end
  end

  return false
end

---@param win integer
---@return boolean
-- 该窗口是否应渲染 bufferline。bufferline 属于「窗口」而非「当前 buffer」：
--   • 当前是正常文件 buffer → 显示；
--   • 当前是临时预览 buf（explorer 在树里 j/k 预览），但窗口已有固定分组 → 仍显示既有标签，
--     不能因为「现在临时显示的是预览」就把整条标签栏藏掉
function M.should_show(win)
  if not M.is_editor_win(win) then return false end
  if M.ignored_win(win) then return false end

  local buf = vim.api.nvim_win_get_buf(win)
  if M.normal_buf(buf) then return true end

  if M.is_preview(win, buf) then
    local s = M.wins[win]
    if not s then return false end
    -- 与 render（先 prune 再渲染）口径一致：只看「有效成员」。否则预览态下成员全失效时，
    -- should_show 仍判真、render prune 成空 → 残留一条只有底色的空标签栏
    for _, b in ipairs(s.bufs) do
      if M.normal_buf(b) then return true end
    end
    return false
  end

  return false
end

---@param win integer
---@return {bufs: integer[]}
function M.win_state(win)
  local s = M.wins[win]
  if not s then
    s = { bufs = {} }
    M.wins[win] = s
  end
  return s
end

---@param list integer[]
---@param buf integer
---@return boolean
local function has_buf(list, buf)
  for _, b in ipairs(list) do
    if b == buf then return true end
  end
  return false
end

---@param list integer[]
---@param buf integer
---@return integer?
local function index_of(list, buf)
  for i, b in ipairs(list) do
    if b == buf then return i end
  end
end

---@param win integer
function M.prune(win)
  local s = M.wins[win]
  if not s then return end

  s.bufs = vim.tbl_filter(M.normal_buf, s.bufs)
end

---@param win integer
---@param buf integer
function M.add(win, buf)
  if not M.normal_buf(buf) then return end

  -- 把 buf 纳入分组即「成为成员」，撤销任何旧的 removed 标记：
  -- 窗口真正落定显示某 buffer（render/select/replacement）时它就该是成员
  M.clear_removed(win, buf)

  local s = M.win_state(win)
  M.prune(win)

  if not has_buf(s.bufs, buf) then
    table.insert(s.bufs, buf)
  end
end

---@param win integer
---@param buf integer
function M.remove_from_win(win, buf)
  local s = M.wins[win]
  if not s then return end

  s.bufs = vim.tbl_filter(function(b)
    return b ~= buf and M.normal_buf(b)
  end, s.bufs)
end

---@param win integer
---@param buf integer
---@return boolean
function M.is_removed(win, buf)
  local r = M.removed[win]
  return r ~= nil and r[buf] == true
end

---@param win integer
---@param buf integer
function M.clear_removed(win, buf)
  local r = M.removed[win]
  if not r then return end

  r[buf] = nil
  if next(r) == nil then M.removed[win] = nil end
end

-- 显式删除：移出分组并记下「该窗口拒绝过此 buf」，后续自动事件不得复原
---@param win integer
---@param buf integer
function M.detach(win, buf)
  M.remove_from_win(win, buf)

  M.removed[win] = M.removed[win] or {}
  M.removed[win][buf] = true
end

---@param win integer
---@param buf integer
---@return boolean
function M.has_in_win(win, buf)
  local s = M.wins[win]
  if not s then return false end

  return has_buf(s.bufs, buf)
end

---@param buf integer
---@param exclude_win? integer
---@return boolean
function M.contains_buf(buf, exclude_win)
  for win, s in pairs(M.wins) do
    if win ~= exclude_win and has_buf(s.bufs, buf) then return true end
  end

  return false
end

---@param win integer
---@param buf integer
---@return integer?
function M.index_of(win, buf)
  local s = M.wins[win]
  if not s then return nil end

  return index_of(s.bufs, buf)
end

---@return integer[]
function M.all_bufs()
  local seen = {}
  local out = {}

  for _, s in pairs(M.wins) do
    for _, buf in ipairs(s.bufs) do
      if not seen[buf] and M.normal_buf(buf) then
        seen[buf] = true
        table.insert(out, buf)
      end
    end
  end

  return out
end

function M.clear_buffers()
  for _, s in pairs(M.wins) do
    s.bufs = {}
  end
  M.preview_bufs = {}
  M.removed = {}
end

---@param win integer
---@param buf integer
function M.set_preview(win, buf)
  M.preview_bufs[win] = buf
  M.remove_from_win(win, buf)
end

---@param win integer
---@param buf? integer
function M.clear_preview(win, buf)
  if buf and M.preview_bufs[win] ~= buf then return end

  M.preview_bufs[win] = nil
end

---@param win integer
---@param buf integer
---@return boolean
function M.is_preview(win, buf)
  return M.preview_bufs[win] == buf
end

---@param buf integer
function M.remove_buf(buf)
  for _, s in pairs(M.wins) do
    s.bufs = vim.tbl_filter(function(b)
      return b ~= buf and M.normal_buf(b)
    end, s.bufs)
  end

  for win, preview in pairs(M.preview_bufs) do
    if preview == buf then M.preview_bufs[win] = nil end
  end

  -- buf 被全局删除：清掉所有窗口对它的 removed 记录，避免 buf id 复用后误伤新 buffer
  for win, r in pairs(M.removed) do
    if r[buf] then M.clear_removed(win, buf) end
  end
end

---@param win integer
function M.remember_winbar(win)
  if M.owned_winbars[win] then return end

  local wb = vim.wo[win].winbar
  -- split / tab split 会把我方 winbar 继承给新窗口；别把这份「继承来的我方串」当用户原值存档，
  -- 否则 restore_winbar / disable 会把它写回去 → 残留一条陈旧标签栏
  if wb and wb:find(M.WINBAR_MARKER, 1, true) then wb = '' end

  M.previous_winbars[win] = wb
  M.owned_winbars[win] = true
end

---@param win integer
function M.restore_winbar(win)
  if not M.owned_winbars[win] then return end

  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = M.previous_winbars[win] or ''
  end

  M.owned_winbars[win] = nil
  M.previous_winbars[win] = nil
end

---@param win integer
-- 清掉「继承来的」bufferline winbar 残留。`tab split` / `:split` 会把源窗口的
-- winbar 复制给新窗口；若新窗口不该显示 bufferline（如 vv-git 的 tab），而这份
-- winbar 又是我们生成的（含 `VVBufferline` 高亮组）但从未被我们登记 owned，
-- restore_winbar 不会动它 → 残留。这里只清「我们自己的串」，绝不动别人（vv-git
-- 冲突标题、用户自定义 winbar 等）的 winbar
function M.clear_orphan_winbar(win)
  if M.owned_winbars[win] then return end
  if not vim.api.nvim_win_is_valid(win) then return end

  local wb = vim.wo[win].winbar
  if wb and wb ~= '' and wb:find(M.WINBAR_MARKER, 1, true) then
    vim.wo[win].winbar = ''
  end
end

---@param win integer
function M.remove_win(win)
  M.wins[win] = nil
  M.owned_winbars[win] = nil
  M.previous_winbars[win] = nil
  M.preview_bufs[win] = nil
  M.removed[win] = nil
end

function M.reset()
  M.wins = {}
  M.owned_winbars = {}
  M.previous_winbars = {}
  M.preview_bufs = {}
  M.removed = {}
end

return M
