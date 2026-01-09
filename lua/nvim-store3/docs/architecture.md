# 🌟 nvim-store3 — A Professional Persistent Storage Framework for Neovim

**nvim-store3** 是一个为 Neovim 插件生态设计的 **专业级持久化存储框架**。
它提供：

- 透明的键名自动编码
- 可插拔的存储后端（JSON / Memory / 可扩展 SQLite）
- 内存缓存层
- 插件系统（basic_cache / extmarks / 自定义插件）
- 点号路径查询
- 命名空间管理
- 事件系统（on/emit）
- 项目级 / 全局级存储隔离

它的目标是成为 **Neovim 插件的数据层标准**。

---

# ✨ 特性一览

| 功能 | 描述 |
|------|------|
| **自动编码（auto_encode）** | 支持中文、空格、`.`、`/` 等任意键名 |
| **插件系统（plugins）** | basic_cache、extmarks、notes、marks 等可扩展 |
| **多后端支持** | JSON（默认）、Memory（测试用）、未来可扩展 SQLite |
| **项目级 / 全局级存储** | 自动区分不同项目的数据 |
| **事件系统** | `store:on("set", ...)`、`store:on("flush", ...)` |
| **点号路径查询** | `store:query("notes.today.1")` |
| **命名空间管理** | `store:namespace_keys("notes")` |
| **自动 flush** | 退出 Neovim 时自动写入磁盘 |
| **原子写入 + 备份恢复** | 防止 JSON 文件损坏 |

---

# 📦 安装

使用 lazy.nvim：

```lua
{
    "yourname/nvim-store3",
    config = function()
        -- 可选：初始化全局存储
        require("nvim-store3").global()
    end
}
```

---

# 🚀 快速开始

## 获取全局存储

```lua
local store = require("nvim-store3").global()
store:set("username", "佳")
print(store:get("username"))
```

## 获取项目存储

```lua
local project = require("nvim-store3").project()
project:set("todo.1", "Implement mark system")
```

---

# 🔧 配置（专业版）

nvim-store3 使用统一的配置结构：

```lua
local store = require("nvim-store3").global({
    auto_encode = true,

    storage = {
        backend = "json",
        flush_delay = 1000,
    },

    plugins = {
        basic_cache = true,
        extmarks = {
            persist_extmarks = true,
        },
    },
})
```

---

# 🧩 插件系统（Plugins）

插件全部放在：

```lua
plugins = { ... }
```

示例：

```lua
plugins = {
    basic_cache = true,
    extmarks = { persist_extmarks = true },

    -- 自定义插件
    notes = "myplugin.notes",
}
```

## 注册自定义插件

```lua
require("nvim-store3").register_plugin("notes", "myplugin.notes")
```

插件模块结构：

```lua
local M = {}

function M.new(store, config)
    return setmetatable({
        store = store,
        config = config,
    }, { __index = M })
end

return M
```

---

# 🧠 自动编码（auto_encode）

nvim-store3 支持任意键名，包括：

- 中文
- 空格
- 点号 `.`
- 路径 `/`
- 特殊字符

示例：

```lua
store:set("今日.任务/重要", "写代码")
```

内部会自动编码为安全的 Base64 格式：

```
b64:xxxxxx_hash
```

但对用户完全透明。

---

# 🔍 点号路径查询

```lua
store:set("notes.today.1", "Fix bug")
store:set("notes.today.2", "Write README")

print(store:query("notes.today.1"))
```

---

# 🗂 命名空间管理

```lua
store:set("notes.1", "A")
store:set("notes.2", "B")

local keys = store:namespace_keys("notes")
-- { "1", "2" }
```

---

# ⚡ 事件系统（专业版）

你可以监听存储事件：

```lua
store:on("set", function(ev)
    print("Key updated:", ev.key)
end)

store:on("flush", function(ev)
    print("Flushed:", ev.ok)
end)
```

事件类型：

| 事件 | 说明 |
|------|------|
| `set` | 写入键值 |
| `delete` | 删除键 |
| `flush` | 写入磁盘 |
| 插件可扩展 | notes_update / mark_changed 等 |

---

# 💾 存储后端

## JSON 后端（默认）

- 原子写入（tmp + rename）
- 自动备份 `.backup`
- flush_delay 防抖写入
- 写锁 + pending queue 防止并发写入

## Memory 后端（测试用）

```lua
storage = { backend = "memory" }
```

---

# 🧱 架构图

```
┌──────────────────────────────┐
│         nvim-store3          │
├──────────────────────────────┤
│ init.lua (入口)              │
│   ├─ global()                │
│   ├─ project()               │
│   └─ register_plugin()       │
├──────────────────────────────┤
│ core/store.lua               │
│   ├─ CRUD                    │
│   ├─ auto_encode             │
│   ├─ events (on/emit)        │
│   ├─ namespace_keys          │
│   └─ plugin_loader           │
├──────────────────────────────┤
│ core/plugin_loader.lua       │
│   ├─ registry                │
│   ├─ load_plugins()          │
│   └─ load_plugin()           │
├──────────────────────────────┤
│ storage/                     │
│   ├─ json_backend            │
│   └─ memory_backend          │
├──────────────────────────────┤
│ features/                    │
│   ├─ basic_cache             │
│   └─ extmarks                │
└──────────────────────────────┘
```

---

# 🧩 开发自定义插件

插件可以：

- 访问 store API
- 监听事件
- 持久化自己的数据
- 提供自己的命名空间

示例：

```lua
local M = {}

function M.new(store, config)
    local self = setmetatable({
        store = store,
        config = config,
    }, { __index = M })

    store:on("set", function(ev)
        print("Plugin saw set:", ev.key)
    end)

    return self
end

return M
```

---

# 🛣 Roadmap

- [ ] SQLite 后端
- [ ] notes 插件（带标签、搜索）
- [ ] marks 插件（AST anchor + extmarks）
- [ ] symbol_index 插件（增量索引）
- [ ] UI 面板（Telescope / FZF）
- [ ] 自动迁移工具（store2 → store3）

---

# 📜 License
