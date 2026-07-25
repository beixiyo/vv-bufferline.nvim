<div align="center">

# vv-bufferline.nvim

English | [中文](./README.zh-CN.md)

<img src="https://github.com/beixiyo/vv-bufferline.nvim/releases/download/assets-2026-07-25/vv-bufferline.png" alt="vv-bufferline demo" width="900" />

Want my Neovim config? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>

A VSCode-like **split-local** buffer tabline

<img src="https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white" alt="Neovim" />
<img src="https://img.shields.io/badge/Lua-2C2D72?logo=lua&logoColor=white" alt="Lua" />

</div>

`vv-bufferline` uses the window-local `winbar` so that **every window** renders
its own list of visited buffers. Neovim's buffers are still global — only the
tab UI state is isolated per window

## Why build this instead of using an existing bufferline

Mainstream bufferlines (`akinsho/bufferline.nvim`, `nvim-cokeline`, etc.) are
essentially a single **global tabline**: every window shares one tabline that
"lists all buffers". This plugin exists to solve the things they cannot do by
design, or can only fake with hacks:

- **Every split minds its own business (the core requirement)**: the tabline is
  attached to each window's `winbar`, so each split only shows the buffers it
  has opened — exactly like VSCode's editor groups. When the left and right
  splits open different sets of files, they never bleed into each other, whereas
  a global tabline cannot express "this split only shows these few"
- **winbar first**: tabs naturally follow the window and are inherited by
  `:split`; they do not take over the global `tabline`, and do not fight with
  anything else that uses the tabline (the built-in tabline is hidden by
  default, so opening multiple tabs does not produce `pathshorten` noise)
- **Optional global display**: if you prefer the traditional global bufferline,
  switch to `render_target = 'tabline'` to render the buffer group of the
  currently active editor window into the global tabline
- **Deep collaboration with the vv-* ecosystem**: `should_show` keeps the
  tabline from disappearing while vv-explorer is previewing a file;
  `ignored_win` plus the tab-scoped convention variable `vv_bufferline_ignore`
  lets vv-git's own tab be skipped entirely so no tabs are stacked onto it;
  diagnostics and icons go uniformly through `vv-utils` / `vv-icons`. These are
  collaboration points tailor-made for this plugin — third-party plugins either
  cannot do them, or have to force it with monkey-patching
- **Lightweight**: it does not take over Neovim's buffer model (buffers stay
  global), it only maintains a layer of window-level UI state; no extra
  dependencies

## Features

- Per-window buffer tabs for normal editor windows
- Click a tab → switch to that buffer in the current split
- Hovering a tab shows `×`; clicking `×` → closes via `vv-utils.bufdelete`
- File icons and colors via `vv-icons` / `mini.icons`
- Modified indicator
- Diagnostic badges via `vv-utils.diagnostics`
- Automatically filters special windows: help, quickfix, terminal,
  `vv-explorer`, `vv-git`, diff windows
- Tab truncation in narrow windows

## Installation and configuration

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

Option meanings:

- `max_name_width`: max display width of a file name before it is truncated
- `show_close`: always show the close button
- `hover_close`: show the close button when hovering a tab, without taking up
  extra layout width
- `diagnostics`: diagnostic badges
- `hide_tabline`: hide the built-in tabline (buffers are already shown in the
  winbar)
- `render_target`: `'winbar'` renders per window; `'tabline'` renders the
  current group globally
- `exclude_filetypes`: filetypes for which the tabline is not shown
- `colors`: optional theme colors

## Commands

| Command | Description |
|---|---|
| `:VVBufferlineEnable` | Enable the tabline |
| `:VVBufferlineDisable` | Disable it and restore the display host |
| `:VVBufferlineToggle` | Toggle |
| `:VVBufferlineCloseCurrent` | Close the current tab |
| `:VVBufferlineCloseCurrentForce` | Force-close the current tab (discard unsaved changes) |
| `:VVBufferlineCloseLeft` | Close the buffers to the left of the current tab |
| `:VVBufferlineCloseRight` | Close the buffers to the right of the current tab |
| `:VVBufferlineCloseOthers` | Close all buffers except the current tab |
| `:VVBufferlineCloseAll` | Close all buffers |

## Design

This plugin deliberately does **not** replace Neovim's buffer model — buffers
remain global. Each window merely maintains one extra UI list of "buffers
visited in this window". By default it renders into `vim.wo[win].winbar`, so
every split gets its own tabline at the same time; with
`render_target = 'tabline'` only the group of the currently active editor window
is rendered into the global `tabline`, which suits people who prefer a single
global bufferline

## License

[MIT](./LICENSE)
