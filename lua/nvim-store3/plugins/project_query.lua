-- lua/nvim-store3/plugins/project_query.lua
-- 项目数据查询插件（修复缩进）

local M = {}

function M.new(store)
	local self = { store = store }
	setmetatable(self, { __index = M })
	return self
end

-- 获取所有命名空间
function M:get_namespaces()
	local keys = self.store:keys()
	local namespaces = {}
	local ns_set = {}

	for _, key in ipairs(keys) do
		local dot_pos = key:find("%.")
		if dot_pos then
			local ns = key:sub(1, dot_pos - 1)
			if not ns_set[ns] then
				ns_set[ns] = true
				table.insert(namespaces, ns)
			end
		end
	end

	table.sort(namespaces)
	return namespaces
end

-- 格式化 JSON（纯Lua实现）
function M:pretty_json(data, indent)
	indent = indent or ""
	local lines = {}

	if type(data) == "table" then
		-- 判断是数组还是对象
		local is_array = true
		local max_index = 0
		for k, _ in pairs(data) do
			if type(k) ~= "number" then
				is_array = false
				break
			end
			max_index = math.max(max_index, k)
		end
		if is_array then
			for i = 1, max_index do
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
				local sub_lines = self:pretty_json(v, indent .. "  ")
				for j, line in ipairs(sub_lines) do
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
				local sub_lines = self:pretty_json(v, indent .. "  ")

				-- 第一个子行合并到键名行
				if #sub_lines == 1 then
					-- 单行值，直接合并
					table.insert(lines, indent .. '  "' .. k .. '": ' .. sub_lines[1]:match("^%s*(.+)$"))
				else
					-- 多行值，键名单独一行
					table.insert(lines, indent .. '  "' .. k .. '": ')
					for j, line in ipairs(sub_lines) do
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
		table.insert(lines, indent .. '"' .. data .. '"')
	elseif type(data) == "number" or type(data) == "boolean" then
		table.insert(lines, indent .. tostring(data))
	elseif data == nil then
		table.insert(lines, indent .. "null")
	else
		table.insert(lines, indent .. tostring(data))
	end

	return lines
end

-- 显示格式化的数据
function M:show_json(namespace)
	-- 获取命名空间下的所有数据
	local keys = self.store:namespace_keys(namespace)
	local data = {}

	for _, key in ipairs(keys) do
		local full_key = namespace .. "." .. key
		data[key] = self.store:get(full_key)
	end

	-- 格式化
	local lines = self:pretty_json(data)

	-- 调试：打印实际的行内容
	-- for i, line in ipairs(lines) do
	--     print(string.format("Line %d: '%s'", i, line))
	-- end

	-- 计算最佳宽度和高度
	local max_line_length = 0
	for _, line in ipairs(lines) do
		max_line_length = math.max(max_line_length, #line)
	end

	-- 宽度：最长行 + 4（边框），不超过屏幕宽度
	local width = math.min(max_line_length + 4, vim.o.columns - 4)

	-- 高度：行数 + 4（边框+标题），不超过屏幕高度
	local height = math.min(#lines + 4, vim.o.lines - 4)

	-- 创建浮窗
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- 设置语法高亮
	vim.bo[buf].filetype = "json"
	vim.bo[buf].modifiable = false

	-- 创建窗口（自动居中）
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

	-- 按 q 关闭
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, "n", "<ESC>", "<cmd>close<CR>", { noremap = true, silent = true })
end

-- 交互式选择命名空间
function M:select_namespace()
	local namespaces = self:get_namespaces()

	if #namespaces == 0 then
		vim.notify("当前项目没有数据", vim.log.levels.INFO)
		return
	end

	vim.ui.select(namespaces, {
		prompt = "选择命名空间查看数据",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice then
			self:show_json(choice)
		end
	end)
end

-- 注册命令
function M.setup()
	vim.api.nvim_create_user_command("Store", function()
		local store = require("nvim-store3").project()
		local query = M.new(store)
		query:select_namespace()
	end, {
		desc = "选择命名空间并查看格式化的数据",
	})
end

return M
