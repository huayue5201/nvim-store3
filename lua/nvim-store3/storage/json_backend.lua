--- File: /Users/lijia/nvim-store3/lua/nvim-store3/storage/json_backend.lua
--- JSON 存储后端（精简版）

local Json = require("nvim-store3.util.json")
local async_util = require("nvim-store3.util.async")

local JsonBackend = {}
JsonBackend.__index = JsonBackend

--- 生成本写入者的唯一标识（进程内唯一；用于 epoch 归属判定）
--- @return string
local function new_writer_id()
	local pid = 0
	pcall(function()
		pid = vim.fn.getpid()
	end)
	return string.format("%d-%d-%d", pid, os.time(), math.random(1, 1000000000))
end

--- 归一化 epoch（容忍缺失/旧格式）
--- @param e any
--- @return table { n: number, writer: string|nil }
local function normalize_epoch(e)
	if type(e) ~= "table" then
		return { n = 0, writer = nil }
	end
	return { n = tonumber(e.n) or 0, writer = e.writer }
end

--- 创建 JSON 后端实例
--- @param config table 配置，必须包含 path
--- @return table JSON 后端实例
function JsonBackend.new(config)
	if not config.path then
		error("JSON backend requires 'path' in config")
	end

	return setmetatable({
		config = config,
		version = config.version or 2,
		data = {},
		dirty = false,
		_save_task = nil,
		_loaded = false,
		_write_lock = false,
		_pending_writes = {},
		-- ⭐ epoch 护栏（config.epoch_guard 开启时生效）
		_writer_id = new_writer_id(),
		_epoch_seen = normalize_epoch(nil),
		_conflict = false,
	}, JsonBackend)
end

--- 加载数据（v2 包装格式）
--- @return table 加载的数据
function JsonBackend:load()
	if not self._loaded then
		local raw = Json.load(self.config.path)
		if type(raw) == "table" and raw.version == self.version and type(raw.data) == "table" then
			self.data = raw.data
		else
			self.data = {}
		end
		-- 记录加载时看到的 epoch，作为后续冲突判定的基线
		self._epoch_seen = normalize_epoch(type(raw) == "table" and raw.epoch or nil)
		self._loaded = true
	end
	return self.data
end

---------------------------------------------------------------------
-- epoch 护栏：防止陈旧实例整库覆盖较新的存储
---------------------------------------------------------------------
--- 检测磁盘 epoch 是否已被其他写入者改写
--- @return boolean
function JsonBackend:_epoch_conflict()
	if not self.config.epoch_guard then
		return false
	end
	if self._conflict then
		return true
	end
	if vim.fn.filereadable(self.config.path) ~= 1 then
		return false
	end
	local raw = Json.load(self.config.path)
	local disk = normalize_epoch(type(raw) == "table" and raw.epoch or nil)
	local seen = self._epoch_seen or normalize_epoch(nil)
	return disk.n ~= seen.n or disk.writer ~= seen.writer
end

--- 处理外部覆盖：保留双方数据、拒绝写入、通知用户（只做一次）
function JsonBackend:_handle_epoch_conflict()
	self._conflict = true
	local ts = os.date("%Y%m%d-%H%M%S")
	local external_backup = string.format("%s.conflict-%s", self.config.path, ts)
	local local_backup = string.format("%s.conflict-local-%s", self.config.path, ts)

	-- 保留磁盘上的外部版本
	if vim.fn.filereadable(self.config.path) == 1 then
		pcall(function()
			vim.fn.writefile(vim.fn.readfile(self.config.path), external_backup)
		end)
	end
	-- 保留本进程待写入的快照
	pcall(Json.save, local_backup, { version = self.version, epoch = self._epoch_seen, data = self.data })

	vim.notify(
		string.format(
			"nvim-store3: 检测到存储被外部覆盖，已拒绝写入以防数据丢失。\n磁盘版本: %s\n本地快照: %s",
			external_backup,
			local_backup
		),
		vim.log.levels.ERROR,
		{ title = "nvim-store3" }
	)
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
	local delay = self.config.flush_delay
	if not delay or delay <= 0 then
		self:flush()
		return
	end

	-- 防抖：取消上一轮，delay 毫秒后落盘
	async_util.debounce(self, "_save_task", delay, function()
		self:flush()
	end)
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

	-- ⭐ epoch 护栏：磁盘被其他写入者改写时拒绝覆盖
	if self:_epoch_conflict() then
		if not self._conflict then
			self:_handle_epoch_conflict()
		end
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

		local payload = { version = self.version, data = self.data }
		if self.config.epoch_guard then
			local seen = self._epoch_seen or normalize_epoch(nil)
			payload.epoch = { n = (seen.n or 0) + 1, writer = self._writer_id }
		end

		success = Json.save(self.config.path, payload)

		if success then
			if self.config.epoch_guard then
				self._epoch_seen = payload.epoch
			end
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
