local Help = {}

function Help.get_headings(help_text)
    local result = {}
    -- some patterns taken from $VIMRUNTIME/syntax/help.vim
    local section_pattern = "^[=][=][=].*[=][=][=]$"   --- heading on next line
    local subsection_pattern = "^[-][-][-].*[-][-]$" --- heading/tag on next line
    -- for the next two patterns, the previous line must also be empty
    local chapter_pattern = "^%u[%u%s]*$"
    local column_heading_pattern = "^%u[%a%s]*[~]$" -- for so-called 'column headings' (:h help-writing)
    local line_number = 1
    local prev_line_empty = false
    local pending_heading = nil
    for line in help_text:gmatch("([^\r\n]*)\r?\n?") do
        local section = line:match(section_pattern)
        local subsection = line:match(subsection_pattern)
        local chapter = line:match(chapter_pattern)
        local column_heading = line:match(column_heading_pattern)
        local entry = { line = line_number }
        if pending_heading == "section" then
            entry.text = line:gsub("^%s*", ""):gsub("%s%s.*$", "")
            entry.level = 1
            table.insert(result, entry)
            pending_heading = nil
        elseif pending_heading == "subsection" then
            entry.text = line:gsub("^%s*[*]?", ""):gsub("%s%s.*$", ""):gsub("[*]$", "")
            entry.level = 2
            table.insert(result, entry)
            pending_heading = nil
        elseif section then
            pending_heading = "section"
        elseif subsection then
            pending_heading = "subsection"
        elseif prev_line_empty and chapter then
            entry.text = chapter
            entry.level = 3
            table.insert(result, entry)
        elseif prev_line_empty and column_heading then
            entry.text = column_heading:gsub("[~]$", "")
            entry.level = 4
            table.insert(result, entry)
        end
        if line:match("^$") then
            prev_line_empty = true
        else
            prev_line_empty = false
        end
        line_number = line_number + 1
    end
    return result
end

return Help
