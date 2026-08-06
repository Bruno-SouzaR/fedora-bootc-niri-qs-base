# ==============================================================================
# ESTÁGIO 1: Imagem Base OCI Estável (Fedora bootc 44)
# ==============================================================================
FROM quay.io/fedora/fedora-bootc:44 AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Instalação dos Pacotes e Firmwares
# ==============================================================================

# 1. Plugin do COPR e repositórios comunitários (Niri e Ghostty)
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty

# 2. Firmwares de Hardware e Drivers de Vídeo/Áudio (Intel Lunar Lake)
RUN dnf install -y \
    linux-firmware \
    alsa-sof-firmware \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    libva \
    mesa-va-drivers \
    NetworkManager-wifi \
    bluez-tools

# 3. Gerenciador de Login, Compositor e Shell
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

# 7. Motores de Contêiner e Sandbox
RUN dnf install -y \
    podman \
    crun \
    fuse-overlayfs \
    distrobox \
    flatpak

# Limpeza do cache do DNF5
RUN dnf clean all && rm -rf /var/cache/dnf/*

# ==============================================================================
# ESTÁGIO 3: Configurações, Criar Usuários, Serviços e OSTree Commit
# ==============================================================================

COPY system_files/ /

# 1. Cria o usuário e o diretório de estado do 'greeter' exigido pelo greetd
RUN useradd -r -M -d /var/lib/greetd -s /sbin/nologin -G video,input,render greeter || true && \
    mkdir -p /var/lib/greetd && \
    chown -R greeter:greeter /var/lib/greetd

# 2. Mascara o serviço que falhava ao tentar remontar a raiz OCI
RUN systemctl mask systemd-remount-fs.service

# 3. Ativação dos Serviços do Systemd
RUN systemctl enable NetworkManager.service && \
    systemctl enable bluetooth.service && \
    systemctl enable greetd.service && \
    systemctl enable podman.socket && \
    systemctl enable bootc-fetch-apply-updates.service

ENV OSTREE_CONTAINER_OPTION_TRANSIENT_ETC=true

# Sela a camada OCI para compatibilidade nativa com o motor de boot do OSTree
RUN ostree container commit