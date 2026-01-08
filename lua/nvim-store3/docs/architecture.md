# 🏛️ nvim-store3 Architecture Guide
**Neovim Plugin Data Persistence Framework — Developer Documentation**

---

# 1. Overview（架构总览）

nvim-store3 是一个 **模块化、可扩展、可测试** 的 Neovim 数据持久化框架。
它的核心目标是：

- 为插件作者提供 **统一的数据存储 API**
- 支持 **全局 / 项目级作用域**
- 提供 **可插拔的功能模块（Feature System）**
- 提供 **可替换的存储后端（Backend System）**
- 提供 **事件系统、缓存系统、路径编码系统**

整体架构如下：

```
┌──────────────────────────────────────────────┐
│                  nvim-store3                 │
├──────────────────────────────────────────────┤
│  init.lua (global/project factory)           │
├──────────────────────────────────────────────┤
│  core/                                       │
│    store.lua          ← Store 实例           │
│    feature_manager.lua ← 动态加载 Feature    │
├──────────────────────────────────────────────┤
│  storage/                                    │
│    backend_factory.lua                       │
│    json_backend.lua                          │
│    memory_backend.lua                        │
├──────────────────────────────────────────────┤
│  features/                                   │
│    notes/                                    │
│    buffer_cache/                             │
│    extmarks/                                 │
│    semantic/                                 │
│    ...                                       │
├──────────────────────────────────────────────┤
│  util/                                       │
│    path_key.lua                              │
│    json.lua                                  │
│    event.lua                                 │
│    query.lua                                 │
│    id.lua                                    │
└──────────────────────────────────────────────┘
```

---

# 2. Store Architecture（Store 架构）

Store 是整个框架的核心。

## 2.1 Store 的职责

Store 负责：

- 管理存储后端（backend）
- 管理功能模块（features）
- 提供 CRUD API
- 提供点号路径查询
- 提供自动 flush
- 提供作用域隔离（global / project）

Store **不负责业务逻辑**，所有业务逻辑都在 Feature 中实现。

## 2.2 Store 的生命周期

```
Store.new(config)
 ├─ _init_backend()
 ├─ _init_features()
 ├─ _setup_autocmd()  ← VimLeavePre 自动 flush
 └─ ready
```

Store 是一个 **长生命周期单例**：

- `Store.global()` → 全局单例
- `Store.project()` → 项目单例

---

# 3. Backend Architecture（后端架构）

后端是可替换的，所有后端必须实现统一接口：

```
load()
get(namespace, key)
set(namespace, key, value)
delete(namespace, key)
keys(namespace)
flush()
```

## 3.1 JSON Backend

特点：

- 扁平 key-value
- 原子写入
- flush_delay（延迟写入）
- 自动创建目录

适合：

- 小规模数据
- 插件配置
- 笔记、断点、缓存等

## 3.2 Memory Backend

特点：

- 不写入磁盘
- 用于测试

## 3.3 BackendFactory

负责：

- 注册 backend
- 创建 backend 实例

插件作者可以注册自己的后端：

```lua
BackendFactory.register("sqlite", function(config)
  return SqliteBackend.new(config)
end)
```

---

# 4. Feature Architecture（功能模块架构）

Feature 是 nvim-store3 的扩展机制。

每个 Feature 是一个独立模块，具有：

- 独立的配置
- 独立的生命周期
- 独立的 API（挂载到 Store 上）
- 可选的自动命令
- 可选的事件系统

## 4.1 FeatureManager

负责：

- 动态加载 feature
- 校验配置
- enable / disable
- reload

加载流程：

```
config = {
  notes = { auto_setup = true },
  buffer_cache = { ttl = 300 },
}

Store.new(config)
 └─ feature_manager:enable("notes", config.notes)
       └─ require("features.notes.manager").new(store, config)
```

## 4.2 Feature 的结构

以 notes 为例：

```
features/notes/
  manager.lua
  note.lua
  jump_manager.lua
  migration_manager.lua
```

每个 Feature 都是一个“子系统”。

---

# 5. Notes Architecture（笔记系统架构）

Notes 是 nvim-store3 最复杂的 Feature，包含：

- note 数据模型
- CRUD
- 符号索引
- 跳转系统
- 迁移系统
- 事件系统

## 5.1 数据结构

存储结构（扁平 key）：

