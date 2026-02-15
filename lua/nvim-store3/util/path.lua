-- lua/nvim-store3/util/path.lua
-- 路径工具模块（透明 Base64 编码 + 懒初始化目录）

local M = {}

local ENCODED_PREFIX = "b64:"

---------------------------------------------------------------------
-- 键编码工具
---------------------------------------------------------------------
local function needs_encode(key)
	if not key or type(key) ~= "string" then
		return false
	end
	return key:match("[./\\%s:#%[%]]") ~= nil or not key:match("^[%w_%-]+$")
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
			local hash = tostring(string.byte(key, 1) or 0) .. tostring(string.byte(key, #key) or 0) .. tostring(#key)
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
		local encoded_part = hash_pos and encoded_with_hash:sub(1, hash_pos - 1) or encoded_with_hash
		local ok, decoded = pcall(vim.base64.decode, encoded_part)
		if ok and decoded then
			return decoded
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
-- 项目路径（懒初始化，不自动创建目录）
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
-- 全局路径（懒初始化，不自动创建目录）
---------------------------------------------------------------------

local function global_store_dir()
	local cache = vim.fn.stdpath("cache")
	return cache .. "/nvim-store/global"
end

function M.global_store_path()
	return global_store_dir() .. "/data.json"
end

return M
