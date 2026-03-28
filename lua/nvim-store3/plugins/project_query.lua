-- lua/nvim-store3/plugins/project_query.lua
local M = {}

function M.new(store)
	local self = {
		store = store,
		need_refresh = true,
		namespace_counts = {},
	}
	setmetatable(self, { __index = M })

	-- 只在有效存储时监听事件
	if not store._noop then
		store:on("set", function()
			self.need_refresh = true
		end)
		store:on("delete", function()
			self.need_refresh = true
		end)
	end

	return self
end

function M:get_namespaces()
	if self.store._noop then
		return {}
	end

	local keys = self.store:keys()
	local namespaces, seen = {}, {}

	for _, key in ipairs(keys) do
		local ns = key:match("^([^%.]+)")
		if ns and not seen[ns] then
			seen[ns] = true
			table.insert(namespaces, ns)
		end
	end

	table.sort(namespaces)
	return namespaces
end

function M:_refresh_counts()
	if self.store._noop then
		return
	end

	local namespaces = self:get_namespaces()
	for _, ns in ipairs(namespaces) do
		self.namespace_counts[ns] = #self.store:namespace_keys(ns)
	end
	self.need_refresh = false
end

-- 格式化 JSON（纯 Lua 实现，不依赖 json_encode）
function M:_format_json(data, indent)
	indent = indent or ""
	local lines = {}

	if type(data) == "table" then
		-- 判断是否是数组
		local is_array = true
		local max_idx = 0
		for k, _ in pairs(data) do
			if type(k) ~= "number" then
				is_array = false
				break
			end
			max_idx = math.max(max_idx, k)
		end
		if is_array then
			for i = 1, max_idx do
				if data[i] == nil then
					is_array = false
					break
				end
			end
		end

		if is_array then
			-- 数组格式
			table.insert(lines, indent .. "[")
			for i, v in ipairs(data) do
				local sub_lines = self:_format_json(v, indent .. "  ")
				for _, line in ipairs(sub_lines) do
					table.insert(lines, line)
				end
				if i < #data then
					lines[#lines] = lines[#lines] .. ","
				end
			end
			table.insert(lines, indent .. "]")
		else
			-- 对象格式
			table.insert(lines, indent .. "{")
			local keys = {}
			for k, _ in pairs(data) do
				table.insert(keys, k)
			end
			table.sort(keys)

			for i, k in ipairs(keys) do
				local v = data[k]
				local sub_lines = self:_format_json(v, indent .. "  ")

				if #sub_lines == 1 then
					-- 单行值
					local value_line = sub_lines[1]:match("^%s*(.+)$") or sub_lines[1]
					table.insert(lines, indent .. '  "' .. k .. '": ' .. value_line)
				else
					-- 多行值
					table.insert(lines, indent .. '  "' .. k .. '":')
					for _, line in ipairs(sub_lines) do
						table.insert(lines, line)
					end
				end

				if i < #keys then
					lines[#lines] = lines[#lines] .. ","
				end
			end
			table.insert(lines, indent .. "}")
		end
	elseif type(data) == "string" then
		-- 转义字符串
		local escaped = data:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
		table.insert(lines, indent .. '"' .. escaped .. '"')
	elseif type(data) == "number" or type(data) == "boolean" then
		table.insert(lines, indent .. tostring(data))
	elseif data == nil then
		table.insert(lines, indent .. "null")
	else
		table.insert(lines, indent .. tostring(data))
	end

	return lines
end

function M:show_json(namespace)
	if self.store._noop then
		vim.notify("当前不在项目目录中", vim.log.levels.WARN)
		return
	end

	-- 获取命名空间下的所有数据
	local keys = self.store:namespace_keys(namespace)
	local data = {}
	for _, key in ipairs(keys) do
		data[key] = self.store:get(namespace .. "." .. key)
	end

	-- 格式化 JSON
	local lines = self:_format_json(data)

	-- 计算窗口尺寸
	local max_line_len = 0
	for _, line in ipairs(lines) do
		max_line_len = math.max(max_line_len, #line)
	end

	local width = math.min(max_line_len + 4, vim.o.columns - 4)
	local height = math.min(#lines + 4, vim.o.lines - 4)

	-- 创建浮窗
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "json"
	vim.bo[buf].modifiable = false

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " " .. namespace .. " ",
		title_pos = "center",
	})

	-- 设置窗口选项
	vim.wo[win].wrap = true
	vim.wo[win].cursorline = true
	vim.wo[win].number = true
	vim.wo[win].relativenumber = false

	-- 按键映射
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, "n", "<ESC>", "<cmd>close<CR>", { noremap = true, silent = true })
end

function M:select_namespace()
	if self.store._noop then
		vim.notify("当前不在项目目录中", vim.log.levels.WARN)
		return
	end

	if self.need_refresh then
		self:_refresh_counts()
	end

	local items = {}
	for ns, count in pairs(self.namespace_counts) do
		table.insert(items, {
			ns = ns,
			display = string.format("%-20s • %d", ns, count),
		})
	end
	table.sort(items, function(a, b)
		return a.ns < b.ns
	end)

	if #items == 0 then
		vim.notify("没有数据", vim.log.levels.INFO)
		return
	end

	vim.ui.select(items, {
		prompt = "选择命名空间查看数据",
		format_item = function(item)
			return item.display
		end,
	}, function(choice)
		if choice then
			-- 显示前再次验证数据是否存在
			local current_count = self.namespace_counts[choice.ns] or 0
			if current_count == 0 then
				vim.notify(string.format("命名空间 '%s' 的数据已被删除", choice.ns), vim.log.levels.WARN)
				return
			end
			self:show_json(choice.ns)
		end
	end)
end

-- 注册命令
function M.setup()
	vim.api.nvim_create_user_command("Store", function()
		local store = require("nvim-store3").project()
		local query = M.new(store)
		query:select_namespace()
	end, { desc = "查看存储数据" })
end

return M
