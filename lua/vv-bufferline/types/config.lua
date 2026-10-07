---@class VVBufferlineDiagnosticsConfig
---@field enabled boolean 显示最高严重级别与诊断总数 @default true

---@class VVBufferlineColors
---@field fill_bg string? 空 winbar 的背景色
---@field inactive_bg string? 非当前标签的背景色
---@field active_bg string? 当前标签的背景色
---@field inactive_fg string? 非当前标签的前景色
---@field active_fg string? 当前标签的前景色
---@field muted_fg string? 关闭按钮/截断符的前景色
---@field modified_fg string? 已修改标记的前景色

---@class VVBufferlineKeysConfig
---@field prev string|false|nil 切到当前窗口的上一个标签 @default '[b'
---@field next string|false|nil 切到当前窗口的下一个标签 @default ']b'
---@field first string|false|nil 跳到当前窗口的最左标签 @default '[B'
---@field last string|false|nil 跳到当前窗口的最右标签 @default ']B'
---@field close string|false|nil 关闭当前标签（未保存时确认） @default '<leader>bd'
---@field close_force string|false|nil 强制关闭当前标签（丢弃未保存） @default '<leader>bD'
---@field close_left string|false|nil 关闭当前标签左侧的 buffer @default '<leader>bh'
---@field close_right string|false|nil 关闭当前标签右侧的 buffer @default '<leader>bl'
---@field close_others string|false|nil 关闭当前标签以外的 buffer @default '<leader>bo'
---@field close_all string|false|nil 关闭全部 buffer 并收起分屏 @default '<leader>ba'

---@class VVBufferlineCloseCtx
---@field action 'close'|'close_current'|'close_left'|'close_right'|'close_others'|'close_all' 触发的关闭动作
---@field completed boolean 动作是否完成；取消、无可关闭窗口或失败为 false，批量动作可能部分完成
---@field tabpage integer 关闭动作开始时的 tab；延迟展示前须验证仍有效且仍是当前 tab

---@class VVBufferlineHooksConfig
---@field after_close? fun(ctx: VVBufferlineCloseCtx) 关闭尝试返回后的回调（含取消）；使用 completed 决定是否执行展示策略 @default nil

---@class VVBufferlineConfig
---@field max_name_width integer 文件名截断前的最大显示宽度 @default 28
---@field show_close boolean 是否始终显示可点击的关闭按钮 @default false
---@field hover_close boolean 是否在鼠标悬停标签时显示关闭按钮 @default true
---@field exclude_filetypes table<string, boolean> 不显示 winbar 标签栏的 filetype @default { alpha = true, dashboard = true, fzf = true, help = true, ministarter = true, qf = true, trouble = true, ['vv-explorer'] = true, ['vv-git'] = true }
---@field diagnostics VVBufferlineDiagnosticsConfig 诊断徽标配置 @default { enabled = true }
---@field hide_tabline boolean 隐藏 Neovim 内置 tabline（buffer 已在 winbar 显示，内置 tabline 冗余）@default true
---@field render_target 'winbar'|'tabline' 渲染承载；winbar 每窗口显示，tabline 全局显示当前组 @default 'winbar'
---@field track_modified boolean 未归属分组的修改自动入列；完整隐藏追踪需要 Neovim 0.13，旧版仅处理 BufModifiedSet 可报告的修改 @default true
---@field placeholder_filetypes table<string, boolean> 可由修改文件顶替的未修改 nofile 起始页；未命名空白 buffer 无需配置 @default { alpha = true, dashboard = true, ministarter = true }
---@field keys VVBufferlineKeysConfig|false 按窗口标签序切换与关闭的默认键位，接管内置 [b/]b/[B/]B；false 不注册 @default { prev = '[b', next = ']b', first = '[B', last = ']B', close = '<leader>bd', close_force = '<leader>bD', close_left = '<leader>bh', close_right = '<leader>bl', close_others = '<leader>bo', close_all = '<leader>ba' }
---@field hooks VVBufferlineHooksConfig 行为回调 @default {}
---@field colors VVBufferlineColors? 可选的主题色
