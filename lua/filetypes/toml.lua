local Toml = {}

function Toml.get_headings(toml_text)
    local result = {}
    local line_number = 1
    for line in toml_text:gmatch("([^\r\n]*)\r?\n?") do
        local match = line:match("^%[%[?([%w%.]+)%]%]?[%s#]*.*$")
        if match then
            local level = 1
            local t, l = match:gsub("%w+%.", "")
            table.insert(result,
                {
                    line = line_number,
                    text = t,
                    level = level + l,
                }
            )
        end
        line_number = line_number + 1
    end
    return result
end

return Toml
