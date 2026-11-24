# Jazyky – vocabulary practice

[Česky](README.md) · **English**

Scripts for practising vocabulary for **Czech speakers**: German, English, Italian, French, Spanish, Russian, plus golf terminology in German, English and Italian. Words are shown in a translucent note-style window, read aloud (TTS), and each word comes with an example sentence and its Czech translation.

> The user interface, dictionaries and translations are in Czech – every dictionary entry is `foreign word — Czech translation`. Command-line options are Czech words too (`--pasivni` = passive, `--neznama` = unknown words, …).

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

The first start of the window takes about 20 s (`uv` builds PyGObject); later starts are fast.

## Quick start

```sh
jaz                 # interactive practice, language and order are chosen from a menu
jaz de              # German right away
jaz en --swap       # English, Czech first
jaz it --neznama    # only previously unknown words
jaz fr              # French (likewise es = Spanish, ru = Russian)
jaz de --intro      # first a 60 s intro picture with music, 5 s pause, then practice
jaz --pasivni de    # passive listening (plain "pasivni" works too)
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
| `de`, `en`, `it`, `fr`, `es`, `ru`, `de_golf`, `en_golf`, `it_golf` | language / dictionary (menu if omitted) | both |
| `--pasivni`, `pasivni`, `-P` | passive listening instead of interactive (only via `jaz` / `slovicka.sh`) | – |
| `--swap`, `-s` | Czech first, then the foreign word | both |
| `--orig`, `-o` | foreign word first, then Czech | both |
| `--neznama`, `-u` | only saved unknown words | both |
| `--bez-frazi` | do not show or read example sentences | both |
| `--bez-sumu` | no quiet background noise (see [Background sound](#background-sound)) | both |
| `--intro`, `intro` | intro picture with music before practice (see [Intro](#intro---intro)) | both |
| `--vsechna`, `-a` | go through the whole dictionary | passive |
| `--pocet N`, `-n N` | number of words (default 30) | passive |
| `--pauza N`, `-p N` | pause between words in seconds, decimals allowed (default 3) | passive |
| `-h`, `--help` | help | both |

Without `--swap` / `--orig` the script asks for the order (Enter = foreign word first). An interactive round always has 30 words.

## Files

| File | Description |
|---|---|
| `nainstaluj-spoustece.sh` | creates application-menu entries (`.desktop`) |
| `slovicka.sh` | launcher (alias `jaz`): interactive by default, `--pasivni` = listening |
| `slovicka-pasivni.sh` | passive listening |
| `slovicka-interaktivni.sh` | interactive practice |
| `intro.txt` | text of the intro picture – one sentence per line |
| `intro/` | photo and music for the intro; `intro/.vygenerovano/` = composed picture (generated) |
| `intro-obrazek.py` | composes the intro picture (Pillow via `uv run --script`) |
| `slovicka-view.py` | translucent window, menu and intro dialog (GTK4 + Pango), runs via `uv run --script` |
| `spolecne.sh` | shared code (dictionaries, TTS, sentences, window, menus, unknown words); sourced, not run |
| `*_slova.txt`, `golf_*.txt` | dictionaries |
| `fraze/<dictionary>.tsv` | example sentences |
| `fraze/chybne.tsv` | sentences marked with `x` (generated) |
| `fraze/lokalni/` | backup of old sentences from a local model (unused) |
| `neznama_<language>.txt` | saved unknown words (generated) |
| `generuj-fraze-claude.py` | sentence generator using the Claude Batch API |
| `generuj-fraze.py` | sentence generator using a local model (gpt-oss-20b) |
| `rozbor-skriptu.html` | study material (in Czech) – walkthrough of the scripts for learning bash |

## Dictionaries

One line = `foreign — Czech`, the separator is ` — ` (em dash with spaces). Variants can be separated by `/` and are read separately:

```
il controllo / l'ispezione — inspekce / prohlídka
```

Empty lines and lines without the separator are skipped.

| Key | Dictionary | Piper voice |
|---|---|---|
| `de` | `nemcina_slova.txt` | `de_DE-thorsten-medium` |
| `en` | `anglictina_slova.txt` | `en_US-lessac-medium` |
| `it` | `italstina_slova.txt` | `it_IT-riccardo-x_low` |
| `fr` | `francouzstina_slova.txt` | `fr_FR-siwis-medium` |
| `es` | `spanelstina_slova.txt` | `es_ES-davefx-medium` |
| `ru` | `rustina_slova.txt` | `ru_RU-irina-medium` |
| `*_golf` | `golf_<language>.txt` | by language |

Each general dictionary has about 3000 entries: basic verbs, home, town, food, body, work, economy, technology, nature, feelings and set phrases. The French, Spanish and Russian ones follow the topics of the Italian dictionary, with Italian specifics (dishes, sports) replaced by local ones (paella, crêpe, борщ). Russian words are written without stress marks.

A new language is added in `spolecne.sh` (arrays `JAZYKY`, `SOUBORY`, `NAZVY`, `VLAJKY`, `TTS_MODELY`, `TTS_JAZYK`) and in `generuj-fraze.py` (`SLOVNIKY`, `PRIKLADY`). Download the Piper voice from https://huggingface.co/rhasspy/piper-voices (both `.onnx` and `.onnx.json`) into `~/.local/share/piper/`.

## Example sentences

Every word has an example sentence in the foreign language with a Czech translation. In the window it is shown under the word (sentence in turquoise italics, translation in grey). After the word and its translation, the foreign sentence is read aloud as well.

**Status (24 Nov 2026):** all 20,847 words in all nine dictionaries have a sentence. They were generated by Claude via the Batch API – 240 with Claude Opus 5.5 (trial), the rest with Claude Sonnet 5.5 – for USD 8.47 in total.

Format of `fraze/<dictionary>.tsv` (tab-separated):

```
<dictionary line>	<sentence>	<Czech translation>
la chiave — klíč	Non trovo più la chiave della macchina.	Nemůžu najít klíč od auta.
```

Sentences are matched by the **whole dictionary line**. If you change a line in the dictionary, its sentence stops showing; the generator creates a new one on its next run. Sentences can be fixed by hand directly in the `.tsv`.

### Wrong sentences (`x`)

The `x` key appends the current word's sentence to `fraze/chybne.tsv` (no duplicates) and the hint shows **✗ fráze označena** (sentence marked):

```
<sentence file>	<dictionary line>	<sentence>	<translation>
```

Fix it by hand in `fraze/<sentence file>`, or let Claude fix it. Afterwards delete the lines from `chybne.tsv`.

### Generating with Claude (`generuj-fraze-claude.py`)

Uses the Claude **Batch API** (processed in the background, usually within an hour, 50 % discount). The actual cost was USD 0.40 per 1000 words with Sonnet 5.5 and USD 0.78 with Opus 5.5.

Authentication – one of:

```sh
ant auth login                        # Console profile, stored in ~/.config/anthropic/ (default)
read -rs "?API key: " k && printf '%s' "$k" > ~/.config/anthropic/api-key && unset k
```

Do not put the API key into `.zshrc` – Claude Code would start using it instead of the subscription.

```sh
./generuj-fraze-claude.py --nanecisto                    # dry run: plan and cost estimate, sends nothing
./generuj-fraze-claude.py --model claude-sonnet-5-5      # fill in all words without a sentence
./generuj-fraze-claude.py --limit 40                     # trial: 40 words from each dictionary
./generuj-fraze-claude.py --stav                         # status of the submitted batch
```

- Generates only words that do not have a sentence yet – after adding words, just run it again.
- Before sending it shows the number of words and a cost estimate and asks (`--ano` = don't ask). After downloading it prints the real cost from the tokens used.
- Waits for the batch and reports status every minute. Ctrl+C does not cancel the batch – the next run just downloads the results (the pending batch is stored in `fraze/.claude-batch.json`).
- The response is forced to JSON by a schema; sentences that fail the quality check are sent again on the next run. The check rejects e.g. a sentence that copies the whole dictionary line; a dash "—" inside a sentence is fine (Russian uses it routinely).
- Options: `--model claude-opus-5-5 | claude-sonnet-5-5 | claude-haiku-5-5` (default Opus), `--effort low | medium | high` (default `low`), `--davka 25`, dictionary names as arguments.
- Runs via `uv run --script`; `uv` downloads the `anthropic` library itself.

### Generating with a local model (`generuj-fraze.py`)

A free, offline alternative via a llama.cpp server with gpt-oss-20b (`llama-gpt-oss.service`, OpenAI API at `http://127.0.0.1:8080`). **Quality is much lower** – about a third of the Czech translations have grammar mistakes. A whole dictionary takes about 10 hours.

