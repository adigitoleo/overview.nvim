local Markdown = {}

function Markdown.get_headings(markdown_text)
    local result = {}
    local pattern = "^[#]+%s.-$"
    local in_code_block = false
    local line_number = 1
    for line in markdown_text:gmatch("([^\r\n]*)\r?\n?") do
        if in_code_block and line:match("^```") then
            in_code_block = false
        elseif line:match("^```") then
            in_code_block = true
        elseif not in_code_block then
            local heading = line:match(pattern)
            if heading then
                s, l = heading:gsub("#%s?", "")
                table.insert(result,
                    {
                        line = line_number,
                        text = s,
                        level = l,
                    }
                )
            end
        end
        line_number = line_number + 1
    end
    return result
end

return Markdown
