--- File: /Users/lijia/nvim-store3/lua/nvim-store3/core/feature_manager.lua ---
-- lua/nvim-store3/core/feature_manager.lua
-- 功能模块管理器：负责动态加载和管理功能模块

local M = {}

--- 创建新的功能管理器
--- @return table
function M.new()
	local self = {
		_enabled_features = {}, -- 已启用的功能
		_feature_instances = {}, -- 功能实例
		_available_features = { -- 可用功能列表
			"notes", -- 笔记功能
			"extmarks", -- Extmark 功能
			"semantic", -- 语义分析
			"links", -- 链接功能
			"buffer_cache", -- 缓存功能
			"path", -- 路径支持
			"query", -- 查询功能
		},
	}

	return setmetatable(self, { __index = M })
end

--- 检查是否为有效功能
--- @param feature_name string 功能名称
--- @return boolean 是否为有效功能
function M:is_feature(feature_name)
	return vim.tbl_contains(self._available_features, feature_name)
end

--- 启用功能模块
--- @param feature_name string 功能名称
--- @param config table 功能配置
--- @param store table Store 实例
function M:enable(feature_name, config, store)
	if not self:is_feature(feature_name) then
		error(string.format("Unknown feature: %s", feature_name))
	end

	-- 如果已经启用，先禁用
	if self._enabled_features[feature_name] then
		self:disable(feature_name, store)
	end

	-- 验证配置
	local validated_config = self:_validate_config(feature_name, config)

	-- 动态加载功能模块
	local module_path = "nvim-store3.features." .. feature_name .. ".manager"
	local ok, feature_module = pcall(require, module_path)

	if not ok then
		error(string.format("Failed to load feature module '%s': %s", feature_name, feature_module))
	end

	-- 初始化功能实例
	local feature_instance = feature_module.new(store, validated_config)

	-- 注册功能
	self._enabled_features[feature_name] = true
	self._feature_instances[feature_name] = feature_instance

	-- 将功能 API 挂载到 Store 上
	store[feature_name] = feature_instance

	return feature_instance
end

--- 禁用功能模块
--- @param feature_name string 功能名称
--- @param store table Store 实例
function M:disable(feature_name, store)
	if not self._enabled_features[feature_name] then
		return
	end

	-- 清理功能实例
	local feature_instance = self._feature_instances[feature_name]
	if feature_instance and feature_instance.cleanup then
		feature_instance:cleanup()
	end

	-- 从 Store 上移除 API
	store[feature_name] = nil

	-- 更新状态
	self._enabled_features[feature_name] = nil
	self._feature_instances[feature_name] = nil
end

--- 验证功能配置
--- @param feature_name string 功能名称
--- @param config table 原始配置
--- @return table 验证后的配置
function M:_validate_config(feature_name, config)
	-- 基础验证：确保配置是表（或 nil）
	if config == nil then
		return {}
	end

	if type(config) ~= "table" then
		error(string.format("Feature '%s' config must be a table or nil", feature_name))
	end

	-- 功能特定的验证
	local validators = {
		notes = function(cfg)
			if cfg.max_history and type(cfg.max_history) ~= "number" then
				error("notes.max_history must be a number")
			end
			if cfg.auto_sync and type(cfg.auto_sync) ~= "boolean" then
				error("notes.auto_sync must be a boolean")
			end
			return cfg
		end,

		extmarks = function(cfg)
			if cfg.types and not vim.tbl_islist(cfg.types) then
				error("extmarks.types must be a list")
			end
			return cfg
		end,

		buffer_cache = function(cfg)
			if cfg.ttl and type(cfg.ttl) ~= "number" then
				error("buffer_cache.ttl must be a number")
			end
			if cfg.max_size and type(cfg.max_size) ~= "number" then
				error("buffer_cache.max_size must be a number")
			end
			return cfg
		end,
	}

	local validator = validators[feature_name]
	if validator then
		return validator(config)
	end

	return config
end

--- 重新加载所有功能
--- @param new_config table 新的配置
--- @param store table Store 实例
function M:reload(new_config, store)
	-- 禁用所有当前功能
	for feature_name, _ in pairs(self._enabled_features) do
		self:disable(feature_name, store)
	end

	-- 启用新配置中的功能
	for key, value in pairs(new_config) do
		if self:is_feature(key) and value ~= nil then
			self:enable(key, value, store)
		end
	end
end

--- 检查功能是否启用
--- @param feature_name string 功能名称
--- @return boolean 是否启用
function M:is_enabled(feature_name)
	return self._enabled_features[feature_name] or false
end

--- 获取所有启用的功能
--- @return table 启用的功能列表
function M:get_enabled_features()
	local features = {}
	for name, _ in pairs(self._enabled_features) do
		table.insert(features, name)
	end
	return features
end

--- 获取功能实例
--- @param feature_name string 功能名称
--- @return table|nil 功能实例
function M:get_feature(feature_name)
	return self._feature_instances[feature_name]
end

return M
