-- lua/nvim-store3/util/path.lua
---@brief 路径工具模块（纯工具函数，无业务逻辑）

local M = {}

local ENCODED_PREFIX = "b64:"

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

---------------------------------------------------------------------
-- 键名编码/解码
---------------------------------------------------------------------

local function needs_encode(key)
	if not key or type(key) ~= "string" then
		return false
	end
	return key:match('[/\\:%*%?"<>|]') or key:match("[%c]")
end

---编码键名
---@param key string
---@return string
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

---解码键名
---@param safe_key string
---@return string
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

---判断是否为编码键名
---@param key string
---@return boolean
function M.is_encoded_key(key)
	return key and type(key) == "string" and key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX
end

---批量解码键名
---@param safe_keys string[]
---@return string[]
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

---获取项目存储键名
---@return string
function M.project_key()
	local root = M.project_root()
	if not root then
		local cwd = vim.fn.getcwd()
		return "system_" .. cwd:gsub("[/\\]", "_"):gsub("^_", "")
	end
	return root:gsub("[/\\]", "_")
end

---获取项目存储目录
---@return string
function M.project_store_dir()
	return vim.fn.stdpath("cache") .. "/nvim-store/" .. M.project_key()
end

---获取项目存储文件路径
---@return string|nil
function M.project_store_path()
	local root = M.project_root()
	return root and M.project_store_dir() .. "/data.json" or nil
end

---获取全局存储文件路径
---@return string
function M.global_store_path()
	return vim.fn.stdpath("cache") .. "/nvim-store/global/data.json"
end

return M
