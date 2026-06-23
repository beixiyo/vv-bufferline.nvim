# Changelog

## [Unreleased]

### Changed

- **诊断徽标显示为 `vv-icons` 图标 + 数量，并补齐图标和数字间距**：通过 `vv-utils.diagnostics` 复用统一诊断图标与 `Diagnostic*` 高亮，bufferline 自己在徽标中保留 `icon + 空格 + count` 的布局，避免图标和数字紧贴造成视觉错位
