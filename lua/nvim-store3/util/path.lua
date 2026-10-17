-- lua/nvim-store3/util/path.lua
---@brief 路径工具模块（纯工具函数，无业务逻辑）

local M = {}

---项目标志列表
---@type string[]
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

---系统目录黑名单
---@type string[]
local SYSTEM_DIRS = { "/etc", "/var", "/tmp", "/usr", "/bin", "/sbin", "/dev", "/proc" }

---项目根目录缓存
---@type table<string, string|nil>
local root_cache = {}

---哈希长度（目录名使用 SHA-256 前 16 位十六进制）
local HASH_LEN = 16

---------------------------------------------------------------------
-- 路径哈希
---------------------------------------------------------------------

---回退哈希（djb2），仅当 sha256 不可用时使用
---@param str string
---@return string
local function fallback_hash(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + str:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

---计算路径的稳定哈希
---@param path string
---@return string
function M.hash_path(path)
	local ok, hash = pcall(vim.fn.sha256, path)
	if ok and type(hash) == "string" and hash ~= "" then
		return hash:sub(1, HASH_LEN)
	end
	return fallback_hash(path)
end

---旧版存储根目录（历史版本曾误用 stdpath("cache")，重启/清理后可能丢数据）
---@return string
function M.legacy_store_root()
	return vim.fn.stdpath("cache") .. "/nvim-store"
end

-- 是否已执行过旧路径迁移
local migrated = false

---一次性迁移：把旧 cache 目录下的存储搬到持久化的 data 目录
---@return nil
function M.migrate_legacy_store()
	local old = M.legacy_store_root()
	local new = vim.fn.stdpath("data") .. "/nvim-store"

	-- 新目录已存在，或旧目录不存在：无需迁移
	if vim.fn.isdirectory(new) == 1 or vim.fn.isdirectory(old) == 0 then
		return
	end

	vim.fn.mkdir(vim.fn.fnamemodify(new, ":h"), "p")
	if vim.fn.rename(old, new) == 0 then
		vim.notify("nvim-store3: 存储已迁移到 " .. new, vim.log.levels.INFO, { title = "nvim-store3" })
	else
		vim.notify(
			"nvim-store3: 旧存储迁移失败，请手动移动 " .. old .. " -> " .. new,
			vim.log.levels.WARN,
			{ title = "nvim-store3" }
		)
	end
end

---存储根目录（使用持久化的 stdpath("data")，不可放入 cache）
---@return string
function M.store_root()
	if not migrated then
		migrated = true
		M.migrate_legacy_store()
	end
	return vim.fn.stdpath("data") .. "/nvim-store"
end

---------------------------------------------------------------------
-- 项目路径
---------------------------------------------------------------------

---起始目录缓存（避免热路径反复做文件系统解析）
---@type table<string, string>
local start_dir_cache = {}

---规范化项目解析的起始目录（支持传入文件或目录路径）
---@param from string|nil
---@return string
local function start_dir(from)
	-- 没有 from 时必须按「当前」cwd 解析：cwd 会随 :tcd / 会话恢复变化，
	-- 不能把首次结果按 "" 缓存（否则所有项目共用启动目录的 store）。
	local explicit = from ~= nil and from ~= ""
	if explicit then
		local cached = start_dir_cache[from]
		if cached ~= nil then
			return cached
		end
	end

	local path
	if not explicit then
		path = vim.fn.getcwd()
	else
		path = vim.fn.fnamemodify(from, ":p")
		if vim.fn.isdirectory(path) ~= 1 then
			path = vim.fn.fnamemodify(path, ":h")
		end
	end

	-- 解析软链（如 macOS 的 /var -> /private/var），并去掉结尾分隔符，
	-- 保证「文件路径 / 目录路径 / getcwd() / buffer 名」解析到同一个项目
	path = vim.fn.resolve(path)
	path = path:gsub("[/\\]+$", "")
	if path == "" then
		path = "/"
	end

	if explicit then
		start_dir_cache[from] = path
	end
	return path
end

---获取项目根目录
---@param from string|nil 起始路径（文件或目录）；缺省用当前工作目录
---@return string|nil
function M.project_root(from)
	local start = start_dir(from)
	if root_cache[start] ~= nil then
		return root_cache[start]
	end

	for _, sys_dir in ipairs(SYSTEM_DIRS) do
		if start:find(sys_dir, 1, true) == 1 then
			root_cache[start] = nil
			return nil
		end
	end

	local current = start
	for _ = 1, 10 do
		for _, marker in ipairs(PROJECT_MARKERS) do
			local marker_path = current .. "/" .. marker
			if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
				root_cache[start] = current
				return current
			end
		end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break
		end
		current = parent
	end

	root_cache[start] = start
	return start
end

---清空缓存
function M.clear_root_cache()
	root_cache = {}
	start_dir_cache = {}
end

---获取项目存储键名（项目根路径的哈希，避免冲突与超长目录名）
---@param from string|nil 起始路径（文件或目录）；缺省用当前工作目录
---@return string
function M.project_key(from)
	local root = M.project_root(from)
	if not root then
		return "system_" .. M.hash_path(start_dir(from))
	end
	return M.hash_path(root)
end

---获取项目存储目录
---@param from string|nil
---@return string
function M.project_store_dir(from)
	return M.store_root() .. "/projects/" .. M.project_key(from)
end

---获取项目存储文件路径
---@param from string|nil
---@param name string|nil 命名 store（缺省/"default" → data.json，其余 → <name>.json）
---@return string|nil
function M.project_store_path(from, name)
	local root = M.project_root(from)
	if not root then
		return nil
	end
	local dir = M.project_store_dir(from)
	if name and name ~= "" and name ~= "default" then
		return dir .. "/" .. name .. ".json"
	end
	return dir .. "/data.json"
end

---获取项目元数据文件路径
---@param from string|nil
---@param name string|nil 命名 store（缺省/"default" → meta.json，其余 → meta.<name>.json）
---@return string|nil
function M.project_meta_path(from, name)
	local root = M.project_root(from)
	if not root then
		return nil
	end
	local dir = M.project_store_dir(from)
	if name and name ~= "" and name ~= "default" then
		return dir .. "/meta." .. name .. ".json"
	end
	return dir .. "/meta.json"
end

---获取全局存储文件路径
---@return string
function M.global_store_path()
	return M.store_root() .. "/global/data.json"
end

return M
