# Gutter signs design constraint

Neovim ignores `sign_text` when an extmark has `ephemeral = true`. This is tracked in [neovim/neovim#32936](https://github.com/neovim/neovim/issues/32936) and was reproduced on Neovim 0.11.5 and 0.12.2.

CodeDiff therefore uses ordinary persistent ranged extmarks. A changed hunk, move segment, whole-file sign, or unchanged-line blocker needs only one extmark per contiguous range, so storage does not scale with the number of lines covered.

Persistent signs are buffer-local rather than window-local. If another window shows a buffer participating in an active CodeDiff view, it shows the same CodeDiff signs. Suspending or closing the diff clears them.

Neovim 0.11 introduced the experimental `nvim__ns_set()` API, which can scope persistent extmark namespaces to windows. CodeDiff does not depend on that private-style API; window-local signs can be reconsidered when Neovim exposes a stable supported mechanism.
