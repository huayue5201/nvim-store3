-- lua/nvim-store3/util/async.lua
-- vim.async 便捷封装（防抖 / 延迟 / 后台循环）。

local M = {}

local async = vim.async

--- 观测任务失败：忽略取消，其余错误报出（顶层任务默认静默）。
--- on_complete 可能在快速上下文中触发，UI 调用必须切回主循环。
---@param task vim.async.Task
---@return vim.async.Task
local function observe(task)
	task:on_complete(function(err)
		if err == nil or tostring(err):find("closed", 1, true) then
			return
		end
		local message = tostring(err)
		vim.schedule(function()
			vim.notify("nvim-store3 async: " .. message, vim.log.levels.ERROR)
		end)
	end)
	return task
end

--- 防抖：取消 obj[field] 上一轮任务，delay 毫秒后执行 fn。
---@param obj table 持有任务的目标（实例或模块表）
---@param field string 任务字段名
---@param delay integer 延迟毫秒
---@param fn fun()
---@return vim.async.Task
function M.debounce(obj, field, delay, fn)
	local prev = obj[field]
	if prev then
		prev:close()
	end

	obj[field] = observe(async.run(function()
		async.sleep(delay)
		obj[field] = nil
		fn()
	end))
	return obj[field]
end

--- 取消并清除 obj[field] 上的任务。
---@param obj table
---@param field string
function M.cancel(obj, field)
	local task = obj[field]
	if task then
		task:close()
		obj[field] = nil
	end
end

--- 后台循环：延迟 delay 毫秒后，每 interval 毫秒执行一次 fn，直到被取消。
---@param delay integer 首次执行前的延迟（毫秒）
---@param interval integer 之后每次执行的间隔（毫秒）
---@param fn fun()
---@return vim.async.Task
function M.loop(delay, interval, fn)
	return observe(async.run(function()
		async.sleep(delay)
		while not async.is_closing() do
			fn()
			async.sleep(interval)
		end
	end)):detach()
end

return M
