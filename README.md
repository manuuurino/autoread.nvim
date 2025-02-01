# autoread.nvim

A Neovim plugin that automatically reloads files when they are changed outside of the editor.

## Features

- Automatically reload files when they change on disk
- Configurable check interval
- Optional notifications when files are reloaded
- Simple commands to enable/disable/toggle auto-reload

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "manuuurino/autoread.nvim",
    cmd = "Autoread",
    opts = {},
}
```

## Configuration

```lua
-- Default configuration
require("autoread").setup({
    -- Check interval in milliseconds
    interval = 500,
    -- Show notifications when files change
    notify_on_change = true,
     -- How to handle cursor position after reload: "preserve", "scroll_down", or "none"
    cursor_behavior = "preserve",
})
```

## Commands

- `:Autoread [interval]` - Toggle autoread on/off with optional **temporary** interval in milliseconds
  When providing an interval, it will update the interval if enabled or enable with that interval if disabled, rather than toggling off.
- `:AutoreadOn [interval]` - Enable autoread with optional **temporary** interval in milliseconds
- `:AutoreadOff` - Disable autoread
- `:AutoreadCursorBehavior <behavior>` - Set cursor behavior ("preserve", "scroll_down", or "none")

## API

```lua
local autoread = require("autoread")

-- Enable autoread with optional temporary interval
autoread.enable(1000) -- Check every 1000ms temporarily

-- Disable autoread
autoread.disable()

-- Toggle autoread with optional temporary interval
autoread.toggle(1000) -- Toggle with temporary 1000ms interval

-- Check if enabled
autoread.is_enabled()

-- Get configured interval
autoread.get_interval()

-- Set new default interval in configuration
autoread.set_interval(2000)

-- Updates the current timer to the desired interval temporarily
autoread.update_interval(500)

-- Set cursor behavior
autoread.set_cursor_behavior("preserve") -- "preserve", "scroll_down", or "none"
```

### Events

The plugin triggers the following User events that you can hook into:

- `AutoreadPreCheck` - Before checking files for changes
- `AutoreadPostCheck` - After checking files for changes
- `AutoreadPreReload` - Before reloading changed files
- `AutoreadPostReload` - After reloading changed files

Example of using events:

```lua
vim.api.nvim_create_autocmd("User", {
    pattern = "AutoreadPostReload",
    callback = function(event)
        -- event.data contains the FileChangedShellPost event data
        print("File reloaded:", event.data.file)
    end,
})
```

## License

[MIT](./LICENSE)
