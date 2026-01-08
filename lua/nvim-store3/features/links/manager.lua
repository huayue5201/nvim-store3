--- File: /Users/lijia/nvim-store3/lua/nvim-store3/features/links/manager.lua ---
-- lua/nvim-store3/features/links/manager.lua
-- Links 功能管理器（由原 core/link.lua 迁移）

local M = {}

--- 创建 Links 管理器
--- @param store table Store 实例
--- @param config table 配置
--- @return table Links 管理器
function M.new(store, config)
	config = config or {}

	local self = {
		store = store,
		config = config,
		_initialized = false,
	}

	setmetatable(self, { __index = M })

	return self
end

--- 确保 links 表存在
--- @return table links 表
function M:_ensure_links()
	local links = self.store:get("links")
	if not links then
		links = {}
		self.store:set("links", links)
	end
	return links
end

--- 确保某个节点存在
--- @param links table links 表
--- @param key string 节点名称
--- @return table 节点表
function M:_ensure_node(links, key)
	if links[key] == nil then
		links[key] = {}
	end
	return links[key]
end

--- 添加双向链接
--- @param a string 节点 A
--- @param b string 节点 B
function M:add(a, b)
	if a == b then
		return
	end

	local links = self:_ensure_links()
	local la = self:_ensure_node(links, a)
	local lb = self:_ensure_node(links, b)

	la[b] = true
	lb[a] = true

	-- 保存回存储
	self.store:set("links", links)
end

--- 删除双向链接
--- @param a string 节点 A
--- @param b string 节点 B
function M:remove(a, b)
	local links = self.store:get("links")
	if not links then
		return
	end

	-- 删除 a -> b
	if links[a] then
		links[a][b] = nil
		if next(links[a]) == nil then
			self.store:delete("links." .. a)
		else
			self.store:set("links." .. a, links[a])
		end
	end

	-- 删除 b -> a
	if links[b] then
		links[b][a] = nil
		if next(links[b]) == nil then
			self.store:delete("links." .. b)
		else
			self.store:set("links." .. b, links[b])
		end
	end
end

--- 获取节点的所有链接
--- @param key string 节点名称
--- @return table 链接表（键为链接节点，值为 true）
function M:get(key)
	local links = self.store:get("links")
	if not links then
		return {}
	end
	return links[key] or {}
end

--- 获取节点的所有链接节点列表
--- @param key string 节点名称
--- @return string[] 链接节点列表
function M:get_list(key)
	local links = self:get(key)
	local result = {}

	for linked_key, _ in pairs(links) do
		table.insert(result, linked_key)
	end

	return result
end

--- 移除节点的所有链接
--- @param key string 节点名称
function M:remove_all(key)
	local links = self.store:get("links")
	if not links then
		return
	end

	-- 获取该节点的所有链接
	local node_links = links[key]
	if node_links then
		-- 删除其他节点指向该节点的链接
		for other, _ in pairs(node_links) do
			if links[other] then
				links[other][key] = nil
				if next(links[other]) == nil then
					self.store:delete("links." .. other)
				else
					self.store:set("links." .. other, links[other])
				end
			end
		end
	end

	-- 删除该节点
	self.store:delete("links." .. key)
end

--- 检查两个节点是否链接
--- @param a string 节点 A
--- @param b string 节点 B
--- @return boolean 是否链接
function M:connected(a, b)
	local links = self:get(a)
	return links[b] == true
end

--- 查找两个节点的共同链接
--- @param a string 节点 A
--- @param b string 节点 B
--- @return string[] 共同链接节点列表
function M:common_links(a, b)
	local links_a = self:get_list(a)
	local links_b = self:get_list(b)

	local common = {}
	local set_b = {}

	-- 创建集合以便快速查找
	for _, node in ipairs(links_b) do
		set_b[node] = true
	end

	-- 查找共同节点
	for _, node in ipairs(links_a) do
		if set_b[node] and node ~= a and node ~= b then
			table.insert(common, node)
		end
	end

	return common
end

--- 获取所有节点
--- @return string[] 所有节点列表
function M:get_all_nodes()
	local links = self.store:get("links")
	if not links then
		return {}
	end

	local nodes = {}
	for node, _ in pairs(links) do
		table.insert(nodes, node)
	end

	return nodes
end

--- 获取链接数统计
--- @return table 统计信息
function M:get_stats()
	local links = self.store:get("links") or {}

	local total_nodes = 0
	local total_links = 0
	local max_links = 0
	local max_links_node = nil

	for node, node_links in pairs(links) do
		total_nodes = total_nodes + 1

		local link_count = 0
		for _ in pairs(node_links) do
			link_count = link_count + 1
		end

		total_links = total_links + link_count

		if link_count > max_links then
			max_links = link_count
			max_links_node = node
		end
	end

	-- 每个链接被计数两次（双向），所以除以2
	total_links = math.floor(total_links / 2)

	return {
		total_nodes = total_nodes,
		total_links = total_links,
		max_links = max_links,
		max_links_node = max_links_node,
		average_links = total_nodes > 0 and total_links / total_nodes or 0,
	}
end

--- 清理资源
function M:cleanup()
	-- 目前没有需要清理的资源
end

return M
