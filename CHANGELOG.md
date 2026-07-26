# Changelog

## [0.1.1] - 2026-07-26

### Fixed

- 禁用插件时恢复启用前已有的 winbar 点击回调，并保留启用后被其他插件替换的回调，避免污染全局 `v:lua` 处理函数

## [0.1.0] - 2026-07-13

### Changed

- **诊断徽标显示为 `vv-icons` 图标 + 数量，并补齐图标和数字间距**：通过 `vv-utils.diagnostics` 复用统一诊断图标与 `Diagnostic*` 高亮，bufferline 自己在徽标中保留 `icon + 空格 + count` 的布局，避免图标和数字紧贴造成视觉错位
