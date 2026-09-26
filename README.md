> Neovim persistent storage solution — keep plugin data across sessions

[![Lua](https://img.shields.io/badge/Lua-5.1-blue.svg)](https://www.lua.org/)
[![Neovim](https://img.shields.io/badge/Neovim-0.8+-green.svg)](https://neovim.io/)
[![License](https://img.shields.io/badge/License-MIT-red.svg)](LICENSE)

nvim-store3 is a persistent storage solution designed for Neovim, providing
cross-session data persistence, an event system, hashed project directories
and smart project detection.

[中文文档](README.zh.md)

## ✨ Features

- 🎯 **Dual-scope storage** — global and project-level storage, with data
  isolation handled automatically
- 🧠 **Smart project detection** — automatically detects the project root,
  avoiding pollution of system directories
- 🔌 **Plugin architecture** — supports dynamically loaded plugins that mount
  directly onto a store instance
- 📡 **Event-driven** — built-in event system for data-change listeners
- 🗂️ **Hashed project directories** — project directories use SHA-256 hashed
  names, avoiding path conflicts and overlong directory names
- 💾 **Atomic writes** — the JSON backend supports atomic writes and automatic
  backups
- 🧹 **Smart cleanup** — automatically cleans empty/expired projects, and
  limits the count when disk space runs low

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nvim-store3",
  config = function()
    -- Optional: customize cleanup
    require("nvim-store3").setup_cleanup({
      enabled = true,
      max_age_days = 90,        -- clean projects untouched for 90 days
      max_count = 50,           -- keep at most 50 projects
      min_free_space_mb = 100,  -- limit count when disk < 100MB
      check_interval_hours = 24 -- check once a day
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

## 🚀 Quick start

### Basic usage

```lua
-- Get the global store instance
local store = require("nvim-store3").global()

-- Store data
store:set("theme", "dark")
store:set("last_session", { file = "main.lua", line = 42 })

-- Read data
local theme = store:get("theme")  -- "dark"
local session = store:get("last_session")  -- { file = "main.lua", line = 42 }

-- Delete data
store:delete("theme")

-- Persist to disk
store:flush()
```

### Project storage

```lua
-- Project storage auto-detects the current project root
local project = require("nvim-store3").project()

-- Store project-specific data
project:set("bookmarks", {
  { file = "src/main.lua", line = 10 },
  { file = "src/utils.lua", line = 25 }
})
```

### Organizing data with namespaces

```lua
-- Use dot-separated keys to organize data
store:set("notes.today.1", { title = "Meeting notes", content = "..." })
store:set("notes.today.2", { title = "TODO list", content = "..." })
store:set("config.editor", { theme = "dark", font_size = 14 })

-- Get all keys under a namespace
local notes = store:namespace_keys("notes")  -- {"today.1", "today.2"}

-- Path query
local note = store:query("notes.today.1")  -- { title = "Meeting notes", ... }
```

## 📖 Core API

### Store instance methods

| Method | Description | Example |
|--------|-------------|---------|
| `:set(key, value)` | Store data | `store:set("name", "value")` |
| `:get(key)` | Read data | `local val = store:get("name")` |
| `:delete(key)` | Delete data | `store:delete("name")` |
| `:keys()` | Get all keys | `local keys = store:keys()` |
| `:namespace_keys(ns)` | Get keys under a namespace | `store:namespace_keys("notes")` |
| `:query(path)` | Path query (supports nesting) | `store:query("notes.today.1")` |
| `:flush()` | Persist to disk | `store:flush()` |
| `:on(event, callback)` | Subscribe to an event | `store:on("set", fn)` |
| `:get_stats()` | Get statistics | `local stats = store:get_stats()` |

### Event system

```lua
-- Listen for data changes
store:on("set", function(payload)
  print("data set:", payload.key, payload.value)
end)

store:on("delete", function(payload)
  print("data deleted:", payload.key)
end)

store:on("flush", function(payload)
  if payload.ok then
    print("data persisted")
  end
end)
```

### Store statistics

```lua
local stats = store:get_stats()
print("total keys:", stats.total_keys)
print("cache size:", stats.cache_size)
print("estimated size:", stats.estimated_size, "bytes")
print("scope:", stats.scope)
print("noop mode:", stats.noop)  -- true in system directories
```

## 🎮 Commands

The plugin provides these Neovim commands automatically:

| Command | Description | Source |
|---------|-------------|--------|
| `:Store` | Interactively view project data | project_query plugin |
| `:StoreDelete [namespace]` | Delete namespace data | project_delete plugin |

## ⚙️ Configuration

### Storage configuration

```lua
-- Global storage configuration
local store = require("nvim-store3").global({
  storage = {
    backend = "json",
    flush_delay = 1000,  -- delayed save (milliseconds)
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

### Cleanup system configuration

```lua
local Cleanup = require("nvim-store3.core.cleanup")

-- Custom cleanup configuration
Cleanup.setup({
  enabled = true,              -- enable automatic cleanup
  max_age_days = 90,           -- clean projects untouched for 90 days
  max_count = 50,              -- keep at most 50 projects
  min_free_space_mb = 100,     -- limit count when disk < 100MB
  check_interval_hours = 24,   -- check once a day
})

-- Or via the init.lua shortcut
require("nvim-store3").setup_cleanup({
  max_age_days = 60,
  max_count = 30,
})
```

## 🔌 Built-in plugins

### Basic Cache — LRU cache plugin

```lua
-- Enable the cache plugin
local store = require("nvim-store3").global({
  plugins = { basic_cache = true }
})

local cache = store.basic_cache

-- Set a cache entry (optional TTL)
cache:set("key", "value", 300)  -- expires after 5 minutes

-- Get a cache entry
local value = cache:get("key")

-- Delete a cache entry
cache:delete("key")

-- Clean expired entries
cache:cleanup_expired()

-- Get statistics
local stats = cache:get_stats()  -- { enabled = true, size = 10 }
```

**Cache features**:
- LRU eviction
- TTL expiry
- write-through / read-through modes
- automatic cleanup timer

### Project Query — project query plugin

```lua
local store = require("nvim-store3").project({
  plugins = { project_query = true }
})

local query = store.project_query

-- Get all namespaces
local namespaces = query:get_namespaces()

-- Show a formatted JSON floating window
query:show_json("notes")

-- Interactively select a namespace
query:select_namespace()
```

### Project Delete — project delete plugin

```lua
local store = require("nvim-store3").project({
  plugins = { project_delete = true }
})

local deleter = store.project_delete

-- Get namespace list
local namespaces = deleter:get_namespaces()

-- Delete a namespace (with interactive confirmation)
deleter:delete_namespace("notes")

-- Interactively select and delete
deleter:select_and_delete()
```

## 🧩 Developing plugins

### Basic plugin structure

```lua
-- plugins/my_plugin.lua
local M = {}

function M.new(store, config)
  local self = {
    store = store,
    config = config or {},
  }

  setmetatable(self, { __index = M })

  -- No-op instance check (returns silently in system directories)
  if store._noop then
    return self
  end

  -- Listen for events
  store:on("set", function(payload)
    self:on_data_change(payload)
  end)

  return self
end

function M:on_data_change(payload)
  -- Handle data changes
  print("data changed:", payload.key)
end

function M:my_method()
  return self.store:get("some_key")
end

function M:cleanup()
  -- Clean up resources (called on unload)
  self.store:flush()
end

return M
```

### Register and use a plugin

```lua
-- Register a plugin
require("nvim-store3").register_plugin("my_plugin", "path.to.my_plugin")

-- Enable the plugin
local store = require("nvim-store3").global({
  plugins = {
    my_plugin = { enabled = true, custom_option = "value" }
  }
})

-- Use the plugin (direct access)
store.my_plugin:my_method()
```

## 🗂️ Storage layout

```
~/.cache/nvim/nvim-store/                    # actual path = stdpath("cache") .. "/nvim-store"
├── global/                                  # global storage
│   └── data.json                            # { "version": 2, "data": {...} }
└── projects/                                # project storage
    ├── 4269cebe2bf51ea9/                    # project A (first 16 chars of root-path SHA-256)
    │   ├── meta.json                        # { root, created_at, accessed_at, updated_at }
    │   └── data.json                        # { "version": 2, "data": {...} }
    └── ...
```

**Project detection rules**:
- Walk upward looking for project markers (.git, package.json, Makefile, etc.)
- System-directory blacklist (/etc, /var, /tmp, etc.) — no storage is created
- The same project uses the same store regardless of the subdirectory you
  enter from
- The project directory name is the first 16 chars of the project root path's
  SHA-256 hash; the real path is recorded in `meta.json`'s `root` field
  (avoiding long directory names and path conflicts)

## 🧹 Smart cleanup strategy

nvim-store3 has a built-in smart cleanup mechanism that manages project
storage automatically:

| Priority | Strategy | Condition | Notes |
|----------|----------|-----------|-------|
| 1 | Clean empty projects | unconditional | projects whose data.json is {} are cleaned first |
| 2 | Clean expired projects | untouched beyond the configured days | default 90 days, configurable |
| 3 | Limit count | disk space below threshold | default 100MB, deletes the oldest projects |

> The "access time" is recorded in `meta.json`'s `accessed_at` field (updated
> every time a project store is opened), kept separate from the "write time"
> `updated_at`, so read-only projects are not misjudged as expired.

A notification is shown during cleanup so users know what happened.

## 🎯 Best practices

### 1. Data organization

```lua
-- ✅ Use namespaces
store:set("bookmarks.lua", { line = 10, file = "main.lua" })
store:set("bookmarks.python", { line = 20, file = "app.py" })

-- ✅ Use nested structures
store:set("config.editor", { theme = "dark", font_size = 14 })
store:set("config.lsp", { enabled = true, servers = { "lua_ls" } })
```

### 2. Performance optimization

```lua
-- Use cache to reduce disk access
local store = require("nvim-store3").global({
  plugins = { basic_cache = { default_ttl = 60 } }
})

-- Batch reads with namespace_keys
local bookmarks = {}
for _, key in ipairs(store:namespace_keys("bookmarks")) do
  bookmarks[key] = store:get("bookmarks." .. key)
end
```

### 3. Event listeners

```lua
-- Auto-log data changes
store:on("set", function(payload)
  vim.notify(string.format("[Store] %s = %s", payload.key, vim.inspect(payload.value)))
end)
```

## 🐛 Troubleshooting

### Data save failures

```lua
-- Check paths
local Path = require("nvim-store3.util.path")
print("Global path:", Path.global_store_path())
print("Project path:", Path.project_store_path())

-- Manually trigger a save
store:flush()
```

### Project detection issues

```lua
-- Debug the project root
local Path = require("nvim-store3.util.path")
print("Project root:", Path.project_root())
print("Project key:", Path.project_key())  -- hash of the root path (directory name), not the full path
```

### Cleanup statistics

```lua
local Cleanup = require("nvim-store3.core.cleanup")
local stats = Cleanup.get_stats()
print(string.format("projects: %d, total size: %.2f MB",
  stats.total_projects, stats.total_size_mb))
print(string.format("empty: %d, expired: %d",
  stats.empty_projects, stats.expired_projects))
print(string.format("free disk: %.2f MB", stats.free_space_mb))
```

## 📄 License

MIT License © nvim-store3 Team
