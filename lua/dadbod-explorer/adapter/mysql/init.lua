local M = {}
local de = require("dadbod-explorer")
local dadbod = require("dadbod-explorer.dadbod")
local adapter_utils = require("dadbod-explorer.adapter")
local queries = require("dadbod-explorer.adapter.mysql.queries")

local ObjKind = {
    TABLE = "table",
    VIEW = "view",
    FUNC = "function"
}

local function dadbod_get_sql_results_internal(conn, sql)
    local db_dispatch_fn = vim.fn['db#adapter#dispatch']
    local command_to_dispatch = db_dispatch_fn(conn, 'filter')

    -- remove table format (we watch tab separated batch)
    for i = #command_to_dispatch, 1, -1 do
        if command_to_dispatch[i] == '--table' or command_to_dispatch[i] == '-t' then
            table.remove(command_to_dispatch, i)
        end
    end

    -- additional flags
    table.insert(command_to_dispatch, '--batch')
    table.insert(command_to_dispatch, '--silent')
    table.insert(command_to_dispatch, '--skip-column-names')

    local sql_to_run = sql
    if type(sql_to_run) == 'table' then
        sql_to_run = table.concat(sql_to_run, "\n")
    end

    local db_systemlist_fn = vim.fn['db#systemlist']
    local result = db_systemlist_fn(command_to_dispatch, sql_to_run)
    vim.print('before', result)

    -- some basic post-processing
    if result and #result >= 1 then
        if string.match(result[1], '^mysql: %[Warning%]') then
            result = { unpack(result, 2) }
        end
    end
    vim.print('after', result)

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

local function object_list(conn)
    local items = {}
    for _, obj in ipairs(object_list_tables(conn)) do
        table.insert(items, { kind = ObjKind.TABLE, name = obj })
    end

    for _, obj in ipairs(object_list_views(conn)) do
        table.insert(items, { kind = ObjKind.VIEW, name = obj })
    end

    for _, obj in ipairs(object_list_functions(conn)) do
        table.insert(items, { kind = ObjKind.FUNC, name = obj })
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function object_list_relation_cols(conn)
    local result = dadbod_get_sql_results_internal(
        conn,
        queries.columns.relation_columns
    )
    return result or {}
end

local actions = {
    describe = {
        label = "Describe Table, View or Function",
        object_list = object_list,
        format_item = function(obj) return obj.name end,
        process_item = function(conn, obj)
            if obj.kind == ObjKind.TABLE or obj.kind == ObjKind.VIEW then
                dadbod.run_sql(conn, string.format([[desc %s]], obj.name))
            end
            if obj.kind == ObjKind.FUNC then
                dadbod.run_sql(conn, string.format([[
                select  routine_definition
                from    information_schema.routines
                where   concat(
                            case
                            when routine_schema REGEXP '[^0-9a-zA-Z$_]'
                                then concat('`',routine_schema,'`')
                            else routine_schema
                            end,
                            '.',
                            case
                            when routine_name REGEXP '[^0-9a-zA-Z$_]'
                                then concat('`',routine_name,'`')
                            else routine_name
                            end
                        ) = '%s'
                ]], obj.name))
            end
        end,
    },
    show_sample = {
        label = "Sample Records",
        object_list = object_list_relations,
        format_item = function(obj) return obj.name end,
        process_item = function(conn, obj)
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
        format_item = function(obj) return obj.name end,
        process_item = function(conn, obj)
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
        format_item = function(obj) return obj.name end,
        process_item = function(conn, obj)
            local relation = obj.name
            local columns_sql = string.format(
                queries.columns.relation_columns,
                relation
            )
            local result = dadbod_get_sql_results_internal(conn, columns_sql)
            vim.print(result)
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
        process_item = function(conn)
            local tables = object_list_tables(conn)
            local views = object_list_views(conn)
            local funcs = object_list_functions(conn)

            local results = {}
            adapter_utils.append_to_results(results, "Table", tables)
            adapter_utils.append_to_results(results, "View", views)
            adapter_utils.append_to_results(results, "Function", funcs)

            if results and #results > 0 then
                adapter_utils.show_in_preview(results)
            end
        end,
    },
    show_distribution = {
        label = "Values Distribution (with filter)",
        object_list = object_list_relations,
        format_item = function(obj) return obj.name end,
        process_item = function(conn, obj)
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
    name = "mysql",
    get_actions = M.get_actions
})

return M
