local M = {}

local sql_tables = [[
    select
        concat(
            case
                when table_schema REGEXP '[^0-9a-zA-Z$_]'
                    then concat('`', table_schema, '`')
                else table_schema
            end,
            '.',
            case
                when table_name REGEXP '[^0-9a-zA-Z$_]'
                    then concat('`', table_name, '`')
                else table_name
            end
        ) as obj
    from information_schema.tables
    where table_schema = database()
        and table_type = 'BASE TABLE'
    order by table_name
]]

local sql_views = [[
    select
        concat(
            case
                when table_schema REGEXP '[^0-9a-zA-Z$_]'
                    then concat('`', table_schema, '`')
                else table_schema
            end,
            '.',
            case
                when table_name REGEXP '[^0-9a-zA-Z$_]'
                    then concat('`', table_name, '`')
                else table_name
            end
        ) as obj
    from information_schema.tables
    where table_schema = database()
        and table_type = 'VIEW'
    order by 1
]]


M.objects = {

    tables = sql_tables,

    views = sql_views,

    functions = [[
        select
            concat(
                case
                    when routine_schema REGEXP '[^0-9a-zA-Z$_]'
                        then concat('`', routine_schema, '`')
                    else routine_schema end,
                    '.',
                    case
                        when routine_name REGEXP '[^0-9a-zA-Z$_]'
                            then concat('`', routine_name, '`')
                        else routine_name
                    end
            ) as func
        from information_schema.routines
        where routine_schema = database()
        order by 1
    ]],

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
    select
        case
            when column_name REGEXP '[^0-9a-zA-Z$_]'
                then concat('`', column_name, '`')
            else column_name
        end as col
    from information_schema.columns
    where table_schema = database()
        and concat(
            case
                when table_schema REGEXP '[^0-9a-zA-Z$_]'
                    then concat('`', table_schema, '`')
                else table_schema
            end,
            '.',
            case
                when table_name REGEXP '[^0-9a-zA-Z$_]'
                    then concat('`', table_name, '`')
                else table_name
            end
        ) = '%s'
    order by table_name, ordinal_position
]],
}


return M
