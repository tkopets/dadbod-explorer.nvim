local M = {}

M.objects = {
    tables = [[
        select format('%s.%s.%s', table_catalog, table_schema, table_name) as object_name
        from `region-us`.INFORMATION_SCHEMA.TABLES
        where table_type = 'BASE TABLE'
        order by 1
    ]],
    views = [[
        select format('%s.%s.%s', table_catalog, table_schema, table_name) as object_name
        from `region-us`.INFORMATION_SCHEMA.TABLES
        where table_type = 'VIEW'
        order by 1
    ]],
    routines = [[
        select format('%s.%s.%s', routine_catalog, routine_schema, routine_name) as object_name
        from `region-us`.INFORMATION_SCHEMA.ROUTINES
        order by 1
    ]],
}

M.objects.relations = string.format([[
    select *
    from (
        (%s)
        union all
        (%s)
    ) as x
    order by 1
    ]],
    M.objects.tables,
    M.objects.views
)

M.columns = {
    relation_columns = [[
        select column_name
        from `region-us`.INFORMATION_SCHEMA.COLUMNS
        where concat(table_catalog, '.', table_schema, '.', table_name) = '%s'
        order by 1
    ]]
}

return M
