--- File: /Users/lijia/nvim-store3/lua/nvim-store3/storage/backend_factory.lua
--- 存储后端工厂（精简版）

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

	--- 创建内存后端实例
	--- @param cfg table 配置
	--- @return table 内存后端实例
	function MemoryBackend.new(cfg)
		local self = {
			config = cfg or {},
			data = {},
		}
		return setmetatable(self, MemoryBackend)
	end

	--- 获取数据
	--- @param key string 键名
	--- @return any 数据值
	function MemoryBackend:get(key)
		if key then
			return self.data[key]
		end
		return self.data
	end

	--- 设置数据
	--- @param key string 键名
	--- @param value any 数据值
	--- @return boolean 是否成功
	function MemoryBackend:set(key, value)
		self.data[key] = value
		return true
	end

	--- 删除数据
	--- @param key string 键名
	--- @return boolean 是否成功
	function MemoryBackend:delete(key)
		if self.data[key] == nil then
			return false
		end
		self.data[key] = nil
		return true
	end

	--- 获取所有键
	--- @return table 键列表
	function MemoryBackend:keys()
		local keys = {}
		for k, _ in pairs(self.data) do
			table.insert(keys, k)
		end
		return keys
	end

	--- 持久化（内存后端不做任何操作）
	--- @return boolean 总是返回 true
	function MemoryBackend:flush()
		return true
	end

	return MemoryBackend.new(config)
end)

return BackendFactory
