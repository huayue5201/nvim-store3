-- lua/nvim-store3/init.lua
---@brief nvim-store3 主入口模块

local M = {}

local global_instance = nil
local project_instances = {}

---创建默认配置
---@param scope string
---@param Path table
---@return table
local function default_config(scope, Path)
	if scope == "global" then
		return {
			scope = scope,
			storage = {
				path = Path.global_store_path(),
				backend = "json",
				flush_delay = 1000,
				version = 2,
			},
			plugins = {},
		}
	end

	return {
		scope = scope,
		storage = {
			path = Path.project_store_path(),
			meta_path = Path.project_meta_path(),
			root = Path.project_root(),
			backend = "json",
			flush_delay = 1000,
			version = 2,
		},
		plugins = {},
	}
end

---合并用户配置
---@param base table
---@param opts table|nil
---@return table
local function merge_config(base, opts)
	if opts then
		return vim.tbl_deep_extend("force", base, opts)
	end
	return base
end

---获取全局存储实例
---@param opts table|nil
---@return table
function M.global(opts)
	if not global_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")
		global_instance = Store.new(merge_config(default_config("global", Path), opts))
	end
	return global_instance
end

---获取项目存储实例（按当前项目根目录分别缓存）
---@param opts table|nil
---@return table
function M.project(opts)
	local Path = require("nvim-store3.util.path")
	local key = Path.project_key()

	if not project_instances[key] then
		local Store = require("nvim-store3.core.store")
		project_instances[key] = Store.new(merge_config(default_config("project", Path), opts))
	end

	return project_instances[key]
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

---清理所有存储实例
function M.clear()
	if global_instance then
		global_instance:cleanup()
		global_instance = nil
	end
	for _, instance in pairs(project_instances) do
		instance:cleanup()
	end
	project_instances = {}
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

return M
