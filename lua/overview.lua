local api = vim.api
local Overview = {}
local markdown = require("filetypes.markdown")

Overview.config = {
    window = {
        location = "right", -- or "left"
        width = 32,
        wrap = true,        -- text wap for long section titles
        list = false,       -- show listchars in the floating window (BROKEN?)
        winblend = 25,      -- transparency setting
        zindex = 21,        -- floating window 'priority'
    },
    toc = {
        maxlevel = 3,                  -- max. nesting level in table of contents
        foldenable = true,             -- fold (i.e. hide) nested sections in table of contents
        foldlevel = 2,                 -- enable folding beyond this nesting level
        autoupdate = true,             -- automatically update TOC when the connected buffer is changed
    },
    refresh = { augroup = "Overview" } -- autocommand group for refresh autocommands
}

Overview.state = {
    parser = nil, -- parser function appropriate for the source buffer type
    anchors = {}, -- anchors that the parsed headings refer to
    sbuf = -1,    -- source buffer ID
    obuf = -1,    -- TOC buffer ID
    owin = -1,    -- TOC window ID
}


-- Return parser for the current filetype (nil if unsupported).
local function get_parser()
    -- local bt = vim.o.buftype
    local ft = vim.o.filetype
    local parser = nil
    if ft == "markdown" then
        parser = markdown.get_headings
    end
    return parser
end

-- Generate TOC from 'tree' of headings.
local function decorate_headings(headings)
    -- TODO: Put shortened buffer name at the top of the TOC? Use floatwin title?
    result = {}
    for _, v in pairs(headings) do
        if v.level > 1 then
            table.insert(result, "+" .. string.rep("-", 2 * v.level - 3) .. " " .. v.text)
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
    -- NOTE: Using nvim_win_set_cursor with any winid except 0 seems to be broken.
    -- Therefore, we need to explicitly focus the correct window first.
    api.nvim_set_current_win(vim.fn.bufwinid(api.nvim_buf_get_name(Overview.state.sbuf)))
    api.nvim_win_set_cursor(0, { Overview.state.anchors[tonumber(opts.line1)], 0 })
end

-- Make TOC and draw to buffer.
local function draw()
    api.nvim_buf_set_option(Overview.state.obuf, "modifiable", true)
    local content = table.concat(api.nvim_buf_get_lines(Overview.state.sbuf, 0, -1, true), "\n")
    local headings = Overview.state.parser(content)
    store_anchors(headings)
    opts = { desc = "Jump to anchor in source buffer", range = true }
    api.nvim_buf_create_user_command(Overview.state.obuf, "Jump", jump, opts)
    opts.range = nil
    api.nvim_buf_set_keymap(Overview.state.obuf, "n", [[<Cr>]], [[<Cmd>Jump<Cr>]], opts)
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
    augroup = api.nvim_create_augroup(Overview.config.refresh.augroup, {})
    local au = function(event, pattern, callback, desc)
        api.nvim_create_autocmd(
            event, { group = Overview.config.refresh.augroup, pattern = pattern, callback = callback, desc = desc }
        )
    end
    au({ "BufWritePost", "TextChanged" }, "*", Overview.refresh, "[overview.nvim] Refresh TOC contents")
    au(
        "VimResized", "*",
        vim.schedule_wrap(function() api.nvim_win_set_height(Overview.state.owin, get_avail_height()) end),
        "[overview.nvim] Resize TOC window"
    )
    au("BufEnter", "*", Overview.swap, "[overview.nvim] Swap TOC source if possible")
end

-- Delete autocommands and augroup.
local function delete_autocommands() api.nvim_del_augroup_by_name(Overview.config.refresh.augroup) end

-- Create new or focus existing TOC window.
local function show(buf, win)
    -- buf: handle to possibly existing buffer
    -- win: handle to possibly existing window
    local wc = vim.o.columns
    local width = Overview.config.window.width
    if width - 2 > wc then
        api.nvim_err_writeln("[overview.nvim]: Window is too narrow for TOC display!")
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
        api.nvim_set_current_win(vim.fn.bufwinid(api.nvim_buf_get_name(Overview.state.sbuf)))
    else
        api.nvim_set_current_win(Overview.state.owin)
    end
end

-- Open new TOC for current buftype, if supported.
function Overview.open()
    parser = get_parser()
    if parser == nil then
        api.nvim_err_writeln("[overview.nvim]: Unsupported filetype.")
        return
    end
    Overview.state.parser = parser
    Overview.state.sbuf = api.nvim_win_get_buf(0)
    Overview.state.obuf, Overview.state.owin = show(Overview.state.obuf, Overview.state.owin)
    draw()
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

-- Close possibly existing TOC.
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

create_autocommands()
return Overview
