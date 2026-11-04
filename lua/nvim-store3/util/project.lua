-- lua/nvim-store3/util/project.lua
---@brief 项目身份与项目目录清单（消费者共用：todo2、notes 等）
---
--- 身份（identity）决定目录名，原则是「同一份代码，换个路径 / 换台机器还是同一个项目」：
---   1. 有 git 远端  → `<host>/<owner>/<repo>[#子目录]`
---   2. 没有远端     → `local:<项目根绝对路径>`
--- 目录名 = `<slug>--<sha256(identity) 前 8 位>`：人可读（slug 取项目根目录名），
--- 且不撞车（同名项目、同名但不同远端都不会串）。
---
--- 项目根沿用 `nvim-store3.util.path.project_root`（`.git` / `package.json` / …），
--- 所以各消费者对「一个项目」的边界判定完全一致，monorepo 子包也各归各的。
---
--- 每个项目目录里写一份 `.project.json`（身份 / 根路径 / 展示名）：目录名里的 hash
--- 是身份算出来的，没有清单就无法反推「这个目录属于哪个项目」，项目从磁盘消失之后
--- 也就判断不了该不该回收。清单只是账本，不含业务数据。

local M = {}

--- 清单文件名（放在各消费者自己的项目目录里）
M.MANIFEST = ".project.json"

--- slug 最长长度（目录名可读部分）
local SLUG_MAX = 40
--- 身份哈希取多少位十六进制
local HASH_LEN = 8
--- 单次 git 调用的超时（毫秒）
local GIT_TIMEOUT = 3000

--- 身份缓存：项目根 → 身份串
---@type table<string, string>
local identity_cache = {}

local function uv()
	return vim.uv or vim.loop
end

---------------------------------------------------------------------
-- 路径
---------------------------------------------------------------------

--- 去掉结尾分隔符并解析软链（macOS 的 /var → /private/var）。
---@param path string
---@return string
function M.realpath(path)
	local p = vim.fn.fnamemodify(path, ":p")
	p = p:gsub("[/\\]+$", "")
	if p == "" then
		p = "/"
	end
	local real = uv() and uv().fs_realpath and uv().fs_realpath(p)
	if real and real ~= "" then
		p = real:gsub("[/\\]+$", "")
	end
	return p
end

--- 路径的 basename（忽略结尾分隔符）。
---@param path string
---@return string
function M.basename(path)
	return (path:gsub("(.)/+$", "%1"):match("([^/]+)$") or path)
end

--- 项目根：优先用 nvim-store3 的项目标志判定，失败才回退到路径自身。
---@param path? string 目录或文件（默认 cwd）
---@return string
function M.root(path)
	local start = path
	if start == nil or start == "" then
		start = vim.fn.getcwd()
	end

	local ok, store_path = pcall(require, "nvim-store3.util.path")
	if ok and store_path and store_path.project_root then
		local ok_root, root = pcall(store_path.project_root, start)
		if ok_root and root and root ~= "" then
			return root
		end
	end
	return M.realpath(start)
end

--- 只在向上真的找到项目标志时返回根；找不到返回 nil。
--- 消费者用它回答「当前目录算不算一个项目」——`M.root()` 的兜底是路径自身，
--- 无法区分「这就是项目根」和「这里根本没有项目」。
---@param path? string
---@return string|nil
function M.marker_root(path)
	local ok, store_path = pcall(require, "nvim-store3.util.path")
	if not ok or not store_path or not store_path.PROJECT_MARKERS then
		return nil
	end
	local start = M.realpath(path or vim.fn.getcwd())
	local current = start
	for _ = 1, 10 do
		for _, marker in ipairs(store_path.PROJECT_MARKERS) do
			local marker_path = current .. "/" .. marker
			if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
				return current
			end
		end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			return nil
		end
		current = parent
	end
	return nil
end

---------------------------------------------------------------------
-- git
---------------------------------------------------------------------

--- 执行 git 并取单行输出（非零退出返回 nil）。
---@param args string[]
---@param cwd? string
---@return string|nil
local function git_line(args, cwd)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	local ok, proc = pcall(vim.system, cmd, { cwd = cwd, text = true })
	if not ok or not proc then
		return nil
	end
	local ok_wait, res = pcall(function()
		return proc:wait(GIT_TIMEOUT)
	end)
	if not ok_wait or not res or res.code ~= 0 then
		return nil
	end
	local line = (res.stdout or ""):match("^%s*(.-)%s*$")
	return line ~= "" and line or nil
end

--- git 工作区根（不在工作区内返回 nil）。
---@param cwd? string
---@return string|nil
function M.toplevel(cwd)
	return git_line({ "rev-parse", "--show-toplevel" }, cwd)
end

--- 远端地址（origin 优先；没有 origin 时取第一个远端）。
---@param cwd? string
---@return string|nil
function M.remote_url(cwd)
	local url = git_line({ "config", "--get", "remote.origin.url" }, cwd)
	if url then
		return url
	end
	local first = git_line({ "remote" }, cwd)
	first = first and first:match("^([^\n]+)")
	return first and git_line({ "config", "--get", "remote." .. first .. ".url" }, cwd) or nil
end

--- 远端地址归一化：去掉协议、认证信息、端口、`.git` 后缀。
--- 本地路径形式的远端不算身份（换台机器就不再是同一个项目）。
---@param url? string
---@return string|nil
function M.normalize_remote(url)
	url = vim.trim(url or "")
	if url == "" then
		return nil
	end

	local host, rest
	-- scp 风格：git@github.com:owner/repo.git
	local scp_host, scp_path = url:match("^[^/@]+@([^/:]+):(.+)$")
	if scp_host then
		host, rest = scp_host, scp_path
	else
		-- scheme://[user[:pass]@]host[:port]/path
		local body = url:match("^[%w+.%-]+://(.+)$")
		if not body then
			return nil
		end
		body = body:gsub("^[^/@]*@", "")
		local h, p = body:match("^([^/]+)(/.*)$")
		if not h then
			return nil
		end
		host, rest = h:gsub(":%d+$", ""), p
	end

	rest = rest:gsub("^/+", ""):gsub("/+$", ""):gsub("%.git$", "")
	if rest == "" then
		return nil
	end
	return host:lower() .. "/" .. rest
