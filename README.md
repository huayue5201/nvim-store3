> Neovim 持久化存储解决方案 - 让插件数据跨会话持久化

[![Lua](https://img.shields.io/badge/Lua-5.1-blue.svg)](https://www.lua.org/)
[![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg)](https://neovim.io/)
[![License](https://img.shields.io/badge/License-MIT-red.svg)](LICENSE)

nvim-store3 是一个专为 Neovim 设计的持久化存储方案，提供跨会话的数据持久化、事件驱动、自动编码和智能项目识别功能。

## ✨ 特性

- 🎯 **双作用域存储** - 全局存储和项目级存储，数据自动隔离
- 🧠 **智能项目识别** - 自动识别项目根目录，避免污染系统目录
- 🔌 **插件化架构** - 支持动态加载插件，插件直接挂载到 store 实例
- 📡 **事件驱动** - 内置事件系统，支持数据变更监听
- 🔐 **自动编码** - 智能键名编码，确保文件系统兼容性
- 💾 **原子写入** - JSON 后端支持原子写入和自动备份
- 🧹 **智能清理** - 自动清理空项目、过期项目，磁盘空间不足时自动限制数量

## 📦 安装

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nvim-store3",
  config = function()
    -- 可选：自定义清理配置
    require("nvim-store3").setup_cleanup({
      enabled = true,
      max_age_days = 90,        -- 90天未访问清理
      max_count = 50,           -- 最多保留50个项目
      min_free_space_mb = 100,  -- 磁盘低于100MB时限制数量
      check_interval_hours = 24 -- 每天检查一次
    })
  end
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nvim-store3",
  config = function()
    require("nvim-store3").setup_cleanup()
  end
}
```

## 🚀 快速开始

### 基础使用

```lua
-- 获取全局存储实例
local store = require("nvim-store3").global()

-- 存储数据
store:set("theme", "dark")
store:set("last_session", { file = "main.lua", line = 42 })

-- 读取数据
local theme = store:get("theme")  -- "dark"
local session = store:get("last_session")  -- { file = "main.lua", line = 42 }

-- 删除数据
store:delete("theme")

-- 持久化到磁盘
store:flush()
```

### 项目存储

```lua
-- 项目存储会自动识别当前项目的根目录
local project = require("nvim-store3").project()

-- 存储项目特定数据
project:set("bookmarks", {
  { file = "src/main.lua", line = 10 },
  { file = "src/utils.lua", line = 25 }
})
```

### 使用命名空间组织数据

```lua
-- 使用点号分隔的键来组织数据
store:set("notes.today.1", { title = "Meeting notes", content = "..." })
store:set("notes.today.2", { title = "TODO list", content = "..." })
store:set("config.editor", { theme = "dark", font_size = 14 })

-- 获取特定命名空间下的所有键
local notes = store:namespace_keys("notes")  -- {"today.1", "today.2"}

-- 路径查询
local note = store:query("notes.today.1")  -- { title = "Meeting notes", ... }
```

## 📖 核心 API

### Store 实例方法

| 方法 | 描述 | 示例 |
|------|------|------|
| `:set(key, value)` | 存储数据 | `store:set("name", "value")` |
| `:get(key)` | 获取数据 | `local val = store:get("name")` |
| `:delete(key)` | 删除数据 | `store:delete("name")` |
| `:keys()` | 获取所有键 | `local keys = store:keys()` |
| `:namespace_keys(ns)` | 获取命名空间下的键 | `store:namespace_keys("notes")` |
| `:query(path)` | 路径查询（支持嵌套） | `store:query("notes.today.1")` |
| `:flush()` | 持久化到磁盘 | `store:flush()` |
| `:on(event, callback)` | 订阅事件 | `store:on("set", fn)` |
| `:get_stats()` | 获取统计信息 | `local stats = store:get_stats()` |
| `:set_auto_encode(bool)` | 设置自动编码 | `store:set_auto_encode(true)` |

### 事件系统

```lua
-- 监听数据变化
store:on("set", function(payload)
  print("数据已设置:", payload.key, payload.value)
end)

store:on("delete", function(payload)
  print("数据已删除:", payload.key)
end)

store:on("flush", function(payload)
  if payload.ok then
    print("数据已持久化")
  end
end)
```

### 存储统计

```lua
local stats = store:get_stats()
print("总键数:", stats.total_keys)
print("编码键数:", stats.encoded_keys)
print("缓存大小:", stats.cache_size)
print("估算大小:", stats.estimated_size, "bytes")
print("作用域:", stats.scope)
print("空操作模式:", stats.noop)  -- 系统目录时为 true
```

## 🎮 命令

安装插件后自动提供以下 Neovim 命令：

| 命令 | 描述 | 来源 |
|------|------|------|
| `:Store` | 交互式查看项目数据 | project_query 插件 |
| `:StoreDelete [namespace]` | 删除命名空间数据 | project_delete 插件 |

## ⚙️ 配置

### 存储配置

```lua
-- 全局存储配置
local store = require("nvim-store3").global({
  auto_encode = true,  -- 自动编码键名
  storage = {
    backend = "json",
    flush_delay = 1000,  -- 延迟保存（毫秒）
  },
  plugins = {
    basic_cache = {
      default_ttl = 300,
      write_through = true,
      read_through = true,
    }
  }
})
```

### 清理系统配置

```lua
local Cleanup = require("nvim-store3.core.cleanup")

-- 自定义清理配置
Cleanup.setup({
  enabled = true,              -- 是否启用自动清理
  max_age_days = 90,           -- 90天未访问的项目清理
  max_count = 50,              -- 最多保留50个项目
  min_free_space_mb = 100,     -- 磁盘低于100MB时限制数量
  check_interval_hours = 24,   -- 每天检查一次
})

-- 或通过 init.lua 快捷函数
require("nvim-store3").setup_cleanup({
  max_age_days = 60,
  max_count = 30,
})
```

## 🔌 内置插件

### Basic Cache - LRU 缓存插件

```lua
-- 启用缓存插件
local store = require("nvim-store3").global({
  plugins = { basic_cache = true }
})

local cache = store.basic_cache

-- 设置缓存（可选 TTL）
cache:set("key", "value", 300)  -- 5分钟后过期

-- 获取缓存
local value = cache:get("key")

-- 删除缓存
cache:delete("key")

-- 清理过期项
cache:cleanup_expired()

-- 获取统计
local stats = cache:get_stats()  -- { enabled = true, size = 10 }
```

**缓存特性**：
- LRU 淘汰策略
- TTL 过期机制
- write-through / read-through 模式
- 自动清理定时器

### Project Query - 项目查询插件

```lua
local store = require("nvim-store3").project({
  plugins = { project_query = true }
})

local query = store.project_query

-- 获取所有命名空间
local namespaces = query:get_namespaces()

-- 显示格式化的 JSON 浮窗
query:show_json("notes")

-- 交互式选择命名空间
query:select_namespace()
```

### Project Delete - 项目删除插件

```lua
local store = require("nvim-store3").project({
  plugins = { project_delete = true }
})

local deleter = store.project_delete

-- 获取命名空间列表
local namespaces = deleter:get_namespaces()

-- 删除命名空间（交互式确认）
deleter:delete_namespace("notes")

-- 交互式选择删除
deleter:select_and_delete()
```

## 🧩 开发插件

### 插件基本结构

```lua
-- plugins/my_plugin.lua
local M = {}

function M.new(store, config)
  local self = {
    store = store,
    config = config or {},
  }

  setmetatable(self, { __index = M })

  -- 空操作实例检查（系统目录时静默返回）
  if store._noop then
    return self
  end

  -- 监听事件
  store:on("set", function(payload)
    self:on_data_change(payload)
  end)

  return self
end

function M:on_data_change(payload)
  -- 处理数据变化
  print("数据已变更:", payload.key)
end

function M:my_method()
  return self.store:get("some_key")
end

function M:cleanup()
  -- 清理资源（卸载时调用）
  self.store:flush()
end

return M
```

### 注册并使用插件

```lua
-- 注册插件
require("nvim-store3").register_plugin("my_plugin", "path.to.my_plugin")

-- 启用插件
local store = require("nvim-store3").global({
  plugins = {
    my_plugin = { enabled = true, custom_option = "value" }
  }
})

-- 使用插件（直接访问）
store.my_plugin:my_method()
```

## 🗂️ 存储结构

```
~/.cache/nvim-store/
├── global/                          # 全局存储
│   └── data.json
├── home_user_projects_myapp/        # 项目 A（基于项目根目录）
│   └── data.json
├── home_user_projects_another/      # 项目 B
│   └── data.json
└── ...
```

**项目识别规则**：
- 向上查找项目标志（.git, package.json, Makefile 等）
- 系统目录黑名单（/etc, /var, /tmp 等）不创建存储
- 同一项目无论从哪个子目录进入，使用同一个存储

## 🧹 智能清理策略

nvim-store3 内置智能清理机制，自动管理项目存储：

| 优先级 | 策略 | 条件 | 说明 |
|--------|------|------|------|
| 1 | 清理空项目 | 无条件 | data.json 为 {} 的项目最先清理 |
| 2 | 清理过期项目 | 超过配置天数未访问 | 默认 90 天，可配置 |
| 3 | 限制数量 | 磁盘空间低于阈值 | 默认 100MB，删除最旧的项目 |

清理时会有通知提示，让用户了解清理情况。

## 🎯 最佳实践

### 1. 数据组织

```lua
-- ✅ 使用命名空间
store:set("bookmarks.lua", { line = 10, file = "main.lua" })
store:set("bookmarks.python", { line = 20, file = "app.py" })

-- ✅ 使用嵌套结构
store:set("config.editor", { theme = "dark", font_size = 14 })
store:set("config.lsp", { enabled = true, servers = { "lua_ls" } })
```

### 2. 性能优化

```lua
-- 使用缓存减少磁盘访问
local store = require("nvim-store3").global({
  plugins = { basic_cache = { default_ttl = 60 } }
})

-- 批量读取使用 namespace_keys
local bookmarks = {}
for _, key in ipairs(store:namespace_keys("bookmarks")) do
  bookmarks[key] = store:get("bookmarks." .. key)
end
```

### 3. 事件监听

```lua
-- 自动保存数据变更日志
store:on("set", function(payload)
  vim.notify(string.format("[Store] %s = %s", payload.key, vim.inspect(payload.value)))
end)
```

## 🐛 故障排除

### 数据保存失败

```lua
-- 检查路径
local Path = require("nvim-store3.util.path")
print("Global path:", Path.global_store_path())
print("Project path:", Path.project_store_path())

-- 手动触发保存
store:flush()
```

### 项目识别问题

```lua
-- 调试项目根目录
local Path = require("nvim-store3.util.path")
print("Project root:", Path.project_root())
print("Project key:", Path.project_key())
```

### 清理统计

```lua
local Cleanup = require("nvim-store3.core.cleanup")
local stats = Cleanup.get_stats()
print(string.format("项目总数: %d, 总大小: %.2f MB",
  stats.total_projects, stats.total_size_mb))
print(string.format("空项目: %d, 过期项目: %d",
  stats.empty_projects, stats.expired_projects))
print(string.format("磁盘剩余: %.2f MB", stats.free_space_mb))
```

## 📄 许可证

MIT License © nvim-store3 Team
