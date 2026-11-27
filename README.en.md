# Jazyky – vocabulary practice

[Česky](README.md) · **English**

Vocabulary practice **between any two of seven languages**: Czech, German, English, Italian, French, Spanish and Russian, plus golf terminology. You choose your (native) language and the language you are learning – a Czech learning Spanish, a German learning Czech, a Russian learning English… The interface is available in all seven languages. Words are shown in a translucent note-style window, read aloud (TTS), and each word comes with an example sentence translated into your language.

> Command-line options exist in Czech and English (`--pasivni` / `--passive`, `--neznama` / `--unknown`, …). Some file and function names in the code are Czech.

Two modes:

- **interactive practice** (`jaz` – default) – for each word you answer "I know / I don't know"; unknown words are saved and can be practised separately,
- **passive listening** (`jaz --pasivni`) – words, translations and sentences play on their own with a pause; you can pause and repeat.

**Testing status:** developed and tested on Arch Linux with the **niri** compositor (Wayland). The windows are plain GTK4 and nothing is tied to niri, but **GNOME, KDE, Hyprland, sway and X11 have not been tested yet** – bug reports are welcome.

## Installation

```sh
git clone https://github.com/navik61/jazyky.git ~/Projects/Jazyky
cd ~/Projects/Jazyky

# dependencies (Arch; similar packages elsewhere – see Dependencies)
sudo pacman -S --needed uv mpv ffmpeg gtk4 gobject-introspection cairo pkgconf meson gcc noto-fonts-emoji libnotify
uv tool install piper-tts                 # voice for foreign languages
uv tool install edge-tts                  # Czech voice (online)

# Piper voices → ~/.local/share/piper (see the table in Dictionaries), e.g.:
mkdir -p ~/.local/share/piper && cd ~/.local/share/piper
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json
cd -

./nainstaluj-spoustece.sh                 # "Slovíčka" entries in the application menu
ln -s "$PWD/slovicka.sh" ~/.local/bin/slovicka
```

The first start of the window takes about 20 s (`uv` builds PyGObject); later starts are fast. The interface language and your language are taken from `LANG` at first; change them in the menu (**💬 My language**, **🌐 Interface language**) or with `--z` / `--locale`.

### Windows (WSL2) – untested

> ⚠️ **Untested.** The steps follow what the scripts need (bash, GTK4, mpv, Piper), but I have not tried them on Windows. The scripts do not run directly in Windows (PowerShell, `cmd`) – they are `bash` and the windows use GTK4 on Wayland/X11. The way is **WSL2 with Ubuntu and WSLg** (Linux GUI apps and sound inside Windows 11, or Windows 10 22H2).

1. In PowerShell as administrator: `wsl --install -d Ubuntu`, reboot, create a user. Up-to-date WSL: `wsl --update`.
2. In Ubuntu:

```sh
sudo apt update
sudo apt install -y git curl mpv ffmpeg build-essential pkg-config meson \
    libgtk-4-dev gir1.2-gtk-4.0 libgirepository1.0-dev libcairo2-dev \
    libnotify-bin fonts-noto-color-emoji fonts-noto-core
# if building PyGObject complains about girepository-2.0: apt install libgirepository-2.0-dev
curl -LsSf https://astral.sh/uv/install.sh | sh && exec $SHELL
uv tool install piper-tts && uv tool install edge-tts

git clone https://github.com/navik61/jazyky.git ~/Projects/Jazyky
cd ~/Projects/Jazyky
mkdir -p ~/.local/bin && ln -s "$PWD/slovicka.sh" ~/.local/bin/slovicka
# Piper voices → ~/.local/share/piper (same as in Installation above)
slovicka            # or: slovicka de, slovicka gr
```

3. Run it from the Ubuntu terminal (Windows Terminal). `nainstaluj-spoustece.sh` (rofi/fuzzel) makes no sense in WSL; the language choice appears as a GTK menu.

**Possible problems** (not tried): sound goes through WSLg's PulseAudio (`mpv` must hear the output – check with `mpv --no-video file.mp3`); the window under WSLg may behave differently from a real compositor (background transparency, floating window, focus); the first start is slower because `uv` builds PyGObject. If it does not work, use `SLOVICKA_V_TERMINALU=1` (text mode only). Please report experiences and bugs as a GitHub issue.

## Quick start