end

---------------------------------------------------------------------
-- 身份与目录名
---------------------------------------------------------------------

--- 项目身份串。仓库内的子项目会带上相对路径，所以 monorepo 各子包互不串。
---@param path? string
---@return string
function M.identity(path)
	local root = M.root(path)
	local cached = identity_cache[root]
	if cached then
		return cached
	end

	local identity
	local toplevel = M.toplevel(root)
	local remote = toplevel and M.normalize_remote(M.remote_url(toplevel))
	if remote then
		-- git 的 toplevel 与项目根可能一个解析了符号链接、一个没有，只认真正的前缀
		local rel = root:sub(1, #toplevel + 1) == toplevel .. "/" and root:sub(#toplevel + 2) or ""
		identity = rel ~= "" and (remote .. "#" .. rel) or remote
	else
		identity = "local:" .. root
	end

	identity_cache[root] = identity
	return identity
end

--- 目录名里的可读部分：取自身份（仓库名 / 子包名），而不是本地目录名 ——
--- 这样把仓库换个目录名（或换台机器 clone）之后目录名依然不变。
---@param identity string
---@return string
local function slug_of(identity)
	local base
	local sub = identity:match("#(.+)$")
	local repo = identity:gsub("#.+$", "")
	if sub and sub ~= "" then
		base = vim.fn.fnamemodify(sub, ":t")
	elseif repo:sub(1, 6) == "local:" then
		base = vim.fn.fnamemodify(repo:sub(7), ":t")
	else
		base = vim.fn.fnamemodify(repo, ":t")
	end
	base = base:lower()
	base = base:gsub("[^%w%-%._]", "-"):gsub("%-+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
	if base == "" then
		base = "project"
	end
	if #base > SLUG_MAX then
		base = base:sub(1, SLUG_MAX):gsub("%-+$", "")
	end
	return base
end

--- 由身份串算目录名：`<slug>--<hash8>`。
---@param identity string
---@return string
function M.name_for(identity)
	return slug_of(identity) .. "--" .. vim.fn.sha256(identity):sub(1, HASH_LEN)
end

--- 当前（或指定路径所属）项目的目录名。
---@param path? string
---@return string
function M.name(path)
	return M.name_for(M.identity(path))
end

--- 项目信息（不含存放目录，存放位置由消费者决定）。
---@class StoreProjectInfo
---@field name string 目录名 `<slug>--<hash8>`
---@field label string 展示名（项目根目录名）
---@field root string 项目根绝对路径
---@field identity string 身份串

---@param path? string
---@return StoreProjectInfo
function M.info(path)
	local root = M.root(path)
	local identity = M.identity(root)
	return {
		name = M.name_for(identity),
		label = M.basename(root),
		root = root,
		identity = identity,
	}
end

---------------------------------------------------------------------
-- 项目目录清单（.project.json）
---------------------------------------------------------------------

--- 读目录里的清单（没有 / 坏了都返回 nil）。
---@param dir string
---@return table|nil
function M.read_manifest(dir)
	local path = dir .. "/" .. M.MANIFEST
	if vim.fn.filereadable(path) == 0 then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or type(lines) ~= "table" then
		return nil
	end
	local ok_decode, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok_decode or type(data) ~= "table" then
		return nil
	end
	return data
end

--- 写入 / 修复清单（内容没变就不写；目录不存在直接返回 false）。
---@param dir string
---@param info table 至少含 name / label / identity / root
---@return boolean written
function M.write_manifest(dir, info)
	if not dir or not info or vim.fn.isdirectory(dir) == 0 then
		return false
	end

	local want = {
		name = info.name,
		label = info.label,
		identity = info.identity,
		root = info.root,
	}
	local have = M.read_manifest(dir)
	if
		have
		and have.name == want.name
		and have.label == want.label
		and have.identity == want.identity
		and have.root == want.root
	then
		return false
	end

	local ok, encoded = pcall(vim.json.encode, want)
	if not ok then
		return false
	end
	pcall(vim.fn.writefile, { encoded }, dir .. "/" .. M.MANIFEST)
	return true
end

--- 列出某个存放根目录下的全部项目（跳过 `.` 开头的目录：备份 / 隔离区）。
--- 清单缺失时用目录名兜底，所以手工建的目录也能列出来。
---@param vault string 存放项目目录的根
---@return StoreProjectInfo[]
function M.list(vault)
	local out = {}
	if vim.fn.isdirectory(vault) ~= 1 then
		return out
	end

	local handle = uv().fs_scandir(vault)
	if not handle then
		return out
	end
	while true do
		local name = uv().fs_scandir_next(handle)
		if not name then
			break
		end
		if name:sub(1, 1) ~= "." then
			local dir = vault .. "/" .. name
			if vim.fn.isdirectory(dir) == 1 then
				local manifest = M.read_manifest(dir) or {}
				out[#out + 1] = {
					name = name,
					label = manifest.label or name,
					dir = dir,
					root = manifest.root,
					identity = manifest.identity,
				}
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.label or "") < (b.label or "")
	end)
	return out
end

--- 清空身份缓存（测试或项目远端变化时用）。
---@return nil
function M.clear_cache()
	identity_cache = {}
end

return M
