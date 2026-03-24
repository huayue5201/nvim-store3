# nvim-store3 技术说明文档

## 1. 项目概述

nvim-store3 是一个专为 Neovim 设计的专业级持久化存储解决方案，提供跨会话的数据持久化、事件驱动的插件系统、自动编码机制和实时数据验证功能。

### 1.1 核心特性

- **双作用域存储**：支持全局存储和项目级存储
- **插件化架构**：可插拔的插件系统，支持动态加载和卸载
- **事件驱动**：内置事件系统，支持数据变更监听
- **自动编码**：智能键名编码，确保文件系统兼容性
- **实时验证**：数据操作实时验证，防止竞态条件
- **原子写入**：JSON 存储后端支持原子写入和自动备份

## 2. 系统架构

### 2.1 架构图

```
┌─────────────────────────────────────────────┐
│                nvim-store3                    │
├─────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────────┐ │
│  │  Global  │  │ Project │  │   Plugins   │ │
│  │  Store   │  │  Store  │  │   System    │ │
│  └────┬────┘  └────┬────┘  └──────┬──────┘ │
│       │            │               │        │
│  ┌────┴────────────┴───────────────┴─────┐ │
│  │              Core Store                │ │
│  │  ┌────────┐  ┌────────┐  ┌────────┐   │ │
│  │  │  Data  │  │ Events │  │ Plugin │   │ │
│  │  │ Cache  │  │ System │  │ Loader │   │ │
│  │  └────────┘  └────────┘  └────────┘   │ │
│  └────────────────────────────────────────┘ │
│                     │                        │
│  ┌────────────────────────────────────┐     │
│  │        Storage Backends            │     │
│  │  ┌────────────┐ ┌────────────┐    │     │
│  │  │   JSON     │ │   Memory   │    │     │
│  │  │  Backend   │ │  Backend   │    │     │
│  │  └────────────┘ └────────────┘    │     │
│  └────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

### 2.2 核心模块职责

| 模块 | 路径 | 职责 |
|------|------|------|
| Store | `core/store.lua` | 核心存储逻辑，CRUD 操作，事件管理 |
| Plugin Loader | `core/plugin_loader.lua` | 插件动态加载和管理 |
| Backend Factory | `storage/backend_factory.lua` | 存储后端工厂模式管理 |
| JSON Backend | `storage/json_backend.lua` | JSON 文件持久化 |
| Event System | `util/event.lua` | 事件发布/订阅 |
| Path Utils | `util/path.lua` | 路径处理和键名编码 |
| JSON Utils | `util/json.lua` | JSON 读写和原子操作 |
| ID Generator | `util/id.lua` | 唯一 ID 生成 |

## 3. 核心 API 文档

### 3.1 Store API

#### 创建实例

```lua
-- 全局存储
local store = require("nvim-store3").global({
  auto_encode = true,
  plugins = {
    basic_cache = true,
    project_query = true
  }
})

-- 项目存储
local project_store = require("nvim-store3").project()
```

#### 数据操作

```lua
-- 设置数据
store:set("key", value)

-- 获取数据
local value = store:get("key")

-- 删除数据
store:delete("key")

-- 获取所有键
local keys = store:keys()

-- 获取命名空间下的键
local ns_keys = store:namespace_keys("notes")

-- 持久化到磁盘
store:flush()

-- 路径查询（支持嵌套）
local data = store:query("notes.today.1")
```

#### 事件系统

```lua
-- 订阅事件
store:on("set", function(payload)
  print("数据已设置:", payload.key)
end)

store:on("delete", function(payload)
  print("数据已删除:", payload.key)
end)

store:on("flush", function(payload)
  print("数据已持久化")
end)
```

#### 自动编码控制

```lua
-- 开启/关闭自动编码
store:set_auto_encode(true)

-- 获取自动编码状态
local enabled = store:get_auto_encode()
```

### 3.2 插件系统 API

#### 插件加载器

```lua
local loader = PluginLoader.new(store, config)

-- 加载所有启用的插件
loader:load_plugins()

-- 加载单个插件
loader:load_plugin("basic_cache", { enabled = true })

-- 卸载插件
loader:unload_plugin("basic_cache")

