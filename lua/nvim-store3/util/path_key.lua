-- lua/nvim-store/util/path_key.lua
-- 路径编码模块（将真实文件路径转换为安全 key）
--
-- 设计目标：
--   - 可靠性第一：路径中可能包含 / \ . 空格 中文 emoji 特殊符号
--   - 必须 100% 安全，不会破坏 dot-path 查询
--   - 必须可逆（decode 后能恢复原始路径）
--   - 必须跨平台（Windows / Linux / macOS）
--   - 必须无冲突（Base64 是稳定编码）
--
-- 使用方式（外部插件永远不直接调用）：
--   local key = PathKey.encode(path)
--   local path = PathKey.decode(key)
--
-- 由 nvim-store 底层统一处理，外部插件只传入真实路径。

local M = {}

---------------------------------------------------------------------
-- Base64 编码表
---------------------------------------------------------------------
local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

---------------------------------------------------------------------
-- Base64 encode（纯 Lua 实现）
---------------------------------------------------------------------
function M.encode(data)
	return (
		(data:gsub(".", function(x)
			local r, byte = "", x:byte()
			for i = 8, 1, -1 do
				r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0")
			end
			return r
		end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
			if #x < 6 then
				return ""
			end
			local c = 0
			for i = 1, 6 do
				c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
			end
			return b:sub(c + 1, c + 1)
		end) .. ({ "", "==", "=" })[#data % 3 + 1]
	)
end

---------------------------------------------------------------------
-- Base64 decode（纯 Lua 实现）
---------------------------------------------------------------------
function M.decode(data)
	data = data:gsub("[^" .. b .. "=]", "")
	return (
		data:gsub(".", function(x)
			if x == "=" then
				return ""
			end
			local r, byte = "", (b:find(x) - 1)
			for i = 6, 1, -1 do
				r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0")
			end
			return r
		end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
			if #x ~= 8 then
				return ""
			end
			local c = 0
			for i = 1, 8 do
				c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
			end
			return string.char(c)
		end)
	)
end

return M
