-- 通用缓存插件 - 核心基础设施（懒初始化版）
-- 支持：
--   - O(1) LRU 淘汰（双向链表）
--   - 分层缓存（内存 + store）
--   - 懒初始化（第一次使用时才启动）
--   - vim.loop 定时清理
--   - 与 store 事件系统联动（set/delete）
--   - API 完全不变

local M = {}

---------------------------------------------------------------------
-- 工具函数：安全计算 table 长度（适用于字典表）
---------------------------------------------------------------------
local function table_len(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

---------------------------------------------------------------------
-- 内部工具：双向链表操作（用于 O(1) LRU）
---------------------------------------------------------------------

local function lru_move_to_head(self, node)
	if self._lru_head == node then
		return
	end

	if node.prev then
		node.prev.next = node.next
	end
	if node.next then
		node.next.prev = node.prev
	end

	if self._lru_tail == node then
		self._lru_tail = node.prev
	end

	node.prev = nil
	node.next = self._lru_head

	if self._lru_head then
		self._lru_head.prev = node
	end

	self._lru_head = node

	if not self._lru_tail then
		self._lru_tail = node
	end
end

local function lru_insert_head(self, key)
	local node = {
		key = key,
		prev = nil,
		next = self._lru_head,
	}

	if self._lru_head then
		self._lru_head.prev = node
	end

	self._lru_head = node

	if not self._lru_tail then
		self._lru_tail = node
	end

	return node
end

local function lru_remove_node(self, node)
	if not node then
		return
	end

	if node.prev then
		node.prev.next = node.next
	end
	if node.next then
		node.next.prev = node.prev
	end

	if self._lru_head == node then
		self._lru_head = node.next
	end
	if self._lru_tail == node then
		self._lru_tail = node.prev
	end

	node.prev = nil
	node.next = nil
end

---------------------------------------------------------------------
-- 懒初始化核心
---------------------------------------------------------------------

--- 初始化缓存内部结构（仅第一次使用时执行）
function M:_ensure_initialized()
	if self._initialized then
		return
	end
	self._initialized = true

	-- 初始化缓存表
	self.cache = {}
	self._lru_head = nil
	self._lru_tail = nil
	self._access_count = 0
	self._hit_count = 0
	self._disposed = false

	-- 注册 store 事件（懒注册）
	if self.store and self.store.on then
		self.store:on("set", function(ev)
			if self._disposed or not self.config.enabled then
				return
			end
			if not ev or ev.key == nil then
				return
			end

			local key = ev.key
			local value = ev.value
			local now = os.time()
			local ttl = self.config.default_ttl

			local entry = self.cache[key]
			if entry then
				entry.value = value
				entry.expire_time = now + ttl
				if entry.node then
					lru_move_to_head(self, entry.node)
				end
			else
				if self.config.read_through then
					local node = lru_insert_head(self, key)
					self.cache[key] = {
						value = value,
						expire_time = now + ttl,
						node = node,
					}
					if table_len(self.cache) > self.config.max_size then
						self:_evict_oldest()
					end
				end
			end
		end)

		self.store:on("delete", function(ev)
			if self._disposed then
				return
			end
			if not ev or ev.key == nil then
				return
			end
			self:delete(ev.key)
		end)
	end

	-- 启动定时器（懒启动）
	self:_start_cleanup_timer()
end

---------------------------------------------------------------------
-- 创建缓存实例（不做任何初始化）
---------------------------------------------------------------------
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = {
			enabled = config.enabled ~= false,
			default_ttl = config.default_ttl or 300,
			max_size = config.max_size or 1000,
			cleanup_interval = config.cleanup_interval or 60,
			read_through = config.read_through ~= false,
			write_through = config.write_through ~= false,
		},

		-- 懒初始化标记
		_initialized = false,

		-- 定时器
		_cleanup_timer = nil,
	}

	return setmetatable(self, { __index = M })
end

---------------------------------------------------------------------
-- 设置缓存
---------------------------------------------------------------------
function M:set(key, value, ttl)
	if not self.config.enabled then
		if self.config.write_through and self.store and self.store.set then
			self.store:set(key, value)
		end
		return
	end

	self:_ensure_initialized()

	local now = os.time()
	ttl = ttl or self.config.default_ttl
	local expire_time = now + ttl

	if self.config.write_through and self.store and self.store.set then
		self.store:set(key, value)
	end

	local entry = self.cache[key]
	if entry then
		entry.value = value
		entry.expire_time = expire_time
		if entry.node then
			lru_move_to_head(self, entry.node)
		end
	else
		local node = lru_insert_head(self, key)
		self.cache[key] = {
			value = value,
			expire_time = expire_time,
			node = node,
		}
		if table_len(self.cache) > self.config.max_size then
			self:_evict_oldest()
		end
	end
