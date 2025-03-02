local M = {}

local utils = require("dadbod-explorer.utils")
local dadbod = require("dadbod-explorer.dadbod")

local db_adapters = {}
local actions_order = {
    "describe",
    "show_sample",
    "show_filter",
    "show_distribution",
    "yank_columns",
    "list_objects"
}
local cache = {}

local function get_adapter(conn)
    if not conn then return nil end
    local parsed_url = vim.fn['db#url#parse'](conn)
    if not parsed_url then
        utils.handle_error("Invalid DB URL")
        return nil
    end

    local adapter_name = parsed_url.scheme
    if not adapter_name then
        utils.handle_error("Could not determine adapter")
        return nil
    end
    local adapter = db_adapters[adapter_name]
    if not adapter then
        utils.handle_error("No adapter found for: " .. adapter_name)
        return nil
    end
    return adapter
end

local function action_process_item(conn, action_data, selected_object)
    if not conn or not action_data or not selected_object then return nil end
    if selected_object and action_data.process_item then
        action_data.process_item(conn, selected_object)
    end
end

local function get_action_object_list(conn, action_data)
    if not action_data or not action_data.object_list or not conn then
        return nil
    end

    local conn_hashed = utils.simple_hash(conn)

    -- return cached, if found
    if cache[conn_hashed] ~= nil then
        local cached_object_list = cache[conn_hashed][action_data.object_list]
        if cached_object_list ~= nil then
            return cached_object_list
        end
    end

    local object_list = action_data.object_list(conn)

    -- save to cache
    if cache[conn_hashed] == nil then cache[conn_hashed] = {} end
    cache[conn_hashed][action_data.object_list] = object_list

    if not object_list then return nil end
    return object_list
end

local function select_object(conn, action_data)
    if not action_data or not action_data.object_list then return nil end

    local object_list = get_action_object_list(conn, action_data)
    if not object_list then return nil end

    local items = {}
    for _, obj in ipairs(object_list) do
        local label = obj
        if action_data.format_item then
            label = action_data.format_item(obj)
        end
        table.insert(items, {
            value = obj,
            label = label,
            ordinal = obj
        })
    end

    if #items == 0 then return nil end

    vim.ui.select(items, {
            prompt = "Select Object",
            format_item = function(item) return item.label end
        },
        function(choice)
            local selected_object = choice and choice.value
            action_process_item(conn, action_data, selected_object)
        end
    )
end

local function perform_action(conn, action_data)
    if not action_data then return end

    if action_data.object_list then
        select_object(conn, action_data)
    elseif action_data.process_item then
        action_data.process_item(conn)
    end
end

local function select_action(conn, adapter)
    local actions = adapter.get_actions()
    local sorted_action_keys = utils.custom_sort_keys(actions, actions_order)

    local items = {}
    for _, key_action_name in ipairs(sorted_action_keys) do
        local action_data = actions[key_action_name]
        table.insert(items, {
            value = key_action_name,
            label = action_data.label,
            ordinal = action_data.label
        })
    end

    if #items == 0 then
        vim.notify(
            "dadbod-explorer: No actions available",
            vim.log.levels.DEBUG
        )
        return nil
    end

    vim.ui.select(items, {
            prompt = "Select Action (Optional)",
            format_item = function(item) return item.label end
        },
        function(choice)
            local sel_action_name = choice and choice.value
            local action_data = sel_action_name and actions[sel_action_name]
            perform_action(conn, action_data)
        end
    )
end

function M.explore(db_url)
    local conn = dadbod.get_connection(db_url)
    if not conn then return end

    local adapter = get_adapter(conn)
    if not adapter then return end

    select_action(conn, adapter)
end

function M.action(action_name)
    if action_name == "explore" then
        return function(url) M.explore(url) end
    end

    return function(db_url)
        local conn = dadbod.get_connection(db_url)
        if not conn then return end

        local adapter = get_adapter(conn)
        if not adapter then return end

        local actions = adapter.get_actions()
        local action_data = actions[action_name]
        if not action_data then
            vim.notify(
                "dadbod-explorer: unknow action",
                vim.log.levels.DEBUG
            )
            return
        end

        perform_action(conn, action_data)
    end
end

function M.setup(opts)
    if dadbod.has_dadbod() then
        require("dadbod-explorer.adapter.postgresql")
        require("dadbod-explorer.adapter.bigquery")
    else
        utils.handle_error("vim-dadbod is required but not installed.")
    end

    if opts and opts.mappings then
        for mode, mappings in pairs(opts.mappings) do
            for lhs, action_name in pairs(mappings) do
                vim.keymap.set(
                    mode,
                    lhs,
                    M.action(action_name),
                    { noremap = true, silent = true }
                )
            end
        end
    end
end

function M.register_adapter(adapter)
    if not adapter.name then
        utils.handle_error("Adapter must have a name."); return
    end
    if not adapter.get_actions or type(adapter.get_actions) ~= "function" then
        utils.handle_error("Adapter must have get_actions function"); return
    end
    db_adapters[adapter.name] = adapter
end

return M
