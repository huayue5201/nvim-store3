-- lua/nvim-store3/features/buffer_cache/manager.lua
-- Buffer Cache 功能管理器（由原 core/buffer_cache.lua 迁移）

local M = {}

--- 创建 Buffer Cache 管理器
--- @param store table Store 实例
--- @param config table 配置
--- @return table Buffer Cache 管理器
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = {
			enabled = config.enabled ~= false,
			max_cache_size = config.max_cache_size or 100,
			ttl = config.ttl or 300, -- 秒
		},
		caches = {}, -- bufnr -> {data = {}, created_at = timestamp}
		global_cache = {
			data = {},
			created_at = os.time(),
		},
		_cleanup_timer = nil,
	}

	setmetatable(self, { __index = M })

	-- 启动定期清理
	self:_start_cleanup_timer()

	return self
end

--- 获取或创建缓冲区缓存
--- @param bufnr number 缓冲区编号
--- @return table 缓存数据
function M:_get_or_create_cache(bufnr)
	if not self.config.enabled then
		return { data = {} }
	end

	if not self.caches[bufnr] then
		self.caches[bufnr] = {
			data = {},
			created_at = os.time(),
		}
	end

	return self.caches[bufnr]
end

--- 获取缓冲区缓存数据
--- @param bufnr number 缓冲区编号
--- @param key? string 键名
--- @return any 缓存数据
function M:get(bufnr, key)
	if not self.config.enabled then
		return nil
	end

	local cache = self.caches[bufnr]
	if not cache then
		return nil
	end

	if key then
		return cache.data[key]
	else
		return cache.data
	end
end

--- 设置缓冲区缓存数据
--- @param bufnr number 缓冲区编号
--- @param key string 键名
--- @param value any 数据值
function M:set(bufnr, key, value)
	if not self.config.enabled then
		return
	end

	local cache = self:_get_or_create_cache(bufnr)
	cache.data[key] = value
	cache.created_at = os.time()
end

--- 删除缓冲区缓存数据
--- @param bufnr number 缓冲区编号
--- @param key string 键名
function M:delete(bufnr, key)
	if not self.config.enabled then
		return
	end

	local cache = self.caches[bufnr]
	if cache and cache.data[key] then
		cache.data[key] = nil
	end
end

--- 检查缓冲区缓存中是否有指定键
--- @param bufnr number 缓冲区编号
--- @param key string 键名
--- @return boolean 是否存在
function M:has(bufnr, key)
	if not self.config.enabled then
		return false
	end

	local cache = self.caches[bufnr]
	return cache and cache.data[key] ~= nil
end

--- 获取或创建缓冲区缓存（兼容原buffer_store接口）
--- @param bufnr number 缓冲区编号
--- @return table 缓存对象
function M:get_or_create(bufnr)
	local cache = self:_get_or_create_cache(bufnr)

	-- 返回兼容接口的对象
	local wrapper = {
		data = cache.data,
	}

	function wrapper:get(key)
		return self.data[key]
	end

	function wrapper:set(key, value)
		self.data[key] = value
	end

	function wrapper:delete(key)
		self.data[key] = nil
	end

	return wrapper
end

----------------------------------------------------------------------
-- 过期清理逻辑（按 TTL）
----------------------------------------------------------------------

--- 清理过期的缓存（按 TTL）
function M:_cleanup_expired()
	if not self.config.enabled then
		return
	end

	local now = os.time()
	local to_remove = {}

	-- 清理缓冲区缓存
	for bufnr, cache in pairs(self.caches) do
		if now - cache.created_at > self.config.ttl then
			table.insert(to_remove, bufnr)
		end
	end

	for _, bufnr in ipairs(to_remove) do
		self.caches[bufnr] = nil
	end

	-- 清理全局缓存
	if now - self.global_cache.created_at > self.config.ttl then
		self.global_cache.data = {}
		self.global_cache.created_at = now
	end
end

--- 启动清理定时器（周期性执行 _cleanup_expired）
function M:_start_cleanup_timer()
	if self._cleanup_timer or not self.config.enabled then
		return
	end

	local interval = math.min(self.config.ttl * 1000, 60000) -- 最多1分钟检查一次

	self._cleanup_timer = vim.fn.timer_start(interval, function()
		-- 在安全的调度上下文中执行 Lua 回调
		vim.schedule(function()
			-- 定时执行过期清理
			if self.config.enabled then
				self:_cleanup_expired()
			end
		end)
	end)
end

--- 清除指定缓冲区的所有缓存
--- @param bufnr number 缓冲区编号
function M:clear(bufnr)
	self.caches[bufnr] = nil
end

--- 清除所有缓存
function M:clear_all()
	self.caches = {}
	self.global_cache.data = {}
	self.global_cache.created_at = os.time()
end

--- 获取所有缓存的缓冲区编号
--- @return number[] 缓冲区编号列表
function M:get_buffers()
	local buffers = {}
	for bufnr, _ in pairs(self.caches) do
		table.insert(buffers, bufnr)
	end
	return buffers
end

----------------------------------------------------------------------
-- 全局缓存功能
----------------------------------------------------------------------

--- 设置全局缓存
--- @param key string 键名
--- @param value any 数据值
function M:set_global(key, value)
	if self.config.enabled then
		self.global_cache.data[key] = value
		self.global_cache.created_at = os.time()
	end
end

--- 获取全局缓存
--- @param key string 键名
--- @return any 数据值
function M:get_global(key)
	if self.config.enabled then
		return self.global_cache.data[key]
	end
	return nil
end

--- 删除全局缓存
--- @param key string 键名
function M:delete_global(key)
	if self.config.enabled then
		self.global_cache.data[key] = nil
	end
end

--- 检查全局缓存是否存在
--- @param key string 键名
--- @return boolean 是否存在
function M:has_global(key)
	if self.config.enabled then
		return self.global_cache.data[key] ~= nil
	end
	return false
end

----------------------------------------------------------------------
-- 资源清理
----------------------------------------------------------------------

--- 清理资源（停止定时器 + 清空缓存）
function M:cleanup()
	-- 停止定时器
	if self._cleanup_timer then
		pcall(vim.fn.timer_stop, self._cleanup_timer)
		self._cleanup_timer = nil
	end

	-- 清理所有缓存
	self:clear_all()
end

return M
