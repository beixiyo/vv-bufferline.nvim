<div align="center">

# vv-bufferline.nvim

[English](./README.md) | 中文

<img src="https://github.com/beixiyo/vv-bufferline.nvim/releases/download/assets-2026-07-25/vv-bufferline.png" alt="vv-bufferline 演示" width="900" />

想要我的 Neovim 配置？查看 <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>

类 VSCode 的**分屏局部** buffer 标签栏

<img src="https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white" alt="Neovim" />
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
  状态；无多余依赖

## 特性

- 普通编辑窗口的按窗口 buffer 标签
- 点击标签 → 在当前分屏切换该 buffer
- hover 标签时显示 `×`，点击 `×` → 经 `vv-utils.bufdelete` 关闭
- 文件图标与配色经 `vv-icons` / `mini.icons`
- 已修改标记
- 诊断徽标经 `vv-utils.diagnostics`
- 自动过滤特殊窗口：help、quickfix、终端、`vv-explorer`、`vv-git`、diff 窗
- 窄窗口标签截断

## 安装配置

```lua
require('vv-bufferline').setup({
  max_name_width = 28,            -- 文件名截断前的最大显示宽度
  show_close = false,             -- 始终显示关闭按钮
  hover_close = true,             -- hover 标签时显示关闭按钮，且不额外占用布局宽度
  diagnostics = { enabled = true },
  hide_tabline = true,            -- 隐藏内置 tabline（buffer 已在 winbar 显示）
  render_target = 'winbar',       -- 'winbar' 每窗口显示；'tabline' 全局显示当前组
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

## 设计

本插件刻意**不**替换 Neovim 的 buffer 模型——buffer 仍是全局的。每个窗口只额外
维护一份「在该窗口访问过的 buffer」的 UI 列表。默认渲染进 `vim.wo[win].winbar`，
让每个 split 同时拥有自己的标签栏；`render_target = 'tabline'` 时则只把当前活动
编辑窗口的分组渲染到全局 `tabline`，适合偏好单条全局 bufferline 的使用方式

## 许可证

[MIT](./LICENSE)

## 开发测试

vv-icons 源码也会按固定版本自动准备，`VV_TEST_ICONS` 仅用于可选的显式覆盖

```sh
./tests/run.sh
./tests/run.sh '过滤词'
# 可选：指定 Neovim
NVIM_BIN=/path/to/nvim ./tests/run.sh
```

仅支持 Unix-like 系统；要求 Neovim 0.12+（建议使用 0.12 稳定版）、Git 和 POSIX shell
直接运行 `./tests/run.sh`，首次自动准备固定版本 vv-utils（`ed9b6ae`）与 mini.test 源码，
不要求兄弟仓库、个人 Neovim 配置或预装 parser。依赖保存在 `VV_TEST_DEPS_CACHE`，
默认 `$XDG_CACHE_HOME/nvim-test-deps` 或 `~/.cache/nvim-test-deps`；缓存齐全后可离线运行
`VV_UTILS` 可显式覆盖共享源码路径；`NVIM_BIN` 默认 `nvim`。过滤词按文件路径或中文用例名
做字面子串匹配，无匹配视为失败。入口不安装系统工具

每个具名 case 启动全新子 Neovim，不读取个人配置；cwd、HOME、XDG 与临时文件都位于独立 `/tmp`
父 hook 在断言失败时仍停止子进程并清理 fixture；scheduled 回调异常单独收集后断言
headless 状态验证不能替代真实终端的视觉和鼠标验证

`nvim-web-devicons` 使用替身，不要求安装第三方图标插件
覆盖分割组归属、渲染、预览排除、关闭确认、点击桥接所有权和重配置
