-- nvim-store3/init.lua
local M = {}

local global_instance = nil
local project_instance = nil

local function default_config(scope, Path)
	return {
		scope = scope,
		storage = {
			path = scope == "global" and Path.global_store_path() or Path.project_store_path(),
			backend = "json",
			flush_delay = 1000,
		},
		auto_encode = true,
		plugins = {},
	}
end

function M.global(opts)
	if not global_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")
		global_instance = Store.new(default_config("global", Path))
		if opts then
			global_instance = vim.tbl_deep_extend("force", global_instance, opts)
		end
	end
	return global_instance
end

function M.project(opts)
	if not project_instance then
		local Store = require("nvim-store3.core.store")
		local Path = require("nvim-store3.util.path")
		project_instance = Store.new(default_config("project", Path))
		if opts then
			project_instance = vim.tbl_deep_extend("force", project_instance, opts)
		end
	end
	return project_instance
end

function M.get_available_plugins()
	local PluginLoader = require("nvim-store3.core.plugin_loader")
	local plugins = {}
	for name, _ in pairs(PluginLoader.registry) do
		table.insert(plugins, name)
	end
	return plugins
end

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

function M.register_plugin(plugin_name, module_path)
	require("nvim-store3.core.plugin_loader").registry[plugin_name] = module_path
end

-- 自动启动清理
require("nvim-store3.util.path")._start_auto_cleanup()

return M
