#!/usr/bin/env bash
# ================================================================
# nainstaluj-spoustece.sh — položky do nabídky aplikací (fuzzel, rofi -show drun, GNOME, KDE…)
# Vytvoří ~/.local/share/applications/cz.slovicka*.desktop s cestou k tomuto projektu.
# Spusť znovu po přesunu složky projektu. --odinstaluj = smazat.
# ================================================================
set -euo pipefail

adresar=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
cil="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

if [[ "${1:-}" == "--odinstaluj" ]]; then
    rm -fv "$cil/cz.slovicka.desktop" "$cil/cz.slovicka.poslech.desktop"
    exit 0
fi

mkdir -p "$cil"

# Text z locale/<kód>.tsv: _text kód klíč
_text() { sed -n "s/^$2\t//p" "$adresar/locale/$1.tsv" 2>/dev/null | head -n1; }

# $1 = soubor, $2 = klíč názvu, $3 = klíč popisu, $4 = argumenty spouštěče
# Výchozí texty anglicky, přeložené jako Name[cs]=… atd. (prostředí vybere podle jazyka systému)
_zapis() {
    local kod
    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Name=$(_text en "$2")"
        echo "Comment=$(_text en "$3")"
        for kod in cs de it fr es ru; do
            echo "Name[$kod]=$(_text "$kod" "$2")"
            echo "Comment[$kod]=$(_text "$kod" "$3")"
        done
        echo "Exec=\"$adresar/slovicka.sh\"${4:+ $4}"
        echo "Icon=accessories-dictionary"
        echo "Terminal=false"
        echo "Categories=Education;Languages;"
        echo "Keywords=$(_text en desktop.klicova)slovicka;"
        for kod in cs de it fr es ru; do
            echo "Keywords[$kod]=$(_text "$kod" desktop.klicova)$(_text en desktop.klicova)slovicka;"
        done
        echo "StartupNotify=true"
    } > "$cil/$1"
    echo "→ $cil/$1"
}

_zapis cz.slovicka.desktop desktop.nazev desktop.popis ""
_zapis cz.slovicka.poslech.desktop desktop.poslech desktop.popis_poslech "--pasivni"

command -v update-desktop-database &>/dev/null && update-desktop-database "$cil" 2>/dev/null || true
