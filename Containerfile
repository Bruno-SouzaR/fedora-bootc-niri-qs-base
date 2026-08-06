# ==============================================================================
# ESTÁGIO 1: Imagem Base Polida sem DE (Universal Blue Base 44)
# ==============================================================================
FROM ghcr.io/ublue-os/base-main:44 AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Repositórios COPR e Ferramentas Personalizadas
# ==============================================================================

# 1. Habilitar COPRs para Niri e Ghostty
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty

# 2. Gerenciador de Login SDDM, Niri, Quickshell, Portais e Bibliotecas Qt6
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
    xdg-desktop-portal-gnome \
    polkit-kde-agent-1

# 3. Aplicações Nativas e Utilitários de Desktop
RUN dnf install -y \
    ghostty \
    nautilus \
    gvfs-fuse \
    gvfs-mtp \
    file-roller \
    grim \
    slurp \
    wl-clipboard

# 4. CLI Dev, Produtividade e Ferramentas Diárias
RUN dnf install -y \
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
    distrobox

# Limpeza de cache do DNF5
RUN dnf clean all && rm -rf /var/cache/dnf/*

# ==============================================================================
# ESTÁGIO 3: Copiando Configurações Locais e Ativando Serviços
# ==============================================================================

# Copia a árvore de configurações (incluindo a pasta limpa do pixie-sddm)
COPY system_files/ /

# Habilita o SDDM como gerenciador de login padrão
RUN systemctl enable sddm.service

# Sela a camada OCI para compatibilidade nativa com o OSTree
RUN ostree container commit