```sh
systemctl --user start llama-gpt-oss.service
systemd-run --user --unit=slovicka-fraze ~/Projects/Jazyky/generuj-fraze.py --uvazovani low
journalctl --user -u slovicka-fraze -f        # progress
systemctl --user stop slovicka-fraze          # stop (can be resumed)
```

Options: `--limit N`, `--davka 20`, `--uvazovani low | medium | high` (reasoning, default `medium`), `--pruchody 2`. Both generators write to the same files – do not run them at the same time.

## Unknown words

Words marked `n` in interactive mode are saved to `neznama_<language>.txt` (same format as the dictionary, no duplicates), even when you quit with `q`.

- Practise them with `--neznama` or via the **Neznámá: … (count)** item in the language menu – it only appears for languages that have unknown words.
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
| text | `intro.txt` | each non-empty line = one sentence; the font shrinks to fit |
| photo | `intro/*.jpg`, `*.png`, `*.webp` | the **newest** file is used; cropped to 16 : 9 (centre) |
| music | `intro/*.ogg`, `*.mp3`, `*.opus`, `*.flac`, `*.wav`, `*.m4a` | newest file; plays for at most 60 s, a shorter track is fine |

Just add or overwrite a file. On every start with `--intro` the script computes a fingerprint (sha256) of the text, the photo, the list of flags and `intro-obrazek.py` and compares it with `intro/.vygenerovano/otisk`. If anything changed, it composes a new `intro/.vygenerovano/intro.jpg`: flags of all languages at the top (Noto Color Emoji), the text of `intro.txt` at the bottom, with a dark gradient behind both for readability. If nothing changed, nothing is generated (the check takes a few ms).

