local M = {}

---@param err string
function M.handle_error(err)
    vim.api.nvim_err_writeln("dadbod-explorer error: " .. err)
end

---@param conn string
---@param opts table
---@param opts_path string[]
---@param types string | string[]
---@param default any
function M.get_option(conn, opts, opts_path, types, default)
    local function get_val(data, path)
        local current = data
        for _, key in ipairs(path) do
            if type(current) ~= "table" or current[key] == nil then
                return nil
            end
            current = current[key]
        end
        return current
    end

    local setting = get_val(opts, opts_path)

    if type(setting) == 'function' then
        return setting(conn)
    end

    if type(types) == 'string' then
        if type(setting) == types then
            return setting
        end
    end

    if type(types) == 'table' then
        for _, typ in ipairs(types) do
            if type(setting) == typ then
                return setting
            end
        end
    end

    return default
end

---@param str string
---@return integer
function M.simple_hash(str)
    local h = 0
    for i = 1, #str do
        h = (h * 31 + string.byte(str, i)) % 2 ^ 32
    end
    return h
end

--- Sorts the keys of a table based on a custom order.
---
--- If a key from `table_to_sort` is present in `order_array`, it will be placed
--- according to its index in `order_array`.  Keys not present in `order_array`
--- will be placed at the end, sorted lexicographically.
---
---@param table_to_sort table<any, any> The table whose keys should be sorted.
---@param order_array any[] An array defining the desired order of keys.
---@return any[] . An array of keys from `table_to_sort`, sorted according to the custom order.
function M.custom_sort_keys(table_to_sort, order_array)
    local order_map = {}
    for i, val in ipairs(order_array) do
        order_map[val] = i
    end

    local keys = {}
    for k, _ in pairs(table_to_sort) do
        table.insert(keys, k)
    end

    local function compare_func(a, b)
        local order_a = order_map[a]
        local order_b = order_map[b]

        if order_a and order_b then
            return order_a < order_b
        elseif order_a then
            return true
        elseif order_b then
            return false
        else
            return a < b
        end
    end

    table.sort(keys, compare_func)
    return keys
end

return M
