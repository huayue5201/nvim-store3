-- lua/nvim-store3/core/cleanup.lua
-- 存储清理模块（独立职责）

local M = {}

local default_config = {
	max_age_days = 30, -- 最大保留天数
	max_count = 100, -- 最大项目数量
	auto_cleanup = true, -- 自动清理
	cleanup_interval = 7, -- 清理间隔（天）
}

local config = nil
local cleanup_timer = nil

---------------------------------------------------------------------
-- 获取所有项目存储
---------------------------------------------------------------------
local function get_all_projects()
	local cache = vim.fn.stdpath("cache")
	local store_dir = cache .. "/nvim-store"

	if not vim.fn.isdirectory(store_dir) then
		return {}
	end

	local projects = {}
	local dirs = vim.fn.glob(store_dir .. "/*", false, true)

	for _, dir in ipairs(dirs) do
		-- 跳过全局存储
		if not dir:match("global$") then
			local stat = vim.loop.fs_stat(dir)
			if stat then
				local data_file = dir .. "/data.json"
				local has_data = vim.fn.filereadable(data_file) == 1

				-- 计算目录大小
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
					name = vim.fn.fnamemodify(dir, ":t"),
					last_access = stat.mtime.sec,
					size = size,
					has_data = has_data,
				})
			end
		end
	end

	table.sort(projects, function(a, b)
		return a.last_access < b.last_access
	end)

	return projects
end

---------------------------------------------------------------------
-- 清理空项目
---------------------------------------------------------------------
function M.cleanup_empty()
	local projects = get_all_projects()
	local deleted = 0

	for _, project in ipairs(projects) do
		if not project.has_data then
			vim.fn.delete(project.path, "rf")
			deleted = deleted + 1
		end
	end

	if deleted > 0 then
		vim.notify(string.format("清理了 %d 个空项目存储", deleted), vim.log.levels.INFO)
	end

	return deleted
end

---------------------------------------------------------------------
-- 清理过期项目
---------------------------------------------------------------------
function M.cleanup_expired(max_age_days)
	max_age_days = max_age_days or (config and config.max_age_days or 30)
	local now = os.time()
	local projects = get_all_projects()
	local deleted = 0
	local freed_space = 0

	for _, project in ipairs(projects) do
		local age_days = (now - project.last_access) / 86400
		if age_days > max_age_days then
			vim.fn.delete(project.path, "rf")
			deleted = deleted + 1
			freed_space = freed_space + project.size
		end
	end

	if deleted > 0 then
		local freed_mb = freed_space / 1024 / 1024
		vim.notify(
			string.format(
				"清理了 %d 个过期项目（超过 %d 天），释放 %.2f MB 空间",
				deleted,
				max_age_days,
				freed_mb
			),
			vim.log.levels.INFO
		)
	end

	return { deleted = deleted, freed_space = freed_space }
end

---------------------------------------------------------------------
-- 限制项目数量
---------------------------------------------------------------------
function M.limit_count(max_count)
	max_count = max_count or (config and config.max_count or 100)
	local projects = get_all_projects()
	local deleted = 0

	if #projects > max_count then
		local to_delete = #projects - max_count

		for i = 1, to_delete do
			vim.fn.delete(projects[i].path, "rf")
			deleted = deleted + 1
		end

		vim.notify(
			string.format("清理了 %d 个最旧的项目（超出 %d 限制）", deleted, max_count),
			vim.log.levels.INFO
		)
	end

	return deleted
end

---------------------------------------------------------------------
-- 交互式选择清理
---------------------------------------------------------------------
function M.select_and_cleanup()
	local projects = get_all_projects()

	if #projects == 0 then
		vim.notify("没有可清理的项目存储", vim.log.levels.INFO)
		return
	end

	local items = {}
	for _, p in ipairs(projects) do
		local size_mb = p.size / 1024 / 1024
		local age_days = math.floor((os.time() - p.last_access) / 86400)
		local status = p.has_data and "有数据" or "空"

		table.insert(items, {
			path = p.path,
			display = string.format("%-40s • %6.2f MB • %3d天 • %s", p.name, size_mb, age_days, status),
		})
	end

	vim.ui.select(items, {
		prompt = "选择要清理的项目存储 (Tab多选)",
		format_item = function(item)
			return item.display
		end,
		multi = true,
	}, function(choices)
		if not choices or #choices == 0 then
			return
		end

		local deleted = 0
		local freed_space = 0

		for _, choice in ipairs(choices) do
			local size = 0
			local files = vim.fn.glob(choice.path .. "/*", false, true)
			for _, file in ipairs(files) do
				local stat = vim.loop.fs_stat(file)
				if stat then
					size = size + (stat.size or 0)
				end
			end

			vim.fn.delete(choice.path, "rf")
			deleted = deleted + 1
			freed_space = freed_space + size
		end

		local freed_mb = freed_space / 1024 / 1024
		vim.notify(
			string.format("已删除 %d 个项目，释放 %.2f MB 空间", deleted, freed_mb),
			vim.log.levels.INFO
		)
	end)
end

---------------------------------------------------------------------
-- 获取统计信息
---------------------------------------------------------------------
function M.get_stats()
	local projects = get_all_projects()
	local total_size = 0
	local empty_count = 0

	for _, p in ipairs(projects) do
		total_size = total_size + p.size
		if not p.has_data then
			empty_count = empty_count + 1
		end
	end

	return {
		total_projects = #projects,
		empty_projects = empty_count,
		total_size_bytes = total_size,
		total_size_mb = total_size / 1024 / 1024,
		avg_size_mb = #projects > 0 and (total_size / 1024 / 1024) / #projects or 0,
	}
end

---------------------------------------------------------------------
-- 启动自动清理
---------------------------------------------------------------------
function M.start_auto_cleanup()
	if cleanup_timer then
		return
	end

	local interval_ms = (config and config.cleanup_interval or 7) * 24 * 3600 * 1000

	cleanup_timer = vim.loop.new_timer()
	cleanup_timer:start(
		interval_ms,
		interval_ms,
		vim.schedule_wrap(function()
			M.cleanup_empty()
			M.cleanup_expired()
			M.limit_count()
		end)
	)
end

---------------------------------------------------------------------
-- 停止自动清理
---------------------------------------------------------------------
function M.stop_auto_cleanup()
	if cleanup_timer then
		cleanup_timer:stop()
		cleanup_timer:close()
		cleanup_timer = nil
	end
end

---------------------------------------------------------------------
-- 初始化
---------------------------------------------------------------------
function M.setup(opts)
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	if config.auto_cleanup then
		M.start_auto_cleanup()
	end
end

return M
