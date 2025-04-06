local dadbod = require("dadbod-explorer.dadbod")
local utils = require("dadbod-explorer.utils")
local adapter_utils = require("dadbod-explorer.adapter")
local queries = require("dadbod-explorer.adapter.bigquery.queries")
local format = require("dadbod-explorer.adapter.bigquery.format")

local M = {}

local ObjKind = {
    TABLE = "table",
    VIEW = "view",
    FUNC = "function"
}

local function dadbod_bq_change_format(conn_url, output_format)
    local parsed_conn = vim.fn["db#url#parse"](conn_url)
    if parsed_conn and parsed_conn.params then
        parsed_conn.params.format = output_format
    end
    return vim.fn["db#url#format"](parsed_conn)
end

local function dadbod_bq_sql_results(conn, sql, output_format)
    local conn_str = dadbod_bq_change_format(conn, output_format)
    local db_dispatch_fn = vim.fn['db#adapter#dispatch']
    local command_to_dispatch = db_dispatch_fn(conn_str, 'filter')
    local sql_to_run = sql
    if type(sql_to_run) == 'table' then
        sql_to_run = table.concat(sql_to_run, "\n")
    end

    local db_systemlist_fn = vim.fn['db#systemlist']
    local result = db_systemlist_fn(command_to_dispatch, sql_to_run)
    return result
end

