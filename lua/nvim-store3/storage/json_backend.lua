--- File: /Users/lijia/neovim-plugins/nvim-store3/lua/nvim-store3/storage/json_backend.lua
--- JSON 存储后端
---
--- 数据按前缀分成两个分区，落盘到两个文件：
---
---   facts.*  不可重建的真相（任务、墓碑、孤儿…）→ <dir>/data.json，带 epoch 护栏
---   cache.*  可重建的派生数据（索引、关系缓存）→ <dir>/cache.json，无护栏，
---            丢了只是变慢；删掉 cache.json 即可强制重建
---
--- 分开落盘的两个理由（都不是省 IO）：
---   1. 缓存抖动不再触发 epoch 冲突拒绝——两个 nvim 同时开同一项目时，
---      写缓存不该被当成「整库覆盖」；
---   2. 可以安全地「删 cache.json 重建」，而不会连 facts 一起删掉。

local Json = require("nvim-store3.util.json")
local async_util = require("nvim-store3.util.async")

local JsonBackend = {}
JsonBackend.__index = JsonBackend

local DEFAULT_CACHE_PREFIX = "cache."

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

--- 推导 cache 分区文件路径：与 facts 同目录，名为 cache.json
--- @param path string facts 文件路径
--- @return string
local function derive_cache_path(path)
	local dir = path:match("^(.*)/[^/]*$")
	if dir then
		return dir .. "/cache.json"
	end
	return path .. ".cache"
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
		-- facts 分区（真相）
		data = {},
		-- cache 分区（可重建）
		cache = {},
		cache_path = config.cache_path or derive_cache_path(config.path),
		cache_prefix = config.cache_prefix or DEFAULT_CACHE_PREFIX,
		dirty = false,
		dirty_cache = false,
		_save_task = nil,
		_loaded = false,
		_write_lock = false,
		_pending_writes = {},
		-- ⭐ epoch 护栏（config.epoch_guard 开启时生效，只作用于 facts 分区）
		_writer_id = new_writer_id(),
		_epoch_seen = normalize_epoch(nil),
		_conflict = false,
	}, JsonBackend)
end

