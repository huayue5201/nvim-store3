--- File: /Users/lijia/nvim-store3/lua/nvim-store3/features/extmarks.lua ---
-- Extmarks存储插件 - 可选基础设施
local M = {}

--- 创建Extmarks实例
--- @param store table Store实例
--- @param config table 配置
--- @return table Extmarks实例
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = {
			enabled = config.enabled ~= false,
			namespace = config.namespace or "nvim_store_extmarks",
			persist_extmarks = config.persist_extmarks or false, -- 是否持久化extmarks
		},
		namespaces = {},
	}

	setmetatable(self, { __index = M })

	return self
end

--- 设置extmark
--- @param bufnr number 缓冲区编号
--- @param line number 行号（1-based）
--- @param opts table 选项
--- @return number|nil extmark id
function M:set(bufnr, line, opts)
	if not self.config.enabled then
		return nil
	end

	opts = opts or {}

	-- 获取或创建命名空间
	local ns = self:_ensure_namespace()

	-- 转换为0-based行号
	local row = math.max(0, line - 1)

	-- 设置extmark
	local id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, opts)

	-- 如果需要持久化，存储到store
	if id and self.config.persist_extmarks then
		local key = string.format("extmarks.%d.%d", bufnr, id)
		self.store:set(key, {
			id = id,
			bufnr = bufnr,
			line = line,
			opts = opts,
			created_at = os.time(),
		})
	end

	return id
end

--- 获取extmarks
--- @param bufnr number 缓冲区编号
--- @param opts table 选项
--- @return table extmarks列表
function M:get(bufnr, opts)
	if not self.config.enabled then
		return {}
	end

	opts = opts or {}
	local ns = self:_ensure_namespace()

	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, opts.start or 0, opts.finish or -1, opts)

	local result = {}
	for _, extmark in ipairs(extmarks) do
		local id, row, col = unpack(extmark)
		table.insert(result, {
			id = id,
			line = row + 1, -- 转换为1-based
			col = col,
		})
	end

	return result
end

--- 清理extmarks
--- @param bufnr number 缓冲区编号
function M:clear(bufnr)
	if not self.config.enabled then
		return
	end

	local ns = self:_ensure_namespace()
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- 确保命名空间存在
function M:_ensure_namespace()
	local ns = self.namespaces[self.config.namespace]
	if not ns then
		ns = vim.api.nvim_create_namespace(self.config.namespace)
		self.namespaces[self.config.namespace] = ns
	end
	return ns
end

--- 加载持久化的extmarks
--- @param bufnr number 缓冲区编号
function M:load_persisted(bufnr)
	if not self.config.enabled or not self.config.persist_extmarks then
		return
	end

	local keys = self.store:namespace_keys("extmarks")

	for _, key in ipairs(keys) do
		if key:match("^" .. bufnr .. "%.") then
			local extmark_data = self.store:get("extmarks." .. key)
			if extmark_data and extmark_data.line then
				self:set(extmark_data.bufnr, extmark_data.line, extmark_data.opts)
			end
		end
	end
end

--- 清理资源
function M:cleanup()
	-- 清理所有命名空间
	for ns_name, ns in pairs(self.namespaces) do
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			end
		end
	end

	self.namespaces = {}
end

return M
