-- buffer 关闭/删除编排：处理「从分屏分组关闭某标签，并在无人引用时全局删 buffer」
-- 的整套规则——未保存确认、外部引用判定、关闭当前标签时选替换 buffer、detach 记
-- removed（自动事件不复原）。状态改动后通过 View.refresh 重绘

local State = require('vv-bufferline.state')
local View = require('vv-bufferline.view')

local M = {}

---@param buf integer
---@param force? boolean
---@return boolean
local function confirm_delete(buf, force)
  if force or not vim.bo[buf].modified then return true end

  local ok, choice = pcall(
    vim.fn.confirm,
    ('Save changes to %q?'):format(vim.fn.bufname(buf)),
    '&Yes\n&No\n&Cancel'
  )
  if not ok or choice == 0 or choice == 3 then return false end

  if choice == 1 then
    local wrote = pcall(function() vim.api.nvim_buf_call(buf, vim.cmd.write) end)
    if not wrote then return false end
  end

  return true
end

---@param buf integer
---@param exclude_win? integer
---@return boolean
local function has_external_ref(buf, exclude_win)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if win ~= exclude_win then return true end
  end

  return State.contains_buf(buf, exclude_win)
end

---@param buf integer
---@param force? boolean
local function delete_global_buf(buf, force)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if #vim.fn.win_findbuf(buf) > 0 then return end
  if State.contains_buf(buf) then return end

  pcall(vim.cmd, 'bdelete! ' .. buf)
end

---@param listed? boolean
---@return integer
local function create_empty_buf(listed)
  if listed == nil then listed = true end

  return vim.api.nvim_create_buf(listed, false)
end

---@param win integer
---@param closing_buf integer
---@return integer?
local function replacement_for(win, closing_buf)
  local s = State.win_state(win)
  State.prune(win)

  local idx = State.index_of(win, closing_buf)
  if idx then
    for i = idx - 1, 1, -1 do
      local buf = s.bufs[i]
      if buf ~= closing_buf and State.normal_buf(buf) then return buf end
    end

    for i = idx + 1, #s.bufs do
      local buf = s.bufs[i]
      if buf ~= closing_buf and State.normal_buf(buf) then return buf end
    end
  end

  return nil
end

---@return integer
local function create_fallback_buf()
  return create_empty_buf(false)
end

---@param win integer?
---@return boolean
local function can_close_empty_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  if not State.is_editor_win(win) then return false end

  local count = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if State.is_editor_win(w) and not State.ignored_win(w) then
      count = count + 1
    end
  end

  return count > 1
end

---@param win integer
---@return boolean closed
local function close_empty_win(win)
  if not can_close_empty_win(win) then return false end

  State.remove_win(win)
  local ok = pcall(vim.api.nvim_win_close, win, true)
  return ok and not vim.api.nvim_win_is_valid(win)
end

---@param win integer
---@param buf integer
---@param opts? {force?:boolean}
local function close_tab(win, buf, opts)
  opts = opts or {}
  if not vim.api.nvim_win_is_valid(win) then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if not State.is_editor_win(win) or State.ignored_win(win) then return end

  local cur = vim.api.nvim_win_get_buf(win)
  if State.normal_buf(cur) then State.add(win, cur) end
  State.prune(win)

  local should_delete = not has_external_ref(buf, win)
  if should_delete and not confirm_delete(buf, opts.force) then return end

  local replacement
  if cur == buf then replacement = replacement_for(win, buf) end

  local closed_win = false
  if cur == buf and vim.api.nvim_win_is_valid(win) then
    if replacement then
      local ok = pcall(vim.api.nvim_win_set_buf, win, replacement)
      if not ok then return end
    elseif not close_empty_win(win) then
      local fallback = create_fallback_buf()
      local ok = pcall(vim.api.nvim_win_set_buf, win, fallback)
      if not ok then
        pcall(vim.api.nvim_buf_delete, fallback, { force = true })
        return
      end
    else
      closed_win = true
    end
  end

  -- detach（而非 remove_from_win）：记下「本窗口拒绝过 buf」，自动事件不得复原
  if not closed_win and vim.api.nvim_win_is_valid(win) then
    State.detach(win, buf)
    if replacement and State.normal_buf(replacement) then State.add(win, replacement) end
  end

  delete_global_buf(buf, opts.force)
end

---@param buf integer
function M.close(buf, opts)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  opts = opts or {}
  local win = opts.mouse and View.mouse_interaction_win() or View.interaction_win()
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  close_tab(win, buf, opts)
  vim.schedule(View.refresh)
end

---@param opts? {force?:boolean}
function M.close_current(opts)
  opts = opts or {}
  local win = opts.mouse and View.mouse_interaction_win() or View.interaction_win()
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  close_tab(win, vim.api.nvim_win_get_buf(win), opts)
  vim.schedule(View.refresh)
end

---@param side 'left'|'right'
local function close_side(side)
  local win = View.interaction_win()
  if not win or not State.normal_win(win) then return end

  local cur = vim.api.nvim_win_get_buf(win)
  State.add(win, cur)
  State.prune(win)

  local bufs = State.win_state(win).bufs
  local cur_idx
  for i, buf in ipairs(bufs) do
    if buf == cur then
      cur_idx = i
      break
    end
  end
  if not cur_idx then return end

  local targets = {}
  for i, buf in ipairs(bufs) do
    if (side == 'left' and i < cur_idx) or (side == 'right' and i > cur_idx) then
      table.insert(targets, buf)
    end
  end

  for _, buf in ipairs(targets) do
    if vim.api.nvim_buf_is_valid(buf) then close_tab(win, buf) end
  end

  vim.schedule(View.refresh)
end

function M.close_left()
  close_side('left')
end

function M.close_right()
  close_side('right')
end

function M.close_others()
  local win = View.interaction_win()
  if not win or not State.normal_win(win) then return end

  local cur = vim.api.nvim_win_get_buf(win)
  State.add(win, cur)
  State.prune(win)

  local targets = {}
  for _, buf in ipairs(State.win_state(win).bufs) do
    if buf ~= cur then table.insert(targets, buf) end
  end

  for _, buf in ipairs(targets) do
    close_tab(win, buf)
  end

  vim.schedule(View.refresh)
end

---@param opts? {force?:boolean, close_windows?:boolean}
function M.close_all(opts)
  opts = opts or {}

  local seen = {}
  local targets = State.all_bufs()
  for _, buf in ipairs(targets) do
    seen[buf] = true
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not seen[buf] and State.normal_buf(buf) then
      seen[buf] = true
      table.insert(targets, buf)
    end
  end

  for _, buf in ipairs(targets) do
    if vim.api.nvim_buf_is_valid(buf) and not confirm_delete(buf, opts.force) then return end
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if State.is_editor_win(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if seen[buf] then vim.api.nvim_win_set_buf(win, create_empty_buf(false)) end
    end
  end

  State.clear_buffers()

  for _, buf in ipairs(targets) do
    if vim.api.nvim_buf_is_valid(buf) then pcall(vim.cmd, 'bdelete! ' .. buf) end
  end

  if opts.close_windows then
    pcall(vim.cmd, 'silent! only')
    View.restore_all_winbars()
    return
  end

  vim.schedule(View.refresh)
end

return M
