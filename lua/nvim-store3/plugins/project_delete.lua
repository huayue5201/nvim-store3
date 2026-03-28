-- lua/nvim-store3/plugins/project_delete.lua
local M = {}

function M.new(store)
	local self = {
		store = store,
		need_refresh = true,
		namespace_counts = {},
	}
	setmetatable(self, { __index = M })

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

function M:delete_namespace(namespace)
	if self.store._noop then
		vim.notify("当前不在项目目录中", vim.log.levels.WARN)
		return
	end

	if self.need_refresh then
		self:_refresh_counts()
	end
	local count = self.namespace_counts[namespace] or 0

	if count == 0 then
		vim.notify("命名空间 '" .. namespace .. "' 没有数据", vim.log.levels.INFO)
		return
	end

	vim.ui.input({
		prompt = string.format("删除 %s (%d条数据)？(y/n) ", namespace, count),
	}, function(input)
		if input and input:lower() == "y" then
			local keys = self.store:namespace_keys(namespace)
			for _, key in ipairs(keys) do
				self.store:delete(namespace .. "." .. key)
			end
			self.store:flush()
			self.need_refresh = true
			vim.notify(string.format("✅ 已删除 %d 条数据", #keys), vim.log.levels.INFO)
		end
	end)
end

function M:select_and_delete()
	if self.store._noop then
		vim.notify("当前不在项目目录中", vim.log.levels.WARN)
		return
	end

	if self.need_refresh then
		self:_refresh_counts()
	end

	local items = {}
	for ns, count in pairs(self.namespace_counts) do
		table.insert(items, { ns = ns, display = string.format("%-20s • %d", ns, count) })
	end
	table.sort(items, function(a, b)
		return a.ns < b.ns
	end)

	if #items == 0 then
		vim.notify("没有数据", vim.log.levels.INFO)
		return
	end

	vim.ui.select(items, {
		prompt = "选择要删除的命名空间",
		format_item = function(item)
			return item.display
		end,
	}, function(choice)
		if choice then
			self:delete_namespace(choice.ns)
		end
	end)
end

function M.setup()
	vim.api.nvim_create_user_command("StoreDelete", function(opts)
		local deleter = M.new(require("nvim-store3").project())
		if opts.args and opts.args ~= "" then
			deleter:delete_namespace(opts.args)
		else
			deleter:select_and_delete()
		end
	end, {
		desc = "删除命名空间数据",
		nargs = "?",
		complete = function()
			local store = require("nvim-store3").project()
			if store._noop then
				return {}
			end
			return M.new(store):get_namespaces()
		end,
	})
end

return M
