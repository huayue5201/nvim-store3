-- lua/nvim-store3/util/json.lua
-- JSON 文件读写工具（安全 + 原子写入，统一使用 vim.json）

local Json = {}

-- 临时文件计数器，确保并发写入时文件名唯一
local tmp_counter = 0

---------------------------------------------------------------------
-- 确保目录存在
---------------------------------------------------------------------
local function ensure_dir(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

---------------------------------------------------------------------
-- JSON 编解码（统一使用 vim.json，非阻塞且无废弃警告）
---------------------------------------------------------------------

---解码 JSON 字符串
---@param str string
---@return table|nil
function Json.decode(str)
	local ok, decoded = pcall(vim.json.decode, str)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

---编码为 JSON 字符串
---@param data any
---@return string|nil
function Json.encode(data)
	local ok, encoded = pcall(vim.json.encode, data)
	if ok and encoded then
		return encoded
	end
	return nil
end

---------------------------------------------------------------------
-- 安全读取 JSON 文件
---------------------------------------------------------------------
function Json.load(path)
	if vim.fn.filereadable(path) == 0 then
		return {}
	end

	local content = vim.fn.readfile(path)
	if not content or #content == 0 then
		return {}
	end

	local decoded = Json.decode(table.concat(content, "\n"))
	if decoded ~= nil then
		return decoded
	end

	return {}
end

---------------------------------------------------------------------
-- 安全写入 JSON 文件（原子写入）
---------------------------------------------------------------------
function Json.save(path, data)
	ensure_dir(path)

	local encoded = Json.encode(data)
	if not encoded then
		return false
	end

	-- 使用唯一临时文件名，避免冲突
	tmp_counter = tmp_counter + 1
	local tmp = string.format("%s.tmp.%d.%d", path, os.time(), tmp_counter)
	local ok = vim.fn.writefile({ encoded }, tmp) == 0
	if not ok then
		return false
	end

	local rename_ok = vim.fn.rename(tmp, path) == 0
	if not rename_ok then
		-- 重命名失败，清理临时文件
		pcall(vim.fn.delete, tmp)
		return false
	end

	return true
end

return Json
