local M = {}
local de = require("dadbod-explorer")
local dadbod = require("dadbod-explorer.dadbod")
local adapter_utils = require("dadbod-explorer.adapter")
local queries = require("dadbod-explorer.adapter.postgresql.queries")

local ObjKind = {
    TABLE = "table",
    VIEW = "view",
    FUNC = "function"
}

local function dadbod_get_sql_results_internal(conn, sql)
    local flags = {
        "--no-psqlrc",
        "--tuples-only",
        "--no-align",
        "--field-separator=','"
    }
    return dadbod.get_sql_results(conn, sql, flags)
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

local actions = {
    describe = {
        label = "Describe Table, View or Function",
        object_list = object_list,
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            if obj.kind == ObjKind.TABLE or obj.kind == ObjKind.VIEW then
                dadbod.run_sql(conn, string.format([[\d %s]], obj.name))
            end
            if obj.kind == ObjKind.FUNC then
                dadbod.run_sql(conn, string.format([[\sf %s]], obj.name))
            end
        end,
    },
    show_sample = {
        label = "Sample Records",
        object_list = object_list_relations,
        format_item = function(conn, obj, plugin_opts) return obj.name end,
        process_item = function(conn, obj, plugin_opts)
            local sample_size = de.get_sample_size(conn, obj)
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
            local sql = string.format(
                [[
                \set relation_name %s
                select  pg_catalog.quote_ident(a.attname) as column_name
                from    pg_catalog.pg_class as c
                        join pg_catalog.pg_attribute a on a.attrelid = c.oid
                        left join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
                where   c.relkind in ('r', 'p', 'f', 'm', 'v')
                    and n.nspname not in ('pg_catalog', 'information_schema')
                    and n.nspname !~ '^pg_toast'
                    and a.attnum > 0
                    and a.attisdropped = false
                    and c.oid = :'relation_name'::regclass::oid
                order by n.nspname, c.relname, a.attnum
                ]],
                obj.name
            )
            local result = dadbod_get_sql_results_internal(conn, sql)
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
    name = "postgresql",
    get_actions = M.get_actions
})

return M
