-- lua/nvim-store3/plugins/project_delete.lua
-- 项目数据删除插件（修复版：实时验证 + 安全删除）

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

-- 获取命名空间下的键数量
function M:get_key_count(namespace)
	return #self.store:namespace_keys(namespace)
end

-- 获取所有命名空间的实时计数
function M:get_namespaces_with_counts()
	local namespaces = self:get_namespaces()
	local items = {}

	for _, ns in ipairs(namespaces) do
		local count = self:get_key_count(ns) -- 实时获取最新计数
		local display = string.format("%-20s • %d", ns, count)
		table.insert(items, {
			ns = ns,
			count = count,
			display = display,
		})
	end

	return items
end

-- 确认删除（带二次验证）
function M:confirm_delete(namespace, initial_count)
	-- 删除前再次验证数据是否还存在
	local current_count = self:get_key_count(namespace)

	if current_count == 0 then
		vim.notify(string.format("命名空间 '%s' 已经没有数据了", namespace), vim.log.levels.INFO)
		return
	end

	if current_count ~= initial_count then
		vim.notify(
			string.format("数据已变化：从 %d 变为 %d 条，请重新确认", initial_count, current_count),
			vim.log.levels.WARN
		)
		-- 重新询问
		self:delete_with_confirm(namespace)
		return
	end

	vim.notify(
		string.format("🗑️ 正在删除命名空间 '%s' 的 %d 个键...", namespace, current_count),
		vim.log.levels.INFO
	)

	local keys = self.store:namespace_keys(namespace)
	local deleted_count = 0
	local failed_count = 0

	for _, key in ipairs(keys) do
		local full_key = namespace .. "." .. key
		local success, err = pcall(function()
			self.store:delete(full_key)
			deleted_count = deleted_count + 1
		end)
		if not success then
			failed_count = failed_count + 1
			vim.notify(string.format("删除失败: %s", err), vim.log.levels.ERROR)
		end
	end

	self.store:flush()

	if failed_count > 0 then
		vim.notify(
			string.format("⚠️ 已删除 %d 条，失败 %d 条", deleted_count, failed_count),
			vim.log.levels.WARN
		)
	else
		vim.notify(
			string.format("✅ 已删除命名空间 '%s' 的 %d 条数据", namespace, deleted_count),
			vim.log.levels.INFO
		)
	end
end

-- 删除命名空间前的确认（带实时计数）
function M:delete_with_confirm(namespace)
	local key_count = self:get_key_count(namespace) -- 实时获取最新计数

	if key_count == 0 then
		vim.notify(string.format("命名空间 '%s' 没有数据", namespace), vim.log.levels.INFO)
		return
	end

	vim.ui.input({
		prompt = string.format("删除 %s (%d个键)？(y/n) ", namespace, key_count),
	}, function(input)
		if input and input:lower() == "y" then
			self:confirm_delete(namespace, key_count)
		elseif input and input:lower() == "n" then
			vim.notify("❌ 已取消", vim.log.levels.INFO)
		else
			vim.notify("请输入 y 或 n", vim.log.levels.WARN)
			self:delete_with_confirm(namespace) -- 重新询问
		end
	end)
end

-- 交互式选择并删除命名空间（带实时刷新）
function M:select_and_delete()
	-- 实时获取最新数据
	local items = self:get_namespaces_with_counts()

	if #items == 0 then
		vim.notify("当前项目没有数据", vim.log.levels.INFO)
		return
	end

	vim.ui.select(items, {
		prompt = "选择要删除的命名空间",
		format_item = function(item)
			return item.display
		end,
	}, function(choice)
		if choice then
			self:delete_with_confirm(choice.ns)
		end
	end)
end

-- 直接删除命名空间
function M:delete_namespace(namespace)
	if not namespace or namespace == "" then
		vim.notify("请指定命名空间", vim.log.levels.ERROR)
		return
	end
	self:delete_with_confirm(namespace)
end

-- 获取补全列表（用于命令补全）
function M:get_completion_list()
	return self:get_namespaces()
end

-- 注册命令
function M.setup()
	vim.api.nvim_create_user_command("StoreDelete", function(opts)
		local store = require("nvim-store3").project()
		local deleter = M.new(store)

		if opts.args and opts.args ~= "" then
			deleter:delete_namespace(opts.args)
		else
			deleter:select_and_delete()
		end
	end, {
		desc = "删除命名空间的所有数据",
		nargs = "?",
		complete = function()
			local store = require("nvim-store3").project()
			local deleter = M.new(store)
			return deleter:get_completion_list()
		end,
	})
end

return M
