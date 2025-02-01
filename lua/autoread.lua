---@class Autoread.Config
---@field interval integer? Checks for changes every `interval` milliseconds
---@field notify_on_change boolean? Whether to notify when a file is reloaded

---@class Autoread.ConfigStrict
---@field interval integer Checks for changes every `interval` milliseconds
---@field notify_on_change boolean Whether to notify when a file is reloaded

---@class Autoread.Meta
---@field config Autoread.ConfigStrict
---@field private _timer uv.uv_timer_t?
local M = {}

local default_config = {
	interval = 500,
	notify_on_change = true,
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Autoread" })
end

---@param interval integer?
local function assert_interval(interval)
	assert(type(interval) == "number", "interval must be a number")
	assert(interval > 0, "interval must be greater than 0")
end

local function trigger_reload()
	vim.api.nvim_command("checktime")
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

local function setup_notify_file_changed()
	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		group = vim.api.nvim_create_augroup("AutoreadGroup", {}),
		callback = function(event)
			if M._timer and event and event.file then
				notify(string.format("File changed on disk: %s", event.file))
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

	return config
end

---@param user_config Autoread.Config?
function M.setup(user_config)
	M.config = validate_config(user_config)

	create_user_commands()

	if M.config.notify_on_change then
		setup_notify_file_changed()
	end
end

return M
