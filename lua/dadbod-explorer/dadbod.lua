local M = {}

local utils = require("dadbod-explorer.utils")

function M.has_dadbod()
    return vim.g.loaded_dadbod == 1
end

function M.get_connection(url)
    local resolved_url = vim.fn["db#resolve"](url)
    local conn = vim.fn["db#connect"](resolved_url)
    if not conn then
        utils.handle_error("connection error")
    end
    return conn
end

function M.get_sql_results(conn, sql, flags)
    local db_dispatch_fn = vim.fn['db#adapter#dispatch']
    local command_to_dispatch = db_dispatch_fn(conn, 'interactive')
    if flags then
        command_to_dispatch = db_dispatch_fn(conn, 'interactive', flags)
    end
    local sql_to_run = sql
    if type(sql_to_run) == 'table' then
        sql_to_run = table.concat(sql_to_run, "\n")
    end
    local db_systemlist_fn = vim.fn['db#systemlist']
    local query_result = db_systemlist_fn(command_to_dispatch, sql_to_run)
    return query_result
end

function M.run_sql(conn, sql)
    vim.cmd { cmd = 'DB', args = { string.format('%s %s', conn, sql) } }
end

return M
