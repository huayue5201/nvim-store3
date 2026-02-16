-- nvim-store3/features/basic_cache.lua
-- 基础缓存插件（带安全补丁）

local M = {}

---------------------------------------------------------------------
-- 内部：key 安全层（过滤 nil / vim.NIL / 非字符串）
---------------------------------------------------------------------
local function normalize_key(key)
	if key == nil or key == vim.NIL then
		return nil
	end
	if type(key) ~= "string" then
		return nil
	end
	if key == "" then
		return nil
	end
	return key
end

---------------------------------------------------------------------
-- 创建缓存实例
---------------------------------------------------------------------
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		enabled = config.enabled ~= false,
		default_ttl = config.default_ttl or 300,
		write_through = config.write_through ~= false,
		read_through = config.read_through ~= false,

		_cache = {},
		_expire = {},
		_lru = {},
		_lru_tail = nil,
		_timer = nil,
		_destroyed = false, -- ⭐ 新增：防止 timer 在 cleanup 后继续执行
	}

	setmetatable(self, { __index = M })

	if self.enabled then
		self:_start_cleanup_timer()
	end

	return self
end

---------------------------------------------------------------------
-- 内部：LRU 操作
---------------------------------------------------------------------
function M:_lru_move_to_head(key)
	local node = self._lru[key]
	if not node then
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
end

function M:_lru_insert_head(key)
	local node = { key = key, prev = nil, next = self._lru_head }
	self._lru[key] = node

	if self._lru_head then
		self._lru_head.prev = node
	end

	self._lru_head = node

	if not self._lru_tail then
		self._lru_tail = node
	end
end

function M:_lru_remove_tail()
	local tail = self._lru_tail
	if not tail then
		return nil
	end

	local key = tail.key
	self._lru_tail = tail.prev

	if self._lru_tail then
		self._lru_tail.next = nil
	end

	self._lru[key] = nil
	return key
end

---------------------------------------------------------------------
-- 内部：定时清理（带安全保护）
---------------------------------------------------------------------
function M:_start_cleanup_timer()
	if self._timer then
		return
	end

	self._timer = vim.loop.new_timer()
	self._timer:start(
		60000, -- 每 60 秒清理一次
		60000,
		vim.schedule_wrap(function()
			if self._destroyed then
				return
			end
			self:cleanup_expired()
		end)
	)
end

---------------------------------------------------------------------
-- 设置缓存（带 key 安全层）
---------------------------------------------------------------------
function M:set(key, value, ttl)
	if not self.enabled then
		if self.write_through then
			self.store:set(key, value)
		end
		return
	end

	key = normalize_key(key) -- ⭐ 安全层
	if not key then
		return
	end

	local expire_at = os.time() + (ttl or self.default_ttl)

	self._cache[key] = value
	self._expire[key] = expire_at

	if self._lru[key] then
		self:_lru_move_to_head(key)
	else
		self:_lru_insert_head(key)
	end

	if self.write_through then
		self.store:set(key, value)
	end
end

---------------------------------------------------------------------
-- 获取缓存（带 key 安全层）
---------------------------------------------------------------------
function M:get(key)
	if not self.enabled then
		if self.read_through then
			return self.store:get(key)
		end
		return nil
	end

	key = normalize_key(key) -- ⭐ 安全层
	if not key then
		return nil
	end

	local value = self._cache[key]
	if value ~= nil then
		self:_lru_move_to_head(key)
		return value
	end

	if self.read_through then
		local v = self.store:get(key)
		if v ~= nil then
			self:set(key, v)
		end
		return v
	end

	return nil
end

---------------------------------------------------------------------
-- 删除缓存（带 key 安全层）
---------------------------------------------------------------------
function M:delete(key)
	key = normalize_key(key) -- ⭐ 安全层
	if not key then
		return
	end

	self._cache[key] = nil
	self._expire[key] = nil
	self._lru[key] = nil

	if self.write_through then
		self.store:delete(key)
	end
end

---------------------------------------------------------------------
-- 清理过期缓存（带安全保护）
---------------------------------------------------------------------
function M:cleanup_expired()
	if not self.enabled then
		return
	end

	local now = os.time()

	for key, expire_at in pairs(self._expire) do
		if expire_at <= now then
			self._cache[key] = nil
			self._expire[key] = nil
			self._lru[key] = nil
		end
	end
end

---------------------------------------------------------------------
-- 获取统计信息
---------------------------------------------------------------------
function M:get_stats()
	return {
		enabled = self.enabled,
		size = vim.tbl_count(self._cache),
	}
end

---------------------------------------------------------------------
-- 清理资源（带 timer 安全关闭）
---------------------------------------------------------------------
function M:cleanup()
	self._destroyed = true -- ⭐ 防止 timer 回调继续执行

	if self._timer then
		self._timer:stop()
		self._timer:close()
		self._timer = nil
	end

	self._cache = {}
	self._expire = {}
	self._lru = {}
	self._lru_head = nil
	self._lru_tail = nil
end

return M
