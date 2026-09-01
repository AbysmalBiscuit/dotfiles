# Pure prefix aliases ported from ~/.config/fish/functions.
#
# Aliases rather than `def --wrapped` on purpose: a nushell alias inherits the
# target command's completions, so carapace still fires on the aliased binary.
# Anything with real logic lives in the other lib/*.nu files instead.
#
# `^name` marks calls that would otherwise hit a nushell builtin of the same
# name (watch, du) or recurse into the alias being defined.

# claude
alias cl = claude
alias ca = claude agents
alias cr = claude -r

# listing. nushell's `ls` builtin is left alone: it returns a table that the
# rest of the config pipes into `get modified.0`, which eza cannot do.
alias l = eza --color=auto --icons=auto --classify=auto
alias ll = eza --color=auto --icons=auto --classify=auto -alh
alias la = eza --color=auto --icons=auto --classify=auto -a
alias lt = eza --color=auto --icons=auto --classify=auto --tree --level=2

# fd
alias fdd = fd -t d
alias fdf = fd -t f

# disk
alias df = dysk
alias du = pdu
alias dus = ^du -sh

# coreutils colour wrappers
alias dir = ^dir --color=auto
alias vdir = ^vdir --color=auto
alias diff = ^diff --color=auto
alias egrep = ^egrep --color=auto
alias project-patch = ^diff -rupN

# pacman
alias pacorphans = pacman -Qtdq

# system
alias systemctlu = systemctl --user
alias wnvidia-smi = ^watch -n 1 nvidia-smi
alias wsensors = ^watch -n 1 sensors
alias wanip = dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com
alias wanip6 = dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com
alias tmux = ^tmux -u

# viewers
alias icat = kitty +kitten icat --align left
alias fimaa = fim -o aa

# editors
alias nvims = nvim "+SessionSearch"

# build
alias tsc = bunx tsc --noEmit -p tsconfig.json
