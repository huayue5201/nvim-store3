--- File: /Users/lijia/nvim-store3/lua/nvim-store3/util/query.lua ---
-- lua/nvim-store3/util/query.lua
-- 点号路径查询工具

local M = {}

--- 根据点号路径查询数据
--- @param data table 数据表
--- @param path string 点号路径
--- @return any 查询结果
function M.get(data, path)
	if not path or path == "" then
		return data
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = data

	for _, part in ipairs(parts) do
		if type(current) ~= "table" then
			return nil
		end
		current = current[part]
		if current == nil then
			return nil
		end
	end

	return current
end

--- 设置点号路径的值
--- @param data table 数据表
--- @param path string 点号路径
--- @param value any 值
--- @return boolean 是否成功
function M.set(data, path, value)
	if not path or path == "" then
		return false
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = data

	-- 遍历到倒数第二部分
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(current) ~= "table" then
			return false
		end
		if current[key] == nil then
			current[key] = {}
		end
		current = current[key]
	end

	-- 设置最后一个键
	local last_key = parts[#parts]
	if type(current) == "table" then
		current[last_key] = value
		return true
	end

	return false
end

--- 删除点号路径的值
--- @param data table 数据表
--- @param path string 点号路径
--- @return boolean 是否成功
function M.delete(data, path)
	if not path or path == "" then
		return false
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = data

	-- 遍历到倒数第二部分
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(current) ~= "table" then
			return false
		end
		current = current[key]
		if current == nil then
			return false
		end
	end

	-- 删除最后一个键
	local last_key = parts[#parts]
	if type(current) == "table" and current[last_key] ~= nil then
		current[last_key] = nil
		return true
	end

	return false
end

return M
