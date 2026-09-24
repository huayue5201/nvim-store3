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

---存储根目录
---@return string
function M.store_root()
	return vim.fn.stdpath("cache") .. "/nvim-store"
end

---------------------------------------------------------------------
-- 项目路径
---------------------------------------------------------------------

---获取项目根目录
---@return string|nil
function M.project_root()
	local cwd = vim.fn.getcwd()
	if root_cache[cwd] ~= nil then
		return root_cache[cwd]
	end

	for _, sys_dir in ipairs(SYSTEM_DIRS) do
		if cwd:find(sys_dir, 1, true) == 1 then
			root_cache[cwd] = nil
			return nil
		end
	end

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

---清空缓存
function M.clear_root_cache()
	root_cache = {}
end

---获取项目存储键名（项目根路径的哈希，避免冲突与超长目录名）
---@return string
function M.project_key()
	local root = M.project_root()
	if not root then
		return "system_" .. M.hash_path(vim.fn.getcwd())
	end
	return M.hash_path(root)
end

---获取项目存储目录
---@return string
function M.project_store_dir()
	return M.store_root() .. "/projects/" .. M.project_key()
end

---获取项目存储文件路径
---@return string|nil
function M.project_store_path()
	local root = M.project_root()
	return root and M.project_store_dir() .. "/data.json" or nil
end

---获取项目元数据文件路径
---@return string|nil
function M.project_meta_path()
	local root = M.project_root()
	return root and M.project_store_dir() .. "/meta.json" or nil
end

---获取全局存储文件路径
---@return string
function M.global_store_path()
	return M.store_root() .. "/global/data.json"
end

return M
