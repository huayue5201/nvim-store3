```markdown
# nvim-store3 技术说明文档

## 1. 项目概述

nvim-store3 是一个专为 Neovim 设计的专业级持久化存储解决方案，提供跨会话的数据持久化、事件驱动的插件系统、自动编码机制和智能项目识别功能。

### 1.1 核心特性

- **双作用域存储**：支持全局存储和项目级存储
- **智能项目识别**：自动识别真实项目目录，避免污染系统目录
- **插件化架构**：可插拔的插件系统，支持动态加载和卸载
- **事件驱动**：内置事件系统，支持数据变更监听
- **自动编码**：智能键名编码，确保文件系统兼容性
- **原子写入**：JSON 存储后端支持原子写入和自动备份
- **自动清理**：定期清理空项目、过期项目，控制存储数量

## 2. 系统架构

### 2.1 架构图

```
┌─────────────────────────────────────────────────────────┐
│                    nvim-store3                           │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │   Global    │  │   Project   │  │    Plugins      │ │
│  │    Store    │  │    Store    │  │     System      │ │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘ │
│         │                │                   │          │
│  ┌──────┴────────────────┴───────────────────┴──────┐  │
│  │                   Core Store                      │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │  │
│  │  │  Data    │  │  Events  │  │   Plugin     │   │  │
│  │  │  Cache   │  │  System  │  │   Loader     │   │  │
│  │  └──────────┘  └──────────┘  └──────────────┘   │  │
│  └──────────────────────────────────────────────────┘  │
│                           │                            │
│  ┌────────────────────────────────────────────────┐   │
│  │            Storage Backends                     │   │
│  │  ┌────────────────┐  ┌────────────────────┐   │   │
│  │  │  JSON Backend  │  │   Memory Backend   │   │   │
│  │  └────────────────┘  └────────────────────┘   │   │
│  └────────────────────────────────────────────────┘   │
│                           │                            │
│  ┌────────────────────────────────────────────────┐   │
│  │           Auto Cleanup System                   │   │
│  │  - Empty Projects    - Expired Projects        │   │
│  │  - Count Limit       - Interactive Cleanup     │   │
│  └────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 核心模块职责

| 模块 | 路径 | 职责 |
|------|------|------|
| Store | `core/store.lua` | 核心存储逻辑，CRUD 操作，事件管理，空操作实例 |
| Plugin Loader | `core/plugin_loader.lua` | 插件动态加载和管理 |
| Backend Factory | `storage/backend_factory.lua` | 存储后端工厂模式管理 |
| JSON Backend | `storage/json_backend.lua` | JSON 文件持久化，原子写入 |
| Cleanup | `core/cleanup.lua` | 自动清理空项目、过期项目、数量限制 |
| Event System | `util/event.lua` | 事件发布/订阅 |
| Path Utils | `util/path.lua` | 智能项目识别、键名编码、路径管理 |
| JSON Utils | `util/json.lua` | JSON 读写和原子操作 |

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

-- 项目存储（自动识别项目根目录）
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

#### 统计信息

```lua
-- 获取存储统计
local stats = store:get_stats()
print("总键数:", stats.total_keys)
print("编码键数:", stats.encoded_keys)
print("缓存大小:", stats.cache_size)
print("是否空操作:", stats.noop)  -- 系统目录时为 true
```

### 3.2 清理系统 API

```lua
local Cleanup = require("nvim-store3.core.cleanup")

-- 清理空项目
Cleanup.cleanup_empty()

-- 清理过期项目（默认30天）
Cleanup.cleanup_expired(30)

-- 限制项目数量（默认100个）
Cleanup.limit_count(100)

-- 获取统计信息
local stats = Cleanup.get_stats()
print("项目总数:", stats.total_projects)
print("空项目数:", stats.empty_projects)
print("总大小:", stats.total_size_mb, "MB")

-- 交互式清理
Cleanup.select_and_cleanup()
```

### 3.3 插件系统 API

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

### 3.4 插件开发规范

