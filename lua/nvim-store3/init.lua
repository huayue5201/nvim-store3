-- lua/nvim-store3/init.lua
---@brief nvim-store3 主入口模块

local M = {}

local global_instance = nil
local project_instance = nil

---创建默认配置
---@param scope string
---@param Path table
---@return table
local function default_config(scope, Path)
	local path = scope == "global" and Path.global_store_path() or Path.project_store_path()

	return {
		scope = scope,
		storage = {
			path = path,
			backend = "json",
			flush_delay = 1000,
		},
		auto_encode = true,
		plugins = {},
	}
end

---获取全局存储实例
---@param opts table|nil
---@return table
function M.global(opts)
	if not global_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")
		global_instance = Store.new(default_config("global", Path))
		if opts then
			for k, v in pairs(opts) do
				global_instance[k] = v
			end
		end
	end
	return global_instance
end

---获取项目存储实例
---@param opts table|nil
---@return table
function M.project(opts)
	if not project_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")
		project_instance = Store.new(default_config("project", Path))
		if opts then
			for k, v in pairs(opts) do
				project_instance[k] = v
			end
		end
	end
	return project_instance
end

---获取可用插件列表
---@return string[]
function M.get_available_plugins()
	local PluginLoader = require("nvim-store3.core.plugin_loader")
	local plugins = {}
	for name, _ in pairs(PluginLoader.registry) do
		table.insert(plugins, name)
	end
	return plugins
end

---清理存储实例
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

---注册自定义插件
---@param plugin_name string
---@param module_path string
function M.register_plugin(plugin_name, module_path)
	require("nvim-store3.core.plugin_loader").registry[plugin_name] = module_path
end

---配置清理模块
---@param opts table|nil
function M.setup_cleanup(opts)
	local Cleanup = require("nvim-store3.core.cleanup")
	Cleanup.setup(opts or { enabled = true })
end

-- 默认启动清理（使用默认配置）
M.setup_cleanup()

return M
