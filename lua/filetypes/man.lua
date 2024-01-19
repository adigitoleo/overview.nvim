local Man = {}

function Man.get_headings(man_text)
    local result = {}
    local section_pattern = "^%u[%u%s]+$"
    -- the "normal" text block is indented by 5 spaces for mdoc and 7 for man by default
    -- assume that anything with 4 or less leading spaces is a subsection header
    local subsection_pattern = "^%s%s?%s?%s?%a.-$"
    local option_pattern = "^%s*[-][-]?%a.-$" -- previous line must also be empty
    local line_number = 1
    local prev_line_empty = false
    for line in man_text:gmatch("([^\r\n]*)\r?\n?") do
        local section = line:match(section_pattern)
        local subsection = line:match(subsection_pattern)
        local option = line:match(option_pattern)
        if section then
            table.insert(result,
                {
                    line = line_number,
                    text = section,
                    level = 1,
                }
            )
        elseif subsection then
            local count = 0
            s, l = subsection:gsub("^%s+", function(match)
                count = #match; return ""
            end)
            table.insert(result,
                {
                    line = line_number,
                    text = s,
                    level = count > 2 and 3 or 2, -- one level for every two indent spaces
                })
        elseif prev_line_empty and option then
            table.insert(result,
                {
                    line = line_number,
                    text = option:gsub("^%s+", ""):gsub("%s%s.*$", ""),
                    level = 4 -- subsections can only be level 3 max
                }
            )
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

return Man
