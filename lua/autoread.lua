---@alias Autoread.CursorBehavior
---| "preserve" Keep cursor at its current position
---| "scroll_down" Scroll to the bottom after reload
---| "none" Let Neovim handle cursor position naturally

---@alias Autoread.Events
---| "AutoreadPreCheck" Before checking files
---| "AutoreadPostCheck" After checking files
---| "AutoreadPreReload" Before reloading changed files
---| "AutoreadPostReload" After reloading changed files

---@class Autoread.Config
---@field interval integer? Checks for changes every `interval` milliseconds
---@field notify_on_change boolean? Whether to notify when a file is reloaded
---@field cursor_behavior Autoread.CursorBehavior? How to handle cursor position after file reload

---@class Autoread.ConfigStrict
---@field interval integer Checks for changes every `interval` milliseconds
---@field notify_on_change boolean Whether to notify when a file is reloaded
---@field cursor_behavior Autoread.CursorBehavior How to handle cursor position after file reload

---@class Autoread.Meta
---@field config Autoread.ConfigStrict
---@field private _timer uv.uv_timer_t?

local M = {}

---@type Autoread.ConfigStrict
local default_config = {
	interval = 500,
	notify_on_change = true,
	cursor_behavior = "preserve",
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Autoread" })
end

---@param interval integer?
local function assert_interval(interval)
	assert(type(interval) == "number", "interval must be a number")
	assert(interval > 0, "interval must be greater than 0")
end

---@param cursor_behavior Autoread.CursorBehavior? How to handle cursor position after file reload
local function assert_cursor_behavior(cursor_behavior)
	assert(
		type(cursor_behavior) == "string",
		"cursor_behavior must be a string"
	)

	local valid_behaviors = {
		preserve = true,
		scroll_down = true,
		none = true,
	}

	assert(
		valid_behaviors[cursor_behavior],
		"cursor_behavior must be one of: 'preserve', 'scroll_down', or 'none'"
	)
end

---@param event Autoread.Events|string
---@param opts vim.api.keyset.exec_autocmds?
local function exec_autocmds(event, opts)
	vim.api.nvim_exec_autocmds(
		"User",
		vim.tbl_deep_extend("force", { pattern = event }, opts or {})
	)
end

local function trigger_reload()
	exec_autocmds("AutoreadPreCheck")
	vim.api.nvim_command("checktime")
	exec_autocmds("AutoreadPostCheck")
end

---@param interval integer? Checks for changes every `interval` milliseconds *(default: M.config.interval)*
---@return uv.uv_timer_t? timer Timer instance or nil if creation failed
local function create_timer(interval)
	local timer = vim.uv.new_timer()
	if timer then
		timer:start(
			0,
			interval or M.config.interval,
			vim.schedule_wrap(trigger_reload)
		)
	end
	return timer
end

---@param interval integer Checks for changes every `interval` milliseconds
function M.set_interval(interval)
	assert_interval(interval)
	M.config.interval = interval
end

function M.get_interval()
	return M.config.interval
end

---@param interval integer? Temporary interval in ms that doesn't affect the config
function M.enable(interval)
	if interval then
		assert_interval(interval)
	end

	vim.opt.autoread = true
	if not M.is_enabled() then
		M._timer = create_timer(interval)
	end
end

function M.disable()
	vim.opt.autoread = false

	if M.is_enabled() then
		M._timer:close()
		M._timer = nil
	end
end

---@param interval integer? Temporary interval in ms that doesn't affect the config
function M.update_interval(interval)
	if M.is_enabled() then
		M._timer:stop()
		M._timer:start(
			0,
			interval or M.config.interval,
			vim.schedule_wrap(trigger_reload)
		)
	end
end

---@param interval integer? Optional temporary interval in milliseconds (doesn't change default config)
function M.toggle(interval)
	if interval then
		assert_interval(interval)
	end

	if M.is_enabled() then
		M.disable()
	else
		M.enable(interval)
	end
end

function M.is_enabled()
	return M._timer ~= nil
end

---@param cursor_behavior Autoread.CursorBehavior? How to handle cursor position after file reload
function M.set_cusor_behavior(cursor_behavior)
	assert_cursor_behavior(cursor_behavior)
	M.config.cursor_behavior = cursor_behavior --[[@as Autoread.CursorBehavior]]
end

local function create_cursor_handler()
	local cursor_behavior = M.config.cursor_behavior

	if cursor_behavior == "preserve" then
		local cursor = vim.api.nvim_win_get_cursor(0)
		local view = vim.fn.winsaveview()

		return function()
			pcall(vim.fn.winrestview, view)
			pcall(vim.api.nvim_win_set_cursor, 0, cursor)
		end
	elseif cursor_behavior == "scroll_down" then
		return function()
			vim.cmd("normal! Gzb")
		end
	end

	return function() end
end

local function setup_events()
	local group = vim.api.nvim_create_augroup("AutoreadGroup", {})

	local cursor_handler

	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		group = group,
		callback = function(event)
			if M.is_enabled() and event and event.file then
				local has_content = vim.api.nvim_buf_line_count(event.buf) > 1
				if has_content then
					exec_autocmds("AutoreadPreReload", { data = event })
				end

				if M.config.notify_on_change then
					notify(
						string.format("File changed on disk: %s", event.file)
					)
				end

				if has_content then
					if cursor_handler then
						cursor_handler()
						cursor_handler = nil
					end
					cursor_handler = create_cursor_handler()

					exec_autocmds("AutoreadPostReload", { data = event })
				end
			end
		end,
	})
end

local function create_user_commands()
	local create_command = vim.api.nvim_create_user_command

	local function notify_status(status, interval)
		local msg = status
		if interval then
			assert_interval(interval)
			msg = string.format("%s (interval: %dms)", msg, interval)
		end
		notify(msg)
	end

	create_command("Autoread", function(opts)
		local interval = tonumber(opts.args)

		if M.is_enabled() and interval then
			M.update_interval(interval)
		else
			M.toggle(interval)
		end

		if M.is_enabled() then
			notify_status("enabled", interval)
		else
			notify_status("disabled")
		end
	end, {
		nargs = "?",
		desc = "Toggle autoread or update interval. With [interval]: updates timer if enabled, enables with interval if disabled",
	})

	create_command("AutoreadOn", function(opts)
		local interval = tonumber(opts.args)
		M.enable(interval)
		notify_status("enabled", interval)
	end, {
		nargs = "?",
		desc = "Enable autoread with optional temporary interval in milliseconds",
	})

	create_command("AutoreadOff", function()
		M.disable()
		notify("disabled")
	end, {
		desc = "Disable autoread",
	})

	create_command("AutoreadCursorBehavior", function(opts)
		local cursor_behavior = opts.args
		M.set_cusor_behavior(cursor_behavior)
		notify("cursor behavior set to: " .. cursor_behavior)
	end, {
		nargs = 1,
		desc = "Set cursor behavior",
		complete = function()
			return { "preserve", "scroll_down", "none" }
		end,
	})
end

---@param user_config Autoread.Config?
local function validate_config(user_config)
	---@type Autoread.ConfigStrict
	local config =
		vim.tbl_deep_extend("force", default_config, user_config or {})

	assert_interval(config.interval)
	assert(
		type(config.notify_on_change) == "boolean",
		"notify_on_change must be a boolean"
	)

	assert_cursor_behavior(config.cursor_behavior)

	return config
end

---@param user_config Autoread.Config?
function M.setup(user_config)
	M.config = validate_config(user_config)

	create_user_commands()
	setup_events()
end

return M
