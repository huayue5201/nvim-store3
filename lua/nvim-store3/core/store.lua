--- File: /Users/lijia/nvim-store3/lua/nvim-store3/core/store.lua
--- 核心存储模块

local PluginLoader = require("nvim-store3.core.plugin_loader")
local Path = require("nvim-store3.util.path")
local Event = require("nvim-store3.util.event")

local Store = {}
Store.__index = Store

local NULL_MARKER = "__null__"

---------------------------------------------------------------------
-- 创建 Store 实例
---------------------------------------------------------------------
--- 创建新的存储实例
--- @param config table 配置
--- @param config.scope string 作用域（global/project）
--- @param config.storage table 存储配置
--- @param config.auto_encode boolean 是否自动编码键名
--- @param config.plugins table 插件配置
--- @return table Store 实例
function Store.new(config)
	-- 检查存储路径是否有效
	local has_valid_path = config.storage.path and config.storage.path ~= ""

	local self = {
		scope = config.scope,
		storage_config = config.storage,
		_data = {},
		_backend = nil,
		_plugin_loader = nil,
		_auto_encode = config.auto_encode ~= false,
		_events = Event.new(),
		_noop = not has_valid_path, -- 路径无效时为空操作
	}

	setmetatable(self, Store)

	-- 只有有效路径才初始化后端
	if has_valid_path then
		self:_init_backend()
		self._plugin_loader = PluginLoader.new(self, config)
		self._plugin_loader:load_plugins()
		self:_setup_autocmd()
	end

	return self
end

---------------------------------------------------------------------
-- 事件系统
---------------------------------------------------------------------
--- 注册事件监听
--- @param event string 事件名称（set/delete/flush）
--- @param callback function 回调函数
function Store:on(event, callback)
	self._events:on(event, callback)
end

--- 触发事件
--- @param event string 事件名称
--- @param payload table 事件负载
function Store:_emit(event, payload)
	self._events:emit(event, payload)
end

---------------------------------------------------------------------
-- 初始化后端
---------------------------------------------------------------------
--- 初始化存储后端
function Store:_init_backend()
	if self._noop then
		return
	end
	local BackendFactory = require("nvim-store3.storage.backend_factory")
	self._backend = BackendFactory.create(self.storage_config)
end

---------------------------------------------------------------------
-- 自动命令
---------------------------------------------------------------------
--- 设置退出时的自动保存
function Store:_setup_autocmd()
	if self._noop then
		return
	end
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			pcall(function()
				self:flush()
			end)
		end,
	})
end

---------------------------------------------------------------------
-- 键编码
---------------------------------------------------------------------
--- 安全编码键名
--- @param key string 原始键名
--- @return string 编码后的键名
function Store:_safe_key(key)
	if self._noop then
		return key
	end
	if not self._auto_encode then
		return key
	end
	return Path.encode_key(key)
end

---------------------------------------------------------------------
-- CRUD API
---------------------------------------------------------------------
--- 设置键值对
--- @param key string 键名
--- @param value any 值
function Store:set(key, value)
	if self._noop then
		return
	end

	local safe_key = self:_safe_key(key)
	self._data[safe_key] = value
	self._backend:set(safe_key, value)
	self:_emit("set", { key = key, value = value })
end

--- 获取键值
--- @param key string 键名
--- @return any 值
function Store:get(key)
	if self._noop then
		return nil
	end

	local safe_key = self:_safe_key(key)
	local cached = self._data[safe_key]

	if cached == NULL_MARKER then
		return nil
	elseif cached ~= nil then
		return cached
	end

	local value = self._backend:get(safe_key)
	self._data[safe_key] = value or NULL_MARKER
	return value
end

--- 删除键值
--- @param key string 键名
function Store:delete(key)
	if self._noop then
		return
	end

	local safe_key = self:_safe_key(key)
	self._data[safe_key] = nil
	self._backend:delete(safe_key)
	self:_emit("delete", { key = key })
end

--- 获取所有键
--- @return table 键名列表
function Store:keys()
	if self._noop then
		return {}
	end

	if self._backend and self._backend.keys then
		local safe_keys = self._backend:keys()
		return Path.batch_decode_keys(safe_keys)
	end
	return {}
end

--- 获取命名空间下的所有键
--- @param namespace string 命名空间
--- @return table 去掉命名空间前缀的键名列表
function Store:namespace_keys(namespace)
	if self._noop then
		return {}
	end

	if not namespace or namespace == "" then
		return {}
	end

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

--- 持久化数据到磁盘
--- @return boolean 是否成功
function Store:flush()
	if self._noop then
		return true
	end

	local ok = self._backend:flush()
	self:_emit("flush", { ok = ok })

	for k, v in pairs(self._data) do
		if v == NULL_MARKER or v == nil then
			self._data[k] = nil
		end
	end

	return ok
end

--- 获取存储统计信息（优化版：只从缓存读取，不触发后端）
--- @return table 统计信息
function Store:get_stats()
	if self._noop then
		return {
			total_keys = 0,
			encoded_keys = 0,
			cache_size = 0,
			estimated_size = 0,
			scope = self.scope,
			auto_encode_enabled = self._auto_encode,
			noop = true,
		}
	end

	local keys = self:keys()
	local total_size = 0
	local encoded_keys = 0

	-- 只从缓存读取，避免触发后端 IO
	for _, key in ipairs(keys) do
		local safe_key = Path.encode_key(key)
		if Path.is_encoded_key(safe_key) then
			encoded_keys = encoded_keys + 1
		end

		local value = self._data[safe_key]
		if value and value ~= NULL_MARKER then
			local ok, json = pcall(vim.fn.json_encode, value)
			if ok and json then
				total_size = total_size + #json
			end
		end
	end

	return {
		total_keys = #keys,
		encoded_keys = encoded_keys,
		cache_size = vim.tbl_count(self._data),
		estimated_size = total_size,
		scope = self.scope,
		auto_encode_enabled = self._auto_encode,
		noop = false,
	}
end

--- 设置自动编码
--- @param enabled boolean 是否启用
function Store:set_auto_encode(enabled)
	if self._noop then
		return
	end
	if self._auto_encode == enabled then
		return
	end
	self._data = {}
	self._auto_encode = enabled
end

--- 获取自动编码状态
--- @return boolean 是否启用
function Store:get_auto_encode()
	return self._auto_encode
end

--- 路径查询（支持嵌套访问）
--- @param path string 路径，如 "notes.today.1"
--- @return any 查询结果
function Store:query(path)
	if self._noop then
		return nil
	end

	if not path or path == "" then
		return nil
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = self._data

	for i, part in ipairs(parts) do
		if i == 1 then
			local value = self:get(part)
			if value == nil then
				return nil
			end
			current = value
		else
			if type(current) ~= "table" then
				return nil
			end
			current = current[part]
			if current == nil then
				return nil
			end
		end
	end

	return current
end

--- 清理资源
function Store:cleanup()
	if self._noop then
		return
	end

	if self._plugin_loader then
		self._plugin_loader:cleanup()
	end
	self:flush()
	self._data = {}
end

return Store
