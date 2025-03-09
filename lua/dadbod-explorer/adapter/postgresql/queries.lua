local M = {}

local sql_tables = [[
    select  pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(c.relname) as object_name
    from    pg_catalog.pg_class as c
            left join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where   c.relkind in ('r', 'p', 'f')
        and n.nspname not in ('pg_catalog', 'information_schema')
        and n.nspname !~ '^pg_toast'
    order by n.nspname, c.relname
]]

local sql_views = [[
    select  pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(c.relname) as object_name
    from    pg_catalog.pg_class as c
            left join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where   c.relkind in ('m', 'v')
        and n.nspname not in ('pg_catalog', 'information_schema')
        and n.nspname !~ '^pg_toast'
    order by n.nspname, c.relname
]]


M.objects = {

    tables = sql_tables,

    views = sql_views,

    functions = [[
    select  pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(f.proname) || '(' ||
            pg_catalog.oidvectortypes(f.proargtypes) || ')' as object_name
    from    pg_catalog.pg_proc as f
            join pg_catalog.pg_namespace as n on n.oid = f.pronamespace
    where   n.nspname not in ('pg_catalog', 'information_schema')
    order by n.nspname, f.proname]],

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


local sql_relation_columns = [[
    select  pg_catalog.quote_ident(n.nspname) as schema_name,
            pg_catalog.quote_ident(c.relname) as relation_name,
            pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(c.relname) as relation_full_name,
            pg_catalog.quote_ident(a.attname) as column_name,
            pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(c.relname) || '.' ||
            pg_catalog.quote_ident(a.attname) as column_full_name,
            c.relkind,
            a.attrelid,
            a.attnum
    from    pg_catalog.pg_class as c
            join pg_catalog.pg_attribute a on a.attrelid = c.oid
            left join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where   c.relkind in ('r', 'p', 'f', 'm', 'v')
        and n.nspname not in ('pg_catalog', 'information_schema')
        and n.nspname !~ '^pg_toast'
        and a.attnum > 0
        and a.attisdropped = false
    order by n.nspname, c.relname, a.attnum
]]

M.columns = {

    table_columns = [[
    select  pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(c.relname) || '.' ||
            pg_catalog.quote_ident(a.attname) as column_name
    from    pg_catalog.pg_class as c
            join pg_catalog.pg_attribute a on a.attrelid = c.oid
            left join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where   c.relkind in ('r', 'p', 'f')
        and n.nspname not in ('pg_catalog', 'information_schema')
        and n.nspname !~ '^pg_toast'
        and a.attnum > 0
    order by n.nspname, c.relname, a.attnum
]],

    view_columns = [[
    select  pg_catalog.quote_ident(n.nspname) || '.' ||
            pg_catalog.quote_ident(c.relname) || '.' ||
            pg_catalog.quote_ident(a.attname) as column_name
    from    pg_catalog.pg_class as c
            join pg_catalog.pg_attribute a on a.attrelid = c.oid
            left join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where   c.relkind in ('m', 'v')
        and n.nspname not in ('pg_catalog', 'information_schema')
        and n.nspname !~ '^pg_toast'
        and a.attnum > 0
    order by n.nspname, c.relname, a.attnum
]],

    function_columns = [[
    select  column_name
    from (
        select  pg_catalog.quote_ident(n.nspname) || '.' ||
                pg_catalog.quote_ident(f.proname) || '.' ||
                -- '(' || pg_catalog.oidvectortypes(f.proargtypes) || ')' || '.' ||
                pg_catalog.quote_ident(a.attname) as column_name
        from    pg_catalog.pg_proc as f
                join pg_catalog.pg_namespace as n on n.oid = f.pronamespace
                join pg_catalog.pg_type as t on f.prorettype = t.oid
                join pg_catalog.pg_attribute a on a.attrelid = t.typrelid
        where   n.nspname not in ('pg_catalog', 'information_schema')
            and t.typtype = 'c'
        order by n.nspname, f.proname, a.attnum
    ) x
    union all
    select  column_name
    from (
        select  pg_catalog.quote_ident(n.nspname) || '.' ||
                pg_catalog.quote_ident(f.proname) || '.' ||
                unnest(f.proargnames[f.pronargs+1:]) as column_name
        from    pg_catalog.pg_proc as f
                join pg_catalog.pg_namespace as n on n.oid = f.pronamespace
                join pg_catalog.pg_type as t on f.prorettype = t.oid
        where   n.nspname not in ('pg_catalog', 'information_schema')
            and proretset = true
            and t.typname = 'record'
            and coalesce(array_length(f.proargnames[f.pronargs+1:], 1), 0) > 0
        order by n.nspname, f.proname
    ) x
]],

    relation_columns = string.format([[
        select column_name
        from (%s) as x
        ]],
        sql_relation_columns
    ) .. [[
        where relation_full_name = '%s'
        order by x.schema_name, x.relation_name, x.column_name, x.attnum
    ]],
}


return M
