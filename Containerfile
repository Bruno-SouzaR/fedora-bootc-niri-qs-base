# ==============================================================================
# ESTÁGIO 1: Imagem Base Polida sem DE (Universal Blue Base 44)
# ==============================================================================
FROM ghcr.io/ublue-os/base-main:44 AS base

ENV INTERACTIVE=0

# ==============================================================================
# ESTÁGIO 2: Repositórios COPR, Repositório VSCodium e Instalação de Pacotes
# ==============================================================================

RUN dnf install -y 'dnf5-command(copr)' && \
    dnf copr enable -y yalter/niri && \
    dnf copr enable -y scottames/ghostty && \
    dnf copr enable -y solopasha/hyprland && \
    rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg && \
    printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=0\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg\nmetadata_expire=1h\n" > /etc/yum.repos.d/vscodium.repo

RUN dnf install -y \
    sddm \
    qt6-qtdeclarative \
    qt6-qtwayland \
    qt6-qtshadertools \
    qt6-qt5compat \
    qt6-qtsvg \
    qt6-gtkplatformtheme \
    niri \
    xwayland-satellite \
    quickshell \
    swww \
    matugen \
    brightnessctl \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-gnome \
    bluez-tools \
    pipewire-pulseaudio \
    polkit-kde-agent-1 \
    ghostty \
    codium \
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
    fontconfig \
    power-profiles-daemon && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# ==============================================================================
# ESTÁGIO 3: Configuração de Fontes, Zsh, Ícones e Defaults
# ==============================================================================

RUN mkdir -p /usr/share/fonts/JetBrainsMono && \
    curl -fLo /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -o /tmp/JetBrainsMono.zip -d /usr/share/fonts/JetBrainsMono/ && \
    chmod -R 755 /usr/share/fonts/JetBrainsMono && \
    rm -f /tmp/JetBrainsMono.zip && \
    fc-cache -f -v

RUN mkdir -p /usr/share/zsh/plugins /usr/share/zsh/themes && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /usr/share/zsh/themes/powerlevel10k && \
    git clone --depth=1 https://github.com/marlonrichert/zsh-autocomplete.git /usr/share/zsh/plugins/zsh-autocomplete

# Instalação do Tema de Ícones WhiteSur (Versão Alternativa Escura)
RUN git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon-theme && \
    /tmp/WhiteSur-icon-theme/install.sh -a -d /usr/share/icons && \
    rm -rf /tmp/WhiteSur-icon-theme

RUN ln -s /usr/bin/codium /usr/bin/vscodium && \
    sed -i 's|SHELL=/bin/bash|SHELL=/bin/zsh|g' /etc/default/useradd && \
    mkdir -p /etc/skel/Pictures/Screenshots

# ==============================================================================
# ESTÁGIO 4: Copiando Configurações Locais e Ativando Serviços
# ==============================================================================

COPY system_files/ /

RUN systemctl enable sddm.service power-profiles-daemon.service && \
    systemctl set-default graphical.target