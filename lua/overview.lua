local api = vim.api
local Overview = {}
local markdown = require("filetypes.markdown")
local man = require("filetypes.man")
local help = require("filetypes.help")
local toml = require("filetypes.toml")

Overview.config = {
    window = {
        location = "right", -- or "left"
        width = 32,
        wrap = true,        -- text wrap for long section titles
        list = false,       -- show listchars in the floating window (BROKEN?)
        winblend = 25,      -- transparency setting
        zindex = 21,        -- floating window 'priority'
    },
    toc = {
        maxlevel = 3,              -- max. nesting level in table of contents
    },
    augroup = "Overview",          -- name of overview.nvim autocommand group
    remove_default_bindings = true -- remove default binding of gO to :lua require('man').show_toc()` or similar
}

Overview.state = {
    parser = nil, -- parser function appropriate for the source buffer type
    anchors = {}, -- anchors that the parsed headings refer to
    sbuf = -1,    -- source buffer ID
    obuf = -1,    -- TOC buffer ID
    owin = -1,    -- TOC window ID
}

local function warn(msg) api.nvim_err_writeln("[overview.nvim]: " .. msg) end

-- Validate custom user config, fall back to defaults defined above.
local function validate(key, value, section)
    local cfg = Overview.config
    local option = key .. " = " .. value
    if section then
        option = table.concat({ section, key }, ".") .. " = " .. value
        if section == "window" and cfg.window[key] ~= nil then
            if key == "location" and not (value == "right" or value == "left") then
                warn(option .. " must be 'right' or 'left'")
                return cfg[section][key]
            elseif (key == "width" or key == "winblend" or key == "zindex") and not type(value) == "number" then
                warn(option .. " must be a number")
                return cfg[section][key]
            elseif (key == "wrap" or key == "list") and not type(value) == "bool" then
                warn(option .. " must be a boolean")
                return cfg[section][key]
            end
        elseif section == "toc" and cfg.toc[key] ~= nil then
            if key == "maxlevel" and not type(value) == "number" then
                warn(option .. " must be a number")
                return cfg[section][key]
            end
        else
            warn("unrecognized config option " .. option)
        end
    elseif cfg[key] ~= nil then
        if key == "augroup" and not type(value) == "string" then
            warn(option .. " must be a string")
            return cfg[section][key]
        elseif key == "remove_default_bindings" and not type(value) == "bool" then
            warn(option .. " must be a boolean")
            return cfg[section][key]
        end
    else
        warn("unrecognized config option " .. option)
    end
    return value
end

-- Return parser for the current filetype (nil if unsupported).
local function get_parser()
    local ft = vim.o.filetype
    local parser = nil
    if ft == "markdown" then
        parser = markdown.get_headings
    elseif ft == "man" then
        parser = man.get_headings
    elseif ft == "help" then
        parser = help.get_headings
    elseif ft == "toml" or ft == "dosini" then
        -- NOTE: technically, [[double.bracket]] TOML headings are not valid in .ini,
        -- but .ini files are often used for non-strict config files anyway so I allow it.
        parser = toml.get_headings
    end
    return parser
end

-- Generate TOC from 'tree' of headings.
local function decorate_headings(headings)
    -- TODO: Put shortened buffer name at the top of the TOC? Use floatwin title?
    result = {}
    for _, v in pairs(headings) do
        if v.level > 1 then
            if (v.level - 1) <= Overview.config.toc.maxlevel then
                table.insert(result, "+" .. string.rep("-", 2 * v.level - 3) .. " " .. v.text)
            end
        else
            table.insert(result, v.text)
        end
    end
    return result
end

-- Save TOC document anchors from parsed heading metadata.
local function store_anchors(headings)
    Overview.state.anchors = {}
    for _, v in pairs(headings) do
        table.insert(Overview.state.anchors, v.line)
    end
end

-- Jump to anchor in source buffer.
local function jump(opts)
    vim.schedule(function()
        -- NOTE: Using nvim_win_set_cursor with any winid except 0 seems to be broken.
        -- Therefore, we need to explicitly focus the correct window first.
        api.nvim_set_current_win(vim.fn.bufwinid(api.nvim_buf_get_name(Overview.state.sbuf)))
        api.nvim_win_set_cursor(0, { Overview.state.anchors[tonumber(opts.line1)], 0 })
    end)
end

-- Make TOC and draw to buffer.
local function draw()
    api.nvim_buf_set_option(Overview.state.obuf, "modifiable", true)
    local content = table.concat(api.nvim_buf_get_lines(Overview.state.sbuf, 0, -1, true), "\n")
    local headings = Overview.state.parser(content)
    store_anchors(headings)
    api.nvim_buf_set_lines(Overview.state.obuf, 0, -1, true, decorate_headings(headings))
    api.nvim_buf_set_option(Overview.state.obuf, "modifiable", false)
end

-- Get available height for floating sidebars.
local function get_avail_height()
    local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
    local has_statusline = vim.o.laststatus > 0
    -- NOTE: The last -2 here is for the border.
    return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2
end

-- Create autocommands and augroup.
local function create_autocommands()
    augroup = api.nvim_create_augroup(Overview.config.augroup, {})
    local au = function(event, pattern, callback, desc)
        api.nvim_create_autocmd(
            event, { group = Overview.config.augroup, pattern = pattern, callback = callback, desc = desc }
        )
    end
    au({ "BufWritePost", "TextChanged" }, "*", Overview.refresh, "[overview.nvim] Refresh TOC contents")
    au(
        "VimResized", "*",
        vim.schedule_wrap(function() api.nvim_win_set_height(Overview.state.owin, get_avail_height()) end),
        "[overview.nvim] Resize TOC window"
    )
    au("BufEnter", "*", Overview.swap, "[overview.nvim] Swap TOC source if possible")
    if Overview.config.remove_default_bindings then
        au("FileType", "man,help", function() api.nvim_buf_del_keymap(0, "n", "gO") end)
    end
end

-- Delete autocommands and augroup.
local function delete_autocommands() api.nvim_del_augroup_by_name(Overview.config.augroup) end

-- Create new TOC sidebar window or focus existing one.
local function create_sidebar(buf, win)
    local wc = vim.o.columns
    local width = Overview.config.window.width
    if width - 2 > wc then
        warn("Window is too narrow for TOC display!")
        return
    end
    if not api.nvim_buf_is_valid(buf) then
        buf = api.nvim_create_buf(false, true)
    end
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "filetype", "overview")
    if not api.nvim_win_is_valid(win) then
        win = api.nvim_open_win(buf, true, {
            border = { { " ", "NormalFloat" }, },
            relative = "editor",
            style = "minimal",
            zindex = Overview.config.zindex,
            width = width,
            height = get_avail_height(),
            col = Overview.config.window.location == "left" and 0 or wc - width,
            row = 0,
        })
        api.nvim_win_set_option(win, "winblend", Overview.config.window.winblend)
        api.nvim_win_set_option(win, "wrap", Overview.config.window.wrap)
        api.nvim_win_set_option(win, "list", Overview.config.window.list)
    else
        api.nvim_set_current_win(win)
    end
    return buf, win
end

-- Toggle TOC sidebar for current filetype, if supported.
function Overview.toggle()
    if api.nvim_win_is_valid(Overview.state.owin) then
        Overview.close()
    else
        Overview.open()
    end
end

-- Toggle TOC sidebar focus, if open.
function Overview.focus()
    if not api.nvim_win_is_valid(Overview.state.owin) then return end
    if vim.fn.win_getid() == Overview.state.owin then
        local win = vim.fn.bufwinid(api.nvim_buf_get_name(Overview.state.sbuf))
        -- the source buffer should not just be valid but also visible if we are trying to focus it
        if Overview.state.sbuf >= 0 and win >= 0 then
            api.nvim_set_current_win(win)
        else
            Overview.close()
        end
    else
        api.nvim_set_current_win(Overview.state.owin)
    end
end

-- Open new TOC for current buftype, if supported.
function Overview.open()
    parser = get_parser()
    if parser == nil then
        warn("Unsupported filetype.")
        return
    end
    Overview.state.parser = parser
    Overview.state.sbuf = api.nvim_win_get_buf(0)
    Overview.state.obuf, Overview.state.owin = create_sidebar(Overview.state.obuf, Overview.state.owin)
    draw()
    opts = { desc = "Jump to anchor in source buffer", range = true }
    api.nvim_buf_create_user_command(Overview.state.obuf, "Jump", jump, opts)
    opts.range = nil
    api.nvim_buf_set_keymap(Overview.state.obuf, "n", [[<Cr>]], [[<Cmd>Jump<Cr>]], opts)
    api.nvim_buf_set_keymap(Overview.state.obuf, "n", [[<LeftRelease>]], [[<Cmd>Jump<Cr>]], opts)
end

-- Swap TOC source to current buffer, if supported.
function Overview.swap()
    if api.nvim_win_is_valid(Overview.state.owin) then
        parser = get_parser()
        if parser == nil then return end -- No errors, just keep the old TOC in the window.
        Overview.state.parser = parser
        Overview.state.sbuf = api.nvim_win_get_buf(0)
        draw()
    end
end

-- Close possibly existing TOC sidebar.
function Overview.close()
    if api.nvim_win_is_valid(Overview.state.owin) then
        api.nvim_win_close(Overview.state.owin, true)
    end
    if api.nvim_buf_is_valid(Overview.state.obuf) then
        api.nvim_buf_delete(Overview.state.obuf, { force = true })
    end
end

-- Refresh existing TOC or close if corrupted/invalid.
function Overview.refresh()
    if api.nvim_win_is_valid(Overview.state.owin) and api.nvim_buf_is_valid(Overview.state.obuf) then
        draw()
    else
        vim.schedule(Overview.close) -- Clean up TOC window/buffer, augroup, etc.
    end
end

-- Reset TOC window to reload config and autocommands.
function Overview.reset()
    Overview.close()
    delete_autocommands()
    Overview.open()
    create_autocommands()
end

-- Setup function to allow and validate user configuration.
function Overview.setup(config)
    Overview.close()
    delete_autocommands()
    for k, v in pairs(config) do
        if type(v) == "table" then
            for _k, _v in pairs(v) do
                Overview.config[k][_k] = validate(_k, _v, k)
            end
        else
            Overview.config[k] = validate(k, v)
        end
    end
    create_autocommands()
    return Overview
end

create_autocommands()
return Overview
