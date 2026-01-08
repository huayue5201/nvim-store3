--- File: /Users/lijia/nvim-store3/lua/nvim-store3/features/notes/migration_manager.lua ---
-- lua/nvim-store3/features/notes/migration_manager.lua
-- 迁移管理器（由原 notes/migration_manager.lua 迁移）

local M = {}

--- 创建迁移管理器
--- @param store table Store 实例
--- @param notes_manager NotesManager 笔记管理器
--- @param config? table 配置
--- @return table
function M.new(store, notes_manager, config)
	config = config or {}

	local self = {
		store = store,
		notes = notes_manager,
		config = config,
		_migrations = {},
	}

	return setmetatable(self, { __index = M })
end

--- 重建符号索引
--- @return boolean 是否成功
function M:rebuild_symbol_index()
	vim.notify("Rebuilding symbol index...", vim.log.levels.INFO)

	local all_notes = self.notes:get_all()
	local symbol_index = {}

	for note_id, note in pairs(all_notes) do
		if note.symbol then
			local symbol_name = note.symbol.name or ("unnamed_" .. note_id)

			if not symbol_index[symbol_name] then
				symbol_index[symbol_name] = {}
			end

			table.insert(symbol_index[symbol_name], {
				note_id = note_id,
				bufnr = note.bufnr,
				line = note.line,
				type = note.symbol.type,
				scope = note.symbol.scope,
			})
		end
	end

	-- 保存符号索引
	self.store:set("symbol_index", symbol_index)

	vim.notify(
		string.format(
			"Symbol index rebuilt: %d symbols, %d total references",
			#vim.tbl_keys(symbol_index),
			self:_count_total_references(symbol_index)
		),
		vim.log.levels.INFO
	)

	return true
end

--- 计算总引用数
--- @param symbol_index table 符号索引
--- @return number 总引用数
function M:_count_total_references(symbol_index)
	local total = 0
	for _, references in pairs(symbol_index) do
		total = total + #references
	end
	return total
end

--- 迁移旧数据格式
--- @return boolean 是否成功
function M:migrate_old_format()
	local data = self.store:get("notes")

	if not data or type(data) ~= "table" then
		return true -- 没有数据需要迁移
	end

	local migrated = 0
	local new_notes = {}

	-- 检查是否需要迁移
	local needs_migration = false
	for key, value in pairs(data) do
		if not value.id then
			needs_migration = true
			break
		end
	end

	if not needs_migration then
		return true
	end

	-- 执行迁移
	for key, value in pairs(data) do
		if type(value) == "table" then
			if not value.id then
				-- 这是旧格式，需要迁移
				local new_note = {
					id = key,
					bufnr = value.bufnr or 0,
					line = value.line or 0,
					text = value.text or "",
					created_at = value.created_at or os.time(),
					updated_at = value.updated_at or os.time(),
				}

				-- 保留其他字段
				for k, v in pairs(value) do
					if new_note[k] == nil then
						new_note[k] = v
					end
				end

				new_notes[key] = new_note
				migrated = migrated + 1
			else
				-- 已经是新格式
				new_notes[key] = value
			end
		end
	end

	-- 保存迁移后的数据
	if migrated > 0 then
		self.store:set("notes", new_notes)
		vim.notify(string.format("Migrated %d notes to new format", migrated), vim.log.levels.INFO)
	end

	return true
end

--- 清理孤儿笔记（缓冲区已关闭）
--- @return table 清理结果
function M:cleanup_orphan_notes()
	local all_notes = self.notes:get_all()
	local orphan_notes = {}
	local valid_notes = {}

	for note_id, note in pairs(all_notes) do
		if note.bufnr then
			if vim.api.nvim_buf_is_valid(note.bufnr) then
				valid_notes[note_id] = note
			else
				orphan_notes[note_id] = note
			end
		else
			valid_notes[note_id] = note
		end
	end

	-- 保存清理后的笔记
	if next(orphan_notes) then
		self.store:set("notes", valid_notes)
	end

	return {
		cleaned = orphan_notes,
		remaining = valid_notes,
		count = #vim.tbl_keys(orphan_notes),
	}
end

--- 设置自动命令
function M:setup_autocmd()
	-- 缓冲区卸载时检查孤儿笔记
	vim.api.nvim_create_autocmd("BufUnload", {
		callback = function(args)
			-- 可以在这里添加缓冲区卸载时的处理逻辑
			-- 例如：清理与该缓冲区相关的临时数据
		end,
	})

	-- VimEnter 时执行迁移
	vim.api.nvim_create_autocmd("VimEnter", {
		callback = function()
			-- 延迟执行，避免影响启动速度
			vim.defer_fn(function()
				self:migrate_old_format()

				-- 如果配置了自动清理，则执行清理
				if self.config.auto_cleanup then
					local result = self:cleanup_orphan_notes()
					if result.count > 0 then
						vim.notify(string.format("Auto-cleaned %d orphan notes", result.count), vim.log.levels.INFO)
					end
				end
			end, 1000)
		end,
		once = true,
	})
end

--- 导出数据
--- @param format? string 导出格式
--- @return string 导出的数据
function M:export_data(format)
	format = format or "json"

	local data = {
		version = "1.0",
		exported_at = os.time(),
		notes = self.notes:get_all(),
	}

	if format == "json" then
		return vim.fn.json_encode(data)
	else
		error("Unsupported export format: " .. format)
	end
end

--- 导入数据
--- @param data_string string 数据字符串
--- @param format? string 数据格式
--- @return boolean 是否成功
function M:import_data(data_string, format)
	format = format or "json"

	local data
	if format == "json" then
		local ok, decoded = pcall(vim.fn.json_decode, data_string)
		if not ok then
			vim.notify("Failed to parse JSON data", vim.log.levels.ERROR)
			return false
		end
		data = decoded
	else
		error("Unsupported import format: " .. format)
	end

	-- 验证数据格式
	if not data.notes or type(data.notes) ~= "table" then
		vim.notify("Invalid data format: missing notes", vim.log.levels.ERROR)
		return false
	end

	-- 合并数据
	local existing_notes = self.notes:get_all()
	local imported_count = 0
	local skipped_count = 0

	for note_id, note in pairs(data.notes) do
		if not existing_notes[note_id] then
			existing_notes[note_id] = note
			imported_count = imported_count + 1
		else
			skipped_count = skipped_count + 1
		end
	end

	-- 保存合并后的数据
	self.store:set("notes", existing_notes)

	vim.notify(
		string.format("Imported %d notes, skipped %d duplicates", imported_count, skipped_count),
		vim.log.levels.INFO
	)

	return true
end

--- 清理资源
function M:cleanup()
	-- 目前没有需要清理的资源
end

return M