```
notes.<id> → { id, bufnr, line, text, ... }
```

## 5.2 NotesManager

职责：

- 创建 / 更新 / 删除笔记
- 查找笔记
- 搜索笔记
- 触发事件
- 调用 jump_manager / migration_manager

## 5.3 JumpManager

负责：

- 跳转到笔记位置
- 高亮位置
- 自动命令（用户命令）

## 5.4 MigrationManager

负责：

- 旧格式迁移
- 符号索引重建
- 清理孤儿笔记

---

# 6. Buffer Cache Architecture（缓存系统）

BufferCache 是一个轻量级缓存系统：

- 按 bufnr 缓存
- TTL 自动过期
- 定时器自动清理
- 全局缓存 + buffer 缓存

用途：

- AST 缓存
- LSP 解析缓存
- 语义分析缓存

---

# 7. PathKey Architecture（路径编码）

用于将真实路径转换为安全 key：

```
/home/佳/project/main.lua
↓ encode
QUJDREVGR0g=
↓ 存储
dap_breakpoints.QUJDREVGR0g=
```

特点：

- Base64 编码
- 可逆
- 不破坏点号路径
- 跨平台

---

# 8. Event Architecture（事件系统）

每个 Feature 可以拥有自己的事件系统：

```lua
notes:on("note_created", function(payload)
  print(payload.id)
end)
```

事件系统是轻量级的：

- 不支持 once
- 不支持 remove
- 适合插件内部扩展

---

# 9. Data Flow（数据流）

以 NotesManager:update 为例：

```
notes:update(id, updates)
 ├─ store:get("notes.<id>")
 ├─ 修改 note
 ├─ store:set("notes.<id>", note)
 ├─ events:emit("note_updated")
 └─ backend:set("notes.<id>", note)
```

以 DAP 断点同步为例：

```
sync_breakpoints()
 ├─ breakpoints.get()
 ├─ safe_breakpoint_data()
 ├─ PathKey.encode(path)
 ├─ store:set("dap_breakpoints.<encoded>", data)
 └─ backend:set(...)
```

---

# 10. How to Add a New Feature（如何新增 Feature）

假设你要新增一个 `todo` 功能：

## 10.1 创建目录

```
lua/nvim-store3/features/todo/
  manager.lua
```

## 10.2 在 feature_manager 注册

```lua
_available_features = {
  "notes",
  "buffer_cache",
  "todo",
}
```

## 10.3 实现 manager.lua

```lua
local M = {}

function M.new(store, config)
  local self = { store = store, config = config }
  return setmetatable(self, { __index = M })
end

function M:add(item)
  local id = ...
  self.store:set("todo." .. id, item)
end

return M
```

## 10.4 使用

```lua
local store = Store.project({
  todo = { enabled = true },
})

store.todo:add("写文档")
```

---

# 11. How to Add a New Backend（如何新增后端）

例如 SQLite：

## 11.1 注册后端

```lua
BackendFactory.register("sqlite", function(config)
  return SqliteBackend.new(config)
end)
```

## 11.2 实现接口

```lua
function SqliteBackend:get(ns, key) ... end
function SqliteBackend:set(ns, key, value) ... end
function SqliteBackend:delete(ns, key) ... end
function SqliteBackend:keys(ns) ... end
function SqliteBackend:flush() ... end
```

---

# 12. Best Practices（最佳实践）

- 使用命名空间隔离数据：`plugin_x.settings.<key>`
- 使用 PathKey 处理文件路径
- 使用 Store:keys() 枚举数据
- 使用 flush_delay 减少磁盘写入
- Feature 内部不要直接访问 backend
- 不要在 Feature 之间互相调用（保持解耦）
- 所有业务逻辑放在 Feature，不放在 Store

---

# 13. Roadmap（未来扩展）

- SQLite 后端（支持 schema / migration）
- 事务系统（transaction）
- 多 namespace 支持
- 更强的查询系统（Query DSL）
- UI 组件（Notes 面板、Symbol 面板）
- LSP 集成（符号索引）

---

# 14. Maintainer Notes（维护者须知）

- Store 是核心，不要在 Store 中加入业务逻辑
- Feature 是扩展点，保持独立性
- Backend 是可替换的，保持接口稳定
- util 模块必须无副作用
- 所有模块必须可测试（memory backend）
