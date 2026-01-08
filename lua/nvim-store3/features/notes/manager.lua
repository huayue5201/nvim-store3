-- lua/nvim-store3/features/notes/manager.lua
-- Notes 功能管理器（由原 notes/manager.lua 迁移并重构）

local Note = require("nvim-store3.features.notes.note")
local ID = require("nvim-store3.util.id")
local PathKey = require("nvim-store3.util.path_key")
local Event = require("nvim-store3.util.event")

local NotesManager = {}
NotesManager.__index = NotesManager

--- 创建 Notes 管理器
--- @param store table Store 实例
--- @param config table 配置
--- @return NotesManager
function NotesManager.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = config,
		events = Event.new(),
		_initialized = false,
	}

	setmetatable(self, NotesManager)

	-- 延迟初始化子管理器
	self:_lazy_init()

	return self
end

--- 延迟初始化子管理器
function NotesManager:_lazy_init()
	if self._initialized then
		return
	end

	-- 动态加载子模块
	self.jump = require("nvim-store3.features.notes.jump_manager").new(self.store, self)
	self.migration = require("nvim-store3.features.notes.migration_manager").new(self.store, self)

	-- 设置自动命令（如果需要）
	if self.config.auto_setup then
		self.migration:setup_autocmd()
		self.jump:setup_commands()
	end

	self._initialized = true
end

--- 确保已初始化
function NotesManager:ensure_init()
	self:_lazy_init()
end

----------------------------------------------------------------------
-- 核心笔记 CRUD
----------------------------------------------------------------------

--- 创建新笔记
--- @param bufnr number 缓冲区编号
--- @param line number 行号
--- @param extra? table 额外数据
--- @return string 笔记ID
function NotesManager:create(bufnr, line, extra)
	extra = extra or {}

	local note_id = ID.generate("note")

	local note = {
		id = note_id,
		bufnr = bufnr,
		line = line,
		text = extra.text or "",
		created_at = os.time(),
		updated_at = os.time(),
	}

	-- 合并额外数据
	for k, v in pairs(extra) do
		if note[k] == nil then
			note[k] = v
		end
	end

	-- 存储笔记（扁平 key：notes.<id>）
	self.store:set("notes." .. note_id, note)

	-- 触发事件
	self.events:emit("note_created", {
		id = note_id,
		note = note,
		bufnr = bufnr,
		line = line,
	})

	return note_id
end

--- 获取笔记
--- @param id string 笔记ID
--- @return table|nil 笔记数据
function NotesManager:get(id)
	return self.store:get("notes." .. id)
end

--- 删除笔记
--- @param id string 笔记ID
--- @return boolean 是否成功
function NotesManager:delete(id)
	local note = self:get(id)
	if not note then
		return false
	end

	-- 从存储中删除
	self.store:delete("notes." .. id)

	-- 触发事件
	self.events:emit("note_deleted", {
		id = id,
		note = note,
	})

	return true
end

--- 更新笔记
--- @param id string 笔记ID
--- @param updates table 更新数据
--- @return boolean 是否成功
function NotesManager:update(id, updates)
	local note = self:get(id)
	if not note then
		return false
	end

	-- 更新字段
	for k, v in pairs(updates) do
		note[k] = v
	end

	note.updated_at = os.time()

	-- 保存回存储
	self.store:set("notes." .. id, note)

	-- 触发事件
	self.events:emit("note_updated", {
		id = id,
		note = note,
		updates = updates,
	})

	return true
end

----------------------------------------------------------------------
-- 特定字段更新方法
----------------------------------------------------------------------

--- 更新笔记文本
--- @param id string 笔记ID
--- @param new_text string 新文本
--- @return boolean 是否成功
function NotesManager:update_text(id, new_text)
	return self:update(id, { text = new_text })
end

--- 更新笔记行号
--- @param id string 笔记ID
--- @param new_line number 新行号
--- @return boolean 是否成功
function NotesManager:update_line(id, new_line)
	return self:update(id, { line = new_line })
end

--- 移动笔记到新位置
--- @param id string 笔记ID
--- @param new_bufnr number 新缓冲区编号
--- @param new_line number 新行号
--- @return boolean 是否成功
function NotesManager:move(id, new_bufnr, new_line)
	return self:update(id, {
		bufnr = new_bufnr,
		line = new_line,
	})
end

--- 更新笔记 AST 信息
--- @param id string 笔记ID
--- @param opts table AST 选项
--- @return boolean 是否成功
function NotesManager:update_ast(id, opts)
	return self:update(id, { ast = opts })