end

---------------------------------------------------------------------
-- 获取缓存
---------------------------------------------------------------------
function M:get(key)
	self:_ensure_initialized()

	self._access_count = self._access_count + 1

	if not self.config.enabled then
		if self.config.read_through and self.store and self.store.get then
			return self.store:get(key)
		end
		return nil
	end

	local now = os.time()
	local entry = self.cache[key]

	if entry then
		if now > entry.expire_time then
			if entry.node then
				lru_remove_node(self, entry.node)
			end
			self.cache[key] = nil
			return nil
		end

		self._hit_count = self._hit_count + 1
		if entry.node then
			lru_move_to_head(self, entry.node)
		end

		return entry.value
	end

	if self.config.read_through and self.store and self.store.get then
		local value = self.store:get(key)
		if value ~= nil then
			local node = lru_insert_head(self, key)
			self.cache[key] = {
				value = value,
				expire_time = now + self.config.default_ttl,
				node = node,
			}
			if table_len(self.cache) > self.config.max_size then
				self:_evict_oldest()
			end
			return value
		end
	end

	return nil
end

---------------------------------------------------------------------
-- 删除缓存
---------------------------------------------------------------------
function M:delete(key)
	self:_ensure_initialized()

	local entry = self.cache[key]
	if not entry then
		return
	end

	if entry.node then
		lru_remove_node(self, entry.node)
	end

	self.cache[key] = nil
end

---------------------------------------------------------------------
-- 清理过期缓存
---------------------------------------------------------------------
function M:cleanup_expired()
	if not self._initialized or not self.config.enabled then
		return
	end

	local now = os.time()
	local to_remove = {}

	for key, entry in pairs(self.cache) do
		if now > entry.expire_time then
			table.insert(to_remove, key)
		end
	end

	for _, key in ipairs(to_remove) do
		local entry = self.cache[key]
		if entry and entry.node then
			lru_remove_node(self, entry.node)
		end
		self.cache[key] = nil
	end
end

---------------------------------------------------------------------
-- 统计信息
---------------------------------------------------------------------
function M:get_stats()
	if not self._initialized then
		return {
			total_entries = 0,
			expired_entries = 0,
			hit_rate = 0,
			access_count = 0,
			hit_count = 0,
			max_size = self.config.max_size,
		}
	end

	local now = os.time()
	local total = 0
	local expired = 0

	for _, entry in pairs(self.cache) do
		total = total + 1
		if now > entry.expire_time then
			expired = expired + 1
		end
	end

	local hit_rate = self._access_count > 0 and (self._hit_count / self._access_count) or 0

	return {
		total_entries = total,
		expired_entries = expired,
		hit_rate = hit_rate,
		access_count = self._access_count,
		hit_count = self._hit_count,
		max_size = self.config.max_size,
	}
end

---------------------------------------------------------------------
-- 移除最旧的缓存（LRU）
---------------------------------------------------------------------
function M:_evict_oldest()
	local tail = self._lru_tail
	if not tail then
		return
	end

	local key = tail.key
	local entry = self.cache[key]
	if entry and entry.node then
		lru_remove_node(self, entry.node)
	end

	self.cache[key] = nil
end

---------------------------------------------------------------------
-- 启动定时清理（懒启动）
---------------------------------------------------------------------
function M:_start_cleanup_timer()
	if self._cleanup_timer then
		return
	end

	if not self.config.cleanup_interval or self.config.cleanup_interval <= 0 then
		return
	end

	local uv = vim.loop
	local interval_ms = self.config.cleanup_interval * 1000

	local timer = uv.new_timer()
	self._cleanup_timer = timer

	timer:start(interval_ms, interval_ms, function()
		vim.schedule(function()
			if self._disposed then
				return
			end
			self:cleanup_expired()
		end)
	end)
end

---------------------------------------------------------------------
-- 清理资源
---------------------------------------------------------------------
function M:cleanup()
	self._disposed = true

	if self._cleanup_timer then
		pcall(function()
			self._cleanup_timer:stop()
			self._cleanup_timer:close()
		end)
		self._cleanup_timer = nil
	end

	if self._initialized then
		self.cache = {}
		self._lru_head = nil
		self._lru_tail = nil
		self._access_count = 0
		self._hit_count = 0
	end
end

return M
