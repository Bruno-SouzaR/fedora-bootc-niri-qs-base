# ==============================================================================
# ESTÁGIO 1: Imagem Base OCI (Fedora bootc)
# ==============================================================================
FROM quay.io/fedora/fedora-bootc:latest AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Instalação dos Pacotes do Sistema Base
# ==============================================================================

# 1. Instalar o plugin do COPR para o DNF5 e habilitar Niri e Ghostty
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty

# 2. Drivers de Vídeo e Recursos de Hardware (AMD/Intel)
RUN dnf install -y \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    libva \
    mesa-va-drivers \
    NetworkManager-wifi \
    bluez-tools

# 3. Gerenciador de Login, Compositor e Shell (Ajustado: qt6-qtshadertools)
RUN dnf install -y \
    greetd \
    niri \
    xwayland-satellite \
    quickshell \
    qt6-qtdeclarative \
    qt6-qtwayland \
    qt6-qtshadertools \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    gnome-keyring \
    polkit-kde-agent-1

# 4. Servidor de Áudio e Utilitários de Hardware
RUN dnf install -y \
    pipewire \
    wireplumber \
    pipewire-pulseaudio \
    pipewire-alsa \
    upower \
    brightnessctl \
    playerctl

# 5. Aplicações Nativas do Host
RUN dnf install -y \
    ghostty \
    nautilus \
    gvfs \
    gvfs-fuse \
    gvfs-mtp \
    file-roller \
    grim \
    slurp \
    wl-clipboard

# 6. CLI Dev, Produtividade e Monitoramento
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
    wget

# 7. Motores de Extensionamento (Contêineres e Sandbox)
RUN dnf install -y \
    podman \
    crun \
    fuse-overlayfs \
    distrobox \
    flatpak

# Limpeza do cache do DNF5
RUN dnf clean all && rm -rf /var/cache/dnf/*

# ==============================================================================
# ESTÁGIO 3: Copiando Arquivos Locais e Habilitando Serviços
# ==============================================================================

COPY system_files/ /

RUN systemctl enable NetworkManager.service && \
    systemctl enable bluetooth.service && \
    systemctl enable greetd.service && \
    systemctl enable podman.socket && \
    systemctl enable bootc-fetch-apply-updates.service

OSTREE_CONTAINER_OPTION_TRANSIENT_ETC=true