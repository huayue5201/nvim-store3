-- lua/nvim-store3/storage/json_backend.lua
-- JSON 存储后端（简化版）

local Json = require("nvim-store3.util.json")

local JsonBackend = {}
JsonBackend.__index = JsonBackend

function JsonBackend.new(config)
	local self = {
		config = config,
		data = {},
		dirty = false,
		save_timer = nil,
		_loaded = false,
	}

	return setmetatable(self, JsonBackend)
end

--- 加载数据
function JsonBackend:load()
	if not self._loaded then
		self.data = Json.load(self.config.path) or {}
		self._loaded = true
	end
	return self.data
end

--- 获取数据
--- @param namespace? string 命名空间（暂时不使用）
--- @param key? string 键名
function JsonBackend:get(namespace, key)
	self:load()

	if key then
		return self.data[key]
	else
		return self.data
	end
end

--- 设置数据
--- @param namespace? string 命名空间（暂时不使用）
--- @param key string 键名
--- @param value any 数据值
function JsonBackend:set(namespace, key, value)
	self:load()

	self.data[key] = value
	self.dirty = true
	self:_schedule_save()

	return true
end

--- 删除数据
--- @param namespace? string 命名空间（暂时不使用）
--- @param key string 键名
function JsonBackend:delete(namespace, key)
	self:load()

	if self.data[key] == nil then
		return false
	end

	self.data[key] = nil
	self.dirty = true
	self:_schedule_save()

	return true
end

--- 获取所有键
--- @param namespace? string 命名空间
function JsonBackend:keys(namespace)
	self:load()

	local keys = {}
	for k, _ in pairs(self.data) do
		table.insert(keys, k)
	end
	return keys
end

--- 调度保存（带 debounce）
function JsonBackend:_schedule_save()
	-- 如果已有定时器，先停止
	if self.save_timer then
		pcall(vim.fn.timer_stop, self.save_timer)
		self.save_timer = nil
	end

	-- 没有配置 flush_delay 或 <= 0，则立即保存
	if not self.config.flush_delay or self.config.flush_delay <= 0 then
		self:flush()
		return
	end

	-- 使用 timer_start，而不是 defer_fn，这样可以被 timer_stop 取消
	self.save_timer = vim.fn.timer_start(self.config.flush_delay, function()
		-- 在安全的调度上下文中执行
		vim.schedule(function()
			self:flush()
			-- 一次性定时器，执行后清理引用
			self.save_timer = nil
		end)
	end)
end

--- 强制保存
function JsonBackend:flush()
	if not self.dirty then
		return true
	end

	local success = Json.save(self.config.path, self.data)
	if success then
		self.dirty = false
	end

	return success
end

return JsonBackend
