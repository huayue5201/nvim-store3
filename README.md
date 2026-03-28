> Neovim 持久化存储解决方案 - 让插件数据跨会话持久化

[![Lua](https://img.shields.io/badge/Lua-5.1-blue.svg)](https://www.lua.org/)
[![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg)](https://neovim.io/)
[![License](https://img.shields.io/badge/License-MIT-red.svg)](LICENSE)

nvim-store3 是一个专为 Neovim 设计的专业级持久化存储方案，提供跨会话的数据持久化、事件驱动的插件系统、自动编码机制和智能项目识别功能。

## ✨ 特性

- 🎯 **双作用域存储** - 支持全局存储和项目级存储，数据自动隔离
- 🧠 **智能项目识别** - 自动识别真实项目目录，避免污染系统目录
- 🔌 **插件化架构** - 可插拔的插件系统，支持动态加载和卸载
- 📡 **事件驱动** - 内置事件系统，支持数据变更监听
- 🔐 **自动编码** - 智能键名编码，确保文件系统兼容性
- 💾 **原子写入** - JSON 存储后端支持原子写入和自动备份
- 🧹 **自动清理** - 定期清理空项目、过期项目，控制存储数量

## 📦 安装

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nvim-store3",
  config = function()
    require("nvim-store3").setup()
  end
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nvim-store3",
  config = function()
    require("nvim-store3").setup()
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

-- 获取所有书签
local bookmarks = project:get("bookmarks")
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

## 🎮 命令

安装后自动提供以下 Neovim 命令：

| 命令 | 描述 |
|------|------|
| `:Store` | 交互式查看项目数据 |
| `:StoreDelete [namespace]` | 删除指定命名空间的数据 |
| `:StoreCleanup` | 交互式清理项目存储 |
| `:StoreCleanup empty` | 清理所有空项目 |
| `:StoreCleanup expired` | 清理超过30天的项目 |
| `:StoreCleanup limit` | 限制项目数量（保留100个） |
| `:StoreCleanup stats` | 查看存储统计信息 |
| `:StoreInfo` | 显示当前存储信息 |

## ⚙️ 配置

### 基础配置

```lua
require("nvim-store3").setup({
  auto_cleanup = true,      -- 自动清理（默认启用）
  cleanup_interval = 3600,  -- 清理间隔（秒），默认1小时
  max_projects = 100,       -- 最大项目数量
  expire_days = 30,         -- 项目过期天数
})
```

### 自定义存储路径

```lua
-- 修改全局存储路径
require("nvim-store3").setup({
  global_path = vim.fn.stdpath("data") .. "/my-store",
  project_path = vim.fn.stdpath("data") .. "/projects",
})
```

### 插件配置

```lua
-- 启用内置插件
local store = require("nvim-store3").global({
  plugins = {
    basic_cache = true,     -- 启用 LRU 缓存
    project_query = true,   -- 启用查询功能
    project_delete = true,  -- 启用删除功能
  }
})

-- 配置缓存插件
local store = require("nvim-store3").global({
  plugins = {
    basic_cache = {
      default_ttl = 600,    -- 默认缓存10分钟
      write_through = true, -- 同步写入存储
      read_through = true,  -- 缓存读取
    }
  }
})
```

## 🔌 内置插件

### Basic Cache - LRU 缓存插件

提供内存缓存，减少磁盘访问：

```lua
local cache = store:get_plugin("basic_cache")

-- 设置缓存（TTL 可选）
cache:set("key", "value", 300)  -- 5分钟过期

-- 获取缓存
local value = cache:get("key")

-- 清理过期项
cache:cleanup_expired()
```

### Project Query - 项目查询插件

提供格式化的数据查看：

```lua
local query = store:get_plugin("project_query")

-- 获取所有命名空间
local namespaces = query:get_namespaces()

-- 显示格式化的 JSON
query:show_json("notes")
```

### Project Delete - 项目删除插件

安全地删除数据：

```lua
local deleter = store:get_plugin("project_delete")

-- 删除命名空间
deleter:delete_namespace("notes")

-- 交互式选择删除
deleter:select_and_delete()
```

## 🧩 开发插件

创建自定义插件非常简单：

```lua
-- plugins/my_plugin.lua
local M = {}

function M.new(store, config)
  local self = {
    store = store,
    config = config or {},
  }

  setmetatable(self, { __index = M })

  -- 监听事件
  store:on("set", function(payload)
    print("数据变化:", payload.key)
  end)

  return self
end

function M:my_method()
  return self.store:get("some_key")
end

function M:cleanup()
  -- 清理资源
end

return M
```

注册并使用插件：

```lua
-- 注册插件
require("nvim-store3").register_plugin("my_plugin", "path.to.my_plugin")

-- 启用插件
local store = require("nvim-store3").global({
  plugins = {
    my_plugin = { enabled = true }
  }
})

-- 使用插件
local plugin = store:get_plugin("my_plugin")
plugin:my_method()
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
└── ... (最多保留100个项目)
```

## 🎯 最佳实践

### 1. 合理组织数据结构

```lua
-- ✅ 好的实践：使用命名空间
store:set("bookmarks.lua", { line = 10, file = "main.lua" })
store:set("bookmarks.python", { line = 20, file = "app.py" })

-- ❌ 避免：扁平的键名
store:set("bookmark1", ...)
store:set("bookmark2", ...)
```

### 2. 使用事件监听实现响应式

```lua
-- 自动保存书签变化
store:on("set", function(payload)
  if payload.key:match("^bookmarks%.") then
    vim.notify("Bookmark updated: " .. payload.key)
  end
end)
```

### 3. 合理使用缓存

```lua
-- 对于频繁读取的数据使用缓存插件
local cache = store:get_plugin("basic_cache")
cache:set("frequent_data", data, 60)  -- 缓存1分钟
```

## 🐛 故障排除

### 数据保存失败
```bash
# 检查目录权限
ls -la ~/.cache/nvim-store/

# 手动创建目录
mkdir -p ~/.cache/nvim-store
```

### 插件加载失败
```lua
-- 检查插件是否注册
local registry = require("nvim-store3.core.plugin_loader").registry
print(vim.inspect(registry))
```

### 项目识别不正确
```lua
-- 调试项目根目录
local Path = require("nvim-store3.util.path")
print("Project root:", Path.project_root())
print("Store path:", Path.project_store_path())
```

## 📊 性能优化

- 使用 `basic_cache` 插件减少磁盘访问
- 配置 `flush_delay` 合并多次写入
- 使用 `namespace_keys` 批量操作
- 利用事件系统而非轮询

## 🤝 贡献

欢迎提交 Pull Request 或 Issue！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing`)
5. 创建 Pull Request

## 📄 许可证

MIT License © nvim-store3 Team