local function dadbod_bq_cmd_results(conn, command, output_format)
    local conn_str = dadbod_bq_change_format(conn, output_format)
    local db_dispatch_fn = vim.fn['db#adapter#dispatch']
    local command_to_dispatch = db_dispatch_fn(conn_str, 'filter')
    table.remove(command_to_dispatch, #command_to_dispatch)
    for _, v in ipairs(command) do
        table.insert(command_to_dispatch, v)
    end

    local db_systemlist_fn = vim.fn['db#systemlist']
    local result = db_systemlist_fn(command_to_dispatch, '') -- empty as stdin
    return result
end

local function format_bq_object(obj_name)
    -- format relation as "project:dataset.table" for commands
    local result, _ = string.gsub(obj_name, "%.", ":", 1)
    return result
end

local function dadbod_bq_sql_results_csv_no_header(conn, sql)
    local result = dadbod_bq_sql_results(conn, sql, "csv") or {}
    result = { unpack(result, 2) }
    return result
end

local function get_regions(conn, plugin_opts)
    local default = { 'region-eu', 'region-us' }
    local regions = utils.get_option(
        conn,
        plugin_opts,
        { 'adapter', 'bigquery', 'regions' },
        { 'string', 'table' },
        default
    )

    if not regions then
        return default
    end

    if type(regions) == 'string' then
        return { regions }
    end

    return regions
end

local function object_list_tables_in_regions(conn, regions)
    local sql = queries.objects.tables
    local items = {}

    for _, region in ipairs(regions) do
        local region_sql = string.gsub(sql, '`region%-us`', region)

        local objects = dadbod_bq_sql_results_csv_no_header(conn, region_sql)
        for _, obj in ipairs(objects) do
            table.insert(items, { kind = ObjKind.TABLE, name = obj })
        end
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function object_list_views_in_regions(conn, regions)
    -- return dadbod_bq_sql_results_csv_no_header(conn, queries.objects.views)
    local sql = queries.objects.views
    local items = {}

    for _, region in ipairs(regions) do
        local region_sql = string.gsub(sql, '`region%-us`', region)

        local objects = dadbod_bq_sql_results_csv_no_header(conn, region_sql)
        for _, obj in ipairs(objects) do
            table.insert(items, { kind = ObjKind.VIEW, name = obj })
        end
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function object_list_relations_in_regions(conn, regions)
    local items = {}

    for _, item in ipairs(object_list_tables_in_regions(conn, regions)) do
        table.insert(items, item)
    end

    for _, item in ipairs(object_list_views_in_regions(conn, regions)) do
        table.insert(items, item)
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function object_list_relations(conn, plugin_opts)
    local regions = get_regions(conn, plugin_opts)
    return object_list_relations_in_regions(conn, regions)
end

local function object_list_tables(conn, plugin_opts)
    local regions = get_regions(conn, plugin_opts)
    return object_list_tables_in_regions(conn, regions)
end

local actions = {
    describe = {
        label = "Describe Table or View",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return format_bq_object(obj.name) end,
        process_item = function(conn, obj, plugin_opts)
            local cmd = { 'show', format_bq_object(obj.name) }
            local result = dadbod_bq_cmd_results(conn, cmd, 'prettyjson') or {}
            if not result then return end

            local out = format.bq_show_output(table.concat(result, '\n'))
            table.insert(out, '')
            table.insert(out, '# Raw')
            table.insert(out, '```json')
            for _, line in ipairs(result) do
                table.insert(out, line)
            end
            table.insert(out, '```')
            adapter_utils.show_in_preview(out, 'markdown')
        end,
    },
    show_sample = {
        label = "Sample Records",
        object_list = object_list_tables,
        format_item = function(conn, obj, plugin_opts) return format_bq_object(obj.name) end,
        process_item = function(conn, obj, plugin_opts)
            local cmd = { 'head', format_bq_object(obj.name) }
            local result = dadbod_bq_cmd_results(conn, cmd) or {}
            adapter_utils.show_in_preview(result)
        end,
    },
    show_filter = {
        label = "Show Records (with filter)",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return format_bq_object(obj.name) end,
        process_item = function(conn, obj, plugin_opts)
            local function run_sql(filter_condition)
                local sql = string.format(
                    "select * from `%s` where %s",
                    obj.name,
                    filter_condition
                )
                dadbod.run_sql(conn, sql)
            end
            adapter_utils.ask_for_filter_condition(run_sql)
        end,
    },
    yank_columns = {
        label = "Yank Columns",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return format_bq_object(obj.name) end,
        process_item = function(conn, obj, plugin_opts)
            local sql = string.format(
                queries.columns.relation_columns,
                obj.name
            )
            local result = dadbod_bq_sql_results_csv_no_header(conn, sql)
            local columns = result or {}
            if columns then
                local column_string = table.concat(columns, "\n")
                vim.fn.setreg('"', column_string)
                vim.notify(
                    "Yanked columns to default register",
                    vim.log.levels.INFO
                )
            end
        end,
    },
    list_objects = {
        label = "List Objects",
        process_item = function(conn, obj, plugin_opts)
            local regions = get_regions(conn, plugin_opts)

            local tables = object_list_tables_in_regions(conn, regions)
            local views = object_list_views_in_regions(conn, regions)

            local table_list = {}
            for _, table_obj in ipairs(tables) do
                table.insert(table_list, table_obj.name)
            end

            local view_list = {}
            for _, view_obj in ipairs(views) do
                table.insert(view_list, view_obj.name)
            end

            local results = {}
            adapter_utils.append_to_results(results, "Table", table_list)
            adapter_utils.append_to_results(results, "View", view_list)

            if results and #results > 0 then
                adapter_utils.show_in_preview(results)
            end
        end,
    },
    show_distribution = {
        label = "Values Distribution (with filter)",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return format_bq_object(obj.name) end,
        process_item = function(conn, obj, plugin_opts)
            local relation = obj.name
            local columns_sql = string.format(
                queries.columns.relation_columns,
                relation
            )
            local columns = dadbod_bq_sql_results_csv_no_header(
                conn,
                columns_sql
            )

            if #columns == 0 then return nil end

            vim.ui.select(columns, {
                    prompt = "Select Column",
                },
                function(col)
                    if not col then return end

                    local function run_sql(filter_condition)
                        local sql = string.format([[
                            select %s,
                                   count(*) as count
                            from   `%s`
                            where  %s
                            group by 1
                            order by 2 desc]],
                            col,
                            relation,
                            filter_condition
                        )
                        dadbod.run_sql(conn, sql)
                    end

                    adapter_utils.ask_for_filter_condition(run_sql)
                end
            )
        end,
    },
}


M.get_actions = function()
    return actions
end

require("dadbod-explorer").register_adapter({
    name = "bigquery",
    get_actions = M.get_actions
})

return M
