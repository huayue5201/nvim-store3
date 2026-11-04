-- test/project.lua
-- nvim-store3.util.project 的回归测试：项目身份 / 目录名 / 清单。
--
--   nvim --headless -u NONE -l test/project.lua
--
-- 覆盖：非 git 目录的 local 身份、远端归一化（https / scp / 带认证）、
--       同远端不同路径同名、同名不同远端不同名、monorepo 子包、
--       搬家后名字不变、清单读写与 list()。

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(root)

local project = require("nvim-store3.util.project")

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

local function sh(cmd)
	return vim.system({ "sh", "-c", cmd }, { text = true }):wait().code == 0
end

--- 建一个带远端的 git 仓库（不产生提交，只要 .git + config 里的 remote）
local function make_repo(dir, remote)
	vim.fn.mkdir(dir, "p")
	assert(sh(("git -C %q init -q"):format(dir)))
	if remote then
		assert(sh(("git -C %q remote add origin %q"):format(dir, remote)))
	end
	return project.realpath(dir)
end

--- 清缓存，避免上一个用例的身份串沿用
local function fresh()
	project.clear_cache()
end

---------------------------------------------------------------------
-- 1. 非 git 目录：local 身份
---------------------------------------------------------------------
local plain = project.realpath(tmpdir())
fresh()
check("local identity prefixes the absolute root", project.identity(plain) == "local:" .. plain, project.identity(plain))
check("name is slug--hash8", project.name(plain):match("^[%w%._%-]+%-%-%x%x%x%x%x%x%x%x$") ~= nil, project.name(plain))
check("info carries root and label", project.info(plain).root == plain and project.info(plain).label == project.basename(plain))

---------------------------------------------------------------------
-- 2. 远端归一化
---------------------------------------------------------------------
check("https → host/owner/repo", project.normalize_remote("https://github.com/acme/app.git") == "github.com/acme/app")
check(
	"credentials and port stripped, host lowercased",
	project.normalize_remote("https://user:tok@GitHub.com:8443/acme/app.git") == "github.com/acme/app"
)
check("scp style → host/owner/repo", project.normalize_remote("git@github.com:acme/app.git") == "github.com/acme/app")
check("same repo via https and ssh agree", project.normalize_remote("https://github.com/acme/app") == project.normalize_remote("git@github.com:acme/app.git"))
check("local path remote is not an identity", project.normalize_remote("/srv/git/app.git") == nil)
check("empty remote is not an identity", project.normalize_remote("  ") == nil)

---------------------------------------------------------------------
-- 3. 同一远端：不同路径同名；不同远端：同名不同名
---------------------------------------------------------------------
local a = make_repo(tmpdir() .. "/app", "git@github.com:acme/app.git")
local b = make_repo(tmpdir() .. "/elsewhere/app", "https://github.com/acme/app")
fresh()
check("same remote, different paths → same name", project.name(a) == project.name(b), project.name(a) .. " vs " .. project.name(b))
check("identity is the normalised remote", project.identity(a) == "github.com/acme/app", project.identity(a))

local other = make_repo(tmpdir() .. "/app", "git@github.com:other/app.git")
fresh()
check("same dir name, different remote → different name", project.name(a) ~= project.name(other))

---------------------------------------------------------------------
-- 4. monorepo：子包带上相对路径
---------------------------------------------------------------------
local repo = make_repo(tmpdir() .. "/mono", "git@github.com:acme/mono.git")
local pkg = project.realpath(repo .. "/packages/pkg-a")
vim.fn.mkdir(pkg, "p")
vim.fn.writefile({ "{}" }, pkg .. "/package.json")
fresh()
check("sub-package identity has #relpath", project.identity(pkg) == "github.com/acme/mono#packages/pkg-a", project.identity(pkg))
check("sub-package name differs from the repo root", project.name(pkg) ~= project.name(repo))
check("sub-package slug keeps its own dir name", project.name(pkg):match("^pkg%-a%-%-") ~= nil, project.name(pkg))

---------------------------------------------------------------------
-- 5. 搬家：身份不变
---------------------------------------------------------------------
local moved = project.realpath(tmpdir() .. "/moved")
vim.fn.mkdir(vim.fn.fnamemodify(moved, ":h"), "p")
assert(sh(("cp -R %q %q"):format(a, moved)))
fresh()
check("moving a clone keeps its name", project.name(moved) == project.name(a), project.name(moved) .. " vs " .. project.name(a))

---------------------------------------------------------------------
-- 6. 清单
---------------------------------------------------------------------
local vault = tmpdir()
local info = project.info(a)
local dir = vault .. "/" .. info.name
vim.fn.mkdir(dir, "p")
check("write_manifest creates the file", project.write_manifest(dir, info) == true)
check("manifest round-trips", project.read_manifest(dir).identity == info.identity)
check("unchanged manifest is not rewritten", project.write_manifest(dir, info) == false)
check("missing manifest reads as nil", project.read_manifest(vault .. "/nope") == nil)

local bare = vault .. "/handmade--deadbeef"
vim.fn.mkdir(bare, "p")
local listed = project.list(vault)
check("list() includes directories without manifests", #listed == 2, #listed)
check("list() falls back to the directory name as label", (function()
	for _, item in ipairs(listed) do
		if item.name == "handmade--deadbeef" then
			return item.label == "handmade--deadbeef"
		end
	end
end)())
vim.fn.mkdir(vault .. "/.quarantine/x", "p")
check("list() skips dot directories", #project.list(vault) == 2, #project.list(vault))

---------------------------------------------------------------------
-- 7. clear_cache 真的清掉了缓存
---------------------------------------------------------------------
local before = project.identity(a)
assert(sh(("git -C %q remote set-url origin %q"):format(a, "git@github.com:acme/renamed.git")))
check("identity is cached", project.identity(a) == before)
fresh()
check("clear_cache re-reads the remote", project.identity(a) == "github.com/acme/renamed", project.identity(a))

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
