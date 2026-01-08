-- lua/nvim-store/util/path.lua
-- 路径工具模块（项目级数据存储路径统一管理）

local M = {}

---------------------------------------------------------------------
-- 获取项目根目录
---------------------------------------------------------------------
function M.project_root()
	return vim.fn.getcwd()
end

---------------------------------------------------------------------
-- 生成项目 key（用于目录名）
---------------------------------------------------------------------
local function project_key()
	local root = M.project_root()
	return root:gsub("[/\\]", "_")
end

---------------------------------------------------------------------
-- 获取项目级存储目录
---------------------------------------------------------------------
local function project_store_dir()
	local cache = vim.fn.stdpath("cache") -- ~/.cache/nvim
	local dir = cache .. "/nvim-store/" .. project_key()
	M.ensure_dir(dir)
	return dir
end

---------------------------------------------------------------------
-- data.json 路径（项目级主数据文件）
---------------------------------------------------------------------
function M.project_store_path()
	local dir = project_store_dir()
	return dir .. "/data.json"
end

---------------------------------------------------------------------
-- symbol_index.json 路径（符号索引文件）
---------------------------------------------------------------------
function M.project_symbol_index_path()
	local dir = project_store_dir()
	return dir .. "/symbol_index.json"
end

---------------------------------------------------------------------
-- 全局存储路径（跨项目共享）
---------------------------------------------------------------------
function M.global_store_path()
	local data_dir = vim.fn.stdpath("data") -- ~/.local/share/nvim
	local dir = data_dir .. "/nvim-store"
	M.ensure_dir(dir)
	return dir .. "/global.json"
end

---------------------------------------------------------------------
-- 确保目录存在
---------------------------------------------------------------------
function M.ensure_dir(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

return M
