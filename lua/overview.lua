local api = vim.api
local fn = vim.fn
local lsp = vim.lsp
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
        maxlevel = 3, -- max. nesting level in table of contents
    },
    -- For the list of named LSP symbol types, check the symbolKind table at:
    -- <https://lsp-devtools.readthedocs.io/en/latest/capabilities/text-document/document-symbols.html#symbolkind>
    -- Fallbacks apply to all code filetypes that do not have an explicit whitelist pattern table set.
    lsp_const_symbolkinds = { -- Whitelist of symbolKind patterns for constants (global scope)
        _fallback = { "%[Variable%]%s+%u+", "%[Constant%]" },
    },
    lsp_scoped_symbolkinds = { -- Whitelist of symbolKind patterns for any local scope
        _fallback = { "%[Constructor%]", "%[Enum%]", "%[Function%]", "%[Class%]", "%[Method%]", "%[Namespace%]", "%[Struct%]" },
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
        elseif section == "lsp_const_symbolkinds" or section == "lsp_scoped_symbolkinds" then
            if not type(value) == "table" then
                warn(option .. " must be a table")
                if key == "_fallback" then return cfg[section][key] end
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
    elseif not vim.tbl_isempty(lsp.get_active_clients({ bufnr = fn.bufnr() })) then
        parser = "lsp-on-list-handler"
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

-- Save TOC document anchors from parsed heading metadata or |setqflist-what| table.
local function store_anchors(headings, is_lsp_list_source)
    Overview.state.anchors = {}
    if is_lsp_list_source then
        for _, v in pairs(headings) do
            -- TODO: Also support v.col (column number), here and in jump().
            table.insert(Overview.state.anchors, v.lnum)
        end
    else
        for _, v in pairs(headings) do
            table.insert(Overview.state.anchors, v.line)
        end
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

-- Draw list of LSP symbols in floating buffer.
local function draw_lsp(options)
    local items = {}
    local lines = {}
    for _, v in pairs(options.items) do
        local ft = api.nvim_buf_get_option(Overview.state.sbuf, "filetype")
        -- Apply whitelist filter to list of LSP symbols from global scope.
        local const_symbolkinds = Overview.config.lsp_const_symbolkinds[ft]
        if const_symbolkinds == nil then const_symbolkinds = Overview.config.lsp_const_symbolkinds._fallback end
        for _, const_pattern in pairs(const_symbolkinds) do
            if v.col == 1 and string.find(v.text, const_pattern) ~= nil then
                table.insert(lines, v.text)
                table.insert(items, v)
            end
        end
        -- Apply whitelist filter to list of LSP symbols from all local scope.
        local scoped_symbolkinds = Overview.config.lsp_scoped_symbolkinds[ft]
        if scoped_symbolkinds == nil then scoped_symbolkinds = Overview.config.lsp_scoped_symbolkinds._fallback end
        for _, pattern in pairs(scoped_symbolkinds) do
            if string.find(v.text, pattern) ~= nil then
                table.insert(lines, v.text)
                table.insert(items, v)
            end
        end
    end
    store_anchors(items, true)
    api.nvim_buf_set_option(Overview.state.obuf, "modifiable", true)
    api.nvim_buf_set_lines(Overview.state.obuf, 0, -1, true, lines)
    api.nvim_buf_set_option(Overview.state.obuf, "modifiable", false)
end

-- Get available height for floating sidebars.
local function get_avail_height()
    local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
    local has_statusline = vim.o.laststatus > 0
    -- NOTE: The last -2 here is for the border.
    return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2
end

-- Make TOC and draw to buffer.
local function draw()
    local is_lsp_list_source = (Overview.state.parser == "lsp-on-list-handler")
    if is_lsp_list_source then
        lsp.buf.document_symbol({ on_list = draw_lsp })
    else
        local content = table.concat(api.nvim_buf_get_lines(Overview.state.sbuf, 0, -1, true), "\n")
        local headings = Overview.state.parser(content)
        store_anchors(headings, is_lsp_list_source)
        api.nvim_buf_set_option(Overview.state.obuf, "modifiable", true)
        api.nvim_buf_set_lines(Overview.state.obuf, 0, -1, true, decorate_headings(headings))
        api.nvim_buf_set_option(Overview.state.obuf, "buftype", "nofile")
        api.nvim_buf_set_option(Overview.state.obuf, "filetype", "overview")
        api.nvim_buf_set_option(Overview.state.obuf, "modifiable", false)
    end
end

-- Refresh existing TOC or close if corrupted/invalid.
function Overview.refresh()
    if api.nvim_win_is_valid(Overview.state.owin) then
        vim.schedule(draw)
    else
        vim.schedule(Overview.close) -- Clean up TOC window/buffer, augroup, etc.
    end
end

-- Swap TOC source to current buffer, if supported.
function Overview.swap()
    local parser = get_parser()
    if vim.o.filetype ~= "overview" and api.nvim_win_is_valid(Overview.state.owin) and parser ~= nil then
        Overview.state.parser = parser
        vim.schedule(function() Overview.state.sbuf = api.nvim_win_get_buf(0) end)
        Overview.refresh()
    end
end

-- Delete autocommands and augroup.
local function delete_autocommands()
    if Overview.state.augroup ~= nil then
        api.nvim_del_augroup_by_name(Overview.config.augroup)
    end
end

local function au(event, buf, pattern, callback, desc, once)
    -- NOTE: Can't use buf and pattern, must set one to nil.
    return api.nvim_create_autocmd(
        event,
        {
            buffer = buf,
            pattern = pattern,
            group = Overview.config.augroup,
            callback = callback,
            desc = desc,
            once = once
        }
    )
end

-- Create autocommands and augroup.
local function create_autocommands()
    api.nvim_create_augroup(Overview.config.augroup, {})
    -- Every (re)draw of the TOC must trigger filetype=overview.
    au("FileType", nil, "overview", function(ft_ev)
        -- Prevent putting any other buffers in the TOC window.
        -- This makes :b[n|N]ext, :bprevious and :b# equivalent to Overview.focus().
        au("BufWinLeave", ft_ev.buf, nil, vim.schedule_wrap(function()
            if api.nvim_win_is_valid(Overview.state.owin) then
                api.nvim_set_current_buf(ft_ev.buf)
                Overview.focus()
            end
        end))
        -- Watch for changes in source buffer.
        au({ "BufWritePost", "TextChanged" }, Overview.state.sbuf, nil, Overview.refresh,
            "[overview.nvim] Refresh TOC contents")
        au( -- Handle VimResized.
            "VimResized", Overview.state.obuf, nil,
            vim.schedule_wrap(function()
                if api.nvim_win_is_valid(Overview.state.owin) then
                    api.nvim_win_set_height(Overview.state.owin, get_avail_height())
                end
            end),
            "[overview.nvim] Resize TOC window"
        )
    end, nil, true) -- last arg true, otherwise infinite loop (set ft=overview, nvim_set_current_buf)
    au("BufEnter", nil, "*.*", Overview.swap, "[overview.nvim] Swap TOC source if possible")
    if Overview.config.remove_default_bindings then
        au("FileType", nil, "man,help", function() api.nvim_buf_del_keymap(0, "n", "gO") end,
            "[overview.nvim] Remove default gO mapping")
    end
end

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
            focusable = false,
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
        if (
                Overview.state.sbuf >= 0 and api.nvim_buf_is_valid(Overview.state.sbuf)
                and win >= 0 and api.nvim_win_is_valid(win)
            ) then
            vim.schedule(function() api.nvim_set_current_win(win) end)
        else
            vim.schedule(Overview.close)
        end
    else
        api.nvim_set_current_win(Overview.state.owin)
    end
end

-- Open new TOC for current buftype, if supported.
function Overview.open()
    local parser = get_parser()
    if parser == nil then
        warn("Unsupported filetype.")
        return
    else
        Overview.state.parser = parser
        Overview.state.sbuf = api.nvim_win_get_buf(0)
        Overview.state.obuf, Overview.state.owin = create_sidebar(Overview.state.obuf, Overview.state.owin)
        draw()
        local opts = { desc = "Jump to anchor in source buffer", range = true }
        api.nvim_buf_create_user_command(Overview.state.obuf, "Jump", jump, opts)
        opts.range = nil
        api.nvim_buf_set_keymap(Overview.state.obuf, "n", [[<Cr>]], [[<Cmd>Jump<Cr>]], opts)
        api.nvim_buf_set_keymap(Overview.state.obuf, "n", [[<LeftRelease>]], [[<Cmd>Jump<Cr>]], opts)
    end
    create_autocommands()
end

-- Close possibly existing TOC sidebar.
function Overview.close()
    if api.nvim_win_is_valid(Overview.state.owin) then
        api.nvim_win_close(Overview.state.owin, true)
    end
    if api.nvim_buf_is_valid(Overview.state.obuf) then
        api.nvim_buf_delete(Overview.state.obuf, { force = true })
    end
    delete_autocommands()
end

-- Setup function to allow and validate user configuration.
function Overview.setup(config)
    Overview.close()
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

return Overview.setup {}
