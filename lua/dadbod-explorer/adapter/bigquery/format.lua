local adapter = require("dadbod-explorer.adapter")

local M = {}

function M.bq_show_output(show_output)
    local parsed = vim.json.decode(show_output)
    local out = {}
    local relation_name = string.format(
        "%s.%s.%s",
        parsed.tableReference.projectId,
        parsed.tableReference.datasetId,
        parsed.tableReference.tableId
    )
    table.insert(out, string.format("%s `%s`", parsed.type, relation_name))

    table.insert(out, '')
    table.insert(out, '# Fields')
    table.insert(out, '```sql')
    for _, field in ipairs(parsed.schema.fields) do
        local field_str = string.format("%s %s", field.name, field.type)
        if field.mode and field.mode == 'REQUIRED' then
            field_str = field_str .. ' NOT NULL'
        end
        table.insert(out, field_str)
    end
    table.insert(out, '```')

    if parsed.type == 'VIEW' then
        table.insert(out, '')
        table.insert(out, '# Definition')
        table.insert(out, '```sql')
        table.insert(out, string.format(
            "create or replace view `%s` as",
            relation_name .. ';'
        ))
        table.insert(out, parsed.view.query)
        table.insert(out, '```')
    end

    table.insert(out, '')
    table.insert(out, '# Meta')
    table.insert(out, string.format('Created:\t%s',
        adapter.unix_timestamp_to_iso(tonumber(parsed.creationTime / 1000))
    ))
    table.insert(out, string.format('Modified:\t%s',
        adapter.unix_timestamp_to_iso(tonumber(parsed.creationTime / 1000))
    ))
    table.insert(out, 'Location:\t' .. parsed.location)

    if parsed.tableConstraints and parsed.tableConstraints.primaryKey then
        table.insert(out, string.format('Primary Key:\t%s',
            table.concat(parsed.tableConstraints.primaryKey.columns, ', ')
        ))
    end

    if parsed.tableConstraints and parsed.tableConstraints.foreignKeys then
        for _, parsed_fk in ipairs(parsed.tableConstraints.foreignKeys) do
            local src_cols = {}
            local dst_cols = {}
            for _, ref_col in ipairs(parsed_fk.columnReferences) do
                table.insert(src_cols, ref_col.referencingColumn)
                table.insert(dst_cols, ref_col.referencedColumn)
            end
            local ref_table = string.format(
                "%s.%s.%s",
                parsed_fk.referencedTable.projectId,
                parsed_fk.referencedTable.datasetId,
                parsed_fk.referencedTable.tableId
            )

            local fk_formatted = string.format(
                '%s foreign key (%s) references `%s`(%s)',
                parsed_fk.name,
                table.concat(src_cols, ', '),
                ref_table,
                table.concat(dst_cols, ', ')
            )
            table.insert(out, 'Foreign Key:\t' .. fk_formatted)
        end
    end

    if parsed.labels then
        local labels = {}
        for k, v in pairs(parsed.labels) do
            table.insert(labels, string.format('%s: %s', k, v))
        end
        table.insert(out, 'Labels: \t' .. table.concat(labels, ', '))
    end

    if parsed.partitionDefinition then
        local partition = parsed.partitionDefinition.partitionedColumn[1].field
        if parsed.timePartitioning then
            partition = string.format('%s (%s)',
                partition,
                parsed.timePartitioning.type
            )
        end
        table.insert(out, 'Partition:\t' .. partition)
    end

    if parsed.clustering then
        table.insert(out, string.format('Cluster:\t%s',
            table.concat(parsed.clustering.fields, ', ')
        ))
    end

    if out.description then
        table.insert(out, 'Description:\t' .. parsed.description)
    end

    if parsed.numRows then
        table.insert(out, string.format('Number of rows: \t%s',
            adapter.format_int(tonumber(parsed.numRows))
        ))
    end

    if parsed.numPartitions then
        table.insert(out, string.format('Num of partitions:\t%s',
            adapter.format_int(tonumber(parsed.numPartitions))
        ))
    end

    table.insert(out, string.format('Total Logical:  \t%s',
        adapter.size_pretty(tonumber(parsed.numTotalLogicalBytes))
    ))
    table.insert(out, string.format('Active Logical: \t%s',
        adapter.size_pretty(tonumber(parsed.numActiveLogicalBytes))
    ))
    table.insert(out, string.format('Long Term Logical:\t%s',
        adapter.size_pretty(tonumber(parsed.numLongTermLogicalBytes))
    ))

    if parsed.numCurrentPhysicalBytes then
        table.insert(out, string.format('Current Physical:\t%s',
            adapter.size_pretty(tonumber(parsed.numCurrentPhysicalBytes))
        ))
    end

    if parsed.numTotalPhysicalBytes then
        table.insert(out, string.format('Total Physical: \t%s',
            adapter.size_pretty(tonumber(parsed.numTotalPhysicalBytes))
        ))
    end

    if parsed.numActivePhysicalBytes then
        table.insert(out, string.format('Active Physical:\t%s',
            adapter.size_pretty(tonumber(parsed.numActivePhysicalBytes))
        ))
    end

    if parsed.numLongTermPhysicalBytes then
        table.insert(out, string.format('Long term Physical:\t%s',
            adapter.size_pretty(tonumber(parsed.numLongTermPhysicalBytes))
        ))
    end

    if parsed.numTimeTravelPhysicalBytes then
        table.insert(out, string.format('Time travel Phys.:\t%s',
            adapter.size_pretty(tonumber(parsed.numTimeTravelPhysicalBytes))
        ))
    end

    return out
end

return M
