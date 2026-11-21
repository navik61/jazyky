#!/usr/bin/env bash
# ================================================================
# slovicka-interaktivni.sh
# Interaktivní procvičování slovíček s TTS v plovoucím okně kitty
# Použití: ./slovicka-interaktivni.sh [jazyk] [--swap|--orig] [--neznama] [--bez-frazi]
# ================================================================

# Bez grafické relace (cron, systemd) by mpv nenašel PipeWire
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export XDG_RUNTIME_DIR

# ── Konfigurace ─────────────────────────────────────────────────
SKRIPT=$(readlink -f "${BASH_SOURCE[0]}")
readonly SKRIPT
CESTA_SLOVNIKU=$(dirname "$SKRIPT")
readonly CESTA_SLOVNIKU
# shellcheck source=spolecne.sh
source "$CESTA_SLOVNIKU/spolecne.sh" || { echo "Chybí $CESTA_SLOVNIKU/spolecne.sh" >&2; exit 1; }

readonly POCET_KOLO=30
readonly PAUZA_PO_ORIG=1.0
readonly PAUZA_PO_CZ=0.5
readonly PAUZA_PRED_FRAZI=0.8

# 1 = procvičují se jen uložená neznámá slovíčka (--neznama)
JEN_NEZNAMA=0
# 1 = nezobrazovat a nečíst vzorové fráze (--bez-frazi)
BEZ_FRAZI=0

# ── Funkce ──────────────────────────────────────────────────────

_pouziti() {
    echo "Použití: $0 [jazyk] [volby]"
    echo ""
    echo "Jazyky: $(_seznam_jazyku)"
    echo ""
    echo "Volby:"
    echo "  --swap, -s      Nejdříve česky, pak originál"
    echo "  --orig, -o      Nejdříve originál, pak česky (bez dotazu)"
    echo "  --neznama, -u   Procvičit jen dříve neznámá slovíčka"
    echo "  --bez-frazi     Nezobrazovat a nečíst vzorové fráze"
    echo ""
    echo "Ovládání v okně: [Enter] znám · [n] neznám · [z] zopakovat slovíčko · [x] chybná fráze · [q] konec"
    exit "${1:-0}"
}

_uklid() {
    _uklid_tts
    _okno_zavrit
}

_zobraz_slovicko() {
    local radek="$1" jazyk="$2" swap="$3" cislo="$4" celkem="$5"
    local orig="${radek%% — *}" cz="${radek#* — }"
    local fraze="" fraze_cs=""
    if [[ "$BEZ_FRAZI" == "0" ]]; then
        fraze="${FRAZE[$radek]:-}"
        fraze_cs="${FRAZE_CS[$radek]:-}"
    fi
    local nazev="${NAZVY[$jazyk]}"
    [[ "$JEN_NEZNAMA" == "1" ]] && nazev="Neznámá: $nazev"

    local prvni druhy prvni_jazyk druhy_jazyk titulek
    if [[ "$swap" == "1" ]]; then
        prvni="$cz";   prvni_jazyk="cs"
        druhy="$orig"; druhy_jazyk="$jazyk"
        titulek="🇨🇿 $cislo/$celkem  →  ${VLAJKY[$jazyk]}"
    else
        prvni="$orig"; prvni_jazyk="$jazyk"
        druhy="$cz";   druhy_jazyk="cs"
        titulek="${VLAJKY[$jazyk]} $cislo/$celkem  →  🇨🇿"
    fi

    # printf: data v %s se nezpracovávají jako escape sekvence (na rozdíl od echo -e)
    clear
    printf '\e[0;90m%s  │  %s\e[0m\n\n' "$titulek" "$nazev"
    _vypis_zalomene $'\e[1;33m' "$prvni"
    _vypis_zalomene $'\e[0;37m' "$druhy"
    echo
    if [[ -n "$fraze" ]]; then
        _vypis_zalomene $'\e[3;36m' "$fraze"       # kurzíva, tyrkysová
        _vypis_zalomene $'\e[0;90m' "$fraze_cs"
        echo
    fi

    _tts_reci "$prvni" "$prvni_jazyk"
    sleep "$PAUZA_PO_ORIG"
    _tts_reci "$druhy" "$druhy_jazyk"
    if [[ -n "$fraze" ]]; then
        sleep "$PAUZA_PRED_FRAZI"
        _tts_reci "$fraze" "$jazyk"
    fi
    sleep "$PAUZA_PO_CZ"
}

