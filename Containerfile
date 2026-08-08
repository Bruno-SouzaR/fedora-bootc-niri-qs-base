# ==============================================================================
# ESTÁGIO 1: Imagem Base Polida sem DE (Universal Blue Base 44)
# ==============================================================================
FROM ghcr.io/ublue-os/base-main:44 AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Repositórios COPR e Instalação de Pacotes
# ==============================================================================

# 1. Habilitar COPRs para Niri, Ghostty e utilitários Wayland (swww/matugen)
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty && \
    dnf copr enable -y solopasha/hyprland

# 2. Instalação Consolidada dos Pacotes
RUN dnf install -y \
    sddm \
    sddm-wayland-plasma \
    qt6-qtdeclarative \
    qt6-qtwayland \
    qt6-qtshadertools \
    qt6-qt5compat \
    qt6-qtsvg \
    niri \
    xwayland-satellite \
    quickshell \
    swww \
    matugen \
    brightnessctl \
    xdg-desktop-portal-gnome \
    bluez-tools \
    pipewire-pulseaudio \
    polkit-kde-agent-1 \
    ghostty \
    nautilus \
    gvfs-fuse \
    gvfs-mtp \
    file-roller \
    grim \
    slurp \
    wl-clipboard \
    cliphist \
    git \
    gh \
    ripgrep \
    fd-find \
    bat \
    eza \
    jq \
    btop \
    fastfetch \
    unzip \
    zip \
    p7zip \
    tar \
    curl \
    wget \
    distrobox \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    fontconfig && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# ==============================================================================
# ESTÁGIO 3: Configuração da JetBrains Mono Nerd Font, Zsh e Defaults
# ==============================================================================

# 1. Baixar, Instalar e Definir Permissões Globais da JetBrains Mono Nerd Font
RUN mkdir -p /usr/share/fonts/JetBrainsMono && \
    curl -fLo /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -o /tmp/JetBrainsMono.zip -d /usr/share/fonts/JetBrainsMono/ && \
    chmod -R 755 /usr/share/fonts/JetBrainsMono && \
    rm -f /tmp/JetBrainsMono.zip && \
    fc-cache -f -v

# 2. Clonar Temas e Plugins Adicionais do Zsh para /usr/share/zsh
RUN mkdir -p /usr/share/zsh/plugins /usr/share/zsh/themes && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /usr/share/zsh/themes/powerlevel10k && \
    git clone --depth=1 https://github.com/marlonrichert/zsh-autocomplete.git /usr/share/zsh/plugins/zsh-autocomplete

# 3. Alterar o shell padrão do sistema para Zsh e criar diretório do skel para screenshots
RUN sed -i 's|SHELL=/bin/bash|SHELL=/bin/zsh|g' /etc/default/useradd && \
    mkdir -p /etc/skel/Pictures/Screenshots

# ==============================================================================
# ESTÁGIO 4: Copiando Configurações Locais e Ativando Serviços
# ==============================================================================

# Copia a árvore de configurações
COPY system_files/ /

# Habilita o SDDM como gerenciador de login padrão
RUN systemctl enable sddm.service