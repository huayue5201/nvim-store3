-- 通用缓存插件 - 核心基础设施
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
-- 创建缓存实例
---------------------------------------------------------------------
--- @param store table Store实例
--- @param config table 配置
--- @return table 缓存实例
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = {
			enabled = config.enabled ~= false,
			default_ttl = config.default_ttl or 300, -- 默认5分钟
			max_size = config.max_size or 1000,
			cleanup_interval = config.cleanup_interval or 60, -- 清理间隔（秒）
		},
		cache = {}, -- 缓存数据 {key = {value, expire_time, access_time}}
		_cleanup_timer = nil,
		_access_count = 0,
		_hit_count = 0,
	}

	setmetatable(self, { __index = M })

	-- 启动定时清理
	if self.config.enabled then
		self:_start_cleanup_timer()
	end

	return self
end

---------------------------------------------------------------------
-- 设置缓存
---------------------------------------------------------------------
--- @param key string 键名
--- @param value any 值
--- @param ttl number 过期时间（秒，可选）
function M:set(key, value, ttl)
	if not self.config.enabled then
		return
	end

	ttl = ttl or self.config.default_ttl
	local now = os.time()

	self.cache[key] = {
		value = value,
		expire_time = now + ttl,
		access_time = now,
	}

	-- 如果超过最大大小，移除最旧的
	if table_len(self.cache) > self.config.max_size then
		self:_evict_oldest()
	end
end

---------------------------------------------------------------------
-- 获取缓存
---------------------------------------------------------------------
--- @param key string 键名
--- @return any 缓存值
function M:get(key)
	self._access_count = self._access_count + 1

	if not self.config.enabled then
		return nil
	end

	local entry = self.cache[key]
	if not entry then
		return nil
	end

	local now = os.time()

	-- 检查是否过期
	if now > entry.expire_time then
		self.cache[key] = nil
		return nil
	end

	-- 更新访问时间
	entry.access_time = now
	self._hit_count = self._hit_count + 1

	return entry.value
end

---------------------------------------------------------------------
-- 删除缓存
---------------------------------------------------------------------
function M:delete(key)
	self.cache[key] = nil
end

---------------------------------------------------------------------
-- 清理所有过期缓存
---------------------------------------------------------------------
function M:cleanup_expired()
	if not self.config.enabled then
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
		self.cache[key] = nil
	end
end

---------------------------------------------------------------------
-- 获取缓存统计信息
---------------------------------------------------------------------
function M:get_stats()
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
	}
end

---------------------------------------------------------------------
-- 移除最旧的缓存（LRU策略）
---------------------------------------------------------------------
function M:_evict_oldest()
	local oldest_key = nil
	local oldest_time = math.huge -- 修复：不能用 os.time()

	for key, entry in pairs(self.cache) do
		if entry.access_time < oldest_time then
			oldest_time = entry.access_time
			oldest_key = key
		end
	end

	if oldest_key then
		self.cache[oldest_key] = nil
	end
end

---------------------------------------------------------------------
-- 启动定时清理
---------------------------------------------------------------------
function M:_start_cleanup_timer()
	if self._cleanup_timer then
		return
	end

	self._cleanup_timer = vim.fn.timer_start(self.config.cleanup_interval * 1000, function()
		vim.schedule(function()
			self:cleanup_expired()
		end)
	end, { ["repeat"] = -1 })
end

---------------------------------------------------------------------
-- 清理资源
---------------------------------------------------------------------
function M:cleanup()
	if self._cleanup_timer then
		pcall(vim.fn.timer_stop, self._cleanup_timer)
		self._cleanup_timer = nil
	end

	self.cache = {}
	self._access_count = 0
	self._hit_count = 0
end

return M
