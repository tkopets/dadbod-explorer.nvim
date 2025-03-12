local M = {}
local de = require("dadbod-explorer")
local dadbod = require("dadbod-explorer.dadbod")
local adapter_utils = require("dadbod-explorer.adapter")
local queries = require("dadbod-explorer.adapter.sqlite.queries")

local ObjKind = {
    TABLE = "table",
    VIEW = "view",
}

local function dadbod_get_sql_results_internal(conn, sql)
    local db_dispatch_fn = vim.fn['db#adapter#dispatch']
    local command_to_dispatch = db_dispatch_fn(conn, 'interactive')

    -- additional flags
    table.insert(command_to_dispatch, '-csv')
    table.insert(command_to_dispatch, '-noheader')

    local sql_to_run = sql
    if type(sql_to_run) == 'table' then
        sql_to_run = table.concat(sql_to_run, "\n")
    end

    local db_systemlist_fn = vim.fn['db#systemlist']
    local result = db_systemlist_fn(command_to_dispatch, sql_to_run)

    return result
end

local function object_list_tables(conn)
    local result = dadbod_get_sql_results_internal(
        conn,
        queries.objects.tables
    )
    return result or {}
end

local function object_list_views(conn)
    local result = dadbod_get_sql_results_internal(conn, queries.objects.views)
    return result or {}
end

local function object_list_functions(conn)
    local result = dadbod_get_sql_results_internal(
        conn,
        queries.objects.functions
    )
    return result or {}
end

local function object_list_relations(conn)
    local items = {}
    for _, obj in ipairs(object_list_tables(conn)) do
        table.insert(items, { kind = ObjKind.TABLE, name = obj })
    end

    for _, obj in ipairs(object_list_views(conn)) do
        table.insert(items, { kind = ObjKind.VIEW, name = obj })
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local actions = {
    describe = {
        label = "Describe Table or View",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            dadbod.run_sql(
                conn,
                string.format([[
                    .header off
                    select sql
                    from sqlite_schema
                    where name = '%s'
                    ]],
                    obj.name
                )
            )
        end,
    },
    show_sample = {
        label = "Sample Records",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            local sample_size = de.get_sample_size(conn, "show_sample", obj)
            dadbod.run_sql(
                conn,
                string.format([[select * from %s limit %s]], obj.name, sample_size)
            )
        end,
    },
    show_filter = {
        label = "Show Records (with filter)",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            local function run_sql(filter_condition)
                local sql = string.format(
                    "select * from %s where %s",
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
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            local relation = obj.name
            local columns_sql = string.format(
                queries.columns.relation_columns,
                relation
            )
            local result = dadbod_get_sql_results_internal(conn, columns_sql)
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
            local tables = object_list_tables(conn)
            local views = object_list_views(conn)

            local results = {}
            adapter_utils.append_to_results(results, "Table", tables)
            adapter_utils.append_to_results(results, "View", views)

            if results and #results > 0 then
                adapter_utils.show_in_preview(results)
            end
        end,
    },
    show_distribution = {
        label = "Values Distribution (with filter)",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            local relation = obj.name
            local columns_sql = string.format(
                queries.columns.relation_columns,
                relation
            )
            local columns = dadbod_get_sql_results_internal(
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
                            from   %s
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
    name = "sqlite",
    get_actions = M.get_actions
})

return M
