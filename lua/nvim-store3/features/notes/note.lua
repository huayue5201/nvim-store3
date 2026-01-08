--- File: /Users/lijia/nvim-store3/lua/nvim-store3/features/notes/note.lua ---
-- lua/nvim-store3/features/notes/note.lua
-- Note 数据模型（由原 notes/note.lua 迁移）

local M = {}

--- 创建新笔记对象
--- @param id string 笔记ID
--- @param bufnr number 缓冲区编号
--- @param line number 行号
--- @param extra? table 额外数据
--- @return table 笔记对象
function M.new(id, bufnr, line, extra)
	extra = extra or {}

	local note = {
		id = id,
		bufnr = bufnr,
		line = line,
		text = extra.text or "",
		ast = extra.ast,
		symbol = extra.symbol,
		tags = extra.tags or {},
		metadata = extra.metadata or {},
		created_at = extra.created_at or os.time(),
		updated_at = extra.updated_at or os.time(),
	}

	-- 合并其他额外字段
	for k, v in pairs(extra) do
		if note[k] == nil then
			note[k] = v
		end
	end

	return note
end

--- 获取笔记行号
--- @param note table 笔记对象
--- @return number 行号
function M.get_line(note)
	return note.line
end

--- 获取笔记缓冲区
--- @param note table 笔记对象
--- @return number 缓冲区编号
function M.get_buffer(note)
	return note.bufnr
end

--- 获取笔记文本
--- @param note table 笔记对象
--- @return string 文本内容
function M.get_text(note)
	return note.text or ""
end

--- 更新笔记位置
--- @param note table 笔记对象
--- @param bufnr number 新缓冲区编号
--- @param line number 新行号
function M.update_position(note, bufnr, line)
	note.bufnr = bufnr
	note.line = line
	note.updated_at = os.time()
end

--- 更新笔记文本
--- @param note table 笔记对象
--- @param text string 新文本
function M.update_text(note, text)
	note.text = text
	note.updated_at = os.time()
end

--- 添加标签
--- @param note table 笔记对象
--- @param tag string 标签
function M.add_tag(note, tag)
	if not note.tags then
		note.tags = {}
	end

	if not vim.tbl_contains(note.tags, tag) then
		table.insert(note.tags, tag)
		note.updated_at = os.time()
	end
end

--- 移除标签
--- @param note table 笔记对象
--- @param tag string 标签
function M.remove_tag(note, tag)
	if note.tags then
		for i, t in ipairs(note.tags) do
			if t == tag then
				table.remove(note.tags, i)
				note.updated_at = os.time()
				break
			end
		end
	end
end

--- 检查是否包含标签
--- @param note table 笔记对象
--- @param tag string 标签
--- @return boolean 是否包含
function M.has_tag(note, tag)
	if not note.tags then
		return false
	end
	return vim.tbl_contains(note.tags, tag)
end

--- 序列化笔记（用于存储）
--- @param note table 笔记对象
--- @return table 序列化后的笔记
function M.serialize(note)
	return {
		id = note.id,
		bufnr = note.bufnr,
		line = note.line,
		text = note.text,
		ast = note.ast,
		symbol = note.symbol,
		tags = note.tags,
		metadata = note.metadata,
		created_at = note.created_at,
		updated_at = note.updated_at,
	}
end

--- 反序列化笔记（从存储加载）
--- @param data table 序列化数据
--- @return table 笔记对象
function M.deserialize(data)
	return M.new(data.id, data.bufnr, data.line, {
		text = data.text,
		ast = data.ast,
		symbol = data.symbol,
		tags = data.tags,
		metadata = data.metadata,
		created_at = data.created_at,
		updated_at = data.updated_at,
	})
end

--- 比较两个笔记
--- @param a table 笔记A
--- @param b table 笔记B
--- @return boolean 是否相等
function M.equals(a, b)
	if not a or not b then
		return false
	end

	return a.id == b.id and a.bufnr == b.bufnr and a.line == b.line and a.text == b.text
end

--- 获取笔记年龄（秒）
--- @param note table 笔记对象
--- @return number 年龄（秒）
function M.get_age(note)
	return os.time() - (note.created_at or os.time())
end

--- 获取更新年龄（秒）
--- @param note table 笔记对象
--- @return number 更新年龄（秒）
function M.get_update_age(note)
	return os.time() - (note.updated_at or os.time())
end

--- 获取笔记摘要（前N个字符）
--- @param note table 笔记对象
--- @param length number 摘要长度
--- @return string 摘要
function M.get_summary(note, length)
	length = length or 50

	local text = note.text or ""
	if #text <= length then
		return text
	end

	return text:sub(1, length) .. "..."
end

return M