```sh
jaz                 # interactive practice, language and order are chosen from a menu
jaz de              # German right away (from your language)
jaz en --swap       # English, your language first
jaz it --neznama    # only previously unknown words
jaz es --z de       # Spanish for German speakers
jaz cs --z en --locale en   # Czech for English speakers, English interface
jaz de --intro      # first a 60 s intro picture with music, 5 s pause, then practice
jaz --passive de    # passive listening (also "--pasivni" or just "pasivni")
jaz pasivni it -n 50 --intro   # passive listening, 50 words, with intro
```

After choosing the language and order, a floating window opens and everything runs inside it. The terminal is released immediately (the window is detached from it).

### Keys in the window

| Key | Passive (`jaz --pasivni`) | Interactive (`jaz`) |
|---|---|---|
| `space` | pause / resume – also stops reading mid-word | play / pause – pauses and resumes reading; after reading, plays the word again |
| `Enter` | – | I know (also while reading – reading stops) |
| `n` | – | I don't know (saved) |
| `z` | repeat the word from the start (any time, even when paused) | repeat the word (then answer) |
| `x` | mark the example sentence as wrong | mark the example sentence as wrong (then answer) |
| `q` | quit | quit |
| closing the window | quit | quit |

In the terminal fallback the interactive mode needs Enter after each key (`n⏎`, `z⏎`, `x⏎`). In the window a single key press is enough in both modes; `Esc` = `q`.

### Aliases and starting without a terminal

The author's aliases (kept in `~/dotfiles`):

```sh
alias jaz="~/Projects/Jazyky/slovicka.sh"          # interactive by default, --pasivni = listening
alias jazi="~/Projects/Jazyky/slovicka-interaktivni.sh"
```

`slovicka.sh` is the common launcher: without options it runs `slovicka-interaktivni.sh`, with `--pasivni` / `pasivni` / `-P` it runs `slovicka-pasivni.sh`; all other arguments are passed on unchanged (order does not matter). `--interaktivni` / `-I` forces interactive mode. Passive-only options (`--pocet`, `--pauza`, `--vsechna`) work only with `--pasivni`.

The old `--pruhledne` option is still accepted and ignored – the translucent window is now the default.

Without a terminal, the language and order are chosen in a **GTK menu** styled like the card (`slovicka-view.py --vyber`; arrows / `j` `k` / digits / mouse, `Enter` select, `Esc` cancel). Without `uv` it falls back to `rofi`, `fuzzel`, `wofi` or `zenity` (whichever is installed). Errors are shown as notifications (`notify-send`).

**Application menu (fuzzel, rofi `-show drun`, GNOME, KDE):** application launchers only list programs that have a `.desktop` file, not scripts from `PATH`. Create them with:

```sh
./nainstaluj-spoustece.sh               # → ~/.local/share/applications/cz.slovicka*.desktop
./nainstaluj-spoustece.sh --odinstaluj  # remove
```

The menu then shows **Slovíčka** (interactive) and **Slovíčka – poslech** (passive); they can also be found by typing "jazyky", "slovicka", "vocabulary" or a language name in Czech. The project path is written into the files – run the script again after moving the folder.

Symlinks into `PATH` (for rofi `run` mode and the terminal):

```sh
ln -s ~/Projects/Jazyky/slovicka.sh ~/.local/bin/slovicka
ln -s ~/Projects/Jazyky/slovicka-interaktivni.sh ~/.local/bin/slovicka-interaktivni
ln -s ~/Projects/Jazyky/slovicka-pasivni.sh ~/.local/bin/slovicka-pasivni
```

## Options

