-- File: plugin/nvim-store3.lua
-- 轻量入口：注册内置命令并启动自动清理。
-- 存储核心（json_backend 等重模块）在命令触发或首次 global()/project() 时按需加载。

if vim.g.loaded_nvim_store3 then
	return
end
vim.g.loaded_nvim_store3 = 1

-- 注册内置命令（:Store / :StoreDelete），命令回调内延迟 require 存储核心
require("nvim-store3.plugins.project_query").setup()
require("nvim-store3.plugins.project_delete").setup()

-- 启动自动清理（轻量 uv timer，默认 24 小时检查一次）
require("nvim-store3").setup_cleanup()
