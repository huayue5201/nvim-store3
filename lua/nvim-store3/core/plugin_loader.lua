-- 简化版插件加载器 - 只加载核心基础设施插件
local M = {}

-- 核心插件注册表 - 只包含基础设施插件
M.registry = {
	-- 核心基础设施插件
	basic_cache = "nvim-store3.features.basic_cache", -- 通用缓存
	extmarks = "nvim-store3.features.extmarks", -- Extmarks存储

	-- 可选的通用插件（开发者可按需注册）
	-- 注意：不包含notes、semantic等应用功能
}

--- 创建插件加载器
--- @param store table Store实例
--- @param config table 配置
--- @return table 插件加载器
function M.new(store, config)
	local self = {
		store = store,
		config = config or {},
		plugins = {}, -- 已加载插件 {name = instance}
		_loaded = {}, -- 已加载标记
	}

	return setmetatable(self, { __index = M })
end

--- 加载所有配置的插件
function M:load_plugins()
	-- 遍历配置，查找插件配置
	for plugin_name, plugin_config in pairs(self.config) do
		-- 跳过保留字段
		if plugin_name ~= "scope" and plugin_name ~= "storage" then
			-- 如果配置为true，则使用默认配置
			if plugin_config == true then
				plugin_config = {}
			end

			-- 如果配置为false或nil，则跳过
			if plugin_config ~= false and plugin_config ~= nil then
				self:load_plugin(plugin_name, plugin_config)
			end
		end
	end
end

--- 加载单个插件
--- @param plugin_name string 插件名称
--- @param plugin_config table 插件配置
--- @return table|nil 插件实例
function M:load_plugin(plugin_name, plugin_config)
	-- 检查是否已加载
	if self.plugins[plugin_name] then
		return self.plugins[plugin_name]
	end

	-- 检查插件是否在注册表中
	local module_path = M.registry[plugin_name]
	if not module_path then
		-- 允许动态加载未注册的插件
		module_path = plugin_name
		-- 注意：这里简化处理，实际可能需要路径解析
	end

	-- 动态加载插件模块
	local ok, plugin_module = pcall(require, module_path)
	if not ok then
		vim.notify(string.format("Failed to load plugin '%s': %s", plugin_name, plugin_module), vim.log.levels.WARN)
		return nil
	end

	-- 创建插件实例
	local plugin_instance
	if plugin_module.new then
		plugin_instance = plugin_module.new(self.store, plugin_config)
	else
		-- 如果模块没有new方法，使用模块本身作为实例
		plugin_instance = plugin_module
	end

	if not plugin_instance then
		vim.notify(string.format("Failed to initialize plugin '%s'", plugin_name), vim.log.levels.WARN)
		return nil
	end

	-- 存储插件实例
	self.plugins[plugin_name] = plugin_instance
	self._loaded[plugin_name] = true

	-- 将插件API挂载到Store上
	self.store[plugin_name] = plugin_instance

	return plugin_instance
end

--- 卸载插件
--- @param plugin_name string 插件名称
function M:unload_plugin(plugin_name)
	local plugin = self.plugins[plugin_name]
	if not plugin then
		return
	end

	-- 调用清理方法
	if plugin.cleanup then
		pcall(plugin.cleanup, plugin)
	end

	-- 从Store移除
	self.store[plugin_name] = nil
	self.plugins[plugin_name] = nil
	self._loaded[plugin_name] = nil
end

--- 获取插件
--- @param plugin_name string 插件名称
--- @return table|nil 插件实例
function M:get_plugin(plugin_name)
	return self.plugins[plugin_name]
end

--- 检查插件是否已加载
--- @param plugin_name string 插件名称
--- @return boolean 是否已加载
function M:has_plugin(plugin_name)
	return self._loaded[plugin_name] or false
end

--- 清理所有插件
function M:cleanup()
	for plugin_name, _ in pairs(self._loaded) do
		self:unload_plugin(plugin_name)
	end
end

return M
