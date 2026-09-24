-- lua/nvim-store3/core/meta.lua
---@brief 项目元数据管理（meta.json）

local Json = require("nvim-store3.util.json")

local M = {}

---读取项目元数据
---@param meta_path string
---@return table
function M.load(meta_path)
	if not meta_path then
		return {}
	end
	return Json.load(meta_path)
end

---更新访问时间（项目存储被打开时调用）
---首次访问时初始化 root 与 created_at
---@param meta_path string
---@param root string|nil
function M.touch_access(meta_path, root)
	if not meta_path then
		return
	end

	local meta = Json.load(meta_path)
	if not meta.root and root then
		meta.root = root
		meta.created_at = os.time()
	end
	meta.accessed_at = os.time()
	Json.save(meta_path, meta)
end

---更新写入时间（flush 成功后调用）
---@param meta_path string
function M.touch_update(meta_path)
	if not meta_path then
		return
	end

	local meta = Json.load(meta_path)
	if not meta.root then
		return
	end
	meta.updated_at = os.time()
	Json.save(meta_path, meta)
end

return M
