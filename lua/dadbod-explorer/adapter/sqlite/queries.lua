local M = {}

local sql_tables = [[
    select name
    from sqlite_schema
    where type = 'table'
    order by name
]]

local sql_views = [[
    select name
    from sqlite_schema
    where type = 'view'
    order by name
]]


M.objects = {

    tables = sql_tables,

    views = sql_views,

    relations = string.format([[
        select *
        from (
            (%s)
            union all
            (%s)
        ) as x
        order by 1
        ]],
        sql_tables,
        sql_views
    )

}


M.columns = {

    relation_columns = [[
    select name
    from pragma_table_info('%s')
]],

}


return M
