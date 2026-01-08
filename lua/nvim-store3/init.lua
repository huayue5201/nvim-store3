--- File: /Users/lijia/nvim-store3/lua/nvim-store3/init.lua ---
-- lua/nvim-store3/init.lua
-- 新的入口文件，提供 global() 和 project() 工厂函数

local M = {}

-- 存储单例实例
local global_instance = nil
local project_instance = nil

--- 获取全局存储实例
--- @param opts? table 配置选项
--- @return table Store 实例
function M.global(opts)
	if not global_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")

		-- 构建全局配置
		local default_config = {
			scope = "global",
			storage = {
				path = Path.global_store_path(),
				backend = "json",
				lazy_load = false, -- 全局数据立即加载
				flush_delay = 1000,
			},
		}

		-- 合并用户配置
		local config = vim.tbl_deep_extend("force", default_config, opts or {})

		global_instance = Store.new(config)
	end

	return global_instance
end

--- 获取项目存储实例
--- @param opts? table 配置选项
--- @return table Store 实例
function M.project(opts)
	if not project_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")

		-- 构建项目配置
		local default_config = {
			scope = "project",
			storage = {
				path = Path.project_store_path(),
				backend = "json",
				lazy_load = true, -- 项目数据懒加载
				flush_delay = 1000,
			},
		}

		-- 合并用户配置
		local config = vim.tbl_deep_extend("force", default_config, opts or {})

		project_instance = Store.new(config)
	end

	return project_instance
end

--- 清理缓存，用于测试和重载
function M.clear()
	global_instance = nil
	project_instance = nil
end

return M
