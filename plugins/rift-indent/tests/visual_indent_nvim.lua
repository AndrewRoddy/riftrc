-- Neovim set up like Andre's config for visual_indent.py: `vnoremap > >gv`,
-- `vnoremap < <gv`, shiftwidth 4, expandtab. Alt+a is Esc (riftrc maps it to
-- leave Visual mode; in Normal mode it does nothing). Keys are typed by
-- visual_indent.py over RPC (nvim_input), so undo steps split as they do
-- when a person types; these helpers set each case up and read the result.
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.expandtab = true
vim.o.startofline = false
vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", "<A-a>", "<Esc>")
vim.keymap.set("n", "<A-a>", "<Nop>")

vim.o.swapfile = false

function _G.vi_reset(lines)
  local prev = vim.api.nvim_get_current_buf()
  vim.cmd("enew!")
  if vim.api.nvim_buf_is_valid(prev) and prev ~= vim.api.nvim_get_current_buf() then
    vim.api.nvim_buf_delete(prev, { force = true })
  end
  vim.bo.undolevels = -1
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.undolevels = 1000
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

function _G.vi_state()
  local m = vim.fn.mode()
  local mode = (m == "v" or m == "V" or m == "\22") and "visual" or (m == "n" and "normal" or m)
  local cur = vim.api.nvim_win_get_cursor(0)
  return {
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    row = cur[1] - 1,
    col = vim.fn.charcol(".") - 1,
    mode = mode,
  }
end
