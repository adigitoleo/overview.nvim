# overview.nvim

View and navigate a table of contents for markup files.

This [NeoVim](https://neovim.io) plugin, written in Lua, extracts a table of
contents from markup buffers and presents it in an unobtrusive floating window.
The floating overview can also be used to navigate the open buffer.

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

Configuration suggestion:
```lua
overview = require("overview.nvim")  -- Or load("overview") via packer.nvim
if overview then
    bindkey("n", "gO", overview.toggle, { desc = "Toggle Overview sidebar for current buffer" })
    bindkey("n", "go", overview.focus, { desc = "Toggle focus between Overview sidebar and source buffer" })
end
```

Please send patches/queries to my [public inbox](https://lists.sr.ht/~adigitoleo/public-inbox).
