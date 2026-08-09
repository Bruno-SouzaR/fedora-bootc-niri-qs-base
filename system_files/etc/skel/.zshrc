# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ==============================================================================
# CARREGAMENTO INTELIGENTE DE TEMAS E PLUGINS (Fedora + Arch Linux / Distrobox)
# ==============================================================================

# 1. Powerlevel10k
if [[ -f /usr/share/zsh/themes/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/share/zsh/themes/powerlevel10k/powerlevel10k.zsh-theme # Fedora Host
elif [[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme # Arch Linux
elif [[ -f /usr/share/zsh/plugins/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/share/zsh/plugins/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme # Arch Alt
fi

# 2. Autocomplete
if [[ -f /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
fi

# 3. Zsh Autosuggestions
if [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh # Fedora Host
elif [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh # Arch Linux
fi

# 4. Zsh Syntax Highlighting
if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh # Fedora Host
elif [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh # Arch Linux
fi

# ==============================================================================
# CONFIGURAÇÃO DE HISTÓRICO EXPANDIDO
# ==============================================================================
[[ -d ~/.local/share/zsh ]] || mkdir -p ~/.local/share/zsh

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE

# ==============================================================================
# VARIÁVEIS DE AMBIENTE (Qt / GTK / Tema)
# ==============================================================================
export QT_QPA_PLATFORMTHEME=gtk3

# ==============================================================================
# PONTE PARA EXECUTAR O VSCODIUM DO HOST DENTRO DA DISTROBOX
# ==============================================================================
if [[ -f /run/.containerenv || -n "$CONTAINER_ID" ]]; then
  alias vscodium="distrobox-host-exec codium"
  alias codium="distrobox-host-exec codium"
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh