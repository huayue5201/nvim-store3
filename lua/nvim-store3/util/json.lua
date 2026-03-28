-- lua/nvim-store3/util/json.lua
-- JSON 文件读写工具（安全 + 原子写入）

local Json = {}

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

	local ok, decoded = pcall(vim.fn.json_decode, table.concat(content, "\n"))
	if ok and type(decoded) == "table" then
		return decoded
	end

	return {}
end

---------------------------------------------------------------------
-- 安全写入 JSON 文件（原子写入）
---------------------------------------------------------------------
function Json.save(path, data)
	ensure_dir(path)

	local encoded = vim.fn.json_encode(data)
	if not encoded then
		return false
	end

	-- 使用唯一临时文件名，避免冲突
	local tmp = path .. ".tmp." .. os.time() .. "." .. math.random(10000)
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