# Uloží výsledky kola: neznámá přidá do neznama_<jazyk>.txt,
# v režimu --neznama v 1. kole známá ze souboru odebere.
# _zapis_vysledky jazyk cislo_kola jmeno_pole_neznamych jmeno_pole_znamych
_zapis_vysledky() {
    local jazyk="$1" kolo="$2"
    local -n _nez="$3" _zn="$4"
    _neznama_pridej "$jazyk" "${_nez[@]}"
    if [[ "$JEN_NEZNAMA" == "1" && "$kolo" == "1" ]]; then
        _neznama_odeber "$jazyk" "${_zn[@]}"
    fi
}

# _kolo jazyk swap jmeno_pole [cislo_kola]
_kolo() {
    local jazyk="$1" swap="$2" kolo="${4:-1}"
    local -n _vstup="$3"            # nameref: alias pro pole volajícího
    local -a pole_slov=("${_vstup[@]}")
    local celkem=${#pole_slov[@]}
    local -a neznama=() znama=()

    echo -e "\e[1;32m\n▶ Začínám kolo: $celkem slovíček\e[0m"
    echo -e "\e[0;90m  [Enter] = znám │ [n/N] = neznám │ [q/Q] = konec\e[0m\n"
    sleep 0.5

    local i=1 radek odpoved
    for radek in "${pole_slov[@]}"; do
        _zobraz_slovicko "$radek" "$jazyk" "$swap" "$i" "$celkem"

        # [z] přehraje slovíčko znovu, [x] označí frázi jako chybnou; pak se čeká dál
        local oznaceno=0 napoveda
        while :; do
            napoveda="[Enter] znám · [n] neznám · [z] znovu"
            if [[ -n "${FRAZE[$radek]:-}" ]]; then
                if (( oznaceno )); then
                    napoveda+=" · \e[1;31m✗ fráze označena\e[0;90m"
                else
                    napoveda+=" · [x] chybná fráze"
                fi
            fi
            printf '\r\e[K\e[0;90m%b · [q] konec \e[0m' "$napoveda"
            read -r odpoved
            if [[ "${odpoved,,}" == "z" ]]; then
                _zobraz_slovicko "$radek" "$jazyk" "$swap" "$i" "$celkem"
                continue
            fi
            [[ "${odpoved,,}" == "x" ]] || break
            if (( ! oznaceno )) && _oznac_chybnou "$jazyk" "$radek"; then
                oznaceno=1
            fi
            printf '\e[1A'     # zpět na řádek s nápovědou (Enter posunul kurzor)
        done

        case "${odpoved,,}" in
            q) _zapis_vysledky "$jazyk" "$kolo" neznama znama
               echo -e "\n\e[1;31mUkončeno po $((i-1)) slovíčkách.\e[0m"
               exit 0 ;;
            n|ne) neznama+=("$radek") ;;
            *) znama+=("$radek") ;;
        esac

        (( ++i ))
    done

    _zapis_vysledky "$jazyk" "$kolo" neznama znama
    clear

    local pocet_znamych=$(( celkem - ${#neznama[@]} ))
    echo -e "\e[1;32m\n✓ Kolo dokončeno!\e[0m"
    printf "  Znám:   \e[1;32m%d/%d\e[0m\n" "$pocet_znamych" "$celkem"
    printf "  Neznám: \e[1;31m%d/%d\e[0m\n" "${#neznama[@]}" "$celkem"

    if [[ ${#neznama[@]} -gt 0 ]]; then
        echo -en "\n\e[1;33m  Opakovat ${#neznama[@]} neznámých? [Enter=ano / n=ne]: \e[0m"
        local volba
        read -r volba
        if [[ "${volba,,}" != "n" ]]; then
            local -a zamichana
            # shellcheck disable=SC2034  # předává se jménem (nameref)
            mapfile -t zamichana < <(printf '%s\n' "${neznama[@]}" | shuf)
            _kolo "$jazyk" "$swap" zamichana $(( kolo + 1 ))
        fi
    else
        echo -e "\n\e[1;32m  🎉 Výborně! Znáš všechna slovíčka!\e[0m"
    fi
}

_na_preruseni() {
    echo -e "\n\n\e[1;33mPřerušeno.\e[0m"
    exit 0
}
trap _na_preruseni INT TERM HUP    # HUP = zavřené okno
trap _uklid EXIT

main() {
    local jazyk="" swap="0" poradi_zadano="0" arg

    for arg in "$@"; do
        case "$arg" in
            --swap|-s) swap="1"; poradi_zadano="1" ;;
            --orig|-o) swap="0"; poradi_zadano="1" ;;
            --neznama|-u) JEN_NEZNAMA=1 ;;
            --bez-frazi) BEZ_FRAZI=1 ;;
            -h|--help) _pouziti 0 ;;
            *)
                if _je_jazyk "$arg"; then
                    jazyk="$arg"
                else
                    echo "Neznámý argument: $arg" >&2
                    _pouziti 1 >&2
                fi ;;
        esac
    done

    # Výběr jazyka (terminál nebo rofi), včetně uložených neznámých
    if [[ -z "$jazyk" ]]; then
        jazyk=$(_vyber_jazyk) || exit $?
        [[ -z "$jazyk" ]] && exit 0
        if [[ "$jazyk" == neznama:* ]]; then
            jazyk="${jazyk#neznama:}"
            JEN_NEZNAMA=1
        fi
    fi

    if [[ "$poradi_zadano" == "0" && "$V_OKNE" == "0" ]]; then
        swap=$(_vyber_poradi) || exit $?
        [[ -z "$swap" ]] && exit 0
    fi

    local soubor
    if [[ "$JEN_NEZNAMA" == "1" ]]; then
        soubor=$(_soubor_neznamych "$jazyk")
        [[ -s "$soubor" ]] || _chyba "Zatím nemáš uložená žádná neznámá slovíčka (${NAZVY[$jazyk]})."
    else
        soubor="${SOUBORY[$jazyk]}"
        [[ -f "$soubor" ]] || _chyba "Soubor nenalezen: $soubor"
    fi

    # Mimo okno: otevřít plovoucí okno a spustit procvičování v něm
    if _lze_otevrit_okno; then
        local -a argumenty=("$jazyk")
        if [[ "$swap" == "1" ]]; then argumenty+=(--swap); else argumenty+=(--orig); fi
        [[ "$JEN_NEZNAMA" == "1" ]] && argumenty+=(--neznama)
        [[ "$BEZ_FRAZI" == "1" ]] && argumenty+=(--bez-frazi)
        _spust_v_okne "${argumenty[@]}"
        trap - EXIT     # spouštěč nesmí zavřít okno, které právě otevřel
        exit 0
    fi

    [[ "$BEZ_FRAZI" == "0" ]] && _nacti_fraze "$jazyk"

    local -a slovicka
    mapfile -t slovicka < <(grep ' — ' "$soubor" | shuf | head -n "$POCET_KOLO")

    echo -e "\n\e[1;32mNačteno ${#slovicka[@]} slovíček z: $soubor\e[0m"
    sleep 0.8

    clear
    _kolo "$jazyk" "$swap" slovicka

    echo -e "\n\e[1;32m✓ Trénink dokončen.\e[0m"
    if [[ "$V_OKNE" == "1" ]]; then
        echo -en "\e[0;90m[Enter] zavřít okno\e[0m"
        read -r
    fi
}

main "$@"