| Option | Meaning | Mode |
|---|---|---|
| `cs`, `de`, `en`, `it`, `fr`, `es`, `ru`, `<code>_golf` | what you are learning (menu if omitted); must differ from your language | both |
| `--z X`, `--from X`, `-f X` | your (native) language, see [Languages and interface](#languages-and-interface) | both |
| `--locale X`, `-l X` | interface language | both |
| `--pasivni`, `--passive`, `-P` | passive listening instead of interactive (only via `jaz` / `slovicka.sh`) | – |
| `--swap`, `-s` | your language first, then the foreign one | both |
| `--orig`, `-o` | foreign language first, then yours | both |
| `--neznama`, `--unknown`, `-u` | only saved unknown words | both |
| `--bez-frazi`, `--no-phrases` | do not show or read example sentences | both |
| `--bez-sumu`, `--no-noise` | no quiet background noise (see [Background sound](#background-sound)) | both |
| `--gr`, `gr`, `--grammar`, `-g` | grammar instead of words, see [Grammar](#grammar---gr) (en ↔ cs for now) | interactive |
| `--intro`, `intro` | intro picture with music before practice (see [Intro](#intro---intro)) | both |
| `--vsechna`, `--all`, `-a` | go through the whole dictionary | passive |
| `--pocet N`, `--count N`, `-n N` | number of words (default 30) | passive |
| `--pauza N`, `--pause N`, `-p N` | pause between words in seconds, decimals allowed (default 3) | passive |
| `-h`, `--help` | help (in the interface language) | both |

Without `--swap` / `--orig` the script asks for the order (Enter = foreign language first). An interactive round always has 30 words.

## Languages and interface

Each of the seven languages can be **your language** (you learn from it; translations are in it) and a **target language** (the one you learn). The menu lists all target languages except yours, plus two settings at the end:

- **💬 My language** – your (native) language,
- **🌐 Interface language** – language of menus, hints and messages (7 languages).

A choice made in the menu is saved to `~/.config/slovicka/nastaveni` (`zdroj=cs`, `locale=cs`) and applies next time too. Where the languages come from, in order:

| | 1. | 2. | 3. | 4. |
|---|---|---|---|---|
| your language | `--z` | `SLOVICKA_ZDROJ` | saved setting | interface language |
| interface | `--locale` | `SLOVICKA_LOCALE` | saved setting | `LC_ALL` / `LC_MESSAGES` / `LANG` (else English) |

Interface texts live in `locale/<code>.tsv` (key TAB text). Edit them in `nastroje/texty-rozhrani.py`, which generates all seven files at once (same keys everywhere). A missing key falls back to English.

Voices: Czech uses `edge-tts` (online), the other languages Piper (offline). The word is read in the target language, its translation in your language, and the sentence in the target language.

## Files

| File | Description |
|---|---|
| `slovicka.sh` | launcher (alias `jaz`): interactive by default, `--pasivni` = listening |
| `slovicka-interaktivni.sh` | interactive practice |
| `slovicka-pasivni.sh` | passive listening |
| `spolecne.sh` | shared code (languages, dictionary, TTS, sentences, window, menus, unknown words); sourced |
| `slovicka-view.py` | translucent window, menu and intro dialog (GTK4 + Pango), runs via `uv run --script` |
| `slovnik/obecne.tsv`, `slovnik/golf.tsv` | concept dictionary – see [Concept dictionary](#concept-dictionary) |
| `fraze/<set>-<language>.tsv` | example sentences in the target language and their translations |
| `fraze/chybne.tsv` | sentences marked with `x` (generated) |
| `locale/<code>.tsv` | interface texts (generated by `nastroje/texty-rozhrani.py`) |
| `intro.txt`, `intro.<code>.txt` | text of the intro picture (Czech / interface language) – one sentence per line |
| `intro/` | photo and music for the intro; `intro/.vygenerovano/` = composed pictures (generated) |
| `intro-obrazek.py` | composes the intro picture (Pillow via `uv run --script`) |
| `neznama/<yours>-<target>.txt` | saved unknown words (generated, not in git); for grammar `<yours>-<target>-gr.txt` |
| `gramatika/<target>-<source>.tsv` | grammar forms: sentences and word-by-word translation (`en-cs.tsv`, `cs-en.tsv`, `de-cs.tsv`, `fr-cs.tsv`, `it-cs.tsv`, `es-cs.tsv`, `ru-cs.tsv`, `de-en.tsv`) |
| `generuj-claude.py` | fills in words and sentences via the Claude Batch API |
| `nainstaluj-spoustece.sh` | creates application-menu entries (`.desktop`, translated) |
| `nastroje/texty-rozhrani.py` | source of the interface texts in all languages |
| `nastroje/migrace-pojmy.py` | one-off conversion of the old "foreign — Czech" dictionaries to concepts (history) |
| `rozbor-skriptu.md` | study material (in Czech) – walkthrough of the scripts for learning bash |

## Concept dictionary

The dictionary is a table of **concepts**: one row = one meaning, columns = the word in each language. That is what makes any language pair possible.

```
id	cs	de	en	it	fr	es	ru
o00177	klíč	der Schlüssel	the key	la chiave	la clé	la llave	ключ
```

- Two sets: `obecne` (general, ~5,000 concepts: basic verbs, home, town, food, body, work, economy, technology, nature, feelings, set phrases) and `golf` (~1,500 golf terms). The golf set is selected with `<code>_golf`.
- Variants are separated by `/` and read separately (`la clé / la clef`). Notes in parentheses clarify the meaning.
- A concept missing the word in your or the target language is skipped during practice.
- The concepts were created by merging the original "foreign word — Czech" dictionaries by Czech meaning (`nastroje/migrace-pojmy.py`); Claude filled in the missing languages (`generuj-claude.py slova`).

| Code | Language | Voice |
|---|---|---|
| `cs` | Czech | `edge-tts` cs-CZ-AntoninNeural (online) |
| `de` | German | Piper `de_DE-thorsten-medium` |
| `en` | English | Piper `en_US-lessac-medium` |
| `it` | Italian | Piper `it_IT-riccardo-x_low` |
| `fr` | French | Piper `fr_FR-siwis-medium` |
| `es` | Spanish | Piper `es_ES-davefx-medium` |
| `ru` | Russian | Piper `ru_RU-irina-medium` |

Download Piper voices from https://huggingface.co/rhasspy/piper-voices (both `.onnx` and `.onnx.json`) into `~/.local/share/piper/`. A new language is added in `spolecne.sh` (`JAZYKY`, `VLAJKY`, `TTS_MODELY`), as a new column in `slovnik/*.tsv` and `fraze/*.tsv`, in `generuj-claude.py` (`JAZYKY`, `NAZEV`) and in `nastroje/texty-rozhrani.py` (a new column of texts).

## Grammar (`--gr`)

```bash
jaz gr              # target chosen from your language (cs → English)
jaz gr --z en       # native English → Czech or German
jaz gr --neznama    # only saved unknown forms
```

Practises **grammatical forms** of the target language. Each card has three parts, always in this order:

1. a sentence in **your language**,
2. the sentence in the **target language**,
3. a **word-by-word translation** (`≈`, italic) into your language – it shows how the target language *thinks* (e.g. `I have lived here for five years` → `Já mám žil tady po pět rok`).

The header names the form (Present Perfect – for, Conditional 2, Locative – o …). All three parts are read aloud. Keys are the same as for words (`Enter` known, `n` unknown, space pause, `z` repeat, `q` quit); the order is fixed and `--swap` is ignored. A round has 30 items; unknown ones are repeated and saved to `neznama/<yours>-<target>-gr.txt`.

**Data** (`gramatika/<target>-<source>.tsv`, columns `id`, `tvar` (form name), sentence in your language, target sentence, word-by-word translation): `de-en.tsv` has 108 German sentences for English speakers (verb position, separable/reflexive verbs, subordinate clauses, Perfekt/Präteritum, modals, cases and case-governing prepositions, adjective endings, Konjunktiv I/II, passive…; word-by-word translation marks cases `.acc .dat .gen` and endings `-t`), `ru-cs.tsv` has 120 Russian sentences for Czech speakers (zero copula, aspect, verbs of motion, all six cases, dative constructions, *бы/чтобы*, impersonal constructions, *который*…), `it-cs.tsv` has 117 Italian and `es-cs.tsv` 130 Spanish sentences for Czech speakers (tenses, articles, negation, pronouns, prepositions, *essere/avere*, **ser × estar**, *piacere/gustar*, subjunctive, passive, *si/se* constructions…), `fr-cs.tsv` has 119 French sentences for Czech speakers (present, articles incl. partitive, negation, questions, passé composé, imparfait, future, conditional, imperative, **pronouns** y/en, prepositions, relative clauses, subjonctif, passive…), `de-cs.tsv` has 105 German sentences for Czech speakers (verb position, separable/reflexive verbs, subordinate clauses, Perfekt/Präteritum, modals, cases and case-governing prepositions, adjective endings, Konjunktiv I/II, passive…), `en-cs.tsv` has 100 English sentences (tenses, passive, modals, conditionals, reported speech, questions, gerund vs. infinitive, comparison, relative clauses…), `cs-en.tsv` has 68 Czech ones (tenses, aspect, conditional, imperative, reflexives, verbs of motion, **all seven cases**, numerals, agreement, subordinate clauses…). To add another language create `gramatika/<target>-<source>.tsv` with the same columns – `--gr` finds it automatically.

**Notation in the word-by-word line:** `[the]`, `[a]`, `[do]`, `[did]` = word without an equivalent in your language; `works-s`-style suffixes and `a-b` = joined words; `a_b` = one word rendered by several; for Czech `(I)-work` = dropped pronoun, `.loc` `.acc` … = case, `.pf`/`.impf` = aspect, `.m .f .n .pl` = gender/number. Notation is skipped when reading aloud.

## Example sentences

For every concept there is an example sentence in each target language, translated into the other languages. In the window it is shown under the word (sentence in turquoise italics, translation into your language in grey). After the word and its translation, the sentence is read aloud as well.

Format of `fraze/<set>-<target language>.tsv` – parallel sentences: the target-language column is the sentence, the others are its translations:

```
id	cs	de	en	it	fr	es	ru
o00177	Nemůžu najít klíč od auta.	Ich finde den Autoschlüssel nicht.	I can't find the car key.	Non trovo più la chiave della macchina.	…
```

Sentences are matched by concept `id`, so editing a word does not break its sentence. Sentences and translations can be fixed by hand directly in the `.tsv`. If the translation into your language is missing, the sentence is shown without it.

### Wrong sentences (`x`)

The `x` key appends the current word's sentence to `fraze/chybne.tsv` (no duplicates) and the hint shows **✗ sentence marked**:

```
<set>-<target>	<id>	<your language>	<sentence>	<translation>
```

Fix it by hand in `fraze/<set>-<target>.tsv`, or let Claude fix it. Afterwards delete the lines from `chybne.tsv`.

### Generating with Claude (`generuj-claude.py`)

Fills in only what is missing – after adding concepts just run it again. Uses the Claude **Batch API** (processed in the background, usually within an hour, 50 % discount).

```sh
./generuj-claude.py slova --nanecisto     # dry run: plan and cost estimate, sends nothing
./generuj-claude.py slova                 # 1. missing words in the concepts
./generuj-claude.py vety                  # 2. sentences and their translations into all languages
./generuj-claude.py vety --jazyky es --sady golf --limit 20   # only a part (trial)
./generuj-claude.py --stav                # status of the submitted batch
```

- The `slova` step gets examples of existing entries in its prompt so it follows the conventions (articles with nouns, verb infinitives, aspect pairs in Russian…).
- The `vety` step writes a sentence only where it is missing and translates it into the languages that lack a translation.
- Before sending it shows the number of items and a cost estimate and asks (`--ano` = don't ask). After downloading it prints the real cost.
- Ctrl+C does not cancel the batch – the next run just downloads the results (the pending batch is stored in `fraze/.claude-batch.json`). Invalid results (too short, copied entry) are sent again on the next run.
- Options: `--model claude-sonnet-5-5 | claude-opus-5-5 | claude-haiku-5-5` (default Sonnet), `--effort low | medium | high`, `--davka N` (items per request, default 40 words / 8 sentences – with larger batches the model skipped some items), `--sady`, `--jazyky`, `--limit`.
- Authentication – one of: `ant auth login` (Console profile, default), or an API key in `~/.config/anthropic/api-key` (chmod 600). Do not put the API key into `.zshrc` – Claude Code would start using it instead of the subscription.

**Status (24 Nov 2026):** the original Czech dictionaries and sentences (20,847 words, USD 8.47) were converted to concepts; the extension to all 7 languages was generated with Claude Sonnet 5.5 for USD 59.04 (18,497 words, ~21,000 new sentences, ~248,000 translations). All 6,555 concepts have a word, a sentence and translations in all seven languages.

## Unknown words

Words marked `n` in interactive mode are saved to `neznama/<your language>-<target>.txt` (concept ids, no duplicates), even when you quit with `q`. Each language pair has its own file.

- Practise them with `--neznama` or via the **Unknown: … (count)** menu item – it only appears for languages that have unknown words.
- In `--neznama` mode, a word you mark as known in **round 1** is removed from the file (repeat rounds do not change it). An empty file is deleted.
- Passive mode supports `--neznama` too (listening only, the file is not changed).

## Translucent window

The word, translation and sentence are rendered with Pango into a translucent borderless window. The window has a fixed width; its height adapts to the sentence. It runs via `uv run --script` – `uv` builds PyGObject on the first start (about 20 s, then cached). Without a graphical session or without `uv`, practice runs directly in the terminal.

| Variable | Meaning | Default |
|---|---|---|
| `SLOVICKA_STYL` | colours and font, styles 0–9 (0 dark green, 2 wine, 3 dark blue, 4 Nord, 9 large and readable…) | `0` |
| `SLOVICKA_ALFA` | background opacity, hex `00`–`ff` | `POZNAMKA_ALFA`, else `b3` (≈ 70 %) |
| `SLOVICKA_ZOOM` | zoom of the whole window | `1` |
| `SLOVICKA_SIRKA` | window width in px (before zoom) | `760` |

```sh
SLOVICKA_STYL=3 SLOVICKA_ZOOM=1.2 jaz it
```

Extra keys: `=` / `-` / `0` zoom, drag with the mouse to move the window. Closing the window ends practice (an unfinished round is not saved, `q` saves it). App-ids: `cz.slovicka.view` (card and intro), `cz.slovicka.vyber` (menu) – see [Other environments](#other-environments-wayland-x11).

**How it works:** the launcher starts `slovicka-view.py --rezim znaky|radky -- <script> …` detached. The viewer runs the script with `SLOVICKA_V_OKNE=2` in its own process group. The script sends commands (`KARTA`, `NAPOVEDA`, `ZPRAVA`, `INTRO`, `INTRO_KONEC`, tab-separated fields) to the file descriptor `$SLOVICKA_FD` via `_view` in `spolecne.sh`, and receives key presses on stdin (passive as a character for `read -n1`, interactive as a line for `read -r`). The script's terminal output goes to `/dev/null`. The end of the script closes the window; closing the window sends `SIGTERM` to the group (also stopping `piper`/`mpv`).

## Intro (`--intro`)

With `--intro` (or just `intro`), after the language is chosen an intro picture (1280 × 720) is shown in a window above the card while music plays (60 s), then there is a 5 s countdown and practice starts. `q`, `Esc`, space or `Enter` in the picture window skips the intro; `q` in the card quits.

```sh
jaz de --intro         # interactive practice with intro
jaz pasivni it intro   # passive listening with intro
```

**Content you can change:**

| What | Where | Note |
|---|---|---|
| text | `intro.txt` (Czech), `intro.<code>.txt` (other interface languages) | each non-empty line = one sentence; the font shrinks to fit; if there is no text for the interface language, the English one is used |
| photo | `intro/*.jpg`, `*.png`, `*.webp` | the **newest** file is used; cropped to 16 : 9 (centre) |
| music | `intro/*.ogg`, `*.mp3`, `*.opus`, `*.flac`, `*.wav`, `*.m4a` | newest file; plays for at most 60 s, a shorter track is fine |

Just add or overwrite a file. On every start with `--intro` the script computes a fingerprint (sha256) of the text, the photo, the list of flags and `intro-obrazek.py` and compares it with `intro/.vygenerovano/intro-<code>.otisk`. If anything changed, it composes a new `intro/.vygenerovano/intro-<code>.jpg` (separately for each interface language): flags of all seven languages at the top (Noto Color Emoji), the text of `intro.txt` at the bottom, with a dark gradient behind both for readability. If nothing changed, nothing is generated (the check takes a few ms).

| Variable | Meaning | Default |
|---|---|---|
| `SLOVICKA_INTRO_DELKA` | intro length in seconds | `60` |
| `SLOVICKA_INTRO_PAUZA` | pause before practice | `5` |
| `SLOVICKA_INTRO_SIRKA` | picture window width in px (height 16 : 9) | `1280` |

The picture is shown by `slovicka-view.py` as a dialog above the card (command `INTRO`), the music plays through `mpv`. Compositors open a dialog with a parent window as floating – even tiling ones (niri, sway, Hyprland) – without any configuration rules. Without a window (terminal mode) only the music plays.

**Default content:** photo *Rainier Meadow (July 2005)* by Jancarhart, public domain (Wikimedia Commons); music W. A. Mozart – *Eine kleine Nachtmusik* (Serenade in G major, K. 525), 1st movement Allegro, first 60 s of the Musopen recording, public domain (Wikimedia Commons).

## Other environments (Wayland, X11)

All windows are GTK4, so they should work in any Wayland compositor (GNOME, KDE, niri, sway, Hyprland…) and on X11. Nothing is tied to niri. **Only niri has been tested so far; GNOME, KDE, Hyprland, sway and X11 are untested.**

- **Terminal outside the session (tty, ssh, `tmux`):** when neither `WAYLAND_DISPLAY` nor `DISPLAY` is set, the script finds the `$XDG_RUNTIME_DIR/wayland-N` socket itself and the window opens. Force text mode with `SLOVICKA_V_TERMINALU=1`.
- **Floating windows:** the card and the menu have a fixed size, the intro is a dialog above the card. GNOME and KDE show them normally, niri opens them floating by itself. For other tiling compositors that tile fixed-size windows, one rule is enough:

  ```sh
  # sway (~/.config/sway/config)
  for_window [app_id="^cz\.slovicka\."] floating enable, border none

  # Hyprland (hyprland.conf, syntax 0.53+; older: windowrule = float, class:^(cz\.slovicka\..*)$)
  windowrule = match:class ^(cz\.slovicka\..*)$, float 1

  # mango (config.conf)
  windowrule=isfloating:1,appid:cz.slovicka.view
  windowrule=isfloating:1,appid:cz.slovicka.vyber
  ```

- **Focus:** Wayland does not let a window take focus by itself; it needs an activation token (xdg-activation, `DESKTOP_STARTUP_ID` on X11). The script takes the token from the launcher, passes it to the first menu, and each menu issues a token for the next window after a selection (file `$XDG_RUNTIME_DIR/slovicka-aktivace.<PID>`). Windows should therefore open on top in GNOME and KDE too.
- **Placement:** the compositor decides where a window appears (Wayland does not let applications choose). Drag the window with the mouse to move it.
- **Graphics:** `slovicka-view.py` forces the integrated AMD GPU (`VK_DRIVER_FILES`, `__EGL_VENDOR_LIBRARY_FILENAMES`) only when those drivers exist; otherwise GTK chooses.
- **Fonts:** `intro-obrazek.py` finds fonts via `fc-match`, so distribution-specific paths do not matter.

## Background sound

During practice a very quiet white noise plays. It keeps a Bluetooth speaker from going to sleep between words and cutting off the start of short words. It keeps playing during pauses and stops with the script (end, `q`, closing the window). In a mixer (pavucontrol) it shows up as `slovicka-pozadi`.

| Variable | Meaning | Default |
|---|---|---|
| `SLOVICKA_POZADI` | `sum` = noise, `ne` = off, or a path to a sound file (looped) | `sum` |
| `SLOVICKA_SUM_BARVA` | noise colour: `white`, `pink`, `brown` (deeper, more pleasant) | `white` |
| `SLOVICKA_SUM_UROVEN` | noise amplitude (0–1); `0.003` is almost inaudible | `0.003` |
| `SLOVICKA_POZADI_HLASITOST` | file volume in `mpv` (0–100) | `25` |

```sh
SLOVICKA_SUM_BARVA=brown SLOVICKA_SUM_UROVEN=0.01 jaz de    # audible brown noise
SLOVICKA_POZADI=~/Music/rain.mp3 jaz it                      # your own sound
jaz de --bez-sumu                                            # no noise
```

For a permanent setting put it into `~/.zshrc` (`export SLOVICKA_SUM_BARVA=pink`). The noise is generated by `mpv` with ffmpeg's `anoisesrc` filter, no file needed.

## How it works

- **Paths:** `CESTA_SLOVNIKU` is derived from the script's location (`readlink -f`), so symlinks work and the folder can be moved – just update the aliases.
- **Window:** after the selection the script starts itself inside `slovicka-view.py` (via `setsid` and `uv run --script`, detached from the terminal), see [Translucent window](#translucent-window). Without a graphical session or `uv` it runs directly in the terminal.
- **Terminal mode:** the card is laid out by `_vypis_kartu` according to the real terminal size: sentences are wrapped (`fold -s`), blank lines are added only if there is room, and as a last resort the sentence is shortened (`…`). The title with flags and position never scrolls away. Key hints in the terminal are shortened (`[x] chyba`, `[⏎] znám`) to fit on one line.
- **Controls (both modes):** reading runs in the background while the script reads keys (`read -t`). Space sends `SIGSTOP` / `SIGCONT` to the reading (stopping `piper`, `ffmpeg` and `mpv` mid-word), `z` ends it (`SIGTERM`) and the word starts again. Waiting between words is timed with `$EPOCHREALTIME`.
- **TTS:** Czech uses `edge-tts` (without it Piper / `espeak-ng`), the other languages use Piper (program: `SLOVICKA_PIPER`, else `~/.local/share/uv/tools/piper-tts/bin/piper`, `~/.local/bin/piper`, or `piper` from `PATH`; voices: `SLOVICKA_PIPER_MODELY`, else `~/.local/share/piper`; the sample rate is read from `<model>.onnx.json`), Czech uses `edge-tts` (needs internet), fallback `espeak-ng`. `mpv` runs with `--no-input-terminal` so it does not steal keys.
- **Clean-up:** on exit (`q`, Ctrl+C, closing the window, error) reading stops, the window closes and the temporary mp3 in `/tmp` is deleted.

## Dependencies

- Intro: `uv` (downloads Pillow itself), `mpv`, `fontconfig` (`fc-match`), the Noto Color Emoji font (`noto-fonts-emoji`, Debian/Ubuntu `fonts-noto-color-emoji`) for flags, and Noto Sans or DejaVu Sans.
- Windows (card, menu, intro): `uv`, `gtk4`, `pango`, `gobject-introspection`, `cairo` and a compiler (`gcc`, `meson`, `pkgconf`) to build PyGObject; any Wayland compositor or X11.
- Scripts: `bash` 5+, `notify-send`, optionally `rofi` / `fuzzel` / `wofi` / `zenity` (menu without `uv`), `setsid`, `mpv`, `ffmpeg`, `piper-tts` (`uv tool install piper-tts`), `edge-tts`, optionally `espeak-ng`.
- Generating words and sentences: `uv` and access to the Claude API.

## Study material

[`rozbor-skriptu.md`](rozbor-skriptu.md) (in Czech) – a walkthrough of the scripts for learning bash in four parts: the original version with techniques and exercises, fixes of weak spots (code before/after), the extensions (sentences, key controls, sentence generators), and the current version (GTK window via `uv`, intro, play/pause, menu and focus on any Wayland compositor, how it was tested). Exercises have solutions in collapsible blocks.

## Git

Public repository: https://github.com/navik61/jazyky (branch `master`).

## License

[MIT](LICENSE). The default photo and music in `intro/` are public domain (see [Intro](#intro---intro)).

## Troubleshooting

- **No sentence shown** – the concept has no sentence in `fraze/<set>-<target>.tsv`; `./generuj-claude.py vety` fills it in.
- **No words for a language pair** – the concept dictionary is still missing one of the languages: `./generuj-claude.py slova`.
- **The interface is in the wrong language** – it follows `LANG` until you choose one; use **🌐 Interface language** in the menu or `--locale xx`.
- **Keys do nothing** – the window must have focus; keys are read only in the word window, not in the original terminal.
- **Sentence shortened (`…`) or title missing** – in terminal mode the content does not fit; enlarge the terminal.
- **Silence instead of a voice** – Piper, its voice or `edge-tts` is missing (Czech needs internet). Point to Piper and its voices with `SLOVICKA_PIPER` and `SLOVICKA_PIPER_MODELY`; without Piper `espeak-ng` is used.
- **Window opens in the background (GNOME, KDE)** – a window only gets focus with an activation token. When started from an application launcher (rofi, fuzzel, GNOME) the script passes it on; when started from a terminal there is no token and GNOME only shows a "… is ready" notification.
- **"Chybí …/spolecne.sh"** (missing) – `spolecne.sh` must be next to the scripts.
- **Generator: "Přihlášení neplatí nebo vypršelo"** (login invalid or expired) – run `ant auth login`, then start again (the batch keeps running meanwhile).
- **Bluetooth speaker still cuts off the start of words** – raise `SLOVICKA_SUM_UROVEN` (e.g. `0.01`). Some speakers sleep even with a very quiet signal.
- **The window does not open** – run `./slovicka-view.py --rezim znaky -- ./slovicka-pasivni.sh de --orig` by hand and look at the errors. If PyGObject fails to build, system libraries (`gobject-introspection`, `cairo`) or a compiler are missing; without `uv` the script silently runs in the terminal.
- **Intro does not change after editing** – only the newest photo/music in `intro/` is used; `cp -p` may keep an old date (`touch file`). Force recomposition: `rm -r intro/.vygenerovano`.
- **Empty boxes instead of flags** – `noto-fonts-emoji` is missing.
