-- test/backend.lua
-- nvim-store3 存储后端的最小回归测试。
--
--   nvim --headless -u NONE -l test/backend.lua
--
-- 覆盖：基本 CRUD、facts/cache 分区落盘、老格式迁移、epoch 护栏、
--       缓存写入不触发 facts 冲突、删除缺失键的返回值。

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(root)

local JsonBackend = require("nvim-store3.storage.json_backend")
local Json = require("nvim-store3.util.json")

local passed, failed = 0, 0

local function check(name, cond, detail)
	if cond then
		passed = passed + 1
		io.write("  ok   " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL " .. name .. (detail ~= nil and ("  → " .. tostring(detail)) or "") .. "\n")
	end
end

local function tmpdir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return dir
end

local function read(path)
	return Json.load(path)
end

local function new_backend(dir, extra)
	return JsonBackend.new(vim.tbl_extend(
		"force",
		{ path = dir .. "/data.json", flush_delay = 0, version = 2 },
		extra or {}
	))
end

---------------------------------------------------------------------
-- 1. 基本 CRUD
---------------------------------------------------------------------
local d1 = tmpdir()
local b = new_backend(d1)

check("empty load", next(b:load()) == nil)
check("set returns true", b:set("facts.tasks.a1", { content = "x" }) == true)
check("get returns value", b:get("facts.tasks.a1").content == "x")
check("keys has one", #b:keys() == 1)
check("delete existing", b:delete("facts.tasks.a1") == true)
check("delete missing is false", b:delete("facts.tasks.a1") == false)
check("get after delete", b:get("facts.tasks.a1") == nil)

---------------------------------------------------------------------
-- 2. 分区落盘：facts → data.json，cache → cache.json
---------------------------------------------------------------------
local d2 = tmpdir()
local b2 = new_backend(d2)
b2:set("facts.tasks.a1", { content = "keep" })
b2:set("cache.index.file_to_code./tmp/x.rs", { 1 })
check("flush ok", b2:flush() == true)

local facts_file = read(d2 .. "/data.json")
local cache_file = read(d2 .. "/cache.json")
check("facts file exists", vim.fn.filereadable(d2 .. "/data.json") == 1)
check("cache file exists", vim.fn.filereadable(d2 .. "/cache.json") == 1)
check("facts file holds facts", facts_file.data["facts.tasks.a1"] ~= nil)
check("facts file drops cache", facts_file.data["cache.index.file_to_code./tmp/x.rs"] == nil, "#facts")
check("cache file holds cache", cache_file.data["cache.index.file_to_code./tmp/x.rs"] ~= nil)

---------------------------------------------------------------------
-- 3. 重新加载：合并视图仍然是一个键空间
---------------------------------------------------------------------
local b3 = new_backend(d2)
local merged = b3:load()
check("reload sees facts", merged["facts.tasks.a1"] ~= nil)
check("reload sees cache", merged["cache.index.file_to_code./tmp/x.rs"] ~= nil)
check("reload get cache", b3:get("cache.index.file_to_code./tmp/x.rs")[1] == 1)
check("reload keys count", #b3:keys() == 2, #b3:keys())

---------------------------------------------------------------------
-- 4. 老格式迁移：缓存混在 data.json 里时搬到 cache.json
---------------------------------------------------------------------
local d4 = tmpdir()
Json.save(d4 .. "/data.json", {
	version = 2,
	epoch = { n = 7, writer = "old" },
	data = {
		["facts.tasks.z1"] = { content = "z" },
		["cache.relation.child_to_parent.n1"] = "p1",
	},
})
local b4 = new_backend(d4)
b4:load()
check("migrated: merged view intact", b4:get("cache.relation.child_to_parent.n1") == "p1")
b4:flush()
local after = read(d4 .. "/data.json")
local after_cache = read(d4 .. "/cache.json")
check("migrated: facts file clean", after.data["cache.relation.child_to_parent.n1"] == nil)
check("migrated: facts kept", after.data["facts.tasks.z1"] ~= nil)
check("migrated: cache moved", after_cache.data["cache.relation.child_to_parent.n1"] == "p1")

---------------------------------------------------------------------
-- 5. epoch 护栏（只作用于 facts 分区）
---------------------------------------------------------------------
local d5 = tmpdir()
local a = new_backend(d5, { epoch_guard = true })
a:set("facts.tasks.a", 1)
a:flush()

local stale = new_backend(d5, { epoch_guard = true })
stale:load() -- 记住 epoch = 1
a:set("facts.tasks.a", 2)
a:flush() -- 磁盘 epoch 变成 2

stale:set("facts.tasks.a", 99)
local ok_stale = stale:flush()
local disk = read(d5 .. "/data.json")
check("stale writer rejected", ok_stale == false)
check("stale writer did not overwrite", disk.data["facts.tasks.a"] == 2, vim.inspect(disk.data["facts.tasks.a"]))
local conflicts = vim.fn.glob(d5 .. "/data.json.conflict*", false, true)
check("conflict snapshots kept", #conflicts >= 1, #conflicts)

---------------------------------------------------------------------
-- 6. 缓存写入不受 facts 冲突影响
---------------------------------------------------------------------
local cache_ok = stale:set("cache.index.x", { 1 })
stale:flush()
local cache_behind = read(d5 .. "/cache.json")
check("cache write accepted during conflict", cache_ok and cache_behind.data["cache.index.x"] ~= nil)

---------------------------------------------------------------------
-- 7. 无 cache 键时不产生 cache.json
---------------------------------------------------------------------
local d7 = tmpdir()
local b7 = new_backend(d7)
b7:set("facts.tasks.only", true)
b7:flush()
check("no cache file when unused", vim.fn.filereadable(d7 .. "/cache.json") == 0)

---------------------------------------------------------------------
-- 8. 自定义 cache 路径与前缀
---------------------------------------------------------------------
local d8 = tmpdir()
local b8 = new_backend(d8, { cache_path = d8 .. "/derived.json", cache_prefix = "derived." })
b8:set("derived.x", 1)
b8:set("facts.y", 2)
b8:flush()
check("custom cache path used", vim.fn.filereadable(d8 .. "/derived.json") == 1)
check("custom prefix routed", read(d8 .. "/derived.json").data["derived.x"] == 1)
check("custom prefix leaves facts", read(d8 .. "/data.json").data["derived.x"] == nil)

---------------------------------------------------------------------
-- 9. 分区判定
---------------------------------------------------------------------
check("partition cache", b8:partition("derived.x") == "cache")
check("partition facts", b8:partition("facts.x") == "facts")
check("partition nil-safe", b8:partition(nil) == "facts")

---------------------------------------------------------------------
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
