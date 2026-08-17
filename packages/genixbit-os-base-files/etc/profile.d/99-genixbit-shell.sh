# GenixBit OS 1.1.0 — High-Productivity Shell UI & Dynamic Terminal Environment
# Configures Starship-inspired prompt, aliases, and terminal graphics.

if [ -t 1 ]; then
    # ANSI Colors
    C_CYAN='\[\033[38;2;82;217;255m\]'
    C_BLUE='\[\033[38;2;78;123;255m\]'
    C_GREEN='\[\033[38;2;112;226;162m\]'
    C_VIOLET='\[\033[38;2;167;107;255m\]'
    C_RESET='\[\033[0m\]'
    C_BOLD='\[\033[1m\]'

    # Git branch parser helper
    parse_git_branch() {
        git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
    }

    # Dynamic Starship/Powerline style prompt
    if [ -n "$BASH_VERSION" ]; then
        PS1="${C_CYAN}⚡ genixbit${C_RESET} ${C_BLUE}\w${C_VIOLET}\$(parse_git_branch)${C_GREEN} ❯${C_RESET} "
    fi

    # Convenient Developer & AI Aliases
    alias fetch='genixbit-fetch'
    alias ai='genixbit-ai-center run --prompt'
    alias aipull='genixbit-ai-center pull'
    alias voice='genixbit-voice listen'
    alias mesh='genixbit-mesh status'
    alias top='genixbit-top'
    alias diag='genixbit-gpu-diag'
    alias store='genixbit-store-gui'
    alias agents='genixbit-agent-studio'
    alias monitor='genixbit-monitor-gui'
    alias ll='ls -lah --color=auto'
    alias grep='grep --color=auto'

    # Auto-display fetch banner on fresh interactive login
    if [ -z "${GENIXBIT_FETCH_SHOWN:-}" ]; then
        export GENIXBIT_FETCH_SHOWN=1
        if command -v genixbit-fetch >/dev/null 2>&1; then
            genixbit-fetch
        fi
    fi
fi
