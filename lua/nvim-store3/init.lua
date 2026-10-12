-- lua/nvim-store3/init.lua
---@brief nvim-store3 主入口模块

local M = {}

local global_instance = nil
local project_instances = {}

---创建默认配置
---@param scope string
---@param Path table
---@return table
local function default_config(scope, Path, from, name)
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
			path = Path.project_store_path(from, name),
			meta_path = Path.project_meta_path(from, name),
			root = Path.project_root(from),
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

---项目实例缓存键：项目根 + 命名 store
---@param from string|nil
---@param name string|nil
---@return string
local function instance_key(from, name)
	local Path = require("nvim-store3.util.path")
	return Path.project_key(from) .. "\1" .. (name or "default")
end

---获取项目存储实例（按项目根 + 命名 store 分别缓存）
---@param opts table|nil
---@param opts.from string|nil 起始路径（文件或目录），用于解析项目根；缺省用当前工作目录
---@param opts.name string|nil 命名 store（缺省 "default"，落到 projects/<key>/data.json）
---@return table
function M.project(opts)
	opts = opts or {}
	local Path = require("nvim-store3.util.path")
	local from = opts.from
	local name = opts.name or "default"
	local key = instance_key(from, name)

	if not project_instances[key] then
		local Store = require("nvim-store3.core.store")
		-- 不要把 from/name 字段混入 store 配置
		local clean = vim.tbl_extend("force", {}, opts)
		clean.from = nil
		clean.name = nil
		project_instances[key] = Store.new(merge_config(default_config("project", Path, from, name), clean))
	end

	return project_instances[key]
end

---卸载一个项目存储实例（flush 并释放内存）
---@param opts table|nil
---@param opts.from string|nil
---@param opts.name string|nil
---@return boolean 是否确实卸载了一个已加载实例
function M.unload(opts)
	opts = opts or {}
	local key = instance_key(opts.from, opts.name)
	local inst = project_instances[key]
	if inst then
		inst:cleanup()
		project_instances[key] = nil
		return true
	end
	return false
end

---某个项目存储实例是否已加载
---@param opts table|nil
---@param opts.from string|nil
---@param opts.name string|nil
---@return boolean
function M.is_loaded(opts)
	opts = opts or {}
	return project_instances[instance_key(opts.from, opts.name)] ~= nil
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

---列出已加载的项目存储实例名
---@return string[]
function M.loaded_names()
	local names = {}
	for key in pairs(project_instances) do
		local sep = key:find("\1", 1, true)
		table.insert(names, sep and key:sub(sep + 1) or key)
	end
	return names
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
