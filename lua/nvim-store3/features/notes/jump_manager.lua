--- File: /Users/lijia/nvim-store3/lua/nvim-store3/features/notes/jump_manager.lua ---
-- lua/nvim-store3/features/notes/jump_manager.lua
-- 跳转管理器（由原 notes/jump_manager.lua 迁移）

local M = {}

--- 创建跳转管理器
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
		_registered_commands = false,
	}

	return setmetatable(self, { __index = M })
end

--- 跳转到笔记定义
--- @param note_id string 笔记ID
--- @return boolean 是否成功跳转
function M:jump_to_definition(note_id)
	local note = self.notes:get(note_id)
	if not note then
		vim.notify("Note not found: " .. note_id, vim.log.levels.WARN)
		return false
	end

	local bufnr = note.bufnr
	local line = note.line

	-- 确保缓冲区存在
	if not vim.api.nvim_buf_is_valid(bufnr) then
		-- 尝试通过文件名加载缓冲区
		local filename = self:_get_buffer_filename(bufnr)
		if filename and vim.fn.filereadable(filename) == 1 then
			vim.cmd("edit " .. vim.fn.fnameescape(filename))
			bufnr = vim.api.nvim_get_current_buf()
		else
			vim.notify("Buffer not found for note: " .. note_id, vim.log.levels.ERROR)
			return false
		end
	end

	-- 跳转到缓冲区
	if bufnr ~= vim.api.nvim_get_current_buf() then
		vim.api.nvim_set_current_buf(bufnr)
	end

	-- 跳转到行号（0-based）
	local target_line = math.max(0, line - 1)
	vim.api.nvim_win_set_cursor(0, { target_line + 1, 0 })

	-- 可选：居中显示
	vim.cmd("normal! zz")

	-- 可选：高亮瞬间
	self:_highlight_position(bufnr, line)

	vim.notify("Jumped to note: " .. (note.text or note_id):sub(1, 50), vim.log.levels.INFO)
	return true
end

--- 获取缓冲区文件名
--- @param bufnr number 缓冲区编号
--- @return string|nil 文件名
function M:_get_buffer_filename(bufnr)
	-- 尝试从缓冲区获取文件名
	local filename = vim.api.nvim_buf_get_name(bufnr)
	if filename and filename ~= "" then
		return filename
	end

	-- 尝试从存储中获取
	local buffer_info = self.store:get("buffers." .. bufnr)
	if buffer_info and buffer_info.filename then
		return buffer_info.filename
	end

	return nil
end

--- 高亮位置
--- @param bufnr number 缓冲区编号
--- @param line number 行号
function M:_highlight_position(bufnr, line)
	-- 创建临时命名空间
	local ns = vim.api.nvim_create_namespace("nvim_store_jump")

	-- 清除旧的高亮
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	-- 添加高亮（0-based行号）
	local target_line = math.max(0, line - 1)
	vim.api.nvim_buf_set_extmark(bufnr, ns, target_line, 0, {
		hl_group = "Search",
		duration = 2000, -- 2秒后消失
	})
end

--- 设置命令
function M:setup_commands()
	if self._registered_commands then
		return
	end

	-- 跳转到笔记定义命令
	vim.api.nvim_create_user_command("NvimStoreJumpToNote", function(opts)
		local note_id = opts.args
		if note_id == "" then
			vim.notify("Usage: NvimStoreJumpToNote <note_id>", vim.log.levels.ERROR)
			return
		end

		self:jump_to_definition(note_id)
	end, {
		nargs = 1,
		complete = function()
			-- 补全可用的笔记ID
			local all_notes = self.notes:get_all()
			local completions = {}

			for note_id, note in pairs(all_notes) do
				table.insert(completions, note_id)
			end

			return completions
		end,
	})

	-- 查找并跳转到当前行的笔记
	vim.api.nvim_create_user_command("NvimStoreJumpToCurrentLineNote", function()
		local bufnr = vim.api.nvim_get_current_buf()
		local line = vim.api.nvim_win_get_cursor(0)[1]

		local note = self.notes:find_by_position(bufnr, line)
		if note then
			self:jump_to_definition(note.id)
		else
			vim.notify("No note found at current line", vim.log.levels.INFO)
		end
	end, {})

	self._registered_commands = true
end

--- 清理资源
function M:cleanup()
	-- 清理高亮
	local ns = vim.api.nvim_create_namespace("nvim_store_jump")
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		end
	end

	self._registered_commands = false
end

return M
