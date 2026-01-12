-- nvim-store3/core/store.lua
-- 专业版 Store（事件系统 + 自动编码 + 插件系统）

local PluginLoader = require("nvim-store3.core.plugin_loader")
local Path = require("nvim-store3.util.path")
local Event = require("nvim-store3.util.event")

local Store = {}
Store.__index = Store

local NULL_MARKER = "__null__"

---------------------------------------------------------------------
-- 创建 Store 实例
---------------------------------------------------------------------
function Store.new(config)
	local self = {
		scope = config.scope,
		storage_config = config.storage,
		_data = {},
		_backend = nil,
		_plugin_loader = nil,
		_initialized = false,
		_auto_encode = config.auto_encode ~= false,
		_events = Event.new(),
	}

	setmetatable(self, Store)

	-- 初始化后端（不创建目录）
	self:_init_backend()

	-- 加载插件
	self._plugin_loader = PluginLoader.new(self, config)
	self._plugin_loader:load_plugins()

	-- 自动 flush
	self:_setup_autocmd()

	self._initialized = true
	return self
end

---------------------------------------------------------------------
-- 事件系统
---------------------------------------------------------------------
function Store:on(event, callback)
	self._events:on(event, callback)
end

function Store:_emit(event, payload)
	self._events:emit(event, payload)
end

---------------------------------------------------------------------
-- 初始化后端（不创建目录）
---------------------------------------------------------------------
function Store:_init_backend()
	local BackendFactory = require("nvim-store3.storage.backend_factory")

	-- ❗ 删除自动创建目录的逻辑
	-- local dir = vim.fn.fnamemodify(self.storage_config.path, ":h")
	-- if vim.fn.isdirectory(dir) == 0 then
	--   vim.fn.mkdir(dir, "p")
	-- end

	self._backend = BackendFactory.create(self.storage_config)
end

---------------------------------------------------------------------
-- 自动命令：退出时 flush
---------------------------------------------------------------------
function Store:_setup_autocmd()
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
function Store:_safe_key(key)
	if not self._auto_encode then
		return key
	end
	return Path.encode_key(key)
end

function Store:_unsafe_key(safe_key)
	if not self._auto_encode then
		return safe_key
	end
	return Path.decode_key(safe_key)
end

---------------------------------------------------------------------
-- CRUD API
---------------------------------------------------------------------
function Store:set(key, value)
	local safe_key = self:_safe_key(key)
	self._data[safe_key] = value
	self._backend:set(nil, safe_key, value)
	self:_emit("set", { key = key, value = value })
end

function Store:get(key)
	local safe_key = self:_safe_key(key)
	local cached = self._data[safe_key]
	if cached == NULL_MARKER then
		return nil
	elseif cached ~= nil then
		return cached
	end

	local value = self._backend:get(nil, safe_key)
	self._data[safe_key] = value or NULL_MARKER
	return value
end

function Store:delete(key)
	local safe_key = self:_safe_key(key)
	self._data[safe_key] = NULL_MARKER
	self._backend:delete(nil, safe_key)
	self:_emit("delete", { key = key })
end

function Store:batch_set(data)
	for key, value in pairs(data) do
		self:set(key, value)
	end
end

function Store:batch_get(keys)
	local result = {}
	for _, key in ipairs(keys) do
		result[key] = self:get(key)
	end
	return result
end

---------------------------------------------------------------------
-- 查询
---------------------------------------------------------------------
function Store:query(path)
	local Query = require("nvim-store3.util.query")
	local encode_func = function(part)
		return self:_safe_key(part)
	end
	return Query.get(self._data, path, encode_func)
end

---------------------------------------------------------------------
-- 键列表
---------------------------------------------------------------------
function Store:keys()
	if self._backend and self._backend.keys then
		local safe_keys = self._backend:keys(nil)
		return Path.batch_decode_keys(safe_keys)
	end
	return {}
end

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

---------------------------------------------------------------------
-- flush
---------------------------------------------------------------------
function Store:flush()
	local ok = self._backend:flush()
	self:_emit("flush", { ok = ok })
	return ok
end

---------------------------------------------------------------------
-- 统计信息
---------------------------------------------------------------------
function Store:get_stats()
	local keys = self:keys()
	local total_size = 0
	local encoded_keys = 0

	for _, key in ipairs(keys) do
		local value = self:get(key)
		if value then
			total_size = total_size + #vim.fn.json_encode(value)
		end
		local safe_key = Path.encode_key(key)
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

---------------------------------------------------------------------
-- 自动编码开关
---------------------------------------------------------------------
function Store:set_auto_encode(enabled)
	if self._auto_encode == enabled then
		return
	end
	self._data = {}
	self._auto_encode = enabled
end

function Store:get_auto_encode()
	return self._auto_encode
end

---------------------------------------------------------------------
-- 清理资源
---------------------------------------------------------------------
function Store:cleanup()
	if self._plugin_loader then
		self._plugin_loader:cleanup()
	end
	self:flush()
	self._data = {}
end

return Store
