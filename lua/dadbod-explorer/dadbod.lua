local M = {}

local utils = require("dadbod-explorer.utils")

---@return boolean
function M.has_dadbod()
    return vim.g.loaded_dadbod == 1
end

---@param url string | nil
---@return string
function M.get_connection(url)
    local resolved_url = vim.fn["db#resolve"](url)
    local conn = vim.fn["db#connect"](resolved_url)
    if not conn then
        utils.handle_error("connection error")
    end
    return conn
end

---@param conn_or_url string dadbod connection string or URL
---@return string scheme Databod scheme / adapter type (e.g. postgresql, mysql, bigquery)
function M.connection_scheme(conn_or_url)
    return vim.fn['db#url#parse'](conn_or_url).scheme
end

---@param conn string
---@param sql string|string[]
---@param flags? string[]
---@return string[]
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

---@param conn string
---@param sql string
function M.run_sql(conn, sql)
    vim.cmd { cmd = 'DB', args = { string.format('%s %s', conn, sql) } }
end

return M
