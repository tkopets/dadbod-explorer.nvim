local M = {}


function M.show_in_preview(lines, filetype)
    local filename = vim.fn.tempname() .. ".dbexp"
    filename = vim.fn.fnameescape(filename)

    vim.cmd("silent! botright pedit! " .. filename)

    local buf_nr = vim.fn.bufnr(filename)
    local win_id = vim.fn.bufwinid(buf_nr)

    vim.wo[win_id].wrap = false

    vim.bo[buf_nr].buftype = 'nofile'
    vim.bo[buf_nr].bufhidden = 'hide'
    vim.bo[buf_nr].buflisted = false
    vim.bo[buf_nr].swapfile = false

    vim.api.nvim_buf_set_lines(buf_nr, 0, -1, false, lines)

    vim.bo[buf_nr].modifiable = false

    if filetype then
        vim.bo[buf_nr].filetype = filetype
    end
end

function M.ask_for_filter_condition(callback, prompt)
    local input_prompt = prompt
    if not prompt then
        input_prompt = "Enter WHERE clause (or leave blank): "
    end
    local filter_condition
    vim.ui.input(
        { prompt = input_prompt },
        function(input)
            filter_condition = (input == "") and '1=1' or input
            callback(filter_condition)
        end
    )
end

function M.append_to_results(results, title, obj_list)
    if obj_list and #obj_list > 0 then
        table.insert(results, title)
        local header_decor, _ = string.gsub(title, '.', '-')
        table.insert(results, header_decor)
    end

    for _, object in ipairs(obj_list) do
        table.insert(results, object)
    end

    if obj_list and #obj_list > 0 then
        table.insert(results, '')
    end
end

function M.split_at_last_dot(str)
    local last_dot_pos = string.match(str, ".*%.()")
    if not last_dot_pos then
        return str, nil
    end
    local before = string.sub(str, 1, last_dot_pos - 2)
    local after = string.sub(str, last_dot_pos)
    return before, after
end

function M.size_pretty(bytes)
    if type(bytes) ~= "number" then
        return "Invalid Input"
    end

    if bytes < 0 then
        return "-" .. M.human_readable_size(bytes)
    end

    if bytes == 0 then
        return "0"
    end

    local units = { "b", "KB", "MB", "GB", "TB", "PB" }
    local i = 1
    local num = bytes

    while num >= 1024 and i < #units do
        num = num / 1024
        i = i + 1
    end

    -- remove trailing zeros and the decimal point if unnecessary
    return string.format("%.2f", num):gsub("%.?0+$", "") .. " " .. units[i]
end

function M.unix_timestamp_to_iso(unix_timestamp)
    if type(unix_timestamp) ~= "number" then
        return "Invalid Input"
    end
    return os.date("!%Y-%m-%d %H:%M:%S UTC", unix_timestamp)
end

function M.format_int(number)
    local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')

    -- reverse the int-string and append a comma to all blocks of 3 digits
    int = int:reverse():gsub("(%d%d%d)", "%1,")

    -- reverse the int-string back remove an optional comma and put the
    -- optional minus and fractional part back
    return minus .. int:reverse():gsub("^,", "") .. fraction
end

return M
