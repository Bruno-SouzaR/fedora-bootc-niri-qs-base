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

# 3. Fontes, Tipografia e Renderização de Sistema
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

# Limpeza do cache do DNF5
RUN dnf clean all && rm -rf /var/cache/dnf/*

# Adicionar repositório oficial Flathub por padrão
RUN flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ==============================================================================
# ESTÁGIO 3: Processamento Nativo do Systemd, Configurações e OSTree Commit
# ==============================================================================

# 1. Processa declarativamente todos os usuários de sistema (incluindo o 'greeter' do greetd)
RUN systemd-sysusers

# 2. Copia os arquivos de configuração customizados (suas configs do Niri/Quickshell/greetd)
COPY system_files/ /

# 3. Garante permissões adequadas no diretório do greetd e atribui shell de login válido
RUN mkdir -p /var/lib/greetd && \
    chown -R greeter:greeter /var/lib/greetd && \
    usermod -s /bin/bash greeter

# 4. Habilita os serviços nativos do systemd
RUN systemctl enable NetworkManager.service && \
    systemctl enable bluetooth.service && \
    systemctl enable greetd.service && \
    systemctl enable podman.socket && \
    systemctl enable power-profiles-daemon.service && \
    systemctl enable bootc-fetch-apply-updates.service

ENV OSTREE_CONTAINER_OPTION_TRANSIENT_ETC=true

# Registra a imagem OCI para o gerenciador de boot do OSTree
RUN ostree container commit