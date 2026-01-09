-- 核心存储类 - 集成自动路径编码

local PluginLoader = require("nvim-store3.core.plugin_loader")
local Path = require("nvim-store3.util.path")

local Store = {}
Store.__index = Store

-- 特殊标记，用于区分缓存中的nil值和未查询状态
local NULL_MARKER = "__null__"

--- 创建新的 Store 实例
--- @param config table 配置信息
--- @return Store
function Store.new(config)
	local self = {
		scope = config.scope,
		storage_config = config.storage,
		_data = {}, -- 内存缓存（使用编码后的键）
		_backend = nil,
		_plugin_loader = nil,
		_initialized = false,
		_auto_encode = config.auto_encode ~= false, -- 默认启用自动编码
	}

	setmetatable(self, Store)

	-- 初始化存储后端
	self:_init_backend()

	-- 初始化插件加载器（只加载核心插件）
	self._plugin_loader = PluginLoader.new(self, config)
	self._plugin_loader:load_plugins()

	-- 设置自动保存
	self:_setup_autocmd()

	self._initialized = true
	return self
end

--- 初始化存储后端
function Store:_init_backend()
	local BackendFactory = require("nvim-store3.storage.backend_factory")
	local PathUtil = require("nvim-store3.util.path")

	-- 确保存储目录存在
	local dir = vim.fn.fnamemodify(self.storage_config.path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	self._backend = BackendFactory.create(self.storage_config)
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

--- 获取安全的存储键（内部使用）
--- @param key string 原始键名
--- @return string 编码后的安全键
function Store:_safe_key(key)
	if not self._auto_encode then
		return key
	end
	return Path.encode_key(key)
end

--- 获取原始键名（内部使用）
--- @param safe_key string 编码后的安全键
--- @return string 原始键名
function Store:_unsafe_key(safe_key)
	if not self._auto_encode then
		return safe_key
	end
	return Path.decode_key(safe_key)
end

----------------------------------------------------------------------
-- 核心 CRUD API（自动路径编码）
----------------------------------------------------------------------

--- 存储数据（自动编码键名）
--- @param key string 键名
--- @param value any 数据值
function Store:set(key, value)
	local safe_key = self:_safe_key(key)
	self._data[safe_key] = value
	self._backend:set(nil, safe_key, value)
end

--- 获取数据（自动编码键名）
--- @param key string 键名
--- @return any 数据值
function Store:get(key)
	local safe_key = self:_safe_key(key)

	-- 检查内存缓存，但跳过NULL标记
	local cached = self._data[safe_key]
	if cached == NULL_MARKER then
		return nil
	elseif cached ~= nil then
		return cached
	end

	-- 从后端获取
	local value = self._backend:get(nil, safe_key)
	-- 缓存时区分nil值和有效值
	self._data[safe_key] = value or NULL_MARKER
	return value
end

--- 删除数据（自动编码键名）
--- @param key string 键名
function Store:delete(key)
	local safe_key = self:_safe_key(key)
	self._data[safe_key] = NULL_MARKER
	self._backend:delete(nil, safe_key)
end

--- 批量设置数据（自动编码键名）
--- @param data table 键值对表
function Store:batch_set(data)
	for key, value in pairs(data) do
		local safe_key = self:_safe_key(key)
		self._data[safe_key] = value
		self._backend:set(nil, safe_key, value)
	end
end

--- 批量获取数据（自动编码键名）
--- @param keys table 键名列表
--- @return table 键值对表
function Store:batch_get(keys)
	local result = {}
	for _, key in ipairs(keys) do
		result[key] = self:get(key)
	end
	return result
end

--- 查询数据（点号路径，支持编码路径）
--- @param path string 点号路径
--- @return any 查询结果
function Store:query(path)
	local Query = require("nvim-store3.util.query")

	-- 创建编码函数包装器
	local encode_func = function(part)
		return self:_safe_key(part)
	end

	-- 使用带编码器的查询
	return Query.get(self._data, path, encode_func)
end

--- 获取所有键（返回解码后的原始键名）
--- @return string[] 键名列表
function Store:keys()
	if self._backend and self._backend.keys then
		local safe_keys = self._backend:keys(nil)
		return Path.batch_decode_keys(safe_keys)
	end
	return {}
end

--- 获取命名空间下的所有键（返回解码后的原始键名）
--- @param namespace string 命名空间（如 "notes"）
--- @return string[] 键名列表（不含命名空间前缀）
function Store:namespace_keys(namespace)
	local all_keys = self:keys()
	local result = {}
	local prefix = namespace .. "."

	for _, key in ipairs(all_keys) do
		if key:sub(1, #prefix) == prefix then
			table.insert(result, key:sub(#prefix + 1))
		end
	end

	return result
end

--- 强制刷新数据到磁盘
--- @return boolean 是否成功
function Store:flush()
	return self._backend:flush()
end

--- 获取存储统计信息
--- @return table 统计信息
function Store:get_stats()
	local keys = self:keys()
	local total_size = 0
	local encoded_keys = 0

	-- 估算总大小和统计编码键数量
	for _, key in ipairs(keys) do
		local value = self:get(key)
		if value then
			total_size = total_size + #vim.fn.json_encode(value)
		end

		-- 统计编码键数量
		local safe_key = self:_safe_key(key)
		if Path.is_encoded_key(safe_key) then
			encoded_keys = encoded_keys + 1
		end
	end

	return {
		total_keys = #keys,
		encoded_keys = encoded_keys,
		cache_size = #vim.tbl_keys(self._data),
		estimated_size = total_size,
		scope = self.scope,
		auto_encode_enabled = self._auto_encode,
	}
end

--- 启用或禁用自动编码
--- @param enabled boolean 是否启用
function Store:set_auto_encode(enabled)
	if self._auto_encode == enabled then
		return
	end

	-- 清空内存缓存，因为键的编码方式改变了
	self._data = {}
	self._auto_encode = enabled
end

--- 检查是否启用自动编码
--- @return boolean 是否启用
function Store:get_auto_encode()
	return self._auto_encode
end

--- 清理资源
function Store:cleanup()
	if self._plugin_loader then
		self._plugin_loader:cleanup()
	end
	self:flush()
	self._data = {}
end

return Store
