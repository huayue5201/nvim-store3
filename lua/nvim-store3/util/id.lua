-- lua/store/core/id.lua
-- 自动生成唯一 ID 的模块
-- 用于 namespace 内部对象的唯一标识

local M = {}

--- 生成一个唯一 ID
--- 格式：ns_时间戳_随机数
---@param ns string namespace 名称
---@return string 唯一 ID
function M.generate(ns)
	local ts = tostring(os.time())
	local rnd = tostring(math.random(1000, 9999))
	return ns .. "_" .. ts .. "_" .. rnd
end

return M
