-- 点号路径查询工具（增强版：支持编码路径查询）

local M = {}

--- 根据点号路径查询数据
--- @param data table 数据表
--- @param path string 点号路径
--- @param encode_func function 编码函数（可选）
--- @return any 查询结果
function M.get(data, path, encode_func)
	if not path or path == "" then
		return data
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = data

	for _, part in ipairs(parts) do
		if type(current) ~= "table" then
			return nil
		end

		-- 如果提供了编码函数，则对路径部分进行编码
		local key = part
		if encode_func then
			key = encode_func(part)
		end

		current = current[key]
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
--- @param encode_func function 编码函数（可选）
--- @return boolean 是否成功
function M.set(data, path, value, encode_func)
	if not path or path == "" then
		return false
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = data

	-- 遍历到倒数第二部分
	for i = 1, #parts - 1 do
		local part = parts[i]
		local key = part

		-- 如果提供了编码函数，则对路径部分进行编码
		if encode_func then
			key = encode_func(part)
		end

		if type(current) ~= "table" then
			return false
		end

		if current[key] == nil then
			current[key] = {}
		end

		current = current[key]
	end

	-- 设置最后一个键
	local last_part = parts[#parts]
	local last_key = last_part

	if encode_func then
		last_key = encode_func(last_part)
	end

	if type(current) == "table" then
		current[last_key] = value
		return true
	end

	return false
end

--- 删除点号路径的值
--- @param data table 数据表
--- @param path string 点号路径
--- @param encode_func function 编码函数（可选）
--- @return boolean 是否成功
function M.delete(data, path, encode_func)
	if not path or path == "" then
		return false
	end

	local parts = vim.split(path, ".", { plain = true })
	local current = data

	-- 遍历到倒数第二部分
	for i = 1, #parts - 1 do
		local part = parts[i]
		local key = part

		if encode_func then
			key = encode_func(part)
		end

		if type(current) ~= "table" then
			return false
		end

		current = current[key]
		if current == nil then
			return false
		end
	end

	-- 删除最后一个键
	local last_part = parts[#parts]
	local last_key = last_part

	if encode_func then
		last_key = encode_func(last_part)
	end

	if type(current) == "table" and current[last_key] ~= nil then
		current[last_key] = nil
		return true
	end

	return false
end

--- 创建编码函数包装器
--- @param encode_func function 编码函数
--- @return function 包装后的查询函数
function M.with_encoder(encode_func)
	return function(data, path)
		return M.get(data, path, encode_func)
	end
end

return M
