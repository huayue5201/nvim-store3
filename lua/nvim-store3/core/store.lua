--- File: /Users/lijia/nvim-store3/lua/nvim-store3/core/store.lua
--- 核心存储模块

local PluginLoader = require("nvim-store3.core.plugin_loader")
local Event = require("nvim-store3.util.event")
local Meta = require("nvim-store3.core.meta")

local Store = {}
Store.__index = Store

-- 使用表作为哨兵值，避免与用户存储的字符串 "__null__" 冲突
local NULL_MARKER = {}

---------------------------------------------------------------------
-- 创建 Store 实例
---------------------------------------------------------------------
--- 创建新的存储实例
--- @param config table 配置
--- @param config.scope string 作用域（global/project）
--- @param config.storage table 存储配置
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
		_events = Event.new(),
		_noop = not has_valid_path, -- 路径无效时为空操作
		_meta_path = config.storage.meta_path,
		_root = config.storage.root,
	}

	setmetatable(self, Store)

	-- 只有有效路径才初始化后端
	if has_valid_path then
		self:_init_backend()
		self._plugin_loader = PluginLoader.new(self, config)
		self._plugin_loader:load_plugins()
		self:_setup_autocmd()
		self:_touch_access()
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

--- 记录项目访问时间（项目存储被打开即视为一次访问）
function Store:_touch_access()
	if self.scope == "project" and self._meta_path then
		Meta.touch_access(self._meta_path, self._root)
	end
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

	self._data[key] = value
	self._backend:set(key, value)
	self:_emit("set", { key = key, value = value })
end

--- 获取键值
--- @param key string 键名
--- @return any 值
function Store:get(key)
	if self._noop then
		return nil
	end

	local cached = self._data[key]

	if cached == NULL_MARKER then
		return nil
	elseif cached ~= nil then
		return cached
	end

	local value = self._backend:get(key)
	if value == nil then
		self._data[key] = NULL_MARKER
	else
		self._data[key] = value
	end
	return value
end

--- 删除键值
--- @param key string 键名
function Store:delete(key)
	if self._noop then
		return
	end

	self._data[key] = nil
	self._backend:delete(key)
	self:_emit("delete", { key = key })
end

--- 获取所有键
--- @return table 键名列表
function Store:keys()
	if self._noop then
		return {}
	end

	if self._backend and self._backend.keys then
		return self._backend:keys()
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

	if ok then
		Meta.touch_update(self._meta_path)
	end

	return ok
end

--- 获取存储统计信息（优化版：只从缓存读取，不触发后端）
--- @return table 统计信息
function Store:get_stats()
	if self._noop then
		return {
			total_keys = 0,
			cache_size = 0,
			estimated_size = 0,
			scope = self.scope,
			noop = true,
		}
	end

	local keys = self:keys()
	local total_size = 0

	-- 只从缓存读取，避免触发后端 IO
	for _, key in ipairs(keys) do
		local value = self._data[key]
		if value and value ~= NULL_MARKER then
			local ok, json = pcall(vim.json.encode, value)
			if ok and json then
				total_size = total_size + #json
			end
		end
	end

	return {
		total_keys = #keys,
		cache_size = vim.tbl_count(self._data),
		estimated_size = total_size,
		scope = self.scope,
		noop = false,
	}
end

--- 路径查询（支持嵌套访问）
--- 语义：优先按完整扁平键精确匹配（如 "notes.today.1"）；
---       未命中时再按点号逐段下钻嵌套表（如 "config.editor.theme"）。
--- @param path string 路径，如 "notes.today.1"
--- @return any 查询结果
function Store:query(path)
	if self._noop then
		return nil
	end

	if not path or path == "" then
		return nil
	end

	-- 1) 先按完整键精确匹配扁平键（如 "notes.today.1"）
	local direct = self:get(path)
	if direct ~= nil then
		return direct
	end

	-- 2) 否则按路径逐段下钻（支持嵌套表，如 "config.editor.theme"）
	local parts = vim.split(path, ".", { plain = true })
	if #parts < 2 then
		return nil
	end

	local current = self:get(parts[1])
	if type(current) ~= "table" then
		return nil
	end

	for i = 2, #parts do
		current = current[parts[i]]
		if current == nil then
			return nil
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
