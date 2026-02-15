-- nvim-store3/core/plugin_loader.lua
-- 插件加载器（精简版）

local M = {}

---------------------------------------------------------------------
-- 核心插件注册表
---------------------------------------------------------------------
M.registry = {
	basic_cache = "nvim-store3.features.basic_cache",
	extmarks = "nvim-store3.features.extmarks",
}

---------------------------------------------------------------------
-- 创建插件加载器
---------------------------------------------------------------------
function M.new(store, config)
	local self = {
		store = store,
		config = config or {},
		plugins = {},
		_loaded = {},
	}
	return setmetatable(self, { __index = M })
end

---------------------------------------------------------------------
-- 加载所有插件
---------------------------------------------------------------------
function M:load_plugins()
	local plugin_cfg = self.config.plugins or {}
	if type(plugin_cfg) ~= "table" then
		return
	end

	for plugin_name, plugin_config in pairs(plugin_cfg) do
		if plugin_config == true then
			plugin_config = {}
		end
		if plugin_config ~= false and plugin_config ~= nil then
			self:load_plugin(plugin_name, plugin_config)
		end
	end
end

---------------------------------------------------------------------
-- 加载单个插件
---------------------------------------------------------------------
function M:load_plugin(plugin_name, plugin_config)
	if self.plugins[plugin_name] then
		return self.plugins[plugin_name]
	end

	local module_path = M.registry[plugin_name] or plugin_name

	local ok, plugin_module = pcall(require, module_path)
	if not ok then
		vim.notify(string.format("Failed to load plugin '%s': %s", plugin_name, plugin_module), vim.log.levels.WARN)
		return nil
	end

	local plugin_instance
	if type(plugin_module) == "table" and plugin_module.new then
		plugin_instance = plugin_module.new(self.store, plugin_config)
	else
		plugin_instance = plugin_module
	end

	if not plugin_instance then
		vim.notify(string.format("Failed to initialize plugin '%s'", plugin_name), vim.log.levels.WARN)
		return nil
	end

	self.plugins[plugin_name] = plugin_instance
	self._loaded[plugin_name] = true
	self.store[plugin_name] = plugin_instance

	return plugin_instance
end

---------------------------------------------------------------------
-- 卸载插件
---------------------------------------------------------------------
function M:unload_plugin(plugin_name)
	local plugin = self.plugins[plugin_name]
	if not plugin then
		return
	end

	if plugin.cleanup then
		pcall(plugin.cleanup, plugin)
	end

	self.store[plugin_name] = nil
	self.plugins[plugin_name] = nil
	self._loaded[plugin_name] = nil
end

---------------------------------------------------------------------
-- 清理所有插件
---------------------------------------------------------------------
function M:cleanup()
	for name, _ in pairs(self._loaded) do
		self:unload_plugin(name)
	end
end

return M
