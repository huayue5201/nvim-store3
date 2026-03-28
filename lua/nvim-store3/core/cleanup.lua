-- lua/nvim-store3/core/cleanup.lua
---@brief 存储清理模块（智能自动清理）

local M = {}

---@class CleanupConfig
---@field enabled boolean 是否启用自动清理，默认 true
---@field max_age_days number 项目过期天数，默认 90
---@field max_count number 最大项目数量，默认 50
---@field min_free_space_mb number 低于此空间才清理，默认 100
---@field check_interval_hours number 检查间隔（小时），默认 24

---@type CleanupConfig
local config = {
	enabled = true,
	max_age_days = 90,
	max_count = 50,
	min_free_space_mb = 100,
	check_interval_hours = 24,
}

---@type uv_timer_t|nil
local timer = nil
local cleanup_started = false

---获取磁盘剩余空间（MB）
---@return number
local function get_free_space_mb()
	local cache_dir = vim.fn.stdpath("cache")
	local ok, stat = pcall(vim.loop.fs_statvfs, cache_dir)
	if ok and stat and stat.bavail and stat.bsize then
		return (stat.bavail * stat.bsize) / 1024 / 1024
	end
	return 1024 -- 无法获取时返回较大值，不触发清理
end

---获取所有项目存储信息
---@return table[]
local function get_all_projects()
	local store_dir = vim.fn.stdpath("cache") .. "/nvim-store"
	if vim.fn.isdirectory(store_dir) == 0 then
		return {}
	end

	local projects = {}
	for _, dir in ipairs(vim.fn.glob(store_dir .. "/*", false, true)) do
		if not dir:match("global$") then
			local stat = vim.loop.fs_stat(dir)
			if stat then
				local data_file = dir .. "/data.json"
				local has_data = vim.fn.filereadable(data_file) == 1
				if has_data then
					local content = vim.fn.readfile(data_file)
					has_data = table.concat(content, "") ~= "{}"
				end

				-- 计算目录总大小
				local size = 0
				local files = vim.fn.glob(dir .. "/*", false, true)
				for _, file in ipairs(files) do
					local file_stat = vim.loop.fs_stat(file)
					if file_stat then
						size = size + (file_stat.size or 0)
					end
				end

				table.insert(projects, {
					path = dir,
					mtime = stat.mtime.sec,
					size = size,
					has_data = has_data,
				})
			end
		end
	end

	-- 按最后访问时间排序（最旧的在前）
	table.sort(projects, function(a, b)
		return a.mtime < b.mtime
	end)
	return projects
end

---清理空项目（最安全的清理）
---@param projects table[]
---@return number deleted
---@return number freed
local function cleanup_empty(projects)
	local deleted = 0
	local freed = 0
	for _, p in ipairs(projects) do
		if not p.has_data then
			vim.fn.delete(p.path, "rf")
			deleted = deleted + 1
			freed = freed + p.size
		end
	end
	return deleted, freed
end

---清理过期项目（保守策略：只清理超过 max_age_days 的）
---@param projects table[]
---@param max_age_days number
---@return number deleted
---@return number freed
local function cleanup_expired(projects, max_age_days)
	local now = os.time()
	local deleted = 0
	local freed = 0

	for _, p in ipairs(projects) do
		-- 只清理过期的，且必须有数据（空项目已经被清理）
		if p.has_data and (now - p.mtime) / 86400 > max_age_days then
			vim.fn.delete(p.path, "rf")
			deleted = deleted + 1
			freed = freed + p.size
		end
	end

	return deleted, freed
end

