-- lua/nvim-store/core/event.lua
-- 事件系统（Event Emitter）
--
-- 设计目标：
--   - 为 nvim-store 提供统一的事件发布/订阅机制
--   - 支持多事件类型（change / flush / note_update）
--   - 支持多个回调（订阅者）
--   - store.lua 可在任意位置 emit(event, payload)
--   - 外部插件可通过 store:on(event, callback) 订阅
--
-- 使用方式：
--   local Event = require("nvim-store3.core.event")
--   local ev = Event.new()
--   ev:on("change", function(payload) ... end)
--   ev:emit("change", { key = "foo" })

local M = {}

---------------------------------------------------------------------
-- 创建事件管理器
---------------------------------------------------------------------

function M.new()
	local self = {
		_handlers = {}, -- { event = { callback1, callback2, ... } }
	}

	-------------------------------------------------------------------
	-- 注册事件回调
	-------------------------------------------------------------------
	function self:on(event, callback)
		if not self._handlers[event] then
			self._handlers[event] = {}
		end
		table.insert(self._handlers[event], callback)
	end

	-------------------------------------------------------------------
	-- 触发事件
	-------------------------------------------------------------------
	function self:emit(event, payload)
		local handlers = self._handlers[event]
		if not handlers then
			return
		end
		for _, cb in ipairs(handlers) do
			cb(payload)
		end
	end

	return self
end

return M
