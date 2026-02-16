-- lua/nvim-store3/plugins/project_delete.lua
-- 项目数据删除插件 - 极简版

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

-- 确认删除
function M:confirm_delete(namespace, key_count)
	vim.notify(
		string.format("🗑️ 正在删除命名空间 '%s' 的 %d 个键...", namespace, key_count),
		vim.log.levels.INFO
	)

	local keys = self.store:namespace_keys(namespace)
	local deleted_count = 0

	for _, key in ipairs(keys) do
		local full_key = namespace .. "." .. key
		pcall(function()
			self.store:delete(full_key)
			deleted_count = deleted_count + 1
		end)
	end

	self.store:flush()
	vim.notify(
		string.format("✅ 已删除命名空间 '%s' 的 %d 条数据", namespace, deleted_count),
		vim.log.levels.INFO
	)
end

-- 删除命名空间前的确认
function M:delete_with_confirm(namespace)
	local key_count = self:get_key_count(namespace)

	if key_count == 0 then
		vim.notify(string.format("命名空间 '%s' 没有数据", namespace), vim.log.levels.INFO)
		return
	end

	vim.ui.input({
		prompt = string.format("删除 %s (%d个键)？(y/n) ", namespace, key_count),
	}, function(input)
		if input and input:lower() == "y" then
			self:confirm_delete(namespace, key_count)
		else
			vim.notify("❌ 已取消", vim.log.levels.INFO)
		end
	end)
end

-- 交互式选择并删除命名空间
function M:select_and_delete()
	local namespaces = self:get_namespaces()

	if #namespaces == 0 then
		vim.notify("当前项目没有数据", vim.log.levels.INFO)
		return
	end

	local items = {}
	for _, ns in ipairs(namespaces) do
		local count = self:get_key_count(ns)
		-- 固定宽度20，后面跟圆点和数量
		local display = string.format("%-20s • %d", ns, count)
		table.insert(items, {
			ns = ns,
			display = display,
		})
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
			return deleter:get_namespaces()
		end,
	})
end

return M