| Variable | Meaning | Default |
|---|---|---|
| `SLOVICKA_INTRO_DELKA` | intro length in seconds | `60` |
| `SLOVICKA_INTRO_PAUZA` | pause before practice | `5` |
| `SLOVICKA_INTRO_SIRKA` | picture window width in px (height 16 : 9) | `1280` |

The picture is shown by `slovicka-view.py` as a dialog above the card (command `INTRO`), the music plays through `mpv`. Compositors open a dialog with a parent window as floating – even tiling ones (niri, sway, Hyprland) – without any configuration rules. Without a window (terminal mode) only the music plays.

**Default content:** photo *Rainier Meadow (July 2005)* by Jancarhart, public domain (Wikimedia Commons); music W. A. Mozart – *Eine kleine Nachtmusik* (Serenade in G major, K. 525), 1st movement Allegro, first 60 s of the Musopen recording, public domain (Wikimedia Commons).

## Other environments (Wayland, X11)

All windows are GTK4, so they should work in any Wayland compositor (GNOME, KDE, niri, sway, Hyprland…) and on X11. Nothing is tied to niri. **Only niri has been tested so far; GNOME, KDE, Hyprland, sway and X11 are untested.**

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
- **TTS:** foreign languages use Piper (program: `SLOVICKA_PIPER`, else `~/.local/share/uv/tools/piper-tts/bin/piper`, `~/.local/bin/piper`, or `piper` from `PATH`; voices: `SLOVICKA_PIPER_MODELY`, else `~/.local/share/piper`; the sample rate is read from `<model>.onnx.json`), Czech uses `edge-tts` (needs internet), fallback `espeak-ng`. `mpv` runs with `--no-input-terminal` so it does not steal keys.
- **Clean-up:** on exit (`q`, Ctrl+C, closing the window, error) reading stops, the window closes and the temporary mp3 in `/tmp` is deleted.

