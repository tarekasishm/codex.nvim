# VHS tape for the codex.nvim terminal-mode demo.
# Regenerate with:  vhs assets/demo.tape   (needs: vhs, ttyd, ffmpeg, codex login)
# Terminal mode only — it does NOT submit a prompt, so no billable API call.

Output assets/demo.gif

Require nvim
Require codex

Set Shell "zsh"
Set FontSize 15
Set Width 1300
Set Height 760
Set Padding 14
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "cd /Users/thm/Documents/codex.nvim && clear"
Enter
Sleep 400ms
Type "nvim -u assets/demo-init.lua lua/codex/context.lua"
Enter
Sleep 2s
Show

# Toggle the interactive Codex TUI into a right-hand split.
Type ":Codex"
Enter
Sleep 4.5s

# Leave the terminal, hop back to the code window.
Ctrl+\
Ctrl+n
Ctrl+w
Type "h"
Sleep 700ms

# Select a function and send it to Codex as an @file (L..) + fenced snippet.
Type "40G"
Sleep 400ms
Type "V"
Type "10j"
Sleep 800ms
Type ":CodexSend"
Sleep 500ms
Enter
Sleep 3.5s
