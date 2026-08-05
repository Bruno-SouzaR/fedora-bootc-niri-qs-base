# ==============================================================================
# ESTÁGIO 1: Imagem Base OCI (Fedora bootc)
# ==============================================================================
FROM quay.io/fedora/fedora-bootc:latest AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Instalação dos Pacotes do Sistema Base
# ==============================================================================

# 1. Habilitar COPRs (Niri, Ghostty e bootc)
RUN dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty && \
    dnf copr enable -y fedora-bootc/bootc-sub-projects || true

# 2. Hardware e Display (Mesa / Drivers AMD e Intel)
RUN dnf install -y \
    kernel \
    kernel-modules \
    linux-firmware \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    libva \
    libva-intel-driver \
    mesa-va-drivers \
    systemd \
    dbus \
    NetworkManager \
    NetworkManager-wifi \
    bluez \
    bluez-tools

# 3. Gerenciador de Login, Compositor e Shell
RUN dnf install -y \
    greetd \
    niri \
    xwayland-satellite \
    quickshell \
    qt6-qtdeclarative \
    qt6-qtwayland \
    qt6-shadertools \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    gnome-keyring \
    polkit-kde-agent-1

# 4. Servidor de Áudio e Utilitários de Hardware (Notebook/Desktop)
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

# 7. Motores de Extensão (Contêineres e Sandbox)
RUN dnf install -y \
    podman \
    crun \
    fuse-overlayfs \
    distrobox \
    flatpak

# Limpeza de cache para manter a camada da imagem leve
RUN dnf clean all && rm -rf /var/cache/dnf/*

# ==============================================================================
# ESTÁGIO 3: Copiando Arquivos Locais e Habilitando Serviços
# ==============================================================================

# Copia toda a árvore de arquivos de configuração do seu repositório local para a raiz / do sistema
COPY system_files/ /

# Ativação de Serviços do Systemd
RUN systemctl enable NetworkManager.service && \
    systemctl enable bluetooth.service && \
    systemctl enable greetd.service && \
    systemctl enable podman.socket && \
    systemctl enable bootc-fetch-apply-updates.service

# Configuração de persistência de estado do bootc
OSTREE_CONTAINER_OPTION_TRANSIENT_ETC=true