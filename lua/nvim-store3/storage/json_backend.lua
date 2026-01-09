-- lua/nvim-store3/storage/json_backend.lua
-- JSON 存储后端（修复版）

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
		_write_lock = false,
		_pending_writes = {}, -- 待处理的写入队列
	}

	return setmetatable(self, JsonBackend)
end

--- 验证配置
local function validate_config(config)
	if not config.path then
		error("JSON backend requires 'path' in config")
	end
	if config.flush_delay and type(config.flush_delay) ~= "number" then
		error("flush_delay must be a number")
	end
end

--- 加载数据
function JsonBackend:load()
	if not self._loaded then
		validate_config(self.config)
		self.data = Json.load(self.config.path) or {}
		self._loaded = true
	end
	return self.data
end

--- 处理待处理的写入
function JsonBackend:_process_pending_writes()
	if #self._pending_writes == 0 then
		return
	end

	local pending = self._pending_writes
	self._pending_writes = {}

	for _, write in ipairs(pending) do
		local namespace, key, value = unpack(write)
		if value == nil then
			self.data[key] = nil
		else
			self.data[key] = value
		end
	end

	self.dirty = true
	self:_schedule_save()
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
	-- 检查写锁
	if self._write_lock then
		-- 添加到待处理队列
		table.insert(self._pending_writes, { namespace, key, value })
		return true
	end

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
	-- 检查写锁
	if self._write_lock then
		-- 添加到待处理队列
		table.insert(self._pending_writes, { namespace, key, nil })
		return true
	end

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

	-- 创建局部变量捕获当前定时器ID
	local timer_id = vim.fn.timer_start(self.config.flush_delay, function()
		vim.schedule(function()
			-- 只处理当前活动的定时器
			if self.save_timer == timer_id then
				self:flush()
				self.save_timer = nil
			end
		end)
	end)

	self.save_timer = timer_id
end

--- 强制保存（原子操作）
function JsonBackend:flush()
	if not self.dirty and #self._pending_writes == 0 then
		return true
	end

	-- 加锁避免并发写入
	if self._write_lock then
		return false
	end

	self._write_lock = true

	local success = false
	local backup_path = self.config.path .. ".backup"

	-- 使用 xpcall 替代 try-catch（因为 Lua 没有内置 try）
	local function save_data()
		-- 处理所有待处理的写入
		if #self._pending_writes > 0 then
			for _, write in ipairs(self._pending_writes) do
				local namespace, key, value = unpack(write)
				if value == nil then
					self.data[key] = nil
				else
					self.data[key] = value
				end
			end
			self._pending_writes = {}
		end

		-- 先备份原文件
		if vim.fn.filereadable(self.config.path) == 1 then
			local content = vim.fn.readfile(self.config.path)
			if content and #content > 0 then
				vim.fn.writefile(content, backup_path)
			end
		end

		-- 保存新数据
		success = Json.save(self.config.path, self.data)

		if success then
			self.dirty = false
			-- 删除备份
			pcall(vim.fn.delete, backup_path)
		else
			-- 恢复备份
			if vim.fn.filereadable(backup_path) == 1 then
				local backup_content = vim.fn.readfile(backup_path)
				vim.fn.writefile(backup_content, self.config.path)
			end
		end
	end

	local ok, err = xpcall(save_data, debug.traceback)

	if not ok then
		vim.notify("Failed to flush JSON backend: " .. tostring(err), vim.log.levels.ERROR)
		success = false
	end

	-- 解锁
	self._write_lock = false

	-- 如果解锁后有待处理的写入，处理它们
	if #self._pending_writes > 0 then
		self:_process_pending_writes()
	end

	return success
end

--- 创建数据备份
--- @param backup_path string 备份路径
function JsonBackend:create_backup(backup_path)
	self:load()
	return Json.save(backup_path, self.data)
end

--- 从备份恢复
--- @param backup_path string 备份路径
function JsonBackend:restore_from_backup(backup_path)
	local backup_data = Json.load(backup_path)
	if not backup_data or type(backup_data) ~= "table" then
		return false, "Invalid backup file"
	end

	self.data = backup_data
	self.dirty = true
	self:_schedule_save()
	return true
end

return JsonBackend
