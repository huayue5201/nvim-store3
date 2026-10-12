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

-- 注意：不再默认启动破坏性自动清理。
-- 如果确实需要，请在配置里显式调用：
--   require("nvim-store3").setup_cleanup({ enabled = true })
