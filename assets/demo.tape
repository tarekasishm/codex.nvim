# VHS tape for the codex.nvim chat-mode demo.
# Regenerate with:  vhs assets/demo.tape   (needs: vhs, ttyd, ffmpeg, codex login)
# Records a real, live Codex turn — it makes a billable API call.

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
Type "nvim -u assets/demo-init.lua lua/codex/session.lua"
Enter
Sleep 2.5s
Show

# Open the app-server transcript (starts codex app-server lazily).
Type ":CodexChat"
Enter
Sleep 2.5s

# Ask a question — the reply streams into the transcript on the right.
Type ":CodexAsk In one sentence, what is an embedded AI coding assistant useful for?"
Sleep 700ms
Enter
Sleep 15s

# Rest on the completed answer.
Sleep 2s