#### 插件基本结构

```lua
-- my_plugin.lua
local M = {}

function M.new(store, config)
  local self = {
    store = store,
    config = config or {},
  }

  setmetatable(self, { __index = M })

  -- 监听空操作实例（可选）
  if not store._noop then
    self:_init()
  end

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
  if self.store._noop then return end  -- 空操作实例静默返回
  -- 实现功能
end

-- 可选的清理方法（卸载时调用）
function M:cleanup()
  -- 清理资源
end

return M
```

### 3.5 内置插件说明

#### Basic Cache（基础缓存插件）

提供 LRU 缓存和 TTL 过期机制。

```lua
-- 配置
{
  enabled = true,           -- 是否启用
  default_ttl = 300,        -- 默认过期时间（秒）
  write_through = true,     -- 是否同步写入存储
  read_through = true,      -- 是否缓存读取
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
query:get_namespaces_with_counts()   -- 获取带计数的命名空间
query:show_json(namespace)           -- 显示格式化的 JSON
```

#### Project Delete（项目删除插件）

提供安全的数据删除功能。

```lua
-- 使用
:StoreDelete [namespace]  -- 删除指定命名空间（交互式或直接）

-- API
deleter:get_namespaces()               -- 获取命名空间列表
deleter:delete_namespace(namespace)    -- 删除命名空间
deleter:select_and_delete()            -- 交互式选择删除
```

## 4. 存储后端

### 4.1 JSON Backend

```lua
-- 配置
{
  path = "/path/to/data.json",  -- 存储路径
  flush_delay = 1000,           -- 延迟保存（毫秒）
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

-- 智能项目根目录识别
local root = Path.project_root()  -- 返回项目根目录或 nil
print(root)  -- /home/user/projects/myapp

-- 键名编码
local safe = Path.encode_key("file/name")  -- "b64:ZmlsZS9uYW1l_..."
local original = Path.decode_key(safe)     -- "file/name"

-- 路径获取
local store_path = Path.project_store_path()  -- 项目存储路径
local global_path = Path.global_store_path()  -- 全局存储路径

-- 清理功能
Path.cleanup_empty_stores()       -- 清理空项目
Path.cleanup_expired_stores(30)   -- 清理30天以上项目
Path.limit_project_count(100)     -- 限制100个项目
Path.select_and_cleanup()         -- 交互式清理
Path.get_store_stats()            -- 获取存储统计
```

**智能项目识别规则：**
- 向上查找项目标志（.git, package.json 等）
- 系统目录黑名单（/etc, /var, /tmp 等）
- 用户根目录不创建存储
- 同一项目无论从哪个子目录进入，使用同一个存储文件

**编码规则：**
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

### 6.1 基础配置

```lua
-- ~/.config/nvim/init.lua
require("nvim-store3").setup()  -- 自动启动清理
```

### 6.2 完整使用示例

```lua
-- ~/.config/nvim/lua/plugins/nvim-store3.lua
return {
  "nvim-store3",
  config = function()
    local store = require("nvim-store3")

    -- 全局存储（跨项目共享）
    store.global({
      auto_encode = true,
      plugins = {
        basic_cache = true,
      }
    })

    -- 项目存储（当前项目隔离）
    local project = store.project({
      plugins = {
        project_query = true,
        project_delete = true,
      }
    })

    -- 使用项目存储
    project:set("notes.today", { title = "今日笔记", content = "..." })

    -- 查询数据
    local notes = project:namespace_keys("notes")
    print("笔记数量:", #notes)
  end
}
```

### 6.3 命令参考

| 命令 | 描述 |
|------|------|
| `:Store` | 交互式查看项目数据 |
| `:StoreDelete [namespace]` | 删除命名空间数据 |
| `:StoreCleanup` | 交互式清理项目存储 |
| `:StoreCleanup empty` | 清理空项目 |
| `:StoreCleanup expired` | 清理过期项目（>30天） |
| `:StoreCleanup limit` | 限制项目数量（保留100个） |
| `:StoreCleanup stats` | 查看存储统计 |
| `:StoreInfo` | 显示当前存储信息 |

