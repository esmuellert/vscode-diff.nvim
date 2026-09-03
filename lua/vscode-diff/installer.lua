-- Backward compatibility shim
-- Redirects old 'vscode-diff.installer' to the current library installer.
require("vscode-diff._deprecation").warn("vscode-diff.installer", "codediff.core.installer.libvscode_diff")
return require("codediff.core.installer.libvscode_diff")
