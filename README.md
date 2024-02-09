# overview.nvim

View and navigate a table of contents for markup files.

This [NeoVim](https://neovim.io) plugin, written in Lua, extracts a table of
contents (TOC) from markup buffers and presents it in an unobtrusive floating
window. The floating overview can also be used to navigate the open buffer.
The TOC is updated as the buffer contents change (tree-sitter is not required).

![overview.nvim demo](overview.webp)

Filetype support:
- [x] `markdown` (no setext headers yet)
- [x] `man` (improvement of `gO` or `:lua require('man').show_toc()`)
- [x] `toml` (also `dosini`)
- [ ] `tex` ([vimtex](https://github.com/lervag/vimtex) provides `vimtex-toc`)
- [x] `help`
- [ ] `asciidoc`
- [ ] `rst` (reStructuredText)
- [ ] `html`
- [ ] `xml`

Miscellaneous:
- [ ] callback compatible with `lsp-on-list-handler` for e.g. showing the list
  of symbols for the current buffer with `vim.lsp.buf.document_symbol()`

Install the plugin using your preferred plugin manager. Alternatively, NeoVim
can load packages if they are added to your 'packpath'.

### Configuration suggestion:
```lua
-- Set up key bindings to toggle/focus the TOC sidebar.
overview = require("overview.nvim")
if overview then
    bindkey("n", "gO", overview.toggle, { desc = "Toggle Overview sidebar for current buffer" })
    bindkey("n", "go", overview.focus, { desc = "Toggle focus between Overview sidebar and source buffer" })
end
```

Available options are described in `:help overview`.

Please send patches/queries to my [public inbox](https://lists.sr.ht/~adigitoleo/public-inbox).