-- 清理所有插件
loader:cleanup()
```

#### 插件注册表

```lua
-- 内置插件注册
PluginLoader.registry = {
  basic_cache = "nvim-store3.plugins.basic_cache",
  project_query = "nvim-store3.plugins.project_query",
  project_delete = "nvim-store3.plugins.project_delete",
}

-- 注册自定义插件
require("nvim-store3").register_plugin("my_plugin", "path.to.my_plugin")
```

### 3.3 插件开发规范

#### 插件基本结构

```lua
-- my_plugin.lua
local M = {}

function M.new(store, config)
  local self = {
    store = store,
    config = config or {},
    -- 插件私有状态
  }

  setmetatable(self, { __index = M })

  -- 可选的初始化逻辑
  self:_init()

  return self
end

-- 可选的初始化方法
function M:_init()
  -- 设置事件监听等
  self.store:on("set", function(payload)
    -- 处理数据变更
  end)
end

-- 插件功能方法
function M:do_something()
  -- 实现功能
end

-- 可选的清理方法（卸载时调用）
function M:cleanup()
  -- 清理资源
end

return M
```

### 3.4 内置插件说明

#### Basic Cache（基础缓存插件）

提供 LRU 缓存和 TTL 过期机制。

```lua
-- 配置
{
  enabled = true,           -- 是否启用
  default_ttl = 300,         -- 默认过期时间（秒）
  write_through = true,      -- 是否同步写入存储
  read_through = true,       -- 是否缓存读取
}

-- API
cache:set(key, value, ttl)   -- 设置缓存
cache:get(key)               -- 获取缓存
cache:delete(key)            -- 删除缓存
cache:cleanup_expired()      -- 清理过期项
```

#### Project Query（项目查询插件）

提供格式化的数据查看功能。

```lua
-- 使用
:Store  -- 交互式选择命名空间查看数据

-- API
query:get_namespaces()               -- 获取所有命名空间
query:get_namespaces_with_counts()    -- 获取带计数的命名空间
query:show_json(namespace)            -- 显示格式化的 JSON
```

#### Project Delete（项目删除插件）

提供安全的数据删除功能。

```lua
-- 使用
:StoreDelete [namespace]  -- 删除指定命名空间（交互式或直接）

-- API
deleter:get_namespaces()               -- 获取命名空间列表
deleter:delete_namespace(namespace)     -- 删除命名空间
deleter:select_and_delete()             -- 交互式选择删除
```

## 4. 存储后端

### 4.1 JSON Backend

```lua
-- 配置
{
  path = "/path/to/data.json",  -- 存储路径
  flush_delay = 1000,            -- 延迟保存（毫秒）
}

-- 特性
- 原子写入（先写临时文件，再重命名）
- 自动备份（保存前备份原文件）
- 写锁保护（防止并发写入）
- 待写入队列（写锁期间缓存操作）
- 自动目录创建
```

### 4.2 Memory Backend（测试用）

```lua
-- 配置
{
  backend = "memory",
  -- 无持久化，仅内存存储
}
```

## 5. 工具模块

### 5.1 Path 工具

```lua
local Path = require("nvim-store3.util.path")

-- 键名编码
local safe = Path.encode_key("file/name")  -- "b64:ZmlsZS9uYW1l_..."
local original = Path.decode_key(safe)     -- "file/name"

-- 路径获取
local project_root = Path.project_root()
local store_path = Path.project_store_path()
local global_path = Path.global_store_path()
```

编码规则：
- 仅编码危险字符（`/ \ : ? * " < > |` 和控制字符）
- 编码格式：`b64:{base64}_{hash}`
- hash 用于冲突检测

### 5.2 JSON 工具

```lua
local Json = require("nvim-store3.util.json")

-- 安全读取
local data = Json.load("/path/to/file.json")

-- 原子写入
local success = Json.save("/path/to/file.json", data)
```

### 5.3 Event 工具

```lua
local Event = require("nvim-store3.util.event")
local events = Event.new()

-- 订阅
events:on("change", function(payload)
  print("数据变化:", vim.inspect(payload))
end)

-- 发布
events:emit("change", { key = "foo", value = "bar" })
```

## 6. 配置指南

### 6.1 完整配置示例

