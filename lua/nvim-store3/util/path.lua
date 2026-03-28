-- lua/nvim-store3/util/path.lua
local M = {}

local ENCODED_PREFIX = "b64:"

-- 项目标志
local PROJECT_MARKERS = {
	".git",
	".hg",
	".svn",
	".project",
	".idea",
	".vscode",
	"Makefile",
	"package.json",
	"Cargo.toml",
	"pyproject.toml",
	"go.mod",
	"CMakeLists.txt",
	"README.md",
}

-- 系统目录黑名单
local SYSTEM_DIRS = { "/etc", "/var", "/tmp", "/usr", "/bin", "/sbin", "/dev", "/proc" }

-- 缓存
local root_cache = {}
local cleanup_timer = nil
local cleanup_started = false

---------------------------------------------------------------------
-- 键名编码/解码
---------------------------------------------------------------------
local function needs_encode(key)
	if not key or type(key) ~= "string" then
		return false
	end
	return key:match('[/\\:%*%?"<>|]') or key:match("[%c]")
end

function M.encode_key(key)
	if not key or type(key) ~= "string" or key == "" then
		return key or ""
	end
	if key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX then
		return key
	end

	if needs_encode(key) then
		local ok, encoded = pcall(vim.base64.encode, key)
		if ok and encoded then
			local hash =
				string.format("%02x%02x%02x", string.byte(key, 1) or 0, string.byte(key, #key) or 0, #key % 256)
			return ENCODED_PREFIX .. encoded .. "_" .. hash
		end
	end
	return key
end

function M.decode_key(safe_key)
	if not safe_key or type(safe_key) ~= "string" then
		return safe_key or ""
	end

	if safe_key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX then
		local encoded_with_hash = safe_key:sub(#ENCODED_PREFIX + 1)
		local hash_pos = encoded_with_hash:find("_")
		if hash_pos then
			local encoded_part = encoded_with_hash:sub(1, hash_pos - 1)
			local ok, decoded = pcall(vim.base64.decode, encoded_part)
			if ok and decoded then
				return decoded
			end
		end
	end
	return safe_key
end

function M.is_encoded_key(key)
	return key and type(key) == "string" and key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX
end

function M.batch_decode_keys(safe_keys)
	local result = {}
	for _, safe_key in ipairs(safe_keys) do
		table.insert(result, M.decode_key(safe_key))
	end
	return result
end

---------------------------------------------------------------------
-- 项目路径
---------------------------------------------------------------------
function M.project_root()
	local cwd = vim.fn.getcwd()
	if root_cache[cwd] ~= nil then
		return root_cache[cwd]
	end

	-- 系统目录检查
	for _, sys_dir in ipairs(SYSTEM_DIRS) do
		if cwd:find(sys_dir, 1, true) == 1 then
			root_cache[cwd] = nil
			return nil
		end
	end

	-- 向上查找项目标志
	local current = cwd
	for _ = 1, 10 do
		for _, marker in ipairs(PROJECT_MARKERS) do
			local marker_path = current .. "/" .. marker
			if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
				root_cache[cwd] = current
				return current
			end
		end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break
		end
		current = parent
	end

	root_cache[cwd] = cwd
	return cwd
end

function M.clear_root_cache()
	root_cache = {}
end

local function project_key()
	local root = M.project_root()
	if not root then
		local cwd = vim.fn.getcwd()
		return "system_" .. cwd:gsub("[/\\]", "_"):gsub("^_", "")
	end
	return root:gsub("[/\\]", "_")
end

local function project_store_dir()
	return vim.fn.stdpath("cache") .. "/nvim-store/" .. project_key()
end

function M.project_store_path()
	local root = M.project_root()
	return root and project_store_dir() .. "/data.json" or nil
end

function M.project_symbol_index_path()
	local root = M.project_root()
	return root and project_store_dir() .. "/symbol_index.json" or nil
end

function M.global_store_path()
	return vim.fn.stdpath("cache") .. "/nvim-store/global/data.json"
end

---------------------------------------------------------------------
-- 清理功能（硬编码参数）
---------------------------------------------------------------------
local function get_all_projects()
	local store_dir = vim.fn.stdpath("cache") .. "/nvim-store"
	if not vim.fn.isdirectory(store_dir) then
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

				table.insert(projects, {
					path = dir,
					mtime = stat.mtime.sec,
					size = stat.size or 0,
					has_data = has_data,
				})
			end
		end
	end

	table.sort(projects, function(a, b)
		return a.mtime < b.mtime
	end)
	return projects
end

function M.cleanup_empty_stores()
	local deleted = 0
	for _, p in ipairs(get_all_projects()) do
		if not p.has_data then
			vim.fn.delete(p.path, "rf")
			deleted = deleted + 1
		end
	end
	if deleted > 0 then
		vim.notify(string.format("清理了 %d 个空项目", deleted), vim.log.levels.INFO)
	end
	return deleted
end

function M.cleanup_expired_stores()
	local max_age_days = 30
	local now = os.time()
	local deleted, freed = 0, 0

	for _, p in ipairs(get_all_projects()) do
		if (now - p.mtime) / 86400 > max_age_days then
			vim.fn.delete(p.path, "rf")
			deleted = deleted + 1
			freed = freed + p.size
		end
	end

	if deleted > 0 then
		local freed_mb = freed / 1024 / 1024
		vim.notify(
			string.format("清理了 %d 个过期项目（>%d天），释放 %.2f MB", deleted, max_age_days, freed_mb),
			vim.log.levels.INFO
		)
	end
	return { deleted = deleted, freed_space = freed }
end

function M.limit_project_count()
	local max_count = 100
	local projects = get_all_projects()
	local deleted = 0

	if #projects > max_count then
		for i = 1, #projects - max_count do
			vim.fn.delete(projects[i].path, "rf")
			deleted = deleted + 1
		end
		vim.notify(
			string.format("清理了 %d 个最旧项目（保留%d个）", deleted, max_count),
			vim.log.levels.INFO
		)
	end
	return deleted
end

function M.run_full_cleanup()
	M.cleanup_empty_stores()
	M.cleanup_expired_stores()
	M.limit_project_count()
end

function M._start_auto_cleanup()
	if cleanup_started then
		return
	end
	cleanup_started = true

	vim.defer_fn(function()
		M.run_full_cleanup()

		cleanup_timer = vim.loop.new_timer()
		cleanup_timer:start(
			7 * 24 * 3600 * 1000,
			7 * 24 * 3600 * 1000,
			vim.schedule_wrap(function()
				M.run_full_cleanup()
			end)
		)
	end, 5000)
end

function M._stop_auto_cleanup()
	if cleanup_timer then
		cleanup_timer:stop()
		cleanup_timer:close()
		cleanup_timer = nil
	end
	cleanup_started = false
end

function M.get_store_stats()
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

function M.select_and_cleanup()
	local projects = get_all_projects()

	if #projects == 0 then
		vim.notify("没有可清理的项目", vim.log.levels.INFO)
		return
	end

	local items = {}
	for _, p in ipairs(projects) do
		local size_mb = p.size / 1024 / 1024
		local age_days = math.floor((os.time() - p.mtime) / 86400)
		local status = p.has_data and "有数据" or "空"

		table.insert(items, {
			path = p.path,
			display = string.format(
				"%-40s • %6.2f MB • %3d天 • %s",
				p.path:match("([^/]+)$"),
				size_mb,
				age_days,
				status
			),
		})
	end

	vim.ui.select(items, {
		prompt = "选择要清理的项目 (Tab多选)",
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

return M
