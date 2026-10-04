# 测试依赖默认值；由共享入口在启动隔离前加载，只使用已有源码/工具
VV_TEST_ICONS=$(vv_test_source_path VV_TEST_ICONS "$VV_TEST_REPO/../vv-icons.nvim")
export VV_TEST_ICONS
