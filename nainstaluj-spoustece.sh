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

# $1 = soubor, $2 = název, $3 = popis, $4 = argumenty spouštěče
_zapis() {
    cat > "$cil/$1" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec="$adresar/slovicka.sh"${4:+ $4}
Icon=accessories-dictionary
Terminal=false
Categories=Education;Languages;
Keywords=jazyky;slovicka;procvičování;němčina;angličtina;italština;francouzština;španělština;ruština;vocabulary;
StartupNotify=true
EOF
    echo "Vytvořeno: $cil/$1"
}

_zapis cz.slovicka.desktop "Slovíčka" "Interaktivní procvičování slovíček (znám / neznám)" ""
_zapis cz.slovicka.poslech.desktop "Slovíčka – poslech" "Pasivní poslech slovíček s frázemi" "--pasivni"

command -v update-desktop-database &>/dev/null && update-desktop-database "$cil" 2>/dev/null || true
