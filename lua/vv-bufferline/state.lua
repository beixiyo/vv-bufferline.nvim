-- 窗口局部的 buffer 列表状态

local M = {
  wins = {},
  preview_bufs = {},
  layouts = {},
  hover = nil,
  -- removed[win][buf] = true：用户在该窗口「显式删除」过的 buffer
  -- 自动追踪（track_current）必须尊重它，不能因为后续某次 BufEnter 把它复原；
  -- 只有「显式打开」（select / 在该窗口落定显示该 buf → add）才会清除该标记
  removed = {},
  config = {},
}

---@return VVBufferlineConfig
function M.get_config()
  return M.config
end

function M.setup(config)
  M.config = config or {}
end

---@param buf integer
---@return boolean
local function normal_buf(buf)
  return require('vv-bufferline.window').normal_buf(buf)
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

  s.bufs = vim.tbl_filter(normal_buf, s.bufs)
end

---@param win integer
---@param buf integer
function M.add(win, buf)
  if not normal_buf(buf) then return end

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
    return b ~= buf and normal_buf(b)
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
      if not seen[buf] and normal_buf(buf) then
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
      return b ~= buf and normal_buf(b)
    end, s.bufs)
  end

  for win, preview in pairs(M.preview_bufs) do
    if preview == buf then M.preview_bufs[win] = nil end
  end

  -- buf 被全局删除：清掉所有窗口对它的 removed 记录，避免 buf id 复用后误伤新 buffer
  for win, r in pairs(M.removed) do
    if r[buf] then M.clear_removed(win, buf) end
  end

  if M.hover and M.hover.buf == buf then M.hover = nil end
end

---@param win integer
---@param items {buf:integer,start_col:integer,end_col:integer}[]
function M.set_layout(win, items)
  M.layouts[win] = items or {}
end

---@param win integer
function M.clear_layout(win)
  M.layouts[win] = nil
end

---@param win integer
---@param col integer
---@return integer?
function M.buf_at(win, col)
  local items = M.layouts[win]
  if not items then return nil end

  for _, item in ipairs(items) do
    if col >= item.start_col and col <= item.end_col then
      return item.buf
    end
  end
end

---@param win integer
---@param buf integer
---@return boolean changed
function M.set_hovered(win, buf)
  if not vim.api.nvim_win_is_valid(win) then return M.clear_hovered() end
  if not normal_buf(buf) then return M.clear_hovered() end

  if M.hover and M.hover.win == win and M.hover.buf == buf then return false end

  M.hover = { win = win, buf = buf }
  return true
end

---@return boolean changed
function M.clear_hovered()
  if not M.hover then return false end

  M.hover = nil
  return true
end

---@param win integer
---@return integer?
function M.hovered_buf(win)
  if not M.hover or M.hover.win ~= win then return nil end

  return M.hover.buf
end

---@param win integer
function M.remove_win(win)
  M.wins[win] = nil
  M.preview_bufs[win] = nil
  M.removed[win] = nil
  M.layouts[win] = nil
  if M.hover and M.hover.win == win then M.hover = nil end
end

function M.reset()
  M.wins = {}
  M.preview_bufs = {}
  M.removed = {}
  M.layouts = {}
  M.hover = nil
end

return M
