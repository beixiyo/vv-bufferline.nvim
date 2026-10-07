# Changelog

## 0.2.0 - 2026-10-07

### Added

- `track_modified`（默认开启）：窗口外被修改且未出现在任何分组的 buffer（LSP 跨文件编辑、后台格式化等）自动纳入当前编辑窗口并转正 `buflisted`，未保存状态在标签上可见；显式删除过的 buffer 不因此复活，预览 buffer 仍由 `vv-explorer` 的 promote 语义接管
- 默认键位与 `keys` 配置：`[b`/`]b`/`[B`/`]B` 按窗口标签序切换，`<leader>bd`/`bD`/`bh`/`bl`/`bo`/`ba` 关闭系列
- `hooks.after_close(ctx)` 回调：关闭类动作（含鼠标关闭）完成后触发
- `VVBufferlineFirst` / `VVBufferlineLast` 命令与 `jump_to_end(side)` API，跳到当前窗口分组的端点标签
- 修改发生在被忽略的 tab（如 vv-git 的 diff 编辑窗）或 dashboard-only 会话时，归属回退到最近编辑窗口，不再丢弃

### Changed

- 最低 Neovim 版本从 0.10 提升至 0.12

### Fixed (audit)

- 修改追踪的延迟回调受 disable/setup 代次约束，所有窗口的预览槽均不抢占
- 归属排除普通面板；`placeholder_filetypes` 明确起始页策略，未修改的未命名空白 buffer（含 listed）可被顶替
- 重复 setup 按旧 leader 展开值清理自己仍持有的键位，恢复原映射并保留外部重绑；单键禁用类型修正
- `after_close` 增加 `completed` 与 `tabpage`，让展示策略识别取消/失败与过期 tab
- 0.12 回退 `BufModifiedSet`；明确完整隐藏修改追踪需要 0.13，旧版仅尽力处理可报告的修改

## 0.1.1 - 2026-07-26

### Fixed

- 禁用时恢复原有 winbar 点击回调；若已被其他插件替换则保留新回调，避免污染全局处理函数

## 0.1.0 - 2026-07-13

### Changed

- 诊断徽标显示为 `vv-icons` 图标 + 数量，统一诊断配色并补齐间距，避免视觉错位