```lua
-- ~/.config/nvim/lua/plugins/nvim-store3.lua
return {
  "username/nvim-store3",
  config = function()
    local store = require("nvim-store3")

    -- 配置全局存储
    store.global({
      auto_encode = true,
      storage = {
        backend = "json",
        flush_delay = 1000,
      },
      plugins = {
        basic_cache = {
          enabled = true,
          default_ttl = 600,
          write_through = true,
        },
        project_query = true,
        project_delete = true,
      }
    })

    -- 注册自定义插件
    store.register_plugin("my_plugin", "path.to.my_plugin")
  end
}
```

### 6.2 插件启用/禁用

```lua
-- 启用插件（使用默认配置）
plugins = {
  basic_cache = true,
}

-- 启用插件（自定义配置）
plugins = {
  basic_cache = {
    enabled = true,
    default_ttl = 300,
  },
}

-- 禁用插件
plugins = {
  basic_cache = false,
}
```

## 7. 最佳实践

### 7.1 数据组织

```lua
-- 使用命名空间组织数据
store:set("notes.today.1", { title = "今日笔记", content = "..." })
store:set("notes.today.2", { title = "明日计划", content = "..." })
store:set("config.editor", { theme = "dark", font_size = 14 })

-- 查询特定命名空间
local notes = store:namespace_keys("notes")  -- {"today.1", "today.2"}
```

### 7.2 事件监听示例

```lua
-- 数据变更监控
store:on("set", function(payload)
  if payload.key:match("^notes%.") then
    -- 更新笔记相关 UI
    refresh_notes_view()
  end
end)

-- 持久化监控
store:on("flush", function(payload)
  if payload.ok then
    print("数据已保存到磁盘")
  end
end)
```

### 7.3 插件开发示例

```lua
-- plugins/my_counter.lua
local M = {}

function M.new(store, config)
  local self = {
    store = store,
    counts = {},
  }

  setmetatable(self, { __index = M })

  -- 初始化计数
  self.counts = store:get("__counter") or {}

  -- 监听数据变化
  store:on("set", function(payload)
    if payload.key ~= "__counter" then
      self:increment(payload.key)
    end
  end)

  return self
end

function M:increment(key)
  self.counts[key] = (self.counts[key] or 0) + 1
  self.store:set("__counter", self.counts)
end

function M:get_count(key)
  return self.counts[key] or 0
end

function M:cleanup()
  self.store:set("__counter", self.counts)
end

return M
```

## 8. 故障排除

### 8.1 常见问题

**Q: 数据保存失败**
```
可能原因：目录权限不足、磁盘空间不足
解决方案：检查存储路径权限，确保目录可写
```

**Q: 插件加载失败**
```
可能原因：插件路径错误、依赖缺失
解决方案：检查插件注册表路径，确认依赖已安装
```

**Q: 编码键无法解码**
```
可能原因：数据损坏、编码格式不匹配
解决方案：使用 is_encoded_key() 检测，手动修复数据
```

### 8.2 调试工具

```lua
-- 获取存储统计
local stats = store:get_stats()
print("总键数:", stats.total_keys)
print("编码键数:", stats.encoded_keys)
print("缓存大小:", stats.cache_size)

-- 检查编码状态
local key = "test/key"
local safe = Path.encode_key(key)
print("需要编码:", Path.needs_encode(key))
print("是编码键:", Path.is_encoded_key(safe))
```

## 9. 性能优化

### 9.1 缓存策略

- 使用 basic_cache 插件减少后端访问
- 合理设置 TTL 避免内存占用过大
- write_through 确保数据一致性

### 9.2 写入优化

- 配置 flush_delay 合并多次写入
- 使用 namespace_keys 批量操作
- 避免频繁的小数据写入

### 9.3 查询优化

- 使用 query() 方法避免多次 get
- 利用事件系统监听变化而非轮询
- 批量解码减少重复计算

## 10. 版本历史

### v1.0.0
- 初始版本发布
- 基础 CRUD 功能
- JSON 存储后端
- 插件系统框架

### v1.1.0
- 添加事件系统
- 实现自动编码
- 新增项目查询插件
- 新增项目删除插件

### v1.2.0
- 优化自动编码算法
- 添加内存后端
- 改进错误处理
- 完善插件生命周期

## 11. 贡献指南

欢迎提交 Pull Request 或 Issue。请确保：

1. 代码符合 Lua 最佳实践
2. 添加适当的注释和文档
3. 包含单元测试（如适用）
4. 更新版本历史和文档

---

**文档版本**: 1.2.0
**最后更新**: 2024-01-XX
