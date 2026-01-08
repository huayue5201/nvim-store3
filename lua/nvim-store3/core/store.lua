-- lua/nvim-store3/core/store.lua
-- 统一的 Store 类，支持全局和项目作用域

local FeatureManager = require("nvim-store3.core.feature_manager")

--- @class Store
--- @field scope string 作用域："global" 或 "project"
--- @field config table 配置信息
--- @field backend table 存储后端实例
--- @field features table 功能模块管理器
--- @field _data table 内存中的数据缓存
local Store = {}
Store.__index = Store

--- 创建新的 Store 实例
--- @param config table 配置信息
--- @return Store
function Store.new(config)
	local self = {
		scope = config.scope,
		config = config,
		backend = nil,
		features = FeatureManager.new(),
		_data = {},
		_initialized = false,
	}

	setmetatable(self, Store)

	-- 初始化存储后端
	self:_init_backend()

	-- 初始化基础功能（如果配置了的话）
	self:_init_features(config)

	-- 设置退出前自动保存
	self:_setup_autocmd()

	self._initialized = true
	return self
end

--- 初始化存储后端
function Store:_init_backend()
	local BackendFactory = require("nvim-store3.storage.backend_factory")

	-- 确保存储目录存在
	local Path = require("nvim-store3.util.path")
	local dir = vim.fn.fnamemodify(self.config.storage.path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	self.backend = BackendFactory.create(self.config.storage)
end

--- 初始化功能模块
function Store:_init_features(config)
	-- 遍历配置，查找功能配置
	for key, value in pairs(config) do
		if self.features:is_feature(key) and value ~= nil then
			self.features:enable(key, value, self)
		end
	end
end

--- 设置自动命令
function Store:_setup_autocmd()
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			pcall(function()
				self:flush()
			end)
		end,
	})
end

----------------------------------------------------------------------
-- 基础 CRUD API（永远可用）
----------------------------------------------------------------------

--- 存储数据
--- @param key string 键名
--- @param value any 数据值
function Store:set(key, value)
	self._data[key] = value
	self.backend:set(nil, key, value)
end

--- 获取数据
--- @param key string 键名
--- @return any 数据值
function Store:get(key)
	-- 优先从内存缓存获取
	if self._data[key] ~= nil then
		return self._data[key]
	end

	-- 从后端获取
	local value = self.backend:get(nil, key)
	self._data[key] = value
	return value
end

--- 删除数据
--- @param key string 键名
function Store:delete(key)
	self._data[key] = nil
	self.backend:delete(nil, key)
end

--- 查询数据（点号路径）
--- @param path string 点号路径
--- @return any 查询结果
function Store:query(path)
	local Query = require("nvim-store3.util.query")
	return Query.get(self._data, path)
end

--- 获取所有键（由后端提供）
--- @return string[] 键名列表
function Store:keys()
	if self.backend and self.backend.keys then
		return self.backend:keys(nil)
	end
	return {}
end

----------------------------------------------------------------------
-- 其他基础方法
----------------------------------------------------------------------

--- 强制刷新数据到磁盘
--- @return boolean 是否成功
function Store:flush()
	return self.backend:flush()
end

--- 获取作用域
--- @return string 作用域名称
function Store:scope()
	return self.scope
end

--- 获取配置
--- @return table 配置信息
function Store:get_config()
	return vim.deepcopy(self.config)
end

--- 重新加载配置（谨慎使用）
--- @param new_config table 新的配置
function Store:reload_config(new_config)
	-- 验证新配置
	if new_config.scope ~= self.scope then
		error("Cannot change scope after initialization")
	end

	-- 重新初始化功能
	self.features:reload(new_config, self)

	-- 更新配置
	self.config = vim.tbl_deep_extend("force", self.config, new_config)
end

return Store
