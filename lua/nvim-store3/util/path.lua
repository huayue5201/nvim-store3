-- 路径工具模块（增强版：集成透明化的Base64编码）

local M = {}

-- 编码标识前缀，用于识别已编码的键
local ENCODED_PREFIX = "b64:"

--- 判断键名是否需要编码
--- @param key string 原始键名
--- @return boolean 是否需要编码
local function needs_encode(key)
	if not key or type(key) ~= "string" then
		return false
	end

	-- 需要编码的情况：
	-- 1. 包含点号（用于查询语法）
	-- 2. 包含路径分隔符
	-- 3. 包含空格或其他特殊字符
	-- 4. 非ASCII字符（中文字符等）
	return key:match("[./\\%s:#%[%]]") ~= nil or not key:match("^[%w_%-]+$")
end

--- 将原始键名编码为存储安全的字符串
--- @param key string 原始键名
--- @return string 安全的存储键
function M.encode_key(key)
	if not key or type(key) ~= "string" or key == "" then
		return key or ""
	end

	-- 检查是否已经是编码后的键
	if key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX then
		-- 已经是编码格式，直接返回
		return key
	end

	if needs_encode(key) then
		-- 使用Neovim内置API进行编码，并添加前缀
		local ok, encoded = pcall(vim.base64.encode, key)
		if ok and encoded then
			-- 添加短哈希避免编码冲突
			local hash = tostring(string.byte(key, 1) or 0) .. tostring(string.byte(key, #key) or 0) .. tostring(#key)
			return ENCODED_PREFIX .. encoded .. "_" .. hash
		end
	end

	-- 不需要编码或编码失败，返回原键
	return key
end

--- 将存储键解码回原始键名
--- @param safe_key string 安全的存储键
--- @return string 原始键名
function M.decode_key(safe_key)
	if not safe_key or type(safe_key) ~= "string" then
		return safe_key or ""
	end

	-- 检查是否有编码前缀
	if safe_key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX then
		-- 移除前缀和哈希部分
		local encoded_with_hash = safe_key:sub(#ENCODED_PREFIX + 1)
		-- 查找哈希分隔符
		local hash_pos = encoded_with_hash:find("_")
		local encoded_part

		if hash_pos then
			encoded_part = encoded_with_hash:sub(1, hash_pos - 1)
		else
			encoded_part = encoded_with_hash
		end

		local ok, decoded = pcall(vim.base64.decode, encoded_part)
		if ok and decoded then
			return decoded
		end
		-- 解码失败，fallback返回原值
	end

	-- 没有编码前缀或解码失败，直接返回
	return safe_key
end

--- 检查键是否为编码后的键
--- @param key string 待检查的键
--- @return boolean 是否为编码键
function M.is_encoded_key(key)
	return key and type(key) == "string" and key:sub(1, #ENCODED_PREFIX) == ENCODED_PREFIX
end

--- 批量编码键
--- @param keys table 原始键列表
--- @return table 编码后的键列表
function M.batch_encode_keys(keys)
	local result = {}
	for _, key in ipairs(keys) do
		table.insert(result, M.encode_key(key))
	end
	return result
end

--- 批量解码键
--- @param safe_keys table 编码后的键列表
--- @return table 原始键列表
function M.batch_decode_keys(safe_keys)
	local result = {}
	for _, safe_key in ipairs(safe_keys) do
		table.insert(result, M.decode_key(safe_key))
	end
	return result
end

---------------------------------------------------------------------
-- 原有功能保持不变
---------------------------------------------------------------------

--- 获取项目根目录
function M.project_root()
	return vim.fn.getcwd()
end

--- 生成项目key（用于目录名）
local function project_key()
	local root = M.project_root()
	return root:gsub("[/\\]", "_")
end

--- 获取项目级存储目录
local function project_store_dir()
	local cache = vim.fn.stdpath("cache") -- ~/.cache/nvim
	local dir = cache .. "/nvim-store/" .. project_key()
	M.ensure_dir(dir)
	return dir
end

--- data.json 路径（项目级主数据文件）
function M.project_store_path()
	local dir = project_store_dir()
	return dir .. "/data.json"
end

--- symbol_index.json 路径（符号索引文件）
function M.project_symbol_index_path()
	local dir = project_store_dir()
	return dir .. "/symbol_index.json"
end

--- 全局存储路径（跨项目共享）
function M.global_store_path()
	local data_dir = vim.fn.stdpath("data") -- ~/.local/share/nvim
	local dir = data_dir .. "/nvim-store"
	M.ensure_dir(dir)
	return dir .. "/global.json"
end

--- 确保目录存在
function M.ensure_dir(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

return M
