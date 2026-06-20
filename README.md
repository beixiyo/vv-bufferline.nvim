# vv-bufferline.nvim

类 VSCode 的**分屏局部** buffer 标签栏

`vv-bufferline` 通过 window-local 的 `winbar`，让**每个窗口**渲染自己访问过的
buffer 列表。Neovim 的 buffer 仍是全局的，只有标签 UI 状态按窗口隔离

## 为什么自研，而不用现成的 bufferline

主流 bufferline（`akinsho/bufferline.nvim`、`nvim-cokeline` 等）本质是一条
**全局 tabline**：所有窗口共享同一条「列出所有 buffer」的标签栏。这套自研插件
要解决的是它们在设计上做不到、或要 hack 才能凑出来的几件事：

- **分屏各管各的（核心诉求）**：标签栏挂在每个窗口的 `winbar` 上，每个 split
  只显示自己打开过的 buffer——和 VSCode 的 editor group 一样。左右分屏打开不同
  文件集时互不串味，而全局 tabline 做不到「这个分屏只看这几个」
- **winbar 而非 tabline**：标签天然随窗口走、随 `:split` 继承，不抢占全局
  `tabline`，也不和别的用 tabline 的东西打架（并默认隐藏内置 tabline，避免多开
  tab 时冒出 `pathshorten` 噪音）
- **与 vv-* 生态深度协作**：`should_show` 让 vv-explorer 预览文件期间标签栏不消失；
  `ignored_win` + tab 约定变量 `vv_bufferline_ignore` 让 vv-git 的自有 tab 整体
  跳过、不被叠标签；诊断、图标统一走 `vv-utils` / `vv-icons`。这些是为这套插件
  量身定制的协作点，第三方插件要么做不到，要么得靠 monkey-patch 硬凑
- **轻**：不接管 Neovim 的 buffer 模型（buffer 仍全局），只维护一层窗口级 UI
  状态；无多余依赖

## 特性

- 普通编辑窗口的按窗口 buffer 标签
- 点击标签 → 在当前分屏切换该 buffer
- 点击 `×` → 经 `vv-utils.bufdelete` 关闭
- 文件图标与配色经 `vv-icons` / `mini.icons`
- 已修改标记
- 诊断徽标经 `vv-utils.diagnostics`
- 自动过滤特殊窗口：help、quickfix、终端、`vv-explorer`、`vv-git`、diff 窗
- 窄窗口标签截断

## 安装配置

```lua
require('vv-bufferline').setup({
  max_name_width = 28,            -- 文件名截断前的最大显示宽度
  show_close = true,              -- 显示可点击的关闭按钮
  diagnostics = { enabled = true },
  hide_tabline = true,            -- 隐藏内置 tabline（buffer 已在 winbar 显示）
  -- exclude_filetypes = { ... }  -- 不显示标签栏的 filetype
  -- colors = { ... }             -- 可选主题色
})
```

## 命令

| 命令 | 说明 |
|---|---|
| `:VVBufferlineEnable` | 启用分屏局部 winbar 标签 |
| `:VVBufferlineDisable` | 禁用并还原各窗口原 winbar |
| `:VVBufferlineToggle` | 切换 |
| `:VVBufferlineCloseCurrent` | 关闭当前标签 |
| `:VVBufferlineCloseCurrentForce` | 强制关闭当前标签（丢弃未保存） |
| `:VVBufferlineCloseLeft` | 关闭当前标签左侧的 buffer |
| `:VVBufferlineCloseRight` | 关闭当前标签右侧的 buffer |
| `:VVBufferlineCloseOthers` | 关闭当前标签以外的 buffer |
| `:VVBufferlineCloseAll` | 关闭全部 buffer |

## 设计

本插件刻意**不**替换 Neovim 的 buffer 模型——buffer 仍是全局的。每个窗口只额外
维护一份「在该窗口访问过的 buffer」的 UI 列表，再渲染进 `vim.wo[win].winbar`

