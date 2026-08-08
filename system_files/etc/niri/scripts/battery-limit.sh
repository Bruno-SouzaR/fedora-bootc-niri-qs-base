#!/usr/bin/env bash

# Localiza dinamicamente o diretório da bateria (BAT0, BAT1, etc)
BAT_PATH=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)

if [ -z "$BAT_PATH" ] || [ ! -f "$BAT_PATH/charge_control_end_threshold" ]; then
    notify-send -u critical -i battery "Erro de Bateria" "Este sistema não suporta controle de limite de carga."
    exit 1
fi

TARGET="$1"

# Modo Alternar (Toggle)
if [ "$TARGET" = "toggle" ]; then
    CURRENT=$(cat "$BAT_PATH/charge_control_end_threshold" 2>/dev/null || echo 100)
    if [ "$CURRENT" -eq 80 ]; then
        TARGET=100
    else
        TARGET=80
    fi
fi

# Aplica o novo limite no hardware
echo "$TARGET" > "$BAT_PATH/charge_control_end_threshold"

# Notificação na tela
if [ "$TARGET" -eq 80 ]; then
    notify-send -u low -i battery-charging "Limite de Bateria" "Definido para 80% (Modo Vida Útil)"
else
    notify-send -u low -i battery "Limite de Bateria" "Definido para 100% (Carga Completa)"
fi