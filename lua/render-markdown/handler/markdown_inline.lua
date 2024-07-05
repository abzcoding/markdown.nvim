local callout = require('render-markdown.callout')
local logger = require('render-markdown.logger')
local state = require('render-markdown.state')

local M = {}

---@param namespace integer
---@param root TSNode
---@param buf integer
M.render = function(namespace, root, buf)
    for id, node in state.inline_query:iter_captures(root, buf) do
        local capture = state.inline_query.captures[id]
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

    if capture == 'code' then
        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
            end_row = end_row,
            end_col = end_col,
            hl_group = highlights.code,
        })
    elseif capture == 'callout' then
        local key = callout.get_key_exact(value)
        if key ~= nil then
            local callout_text = { state.config.callout[key], highlights.callout[key] }
            vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { callout_text },
                virt_text_pos = 'overlay',
            })
        end
    elseif capture == 'link' then
        local hyperlink_icon = state.config.hyperlink
        local link_text = string.match(value, '%[(.-)%]')
        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
            virt_text_pos = 'inline',
            virt_text = {
                { hyperlink_icon .. link_text, '@markup.link.label' },
            },
            conceal = '',
            end_row = end_row,
            end_col = end_col,
        })
    elseif capture == 'image' then
        local image_icon = state.config.image
        local link_text = string.match(value, '%[(.-)%]')

        vim.api.nvim_buf_set_extmark(buf, namespace, start_row, start_col, {
            virt_text_pos = 'inline',

            virt_text = {
                { image_icon .. link_text, '@markup.link.label' },
            },

            conceal = '',

            end_row = end_row,
            end_col = end_col,
        })
    else
        -- Should only get here if user provides custom capture, currently unhandled
        logger.error('Unhandled inline capture: ' .. capture)
    end
end

return M
