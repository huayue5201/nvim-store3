-- lua/nvim-store3/plugins/project_delete.lua
-- 项目数据删除插件（修复版：实时验证 + 安全删除）

local M = {}

function M.new(store)
	local self = {
		store = store,
		-- 新增：缓存命名空间计数
		namespace_counts = {},
		-- 新增：标记是否需要刷新计数
		need_refresh = true,
	}
	setmetatable(self, { __index = M })

	-- 新增：监听存储事件，数据变化时标记需要刷新
	self:_setup_event_listeners()

	return self
end

-- 新增：设置事件监听器
function M:_setup_event_listeners()
	local store = self.store
	-- 监听数据写入/删除/刷新事件
	store:on("set", function()
		self.need_refresh = true
	end)
	store:on("delete", function()
		self.need_refresh = true
	end)
	store:on("flush", function()
		self.need_refresh = true
	end)
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

-- 获取命名空间下的键数量（优化：带缓存）
function M:get_key_count(namespace)
	-- 如果需要刷新，重新计算所有计数
	if self.need_refresh then
		self:_refresh_all_counts()
	end
	return self.namespace_counts[namespace] or 0
end

-- 新增：刷新所有命名空间的计数
function M:_refresh_all_counts()
	local namespaces = self:get_namespaces()
	local counts = {}

	for _, ns in ipairs(namespaces) do
		counts[ns] = #self.store:namespace_keys(ns)
	end

	self.namespace_counts = counts
	self.need_refresh = false
end

-- 获取所有命名空间的实时计数
function M:get_namespaces_with_counts()
	-- 强制刷新最新计数
	self:_refresh_all_counts()

	local namespaces = self:get_namespaces()
	local items = {}

	for _, ns in ipairs(namespaces) do
		local count = self.namespace_counts[ns] or 0
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
	-- 删除前再次验证数据是否还存在（强制刷新）
	self:_refresh_all_counts()
	local current_count = self.namespace_counts[namespace] or 0

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
	-- 新增：删除后标记需要刷新计数
	self.need_refresh = true

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
	-- 强制刷新最新计数
	self:_refresh_all_counts()
	local key_count = self.namespace_counts[namespace] or 0

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
	-- 实时获取最新数据（强制刷新）
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
	-- 补全前刷新最新命名空间
	self:_refresh_all_counts()
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