## 7. 最佳实践

### 7.1 数据组织

```lua
-- 使用命名空间组织数据
store:set("notes.today.1", { title = "今日笔记", content = "..." })
store:set("notes.today.2", { title = "明日计划", content = "..." })
store:set("config.editor", { theme = "dark", font_size = 14 })

-- 查询特定命名空间
local notes = store:namespace_keys("notes")  -- {"today.1", "today.2"}

-- 路径查询
local note = store:query("notes.today.1")  -- { title = "...", content = "..." }
```

### 7.2 事件监听示例

```lua
-- 数据变更监控
store:on("set", function(payload)
  if payload.key:match("^notes%.") then
    print("笔记已更新:", payload.key)
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

  -- 空操作实例检查
  if store._noop then
    return self
  end

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
  if not self.store._noop then
    self.store:set("__counter", self.counts)
  end
end

return M
```

## 8. 故障排除

### 8.1 常见问题

**Q: 数据保存失败**
```
可能原因：目录权限不足、磁盘空间不足
解决方案：检查 ~/.cache/nvim-store/ 目录权限
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

**Q: 系统目录也创建了存储**
```
可能原因：项目识别配置问题
解决方案：检查 PROJECT_MARKERS 和 SYSTEM_DIRS 配置
```

**Q: 同一项目有多个存储文件**
```
可能原因：从不同子目录进入
解决方案：使用智能项目识别，基于项目根目录生成存储键
```

### 8.2 调试工具

```lua
-- 获取存储统计
local stats = store:get_stats()
print("总键数:", stats.total_keys)
print("编码键数:", stats.encoded_keys)
print("缓存大小:", stats.cache_size)
print("是否空操作:", stats.noop)

-- 检查项目识别
local Path = require("nvim-store3.util.path")
print("项目根目录:", Path.project_root())
print("项目存储路径:", Path.project_store_path())

-- 查看清理统计
local Cleanup = require("nvim-store3.core.cleanup")
local stats = Cleanup.get_stats()
print("项目总数:", stats.total_projects)
print("总大小:", stats.total_size_mb, "MB")
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

### 9.4 存储优化

- 自动清理空项目（减少磁盘占用）
- 自动清理过期项目（>30天）
- 限制项目数量（最多100个）
- 系统目录不创建存储（空操作实例）

## 10. 存储路径说明

```
~/.cache/nvim-store/
├── global/                          # 全局存储
│   └── data.json
├── home_user_projects_myapp/        # 项目存储（基于项目根目录）
│   └── data.json
├── home_user_projects_another/      # 另一个项目
│   └── data.json
└── ... (最多保留100个项目)
```

**项目识别规则：**
- 向上查找 .git、package.json 等项目标志
- 同一项目无论从哪个子目录进入，使用同一个存储
- 系统目录和用户根目录不创建存储

## 11. 版本历史

### v1.2.0 (当前版本)
- 智能项目识别：自动识别真实项目目录
- 统一项目存储：基于项目根目录生成存储键
- 空操作实例：系统目录静默失败
- 自动清理系统：定期清理空项目、过期项目
- 清理命令：交互式和命令行清理
- 性能优化：路径缓存、延迟清理
- 代码精简：移除冗余代码和未使用参数

### v1.1.0
- 添加事件系统
- 实现自动编码
- 新增项目查询插件
- 新增项目删除插件

### v1.0.0
- 初始版本发布
- 基础 CRUD 功能
- JSON 存储后端
- 插件系统框架

## 12. 贡献指南

欢迎提交 Pull Request 或 Issue。请确保：

1. 代码符合 Lua 最佳实践
2. 添加适当的注释和文档
3. 包含单元测试（如适用）
4. 更新版本历史和文档

---

**文档版本**: 1.2.0
**最后更新**: 2024-03-28
**维护者**: nvim-store3 Team
