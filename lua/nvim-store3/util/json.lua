-- lua/nvim-store/util/json.lua
-- JSON 文件读写工具（升级版：API 不变 + 更安全 + 原子写入）
--
-- 提供（与旧版完全一致）：
--   Json.load(path)
--   Json.save(path, data)
--   Json.get(path, key)
--   Json.set(path, key, value)
--   Json.delete(path, key)
--
-- 升级内容：
--   - 自动创建目录
--   - 安全 JSON 解码（不会抛错）
--   - 原子写入（避免文件损坏）
--   - 与增量写入体系兼容（store.lua / symbol_index.lua）

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

	local tmp = path .. ".tmp"
	local ok = vim.fn.writefile({ encoded }, tmp) == 0
	if not ok then
		return false
	end

	vim.fn.rename(tmp, path)
	return true
end

---------------------------------------------------------------------
-- 兼容旧 API：get(path, key)
---------------------------------------------------------------------
function Json.get(path, key)
	local data = Json.load(path)
	return data[key]
end

---------------------------------------------------------------------
-- 兼容旧 API：set(path, key, value)
---------------------------------------------------------------------
function Json.set(path, key, value)
	local data = Json.load(path)
	data[key] = value
	return Json.save(path, data)
end

---------------------------------------------------------------------
-- 兼容旧 API：delete(path, key)
---------------------------------------------------------------------
function Json.delete(path, key)
	local data = Json.load(path)
	if data[key] == nil then
		return false
	end
	data[key] = nil
	return Json.save(path, data)
end

return Json
