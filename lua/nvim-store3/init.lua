-- 简化版入口文件 - 支持自动编码配置

local M = {}

local global_instance = nil
local project_instance = nil

--- 获取全局存储实例
--- @param opts? table 配置选项
--- @return table Store实例
function M.global(opts)
	if not global_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")

		-- 默认配置
		local config = {
			scope = "global",
			storage = {
				path = Path.global_store_path(),
				backend = "json",
				flush_delay = 1000,
			},
			auto_encode = true, -- 默认启用自动编码
		}

		-- 合并用户配置
		if opts then
			config = vim.tbl_deep_extend("force", config, opts)
		end

		global_instance = Store.new(config)
	end

	return global_instance
end

--- 获取项目存储实例
--- @param opts? table 配置选项
--- @return table Store实例
function M.project(opts)
	if not project_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")

		-- 默认配置
		local config = {
			scope = "project",
			storage = {
				path = Path.project_store_path(),
				backend = "json",
				flush_delay = 1000,
			},
			-- auto_encode = true, -- 默认启用自动编码
		}

		-- 合并用户配置
		if opts then
			config = vim.tbl_deep_extend("force", config, opts)
		end

		project_instance = Store.new(config)
	end

	return project_instance
end

--- 获取可用插件列表
--- @return table 插件名称列表
function M.get_available_plugins()
	local PluginLoader = require("nvim-store3.core.plugin_loader")
	local plugins = {}

	for name, _ in pairs(PluginLoader.registry) do
		table.insert(plugins, name)
	end

	return plugins
end

--- 清理所有实例
function M.clear()
	if global_instance then
		global_instance:cleanup()
		global_instance = nil
	end
	if project_instance then
		project_instance:cleanup()
		project_instance = nil
	end
end

--- 注册自定义插件
--- @param plugin_name string 插件名称
--- @param module_path string 模块路径
function M.register_plugin(plugin_name, module_path)
	local PluginLoader = require("nvim-store3.core.plugin_loader")
	PluginLoader.registry[plugin_name] = module_path
end

return M
