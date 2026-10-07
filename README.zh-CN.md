<div align="center">

# vv-bufferline.nvim

[English](./README.md) | 中文

<img src="https://github.com/beixiyo/vv-bufferline.nvim/releases/download/assets-2026-07-25/vv-bufferline.png" alt="vv-bufferline 演示" width="900" />

想要我的 Neovim 配置？查看 <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>

类 VSCode 的**分屏局部** buffer 标签栏

<img src="https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white" alt="Neovim" />
<img src="https://img.shields.io/badge/Lua-2C2D72?logo=lua&logoColor=white" alt="Lua" />

</div>

`vv-bufferline` 通过 window-local 的 `winbar`，让**每个窗口**渲染自己访问过的
buffer 列表。Neovim 的 buffer 仍是全局的，只有标签 UI 状态按窗口隔离

## 为什么自研，而不用现成的 bufferline

主流 bufferline（`akinsho/bufferline.nvim`、`nvim-cokeline` 等）本质是一条
**全局 tabline**：所有窗口共享同一条「列出所有 buffer」的标签栏。这套自研插件
要解决的是它们在设计上做不到、或要 hack 才能凑出来的几件事：

- **分屏各管各的（核心诉求）**：标签栏挂在每个窗口的 `winbar` 上，每个 split
  只显示自己打开过的 buffer——和 VSCode 的 editor group 一样。左右分屏打开不同
  文件集时互不串味，而全局 tabline 做不到「这个分屏只看这几个」
- **winbar 优先**：标签天然随窗口走、随 `:split` 继承，不抢占全局
  `tabline`，也不和别的用 tabline 的东西打架（并默认隐藏内置 tabline，避免多开
  tab 时冒出 `pathshorten` 噪音）
- **可选全局显示**：如果更喜欢传统的全局 bufferline，可以切到
  `render_target = 'tabline'`，把当前活动编辑窗口的 buffer 组显示在全局 tabline
- **与 vv-* 生态深度协作**：`should_show` 让 vv-explorer 预览文件期间标签栏不消失；
  `ignored_win` + tab 约定变量 `vv_bufferline_ignore` 让 vv-git 的自有 tab 整体
  跳过、不被叠标签；诊断、图标统一走 `vv-utils` / `vv-icons`。这些是为这套插件
  量身定制的协作点，第三方插件要么做不到，要么得靠 monkey-patch 硬凑
- **轻**：不接管 Neovim 的 buffer 模型（buffer 仍全局），只维护一层窗口级 UI
  状态

## 特性

- 普通编辑窗口的按窗口 buffer 标签
- 点击标签 → 在当前分屏切换该 buffer
- hover 标签时显示 `×`，点击 `×` → 从当前分组关闭，无其他引用时删除 buffer
- 文件图标与配色经 `vv-icons` / `mini.icons`
- 已修改标记
- `track_modified`：未归属任何分组的修改 buffer 自动入列并转为 listed（默认开启）；
  完整的隐藏修改追踪需要 Neovim 0.13+
- 默认 `[b`/`]b`/`[B`/`]B` 键位按窗口标签序切换（内置映射走全局 buffer 列表，
  与分组顺序不一致）
- 诊断徽标经 `vv-utils.diagnostics`
- 自动过滤特殊窗口：help、quickfix、终端、`vv-explorer`、`vv-git`、diff 窗
- 窄窗口标签截断

## 安装配置

[vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim) 是必需依赖，用于诊断和高亮。文件图标可选（`nvim-web-devicons`，包括 mini.icons 的兼容层）

```lua
-- lazy.nvim
{
  'beixiyo/vv-bufferline.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  opts = {},
}
```

```lua
require('vv-bufferline').setup({
  max_name_width = 28,            -- 文件名截断前的最大显示宽度
  show_close = false,             -- 始终显示关闭按钮
  hover_close = true,             -- hover 标签时显示关闭按钮，且不额外占用布局宽度
  diagnostics = { enabled = true },
  hide_tabline = true,            -- 隐藏内置 tabline（buffer 已在 winbar 显示）
  render_target = 'winbar',       -- 'winbar' 每窗口显示；'tabline' 全局显示当前组
  track_modified = true,          -- 完整隐藏修改追踪需要 Neovim 0.13+
  placeholder_filetypes = { alpha = true, dashboard = true, ministarter = true },
  keys = {
    prev = '[b',
    next = ']b',
    first = '[B',
    last = ']B',
    close = '<leader>bd',
    close_force = '<leader>bD',
    close_left = '<leader>bh',
    close_right = '<leader>bl',
    close_others = '<leader>bo',
    close_all = '<leader>ba',
  },
  -- hooks = { after_close = function(ctx) ... end }  -- 关闭后编排（如 tab 空时开 dashboard）
  -- exclude_filetypes = { ... }  -- 不显示标签栏的 filetype
  -- colors = { ... }             -- 可选主题色
})
```

## 命令

| 命令 | 说明 |
|---|---|
| `:VVBufferlineEnable` | 启用标签栏 |
| `:VVBufferlineDisable` | 禁用并还原显示承载 |
| `:VVBufferlineToggle` | 切换 |
| `:VVBufferlineCloseCurrent` | 关闭当前标签 |
| `:VVBufferlineCloseCurrentForce` | 强制关闭当前标签（丢弃未保存） |
| `:VVBufferlineCloseLeft` | 关闭当前标签左侧的 buffer |
| `:VVBufferlineCloseRight` | 关闭当前标签右侧的 buffer |
| `:VVBufferlineCloseOthers` | 关闭当前标签以外的 buffer |
| `:VVBufferlineCloseAll` | 关闭全部 buffer |
| `:VVBufferlineFirst` | 跳到当前窗口分组的最左标签 |
| `:VVBufferlineLast` | 跳到当前窗口分组的最右标签 |

## 设计

本插件刻意**不**替换 Neovim 的 buffer 模型——buffer 仍是全局的。每个窗口只额外
维护一份「在该窗口访问过的 buffer」的 UI 列表。默认渲染进 `vim.wo[win].winbar`，
让每个 split 同时拥有自己的标签栏；`render_target = 'tabline'` 时则只把当前活动
编辑窗口的分组渲染到全局 `tabline`，适合偏好单条全局 bufferline 的使用方式

## 许可证

[MIT](./LICENSE)

## 开发测试

```sh
./tests/run.sh [literal-filter]
```

要求 Unix-like 系统、Neovim 0.12+、Git、POSIX shell 与已有 vv-utils checkout
默认使用开发工作区或已安装插件源码；`VV_UTILS` 可覆盖发现，`NVIM_BIN` 可指定 Neovim。不下载 vv 插件源码
诊断 fixture 要求已有 vv-icons 源码（`VV_TEST_ICONS` 可覆盖发现）；`nvim-web-devicons` 使用替身
测试使用隔离 child；headless 验证不替代真实 TUI 交互
依赖发现、字面过滤、隔离和 CI 前提见 [共享测试契约](https://github.com/beixiyo/vv-utils.nvim/blob/main/dev/test/README.zh-CN.md)
