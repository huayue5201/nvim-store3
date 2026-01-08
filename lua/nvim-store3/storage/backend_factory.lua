--- File: /Users/lijia/nvim-store3/lua/nvim-store3/storage/backend_factory.lua ---
-- lua/nvim-store3/storage/backend_factory.lua
-- 存储后端工厂（简化版）

local BackendFactory = {}

BackendFactory.registry = {}

--- 注册后端
--- @param name string 后端名称
--- @param factory_func function 工厂函数
function BackendFactory.register(name, factory_func)
	BackendFactory.registry[name] = factory_func
end

--- 创建后端实例
--- @param config table 配置
--- @return table 后端实例
function BackendFactory.create(config)
	local backend_name = config.backend or "json"

	local factory = BackendFactory.registry[backend_name]
	if not factory then
		error(string.format("Unknown storage backend: %s", backend_name))
	end

	return factory(config)
end

-- 注册 JSON 后端
BackendFactory.register("json", function(config)
	return require("nvim-store3.storage.json_backend").new(config)
end)

-- 注册内存后端（用于测试）
BackendFactory.register("memory", function(config)
	local MemoryBackend = {}
	MemoryBackend.__index = MemoryBackend

	function MemoryBackend.new(cfg)
		local self = {
			config = cfg or {},
			data = {},
		}
		return setmetatable(self, MemoryBackend)
	end

	function MemoryBackend:load()
		return self.data
	end

	function MemoryBackend:get(namespace, key)
		if key then
			return self.data[key]
		else
			return self.data
		end
	end

	function MemoryBackend:set(namespace, key, value)
		self.data[key] = value
		return true
	end

	function MemoryBackend:delete(namespace, key)
		if self.data[key] == nil then
			return false
		end
		self.data[key] = nil
		return true
	end

	function MemoryBackend:keys(namespace)
		local keys = {}
		for k, _ in pairs(self.data) do
			table.insert(keys, k)
		end
		return keys
	end

	function MemoryBackend:flush()
		return true
	end

	return MemoryBackend.new(config)
end)

return BackendFactory
