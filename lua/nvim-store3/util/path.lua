-- lua/nvim-store3/util/path.lua
-- 路径工具模块（优化版：只编码危险字符）

local M = {}

local ENCODED_PREFIX = "b64:"

---------------------------------------------------------------------
-- 判断是否需要编码（优化版）
---------------------------------------------------------------------
local function needs_encode(key)
	if not key or type(key) ~= "string" then
		return false
	end

	-- 允许的字符：字母、数字、下划线、短横、点号、中文等 Unicode 字符
	-- 只对真正的文件系统危险字符编码
	-- 危险字符：/ \ : ? * " < > | （Windows/Unix 文件名非法字符）
	if key:match('[/\\:%*%?"<>|]') then
		return true
	end

	-- 控制字符需要编码
	if key:match("[%c]") then
		return true
	end

	return false
end

---------------------------------------------------------------------
-- 编码键名（优化版）
---------------------------------------------------------------------
function M.encode_key(key)
	if not key or type(key) ~= "string" or key == "" then
		return key or ""
	end

	-- 如果已经是编码格式，直接返回
	if key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX then
		return key
	end

	-- 只有真正危险的字符才编码
	if needs_encode(key) then
		local ok, encoded = pcall(vim.base64.encode, key)
		if ok and encoded then
			-- 添加简单校验，避免冲突
			local hash =
				string.format("%02x%02x%02x", string.byte(key, 1) or 0, string.byte(key, #key) or 0, #key % 256)
			return ENCODED_PREFIX .. encoded .. "_" .. hash
		end
	end

	-- 安全的键名直接返回
	return key
end

---------------------------------------------------------------------
-- 解码键名
---------------------------------------------------------------------
function M.decode_key(safe_key)
	if not safe_key or type(safe_key) ~= "string" then
		return safe_key or ""
	end

	-- 只解码带前缀的键
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

---------------------------------------------------------------------
-- 判断是否为编码键
---------------------------------------------------------------------
function M.is_encoded_key(key)
	return key and type(key) == "string" and key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX
end

---------------------------------------------------------------------
-- 批量解码
---------------------------------------------------------------------
function M.batch_decode_keys(safe_keys)
	local result = {}
	for _, safe_key in ipairs(safe_keys) do
		table.insert(result, M.decode_key(safe_key))
	end
	return result
end

---------------------------------------------------------------------
-- 项目路径（保持不变）
---------------------------------------------------------------------
function M.project_root()
	return vim.fn.getcwd()
end

local function project_key()
	local root = M.project_root()
	return root:gsub("[/\\]", "_")
end

local function project_store_dir()
	local cache = vim.fn.stdpath("cache")
	return cache .. "/nvim-store/" .. project_key()
end

function M.project_store_path()
	return project_store_dir() .. "/data.json"
end

function M.project_symbol_index_path()
	return project_store_dir() .. "/symbol_index.json"
end

---------------------------------------------------------------------
-- 全局路径
---------------------------------------------------------------------
local function global_store_dir()
	local cache = vim.fn.stdpath("cache")
	return cache .. "/nvim-store/global"
end

function M.global_store_path()
	return global_store_dir() .. "/data.json"
end

return M
