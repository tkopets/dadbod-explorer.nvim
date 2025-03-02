# Dadbod Explorer

A Neovim plugin for exploring databases, inspired by [vim-dadbod](https://github.com/tpope/vim-dadbod).
It leverages `vim-dadbod` for database connections and query execution, providing a UI for common database exploration tasks.

## Features

* **Explore Database Objects:** List tables, views, and functions.
* **Describe Objects:** View detailed information about tables, views, and functions (using database-specific commands like `\d` in PostgreSQL).
* **Sample Data:** Quickly view a sample of records from a table.
* **Show Records with Filter Condition**: Quickly view a sample of records, and filter using a custom filter condition.
* **Yank Columns:** Copy a list of table columns to the default register.
* **Values Distribution:** See unique values and counts of occurrences.
* **Caching:** Object lists are cached per connection to improve performance.
* **Extensible:** Supports adding custom actions and adapters for different database systems. Currently has built-in support for:
    * PostgreSQL
    * BigQuery

## Prerequisites

* Neovim (0.8 or later)
* [vim-dadbod](https://github.com/tpope/vim-dadbod) (installed and configured)

## Installation

Use your favorite plugin manager.
Here are some examples:

#### Using lazy.nvim
```lua
{
  'tkopets/dadbod-explorer.nvim',
  dependencies = {
    'tpope/vim-dadbod',
    -- Optional: For enhanced UI.  Choose ONE of the following:
    -- 'fzf-lua/fzf-lua',
    -- 'nvim-telescope/telescope-ui-select.nvim',
  },
  -- ft = { "sql" }, -- Optional: enable only for SQL files
  config = function()
    require('dadbod-explorer').setup({
      mappings = {
        n = {
          ["<leader>le"] = "explore",
          ["<leader>ld"] = "describe",
          ["<leader>ls"] = "show_sample",
          ["<leader>lw"] = "show_filter",
          ["<leader>lv"] = "show_distribution",
          ["<leader>ly"] = "yank_columns",
          ["<leader>lo"] = "list_objects",
        },
      },
    })
  end
}
```

#### Using packer.nvim
```lua
use {
  'tkopets/dadbod-explorer.nvim',
  requires = {
    { 'tpope/vim-dadbod' },
    -- Optional: For enhanced UI. Choose ONE of the following:
    -- { 'fzf-lua/fzf-lua' },
    -- { 'nvim-telescope/telescope-ui-select.nvim' },
  },
  -- ft = { "sql" }, -- Optional: enable only for SQL files
  config = function()
    require('dadbod-explorer').setup({
      mappings = {
        n = {
          ["<leader>le"] = "explore",
          ["<leader>ld"] = "describe",
          ["<leader>ls"] = "show_sample",
          ["<leader>lw"] = "show_filter",
          ["<leader>lv"] = "show_distribution",
          ["<leader>ly"] = "yank_columns",
          ["<leader>lo"] = "list_objects",
        },
      },
    })
  end
}
```

#### Using vim-plug
```vim
Plug 'tpope/vim-dadbod'
Plug 'tkopets/dadbod-explorer.nvim'
" Optional: For enhanced UI. Choose ONE of the following:
" Plug 'fzf-lua/fzf-lua'
" Plug 'nvim-telescope/telescope-ui-select.nvim'
```

## Setup

After installing, you'll need to configure the plugin.
You can use the default keybindings, or customize them.
There are two ways of defining keymaps, *either* with `vim.keymap.set` directly (option 1) *or* using `setup` function and `mappings` option (option 2).

### Option 1: Direct `vim.keymap.set`

Place the following in your plugin config section / `init.lua` (or a file sourced by it):
```lua
local de = require('dadbod-explorer')

de.setup()

vim.keymap.set('n', '<leader>le', function() de.explore() end, { desc = 'DB explore' })
vim.keymap.set('n', '<leader>ld', de.action("describe"), { desc = 'DB describe object' })
vim.keymap.set('n', '<leader>ls', de.action("show_sample"), { desc = 'DB show sample records' })
vim.keymap.set('n', '<leader>lw', de.action("show_filter"), { desc = 'DB show records with filter' })
vim.keymap.set('n', '<leader>lv', de.action("show_distribution"), { desc = 'DB values distribution' })
vim.keymap.set('n', '<leader>ly', de.action("yank_columns"), { desc = 'DB yank columns' })
vim.keymap.set('n', '<leader>lo', de.action("list_objects"), { desc = 'DB list objects' })
```

### Option 2: Using `setup({ mappings = ... })`

Place the following in your plugin config section / `init.lua` (or a file sourced by it):
```lua
require('dadbod-explorer').setup({
  mappings = {
    n = {
      ["<leader>le"] = "explore",
      ["<leader>ld"] = "describe",
      ["<leader>ls"] = "show_sample",
      ["<leader>lw"] = "show_filter",
      ["<leader>lv"] = "show_distribution",
      ["<leader>ly"] = "yank_columns",
      ["<leader>lo"] = "list_objects",
    },
  },
})
```

**Note:** Choose *either* Option 1 *or* Option 2. Don't use both.
The examples above use `<leader>` mappings; feel free to customize these to your liking.

## Usage

1. **Setup DB connection URL:** Configure your database connection URLs as described in the vim-dadbod documentation (`:h dadbod-urls`). You have several options:
    * **Global Variable (Lua):** Set a global variable in your `init.lua`:
        ```lua
        vim.g.db_url = 'postgresql://user@host:port/database'
        ```
    * **Global Variable (Vimscript):** Set a global variable in your `vimrc` or `init.vim`:
        ```vim
        let g:db_url = 'postgresql://user@host:port/database'
        ```
    * **Environment Variable `$DATABASE_URL`:**
        * Set environment variable outside of neovim (e.g., in your shell's configuration file like `.bashrc`, `.zshrc`, `.envrc`):
          ```bash
          export DATABASE_URL='postgresql://user@host:port/database'
          ```
        * **Within Neovim:** You can also set the environment variable within Neovim:
            ```lua
            vim.env.DATABASE_URL = 'postgresql://user@host:port/database'
            ```
            or
             ```vim
            let $DATABASE_URL = 'postgresql://user@host:port/database'
            ```
2. **Explore:** Use the configured keybindings (e.g., `<leader>le` if you used the default mappings) to open the Dadbod Explorer.
3. **Navigate:**
    * The explorer will prompt you to select an action.
    * If the action requires selecting an object (table, view, etc.), you'll be presented with a list to choose from.
    For a better user experience, it's highly recommended to use a fuzzy finder plugin like `fzf-lua` or `telescope-ui-select.nvim`.
    See the "Installation" section for details on adding these as optional dependencies.
    * The results of the action will be displayed in a separate preview window.

## Customization

### Adding Adapters

You can extend `dadbod-explorer` to support other databases by creating custom adapters. An adapter is a Lua module that defines a `get_actions` function, which returns a table of actions supported by the database.

In addition to the predefined actions (`describe`, `show_sample`, `show_filter`, `show_distribution`, `yank_columns`, and `list_objects`), adapters can also implement custom actions specific to the database adapter.

See the existing adapters (`lua/dadbod-explorer/adapter/postgresql/init.lua` and `lua/dadbod-explorer/adapter/bigquery/init.lua`) for examples of how to implement adapters. The key parts are:

* **`get_actions()`:** This function returns a table where keys are action names (strings) and values are tables defining the action.
* **Action Definition:** Each action table should have:
    * `label`: A user-friendly description of the action.
    * `object_list` (optional): A function that takes the connection string and returns a list of objects (e.g., table names). If present, the user will be prompted to select an object.
    * `format_item` (optional): A function that takes an object from `object_list` and returns a formatted string for display in the selection list.
    * `process_item`: A function that takes the connection string and the selected object (or `nil` if no `object_list` is provided) and performs the action.

Register your adapter using `require("dadbod-explorer").register_adapter(your_adapter_module)`.

### Keybindings

See the "Setup" section, you can customize the keybindings using either `vim.keymap.set` or the `mappings` option in the `setup()` function.
