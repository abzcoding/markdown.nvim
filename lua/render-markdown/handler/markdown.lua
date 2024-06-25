local callout = require('render-markdown.callout')
local devicons = require('nvim-web-devicons')
local list = require('render-markdown.list')
local logger = require('render-markdown.logger')
local state = require('render-markdown.state')
local ts = require('render-markdown.ts')
local util = require('render-markdown.util')

local M = {}

---@param namespace integer
---@param root TSNode
---@param buf integer
M.render = function(namespace, root, buf)
    for id, node in state.markdown_query:iter_captures(root, buf) do
        local capture = state.markdown_query.captures[id]
        logger.debug_node(capture, node, buf)
        M.render_node(namespace, buf, capture, node)
    end
end

---@param namespace integer
---@param buf integer
---@param capture string
---@param node TSNode
M.render_node = function(namespace, buf, capture, node)
    local highlights = state.config.highlights
    local value = vim.treesitter.get_node_text(node, buf)
    local start_row, start_col, end_row, end_col = node:range()

    if capture == 'heading' then
        local level = vim.fn.strdisplaywidth(value)

        local heading = list.cycle(state.config.headings, level)
        -- Available width is level + 1, where level = number of `#` characters and one is added
        -- to account for the space after the last `#` but before the heading title
        local padding = level + 1 - vim.fn.strdisplaywidth(heading)

        local background = list.clamp_last(highlights.heading.backgrounds, level)
        local foreground = list.clamp_last(highlights.heading.foregrounds, level)

        local heading_text = { string.rep(' ', padding) .. heading, { foreground, background } }
        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, 0, {
            end_row = end_row + 1,
            end_col = 0,
            hl_group = background,
            virt_text = { heading_text },
            virt_text_pos = 'overlay',
            hl_eol = true,
        })
    elseif capture == 'dash' then
        local width = vim.api.nvim_win_get_width(util.buf_to_win(buf))
        local dash_text = { state.config.dash:rep(width), highlights.dash }
        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, 0, {
            virt_text = { dash_text },
            virt_text_pos = 'overlay',
        })
    elseif capture == 'code' then
        local language = vim.treesitter.get_node_text(node:named_child(1), buf)
        local icon, hl = devicons.get_icon(nil, language, { default = true })
        local used_width = 1
        local border = ''

        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
            virt_text_pos = 'overlay',
            virt_text = {
                { icon .. ' ' or 'Hi', hl or '' },
            },
            priority = 8,
            line_hl_group = highlights.code,
        })
        used_width = used_width + vim.fn.strchars(icon)

        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col + used_width, {
            virt_text_pos = 'overlay',
            virt_text = {
                { language ~= nil and ' ' .. language .. ' ' or '', 'Bold' },
            },
            priority = 8,
            line_hl_group = highlights.code,
        })
        used_width = used_width + vim.fn.strchars(language) + 1

        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col + used_width, {
            virt_text_pos = 'overlay',
            virt_text = {
                { border, 'code_block_border' },
            },
            -- sign_text = icon,
            sign_hl_group = hl,
            priority = 8,
            end_row = end_row - 1,
            line_hl_group = highlights.code,
        })

        vim.api.nvim_buf_set_extmark(buf, namespace, end_row - 1, start_col, {
            virt_text_pos = 'overlay',
            virt_text = {
                { string.rep(' ', 3 + vim.fn.strchars(language)), highlights.code },
            },
        })

        for l = 1, (end_row - start_row - 2) do
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row + l, start_col, {
                virt_text_pos = 'inline',
                virt_text = {
                    { ' ', highlights.code },
                },
                priority = 8,
            })
        end
    elseif capture == 'list_marker' then
        if ts.sibling(node, { 'task_list_marker_unchecked', 'task_list_marker_checked' }) ~= nil then
            -- Hide the list marker for checkboxes rather than replacing with a bullet point
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                conceal = '',
            })
        else
            -- List markers from tree-sitter should have leading spaces removed, however there are known
            -- edge cases in the parser: https://github.com/tree-sitter-grammars/tree-sitter-markdown/issues/127
            -- As a result we handle leading spaces here, can remove if this gets fixed upstream
            local _, leading_spaces = value:find('^%s*')
            local level = ts.level_in_section(node, 'list')
            local bullet = list.cycle(state.config.bullets, level)

            local list_marker_text = { string.rep(' ', leading_spaces or 0) .. bullet, highlights.bullet }
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { list_marker_text },
                virt_text_pos = 'overlay',
            })
        end
    elseif capture == 'quote_marker' then
        local highlight = highlights.quote
        local quote = ts.parent_in_section(node, 'block_quote')
        if quote ~= nil then
            local quote_value = vim.treesitter.get_node_text(quote, buf)
            local key = callout.get_key_contains(quote_value)
            if key ~= nil then
                highlight = highlights.callout[key]
            end
        end

        local quote_marker_text = { value:gsub('>', state.config.quote), highlight }
        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
            end_row = end_row,
            end_col = end_col,
            virt_text = { quote_marker_text },
            virt_text_pos = 'overlay',
        })
    elseif vim.tbl_contains({ 'checkbox_unchecked', 'checkbox_checked' }, capture) then
        local checkbox = state.config.checkbox.unchecked
        local highlight = highlights.checkbox.unchecked
        if capture == 'checkbox_checked' then
            checkbox = state.config.checkbox.checked
            highlight = highlights.checkbox.checked
        end
        local padding = vim.fn.strdisplaywidth(value) - vim.fn.strdisplaywidth(checkbox)

        if padding >= 0 then
            local checkbox_text = { string.rep(' ', padding) .. checkbox, highlight }
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { checkbox_text },
                virt_text_pos = 'overlay',
            })
        end
    elseif capture == 'table' then
        if state.config.table_style ~= 'full' then
            return
        end

        ---@param row integer
        ---@param s string
        ---@return integer
        local function get_table_row_width(row, s)
            local result = vim.fn.strdisplaywidth(s)
            if state.config.cell_style == 'raw' then
                result = result - ts.concealed(buf, row, s)
            end
            return result
        end

        local delim = ts.child(node, 'pipe_table_delimiter_row')
        if delim == nil then
            return
        end
        local delim_row, _, _, _ = delim:range()
        local delim_value = vim.treesitter.get_node_text(delim, buf)
        local delim_width = get_table_row_width(delim_row, delim_value)

        local lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
        local start_width = get_table_row_width(start_row, list.first(lines))
        local end_width = get_table_row_width(end_row - 1, list.last(lines))

        if delim_width == start_width and start_width == end_width then
            local headings = vim.split(delim_value, '|', { plain = true, trimempty = true })
            local lengths = vim.tbl_map(function(part)
                return string.rep('─', vim.fn.strdisplaywidth(part))
            end, headings)

            local line_above = { { '┌' .. table.concat(lengths, '┬') .. '┐', highlights.table.head } }
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                virt_lines_above = true,
                virt_lines = { line_above },
            })

            local line_below = { { '└' .. table.concat(lengths, '┴') .. '┘', highlights.table.row } }
            vim.api.nvim_buf_set_extmark(buf, namespace, end_row, start_col, {
                virt_lines_above = true,
                virt_lines = { line_below },
            })
        end
    elseif vim.tbl_contains({ 'table_head', 'table_delim', 'table_row' }, capture) then
        if state.config.table_style == 'none' then
            return
        end

        local highlight = highlights.table.head
        if capture == 'table_row' then
            highlight = highlights.table.row
        end

        if capture == 'table_delim' then
            -- Order matters here, in particular handling inner intersections before left & right
            local row = value
                :gsub('|', '│')
                :gsub('-', '─')
                :gsub(' ', '─')
                :gsub('─│─', '─┼─')
                :gsub('│─', '├─')
                :gsub('─│', '─┤')

            local table_delim_text = { row, highlight }
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { table_delim_text },
                virt_text_pos = 'overlay',
            })
        elseif state.config.cell_style == 'overlay' then
            local table_row_text = { value:gsub('|', '│'), highlight }
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { table_row_text },
                virt_text_pos = 'overlay',
            })
        elseif state.config.cell_style == 'raw' then
            for i = 1, #value do
                local ch = value:sub(i, i)
                if ch == '|' then
                    local table_pipe_text = { '│', highlight }
                    vim.api.nvim_buf_set_extmark(buf, namespace, start_row, i - 1, {
                        end_row = end_row,
                        end_col = i - 1,
                        virt_text = { table_pipe_text },
                        virt_text_pos = 'overlay',
                    })
                end
            end
        end
    else
        -- Should only get here if user provides custom capture, currently unhandled
        logger.error('Unhandled markdown capture: ' .. capture)
    end
end

return M
