#!/usr/bin/env bash

LAST_PROFILE=""

update_power_profile() {
    local TARGET_PROFILE=""

    # 1. Verifica se qualquer fonte AC/Carregador está conectada
    if grep -q 1 /sys/class/power_supply/AC*/online 2>/dev/null || grep -q 1 /sys/class/power_supply/AD*/online 2>/dev/null; then
        TARGET_PROFILE="performance"
    else
        TARGET_PROFILE="power-saver"
    fi

    # 2. Só altera e notifica se o perfil realmente mudou
    if [ "$TARGET_PROFILE" != "$LAST_PROFILE" ]; then
        powerprofilesctl set "$TARGET_PROFILE"
        notify-send -u low -i battery "Perfil de Energia" "Modo alterado para: $TARGET_PROFILE"
        LAST_PROFILE="$TARGET_PROFILE"
    fi
}

# Executa a checagem inicial ao fazer login
update_power_profile

# Escuta eventos da fonte de energia em tempo real
udevadm monitor --subsystem-match=power_supply --udev | while read -r line; do
    update_power_profile
done