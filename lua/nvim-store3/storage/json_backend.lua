--- File: /Users/lijia/nvim-store3/lua/nvim-store3/storage/json_backend.lua
--- JSON 存储后端（精简版）

local Json = require("nvim-store3.util.json")

local JsonBackend = {}
JsonBackend.__index = JsonBackend

--- 创建 JSON 后端实例
--- @param config table 配置，必须包含 path
--- @return table JSON 后端实例
function JsonBackend.new(config)
	if not config.path then
		error("JSON backend requires 'path' in config")
	end

	return setmetatable({
		config = config,
		data = {},
		dirty = false,
		save_timer = nil,
		_loaded = false,
		_write_lock = false,
		_pending_writes = {},
	}, JsonBackend)
end

--- 加载数据
--- @return table 加载的数据
function JsonBackend:load()
	if not self._loaded then
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
		local key, value = unpack(write)
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
--- @param key string 键名
--- @return any 数据值
function JsonBackend:get(key)
	self:load()
	if key then
		return self.data[key]
	end
	return self.data
end

--- 设置数据
--- @param key string 键名
--- @param value any 数据值
--- @return boolean 是否成功
function JsonBackend:set(key, value)
	if self._write_lock then
		table.insert(self._pending_writes, { key, value })
		return true
	end

	self:load()
	self.data[key] = value
	self.dirty = true
	self:_schedule_save()
	return true
end

--- 删除数据
--- @param key string 键名
--- @return boolean 是否成功
function JsonBackend:delete(key)
	if self._write_lock then
		table.insert(self._pending_writes, { key, nil })
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
--- @return table 键列表
function JsonBackend:keys()
	self:load()
	local keys = {}
	for k, _ in pairs(self.data) do
		table.insert(keys, k)
	end
	return keys
end

--- 调度保存（带 debounce）
function JsonBackend:_schedule_save()
	if self.save_timer then
		pcall(vim.fn.timer_stop, self.save_timer)
		self.save_timer = nil
	end

	local delay = self.config.flush_delay
	if not delay or delay <= 0 then
		self:flush()
		return
	end

	local timer_id = vim.fn.timer_start(delay, function()
		vim.schedule(function()
			if self.save_timer == timer_id then
				self:flush()
				self.save_timer = nil
			end
		end)
	end)
	self.save_timer = timer_id
end

--- 强制保存（原子操作）
--- @return boolean 是否保存成功
function JsonBackend:flush()
	if not self.dirty and #self._pending_writes == 0 then
		return true
	end

	if self._write_lock then
		return false
	end

	self._write_lock = true
	local success = false
	local backup_path = self.config.path .. ".backup"

	local function save_data()
		if #self._pending_writes > 0 then
			for _, write in ipairs(self._pending_writes) do
				local key, value = unpack(write)
				if value == nil then
					self.data[key] = nil
				else
					self.data[key] = value
				end
			end
			self._pending_writes = {}
		end

		-- 备份原文件
		if vim.fn.filereadable(self.config.path) == 1 then
			local content = vim.fn.readfile(self.config.path)
			if content and #content > 0 then
				vim.fn.writefile(content, backup_path)
			end
		end

		success = Json.save(self.config.path, self.data)

		if success then
			self.dirty = false
			pcall(vim.fn.delete, backup_path)
		elseif vim.fn.filereadable(backup_path) == 1 then
			local backup_content = vim.fn.readfile(backup_path)
			vim.fn.writefile(backup_content, self.config.path)
		end
	end

	local ok, err = xpcall(save_data, debug.traceback)
	if not ok then
		vim.notify("Failed to flush JSON backend: " .. tostring(err), vim.log.levels.ERROR)
		success = false
	end

	self._write_lock = false

	if #self._pending_writes > 0 then
		self:_process_pending_writes()
	end

	return success
end

return JsonBackend