end

--- 更新笔记符号信息
--- @param id string 笔记ID
--- @param opts table 符号选项
--- @return boolean 是否成功
function NotesManager:update_symbol(id, opts)
	return self:update(id, { symbol = opts })
end

--- 重命名笔记（更新文本）
--- @param id string 笔记ID
--- @param new_text string 新文本
--- @return boolean 是否成功
function NotesManager:rename(id, new_text)
	return self:update_text(id, new_text)
end

----------------------------------------------------------------------
-- 查询方法
----------------------------------------------------------------------

--- 根据位置查找笔记
--- @param bufnr number 缓冲区编号
--- @param line number 行号
--- @return table|nil 笔记数据
function NotesManager:find_by_position(bufnr, line)
	local all_notes = self:get_all()

	for _, note in pairs(all_notes) do
		if note.bufnr == bufnr and note.line == line then
			return note
		end
	end

	return nil
end

--- 删除指定位置的笔记
--- @param bufnr number 缓冲区编号
--- @param line number 行号
--- @return boolean 是否成功
function NotesManager:delete_at(bufnr, line)
	local note = self:find_by_position(bufnr, line)
	if note then
		return self:delete(note.id)
	end
	return false
end

--- 获取所有笔记
--- @return table 所有笔记（id -> note）
function NotesManager:get_all()
	-- 由于底层存储使用扁平 key（notes.<id>），这里通过 keys() 扫描并重建表
	local result = {}
	if not self.store.keys then
		return result
	end

	local keys = self.store:keys()
	for _, key in ipairs(keys) do
		if vim.startswith(key, "notes.") then
			local id = key:sub(#"notes." + 1)
			local note = self.store:get(key)
			if note then
				result[id] = note
			end
		end
	end

	return result
end

--- 获取缓冲区中的所有笔记
--- @param bufnr number 缓冲区编号
--- @return table 笔记列表
function NotesManager:get_by_buffer(bufnr)
	local result = {}
	local all_notes = self:get_all()

	for _, note in pairs(all_notes) do
		if note.bufnr == bufnr then
			table.insert(result, note)
		end
	end

	-- 按行号排序
	table.sort(result, function(a, b)
		return a.line < b.line
	end)

	return result
end

--- 搜索笔记
--- @param query string 搜索查询
--- @return table 匹配的笔记列表
function NotesManager:search(query)
	local result = {}
	local all_notes = self:get_all()

	for _, note in pairs(all_notes) do
		if note.text and string.find(note.text:lower(), query:lower()) then
			table.insert(result, note)
		end
	end

	return result
end

----------------------------------------------------------------------
-- 符号和 AST 相关
----------------------------------------------------------------------

--- 重建符号索引
--- @return boolean 是否成功
function NotesManager:rebuild_symbol_index()
	self:ensure_init()
	return self.migration:rebuild_symbol_index()
end

--- 跳转到定义
--- @param id string 笔记ID
--- @return boolean 是否成功跳转
function NotesManager:goto_definition(id)
	self:ensure_init()
	return self.jump:jump_to_definition(id)
end

--- 获取笔记行号
--- @param id string 笔记ID
--- @return number|nil 行号
function NotesManager:get_line(id)
	local note = self:get(id)
	if note then
		return Note.get_line(note)
	end
	return nil
end

----------------------------------------------------------------------
-- 事件系统
----------------------------------------------------------------------

--- 注册事件监听器
--- @param event string 事件名称
--- @param callback function 回调函数
function NotesManager:on(event, callback)
	self.events:on(event, callback)
end

--- 触发事件
--- @param event string 事件名称
--- @param payload table 事件负载
function NotesManager:emit(event, payload)
	self.events:emit(event, payload)
end

----------------------------------------------------------------------
-- 清理和配置
----------------------------------------------------------------------

--- 清理资源
function NotesManager:cleanup()
	-- 保存所有未保存的更改
	self.store:flush()

	-- 清理子管理器
	if self.jump and self.jump.cleanup then
		self.jump:cleanup()
	end

	if self.migration and self.migration.cleanup then
		self.migration:cleanup()
	end

	-- 重置状态
	self._initialized = false
	self.jump = nil
	self.migration = nil
end

--- 重新加载配置
--- @param new_config table 新配置
function NotesManager:reload_config(new_config)
	self.config = vim.tbl_deep_extend("force", self.config, new_config or {})

	-- 重新初始化子管理器
	if self._initialized then
		self:cleanup()
		self:_lazy_init()
	end
end

return NotesManager