---限制项目数量（仅在空间不足时触发）
---@param projects table[]
---@param max_count number
---@param min_free_space_mb number
---@return number deleted
---@return number freed
local function limit_count_if_needed(projects, max_count, min_free_space_mb)
	local free_space = get_free_space_mb()

	-- 空间充足时不限制数量
	if free_space > min_free_space_mb then
		return 0, 0
	end

	local deleted = 0
	local freed = 0

	if #projects > max_count then
		-- 删除最旧的项目（包括有数据的，因为空间不足）
		for i = 1, #projects - max_count do
			vim.fn.delete(projects[i].path, "rf")
			deleted = deleted + 1
			freed = freed + projects[i].size
		end
	end

	if deleted > 0 then
		vim.notify(
			string.format(
				"磁盘空间不足，清理了 %d 个旧项目，释放 %.2f MB",
				deleted,
				freed / 1024 / 1024
			),
			vim.log.levels.WARN
		)
	end

	return deleted, freed
end

---执行智能清理
local function run_cleanup()
	local projects = get_all_projects()
	local total_deleted = 0
	local total_freed = 0
	local deleted, freed

	-- 策略1：优先清理空项目（最安全）
	deleted, freed = cleanup_empty(projects)
	total_deleted = total_deleted + deleted
	total_freed = total_freed + freed

	if deleted > 0 then
		vim.notify(
			string.format("清理了 %d 个空项目，释放 %.2f MB", deleted, freed / 1024 / 1024),
			vim.log.levels.INFO
		)
		-- 刷新项目列表
		projects = get_all_projects()
	end

	-- 策略2：清理过期项目（超过配置天数）
	deleted, freed = cleanup_expired(projects, config.max_age_days)
	total_deleted = total_deleted + deleted
	total_freed = total_freed + freed

	if deleted > 0 then
		vim.notify(
			string.format(
				"清理了 %d 个过期项目（>%d天），释放 %.2f MB",
				deleted,
				config.max_age_days,
				freed / 1024 / 1024
			),
			vim.log.levels.INFO
		)
		projects = get_all_projects()
	end

	-- 策略3：仅在磁盘空间不足时限制数量
	deleted, freed = limit_count_if_needed(projects, config.max_count, config.min_free_space_mb)
	total_deleted = total_deleted + deleted
	total_freed = total_freed + freed

	if total_deleted == 0 then
		-- 无清理时静默，不打扰用户
		return
	end

	-- 汇总通知
	if total_deleted > 0 then
		vim.notify(
			string.format(
				"存储清理完成：删除 %d 个项目，释放 %.2f MB 空间",
				total_deleted,
				total_freed / 1024 / 1024
			),
			vim.log.levels.INFO,
			{ title = "nvim-store3" }
		)
	end
end

---------------------------------------------------------------------
-- 公共 API
---------------------------------------------------------------------

---启动自动清理
function M.start()
	if not config.enabled then
		return
	end

	if timer or cleanup_started then
		return
	end

	cleanup_started = true

	-- 延迟30秒启动，避免影响启动性能
	vim.defer_fn(function()
		run_cleanup()

		local interval_ms = config.check_interval_hours * 3600 * 1000
		timer = vim.loop.new_timer()
		if timer then
			timer:start(interval_ms, interval_ms, vim.schedule_wrap(run_cleanup))
		end
	end, 30000)
end

---停止自动清理
function M.stop()
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	cleanup_started = false
end

---手动执行清理
function M.run()
	run_cleanup()
end

---获取统计信息
---@return table
function M.get_stats()
	local projects = get_all_projects()
	local total_size = 0
	local empty_count = 0
	local expired_count = 0
	local now = os.time()

	for _, p in ipairs(projects) do
		total_size = total_size + p.size
		if not p.has_data then
			empty_count = empty_count + 1
		end
		if p.has_data and (now - p.mtime) / 86400 > config.max_age_days then
			expired_count = expired_count + 1
		end
	end

	return {
		total_projects = #projects,
		empty_projects = empty_count,
		expired_projects = expired_count,
		total_size_mb = total_size / 1024 / 1024,
		free_space_mb = get_free_space_mb(),
	}
end

---配置清理模块
---@param opts CleanupConfig
function M.setup(opts)
	-- 如果已经在运行，先停止
	if timer or cleanup_started then
		M.stop()
	end

	if opts then
		config = vim.tbl_deep_extend("force", config, opts)
	end

	if config.enabled then
		M.start()
	end
end

return M
