-- Extmarks存储插件 - 可选基础设施
local M = {}

---------------------------------------------------------------------
-- 内部：buffer 安全层（防御 nil / vim.NIL / 无效 buffer）
---------------------------------------------------------------------
local function normalize_buf(buf)
	if buf == nil or buf == vim.NIL then
		return nil
	end
	if type(buf) ~= "number" then
		return nil
	end
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end
	return buf
end

---------------------------------------------------------------------
-- 创建 Extmarks 实例
---------------------------------------------------------------------
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = {
			enabled = config.enabled ~= false,
			namespace = config.namespace or "nvim_store_extmarks",
			persist_extmarks = config.persist_extmarks or false,
		},
		namespaces = {},
	}

	setmetatable(self, { __index = M })
	return self
end

---------------------------------------------------------------------
-- 设置 extmark（带 buffer 安全层）
---------------------------------------------------------------------
function M:set(bufnr, line, opts)
	if not self.config.enabled then
		return nil
	end

	bufnr = normalize_buf(bufnr)
	if not bufnr then
		return nil
	end

	opts = opts or {}
	local ns = self:_ensure_namespace()

	local row = math.max(0, line - 1)

	local id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, opts)

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

---------------------------------------------------------------------
-- 获取 extmarks（带 buffer 安全层）
---------------------------------------------------------------------
function M:get(bufnr, opts)
	if not self.config.enabled then
		return {}
	end

	bufnr = normalize_buf(bufnr)
	if not bufnr then
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
			line = row + 1,
			col = col,
		})
	end

	return result
end

---------------------------------------------------------------------
-- 清理 extmarks（带 buffer 安全层）
---------------------------------------------------------------------
function M:clear(bufnr)
	if not self.config.enabled then
		return
	end

	bufnr = normalize_buf(bufnr)
	if not bufnr then
		return
	end

	local ns = self:_ensure_namespace()
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---------------------------------------------------------------------
-- 确保命名空间存在
---------------------------------------------------------------------
function M:_ensure_namespace()
	local ns = self.namespaces[self.config.namespace]
	if not ns then
		ns = vim.api.nvim_create_namespace(self.config.namespace)
		self.namespaces[self.config.namespace] = ns
	end
	return ns
end

---------------------------------------------------------------------
-- 加载持久化 extmarks（带 buffer 安全层）
---------------------------------------------------------------------
function M:load_persisted(bufnr)
	if not self.config.enabled or not self.config.persist_extmarks then
		return
	end

	bufnr = normalize_buf(bufnr)
	if not bufnr then
		return
	end

	local keys = self.store:namespace_keys("extmarks")

	for _, key in ipairs(keys) do
		if key:match("^" .. bufnr .. "%.") then
			local extmark_data = self.store:get("extmarks." .. key)
			if extmark_data and extmark_data.line then
				local b = normalize_buf(extmark_data.bufnr)
				if b then
					self:set(b, extmark_data.line, extmark_data.opts)
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- 清理资源（带 buffer 安全层）
---------------------------------------------------------------------
function M:cleanup()
	for _, ns in pairs(self.namespaces) do
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			local b = normalize_buf(bufnr)
			if b then
				vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)
			end
		end
	end

	self.namespaces = {}
end

return M