## Dependencies

- Intro: `uv` (downloads Pillow itself), `mpv`, `fontconfig` (`fc-match`), the Noto Color Emoji font (`noto-fonts-emoji`, Debian/Ubuntu `fonts-noto-color-emoji`) for flags, and Noto Sans or DejaVu Sans.
- Windows (card, menu, intro): `uv`, `gtk4`, `pango`, `gobject-introspection`, `cairo` and a compiler (`gcc`, `meson`, `pkgconf`) to build PyGObject; any Wayland compositor or X11.
- Scripts: `bash` 5+, `notify-send`, optionally `rofi` / `fuzzel` / `wofi` / `zenity` (menu without `uv`), `setsid`, `mpv`, `ffmpeg`, `piper-tts` (`uv tool install piper-tts`), `edge-tts`, optionally `espeak-ng`.
- Sentence generation: `uv` and access to the Claude API, or `python3` and a llama.cpp server with gpt-oss-20b.

## Study material

`rozbor-skriptu.html` (in Czech) – a walkthrough of the scripts for learning bash in three parts: the original version with techniques and exercises, fixes of weak spots (code before/after), and the extensions (sentences, key controls, sentence generators). Open with `xdg-open rozbor-skriptu.html`.

## Git

Public repository: https://github.com/navik61/jazyky (branch `master`).

## License

[MIT](LICENSE). The default photo and music in `intro/` are public domain (see [Intro](#intro---intro)).

## Troubleshooting

- **No sentence shown** – check that the word is in `fraze/<dictionary>.tsv` (`grep -F 'word — ' fraze/*.tsv`); after changing a dictionary run the generator.
- **Keys do nothing** – the window must have focus; keys are read only in the word window, not in the original terminal.
- **Sentence shortened (`…`) or title missing** – in terminal mode the content does not fit; enlarge the terminal.
- **Silence instead of a voice** – Piper, its voice or `edge-tts` is missing (Czech needs internet). Point to Piper and its voices with `SLOVICKA_PIPER` and `SLOVICKA_PIPER_MODELY`; without Piper `espeak-ng` is used.
- **Window opens in the background (GNOME, KDE)** – a window only gets focus with an activation token. When started from an application launcher (rofi, fuzzel, GNOME) the script passes it on; when started from a terminal there is no token and GNOME only shows a "… is ready" notification.
- **"Chybí …/spolecne.sh"** (missing) – `spolecne.sh` must be next to the scripts.
- **Claude generator: "Přihlášení neplatí nebo vypršelo"** (login invalid or expired) – run `ant auth login`, then start again (the batch keeps running meanwhile).
- **Local generator: `Connection refused`** – the server is not running: `systemctl --user start llama-gpt-oss.service`.
- **Bluetooth speaker still cuts off the start of words** – raise `SLOVICKA_SUM_UROVEN` (e.g. `0.01`). Some speakers sleep even with a very quiet signal.
- **The window does not open** – run `./slovicka-view.py --rezim znaky -- ./slovicka-pasivni.sh de --orig` by hand and look at the errors. If PyGObject fails to build, system libraries (`gobject-introspection`, `cairo`) or a compiler are missing; without `uv` the script silently runs in the terminal.
- **Intro does not change after editing** – only the newest photo/music in `intro/` is used; `cp -p` may keep an old date (`touch file`). Force recomposition: `rm -r intro/.vygenerovano`.
- **Empty boxes instead of flags** – `noto-fonts-emoji` is missing.
