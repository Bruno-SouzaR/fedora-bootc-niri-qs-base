# ==============================================================================
# ESTÁGIO 1: Imagem Base OCI Estável (Fedora bootc 44)
# ==============================================================================
FROM quay.io/fedora/fedora-bootc:44 AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Instalação de Repositórios e Pacotes do Sistema
# ==============================================================================

# 1. Habilitar plugin do COPR e repositórios comunitários (Niri e Ghostty)
RUN dnf install -y 'dnf5-command(copr)' && \
    dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty

# 2. Firmwares de Hardware, Drivers de Vídeo e Áudio (Intel Lunar Lake / Arc)
RUN dnf install -y \
    linux-firmware \
    alsa-sof-firmware \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    libva \
    mesa-va-drivers \
    NetworkManager-wifi \
    bluez-tools

# 3. Fontes, Tipografia e Renderização de Sistema (Inspirado no ublue-os/base)
RUN dnf install -y \
    fontconfig \
    google-noto-sans-fonts \
    google-noto-color-emoji-fonts \
    dejavu-sans-fonts

# 4. Gerenciador de Energia, Atualização de Firmware e Diagnóstico de Hardware
RUN dnf install -y \
    power-profiles-daemon \
    fwupd \
    pciutils \
    usbutils \
    upower \
    brightnessctl \
    playerctl

# 5. Codecs Multimídia e Aceleração de Mídia (FFmpeg / GStreamer)
RUN dnf install -y \
    ffmpeg-free \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugin-openh264

# 6. Gerenciador de Login, Compositor Niri, Quickshell e Portais XDG
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
    xdg-desktop-portal-gtk \
    xdg-user-dirs \
    xdg-utils \
    desktop-file-utils \
    gnome-keyring \
    polkit-kde-agent-1

# 7. Servidor de Áudio Pipewire
RUN dnf install -y \
    pipewire \
    wireplumber \
    pipewire-pulseaudio \
    pipewire-alsa

# 8. Aplicações Nativas do Host e Utilitários de Desktop
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

# 9. CLI de Desenvolvimento, Produtividade e Monitoramento
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

# 10. Motores de Contêineres, Sandbox e Suporte Flatpak
RUN dnf install -y \
    podman \
    crun \
    fuse-overlayfs \
    distrobox \
    flatpak

# Limpeza de cache do DNF5 para reduzir tamanho da imagem
RUN dnf clean all && rm -rf /var/cache/dnf/*

# Adicionar repositório oficial Flathub por padrão no sistema
RUN flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ==============================================================================
# ESTÁGIO 3: Configurações do Host, Usuários, Serviços e OSTree Commit
# ==============================================================================

# Copia a árvore de arquivos locais de configuração para o /
COPY system_files/ /

# 1. Cria o grupo e usuário do 'greeter' de forma isolada e configura o diretório
RUN groupadd -r greeter || true && \
    useradd -r -g greeter -M -d /var/lib/greetd -s /sbin/nologin greeter || true && \
    mkdir -p /var/lib/greetd && \
    chown -R greeter:greeter /var/lib/greetd

# 2. Mascara o serviço de remontagem da raiz para evitar conflito no boot OCI
RUN systemctl mask systemd-remount-fs.service

# 3. Ativação dos Serviços Essenciais do Systemd
RUN systemctl enable NetworkManager.service && \
    systemctl enable bluetooth.service && \
    systemctl enable greetd.service && \
    systemctl enable podman.socket && \
    systemctl enable power-profiles-daemon.service && \
    systemctl enable bootc-fetch-apply-updates.service

ENV OSTREE_CONTAINER_OPTION_TRANSIENT_ETC=true

# Sela a camada OCI para compatibilidade nativa com o motor de boot do OSTree
RUN ostree container commit