--- 键属于哪个分区
--- @param key string
--- @return string "cache" | "facts"
function JsonBackend:partition(key)
	if type(key) == "string" and key:sub(1, #self.cache_prefix) == self.cache_prefix then
		return "cache"
	end
	return "facts"
end

--- 加载数据（v2 包装格式）
--- @return table 合并后的数据视图
function JsonBackend:load()
	if self._loaded then
		return self:_merged()
	end

	local raw = Json.load(self.config.path)
	if type(raw) == "table" and raw.version == self.version and type(raw.data) == "table" then
		self.data = raw.data
	else
		self.data = {}
	end
	-- 记录加载时看到的 epoch，作为后续冲突判定的基线
	self._epoch_seen = normalize_epoch(type(raw) == "table" and raw.epoch or nil)

	-- cache 分区：优先读独立文件；老版本把缓存混在 data.json 里，这里一次性搬过去
	local cache_raw = Json.load(self.cache_path)
	if type(cache_raw) == "table" and type(cache_raw.data) == "table" then
		self.cache = cache_raw.data
	end

	local migrated = false
	for key, value in pairs(self.data) do
		if self:partition(key) == "cache" then
			if self.cache[key] == nil then
				self.cache[key] = value
			end
			self.data[key] = nil
			migrated = true
		end
	end
	if migrated then
		self.dirty = true -- 让 facts 文件把搬走的键真正删掉
		self.dirty_cache = true
	end

	self._loaded = true
	return self:_merged()
end

--- 合并视图（facts ∪ cache）；对外 API 看到的仍是「一个键空间」
--- @return table
function JsonBackend:_merged()
	local merged = {}
	for key, value in pairs(self.data) do
		merged[key] = value
	end
	for key, value in pairs(self.cache) do
		merged[key] = value
	end
	return merged
end

--- 读、写分区的取值/赋值
--- @param partition string
--- @return table
function JsonBackend:_bucket(partition)
	if partition == "cache" then
		return self.cache
	end
	return self.data
end

--- 标记分区为脏
--- @param partition string
function JsonBackend:_mark_dirty(partition)
	if partition == "cache" then
		self.dirty_cache = true
	else
		self.dirty = true
	end
end

---------------------------------------------------------------------
-- epoch 护栏：防止陈旧实例整库覆盖较新的存储（只针对 facts 分区）
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
	local raw = Json.load(self.config.path)
	local disk = normalize_epoch(type(raw) == "table" and raw.epoch or nil)
	local seen = self._epoch_seen or normalize_epoch(nil)
	return (disk.n or 0) > (seen.n or 0) and disk.writer ~= nil and disk.writer ~= self._writer_id
end

--- 处理 epoch 冲突：保留双方快照并拒绝覆盖
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
		local partition = self:partition(key)
		local bucket = self:_bucket(partition)
		if value == nil then
			bucket[key] = nil
		else
			bucket[key] = value
		end
		self:_mark_dirty(partition)
	end

	self:_schedule_save()
end

--- 获取数据
--- @param key string|nil 键名（nil 返回合并视图）
--- @return any 数据值
function JsonBackend:get(key)
	self:load()
	if key == nil then
		return self:_merged()
	end
	local partition = self:partition(key)
	if partition == "cache" then
		return self.cache[key]
	end
	return self.data[key]
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
	local partition = self:partition(key)
	self:_bucket(partition)[key] = value
	self:_mark_dirty(partition)
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
	local partition = self:partition(key)
	local bucket = self:_bucket(partition)
	if bucket[key] == nil then
		return false
	end
	bucket[key] = nil
	self:_mark_dirty(partition)
	self:_schedule_save()
	return true
end

--- 获取所有键（facts ∪ cache）
--- @return table 键列表
function JsonBackend:keys()
	self:load()
	local keys = {}
	for key in pairs(self.data) do
		table.insert(keys, key)
	end
	for key in pairs(self.cache) do
		table.insert(keys, key)
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

--- 只要还有任一分区是脏的就需要落盘
--- @return boolean
function JsonBackend:is_dirty()
	return self.dirty or self.dirty_cache or #self._pending_writes > 0
end

--- 写 facts 分区（带 epoch 护栏与备份）
--- @return boolean
function JsonBackend:_flush_facts()
	local backup_path = self.config.path .. ".backup"

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

	local success = Json.save(self.config.path, payload)

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

	return success
end

--- 写 cache 分区（无 epoch 护栏：缓存可重建，冲突时后写者胜）
--- @return boolean
function JsonBackend:_flush_cache()
	local ok = Json.save(self.cache_path, { version = self.version, data = self.cache })
	if ok then
		self.dirty_cache = false
	else
		vim.notify("nvim-store3: 缓存分区写入失败（不影响数据）", vim.log.levels.WARN, { title = "nvim-store3" })
	end
	return ok
end

--- 强制保存（原子操作）
--- @return boolean 是否保存成功（facts 分区的结果）
function JsonBackend:flush()
	if not self:is_dirty() then
		return true
	end

	if self._write_lock then
		return false
	end

	self._write_lock = true
	local facts_ok = true
	local cache_ok = true

	local function save_all()
		if #self._pending_writes > 0 then
			local pending = self._pending_writes
			self._pending_writes = {}
			for _, write in ipairs(pending) do
				local key, value = unpack(write)
				local partition = self:partition(key)
				local bucket = self:_bucket(partition)
				if value == nil then
					bucket[key] = nil
				else
					bucket[key] = value
				end
				self:_mark_dirty(partition)
			end
		end

		if self.dirty then
			-- ⭐ epoch 护栏：磁盘被其他写入者改写时拒绝覆盖
			if self:_epoch_conflict() then
				if not self._conflict then
					self:_handle_epoch_conflict()
				end
				facts_ok = false
			else
				facts_ok = self:_flush_facts()
			end
		end

		if self.dirty_cache then
			cache_ok = self:_flush_cache()
		end
	end

	local ok, err = xpcall(save_all, debug.traceback)
	if not ok then
		vim.notify("Failed to flush JSON backend: " .. tostring(err), vim.log.levels.ERROR)
		facts_ok = false
	end

	self._write_lock = false

	if #self._pending_writes > 0 then
		self:_process_pending_writes()
	end

	return facts_ok and cache_ok
end

return JsonBackend
