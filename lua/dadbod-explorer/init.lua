local M = {}

local utils = require("dadbod-explorer.utils")
local dadbod = require("dadbod-explorer.dadbod")

---@alias option_fn fun(conn:string, action_name:string):any
---@class DbExplorerOpts
---@field sample_size? integer|fun(conn:string, action_name:string):integer
---@field adapter? table<string, table<string, any|option_fn>>
---@field mappings? table<string, table<string, string>>
local plugin_opts = {
    sample_size = 100,
    cache_object_list = function(conn)
        if dadbod.connection_scheme(conn) == 'bigquery' then
            return 60 * 60 * 2 -- 2 hours
        end
        return 0
    end,
    cache_results = false,
    adapter = {
        bigquery = {
            regions = { 'region-eu', 'region-us' }
        }
    }
}

---@class DbExplorerAction
---@field label string Action label
---@field object_list fun(conn: string, plugin_opts: DbExplorerOpts): any[] List of objects for selection
---@field format_item fun(conn: string, obj: any, plugin_opts: DbExplorerOpts): string Format single item for display
---@field process_item fun(conn: string, obj: any, plugin_opts: DbExplorerOpts) Perform action on selected item

---@class DbExplorerAdapter
---@field name string Adapter name which corresponds to dadbod adapter scheme
---@field get_actions fun(): table<string, DbExplorerAction>

---@type table<string, DbExplorerAdapter>
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

---@param conn string
---@return DbExplorerAdapter | nil
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

---@param conn string
---@param action_data DbExplorerAction
local function action_process_item(conn, action_data, selected_object)
    if not conn or not action_data then return nil end
    if action_data.process_item then
        action_data.process_item(conn, selected_object, plugin_opts)
    end
end


---@param conn string
---@param action_name string
---@return number
local function get_object_list_cache_age(conn, action_name)
    local val = utils.get_option(
        conn,
        action_name,
        plugin_opts,
        { 'cache_object_list' },
        { 'number', 'boolean' },
        nil
    )
    if not val then return 0 end
    return val
end


---@param conn string
---@param action_data DbExplorerAction
---@param action_name string
local function get_action_object_list(conn, action_data, action_name)
    if not action_data or not action_data.object_list or not conn then
        return nil
    end

    local conn_hashed
    local cache_section = 'object_list'
    local cache_age = get_object_list_cache_age(conn, action_name)
    if cache_age > 0 then
        conn_hashed = utils.simple_hash(conn)

        -- return cached, if found
        if cache[conn_hashed] ~= nil and cache[conn_hashed][cache_section] ~= nil then
            local cache_entry = cache[conn_hashed][cache_section][action_data.object_list]
            if cache_entry ~= nil and cache_entry.expiration >= os.time() then
                return cache_entry.data
            else
                cache[conn_hashed][cache_section][action_data.object_list] = nil
            end
        end
    end

    local object_list = action_data.object_list(conn, plugin_opts)

    if cache_age > 0 then
        -- save to cache
        if cache[conn_hashed] == nil then cache[conn_hashed] = {} end
        if cache[conn_hashed][cache_section] == nil then cache[conn_hashed][cache_section] = {} end
        cache[conn_hashed][cache_section][action_data.object_list] = {
            expiration = os.time() + cache_age,
            data = object_list
        }
    end

    if not object_list then return nil end
    return object_list
end

---@param conn string
---@param action_data DbExplorerAction
---@param action_name string
local function select_object(conn, action_data, action_name)
    if not action_data or not action_data.object_list then return nil end

    local object_list = get_action_object_list(conn, action_data, action_name)
    if not object_list then return nil end

    local items = {}
    for _, obj in ipairs(object_list) do
        local label = obj
        if action_data.format_item then
            label = action_data.format_item(conn, obj, plugin_opts)
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
            if not selected_object then return end
            action_process_item(conn, action_data, selected_object)
        end
    )
end

---@param conn string
---@param action_data DbExplorerAction
---@param action_name string
local function perform_action(conn, action_data, action_name)
    if not action_data then return end

    if action_data.object_list then
        select_object(conn, action_data, action_name)
    elseif action_data.process_item then
        action_process_item(conn, action_data, nil)
    end
end

---@param conn string
---@param adapter DbExplorerAdapter
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
            local action_name = choice and choice.value
            local action_data = action_name and actions[action_name]
            if not action_data then return end
            perform_action(conn, action_data, action_name)
        end
    )
end

---@param db_url string | nil
function M.explore(db_url)
    local conn = dadbod.get_connection(db_url)
    if not conn then return end

    local adapter = get_adapter(conn)
    if not adapter then return end

    select_action(conn, adapter)
end

---@param action_name string
---@return fun(db_url: string)
function M.action(action_name)
    if action_name == "explore" then
        return function(db_url) M.explore(db_url) end
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

        perform_action(conn, action_data, action_name)
    end
end

---@param conn string
---@param action_name string
---@return number
function M.get_sample_size(conn, action_name)
    local val = utils.get_option(
        conn,
        action_name,
        plugin_opts,
        { 'sample_size' },
        'number',
        100
    )
    return val
end

---@param opts? DbExplorerOpts
function M.setup(opts)
    if dadbod.has_dadbod() then
        require("dadbod-explorer.adapter.postgresql")
        require("dadbod-explorer.adapter.mysql")
        require("dadbod-explorer.adapter.bigquery")
    else
        utils.handle_error("vim-dadbod is required but not installed.")
    end

    if opts then
        for k, v in pairs(opts) do
            plugin_opts[k] = v
        end
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

function M.clear_cache()
    cache = {}
end

---@param adapter DbExplorerAdapter
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
