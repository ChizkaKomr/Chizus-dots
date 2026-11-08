#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
#  Chizu's dots installer
#
#  Put this script in the root of the Chizus-dots repo (~/Chizus-dots) and run:
#      ./install_script.sh            # interactive
#      ./install_script.sh -y         # accept all defaults
#      ./install_script.sh --dry-run  # only print what would happen
#
#  Steps:  1) back up existing configs   2) install dependencies   3) install dots
#  Target: Arch Linux and Arch-based distros (CachyOS, EndeavourOS, ...)
# ──────────────────────────────────────────────────────────────────────────────
set -Eeuo pipefail

# ─── settings ─────────────────────────────────────────────────────────────────
DOTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR="$HOME/.dots-backup/$(date +%Y-%m-%d_%H-%M-%S)"
ORIGINAL_HOME="/home/chizuko"   # hardcoded paths in the dots get rewritten to $HOME

# repo folder -> install location.
# "replace": the old folder is backed up, then replaced completely.
# "merge":   the old folder is backed up, then repo files are copied over it
#            (keeps the user's other files, e.g. GTK bookmarks or own wallpapers).
DOTS=(
    "hypr|$CONFIG_DIR/hypr|replace"
    "quickshell|$CONFIG_DIR/quickshell|replace"
    "rofi|$CONFIG_DIR/rofi|replace"
    "waybar|$CONFIG_DIR/waybar|replace"
    "kitty|$CONFIG_DIR/kitty|replace"
    "swaync|$CONFIG_DIR/swaync|replace"
    "wlogout|$CONFIG_DIR/wlogout|replace"
    "matugen|$CONFIG_DIR/matugen|replace"
    "wallust|$CONFIG_DIR/wallust|replace"
    "btop|$CONFIG_DIR/btop|replace"
    "cava|$CONFIG_DIR/cava|replace"
    "fastfetch|$CONFIG_DIR/fastfetch|replace"
    "rmpc|$CONFIG_DIR/rmpc|replace"
    "scripts|$CONFIG_DIR/rice_scripts|replace"
    "gtk-3.0|$CONFIG_DIR/gtk-3.0|merge"
    "gtk-4.0|$CONFIG_DIR/gtk-4.0|merge"
    "Pictures/wallpapers|$HOME/Pictures/wallpapers|merge"
)

# personal / junk files from the repo that should never land on another PC
EXCLUDE=(
    "quickshell/calendar_notes.json"
    "gtk-3.0/bookmarks"
    "gtk-3.0/gtk-3.0"
    "gtk-4.0/gtk-4.0"
    "hypr/current_wallpaper"      # recreated below, points to the new $HOME
    "hypr/modules/input.lua.save"
    "rofi/config.rasi.save"
    "wlogout/layout.save"
)

PACKAGES=(
    # base / build
    git base-devel glib2
    # hyprland stack
    hyprland hypridle hyprlock hyprpicker hyprshot hyprpolkitagent
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    # shell, bar, launcher, notifications, power menu
    quickshell waybar rofi swaync wlogout
    # wallpaper + dynamic colors
    awww matugen wallust
    # clipboard, audio, media, brightness
    wl-clipboard cliphist pipewire pipewire-pulse wireplumber libpulse
    playerctl brightnessctl cava jq
    # apps used by keybinds / configs
    kitty nautilus zen-browser-bin btop fastfetch rmpc mpd
    # theming
    nwg-look adw-gtk-theme papirus-icon-theme bibata-cursor-theme-bin
    # fonts
    adwaita-fonts noto-fonts noto-fonts-emoji noto-fonts-cjk
    ttf-material-symbols-variable ttf-jetbrains-mono-nerd ttf-0xproto-nerd
)

# if a package has no exact match anywhere, try these names instead
declare -A ALTERNATIVES=(
    [awww]="awww-git awww-bin"
    [matugen]="matugen-bin matugen-git"
    [wallust]="wallust-git"
    [quickshell]="quickshell-git"
    [zen-browser-bin]="zen-browser"
    [bibata-cursor-theme-bin]="bibata-cursor-theme"
)

# ─── flags ────────────────────────────────────────────────────────────────────
ASSUME_YES=0
DRY_RUN=0
SKIP_DEPS=0
SKIP_BACKUP=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

  -y, --yes         don't ask, use defaults for every question
  -n, --dry-run     print what would be done, change nothing
      --no-deps     skip installing packages
      --no-backup   skip backing up existing configs (not recommended)
  -h, --help        show this help
EOF
}

while (($#)); do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --no-deps) SKIP_DEPS=1 ;;
        --no-backup) SKIP_BACKUP=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# ─── helpers ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_BLUE=$'\e[1;34m' C_GREEN=$'\e[1;32m' C_YELLOW=$'\e[1;33m' C_RED=$'\e[1;31m' C_DIM=$'\e[2m' C_OFF=$'\e[0m'
else
    C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_OFF=''
fi

step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
info() { printf '  %s->%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '  %s!!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

# run a command, or just print it in dry-run mode
run() {
    if ((DRY_RUN)); then
        printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_OFF" "$*"
    else
        "$@"
    fi
}

# ask "question" default(y|n) -> returns 0 for yes
ask() {
    local question="$1" default="${2:-y}" reply hint="[Y/n]"
    [[ "$default" == n ]] && hint="[y/N]"
    if ((ASSUME_YES)) || [[ ! -t 0 ]]; then
        [[ "$default" == y ]]
        return
    fi
    read -rp "  ?? $question $hint " reply
    reply="${reply:-$default}"
    [[ "${reply,,}" == y* ]]
}

is_excluded() {
    local rel="$1" ex
    for ex in "${EXCLUDE[@]}"; do
        [[ "$rel" == "$ex" || "$rel" == "$ex"/* ]] && return 0
    done
    return 1
}

# ─── sanity checks ────────────────────────────────────────────────────────────
step "Checking system"
[[ $EUID -eq 0 ]] && die "don't run this as root, run it as your normal user (sudo is used when needed)."
command -v pacman >/dev/null || die "pacman not found - this installer only supports Arch-based distros."
[[ -d "$DOTS_DIR/hypr" && -d "$DOTS_DIR/quickshell" ]] \
    || die "can't find the dots next to this script ($DOTS_DIR). Put it in the root of the Chizus-dots folder."
info "dots folder: $DOTS_DIR"
info "installing for: $USER ($HOME)"
((DRY_RUN)) && warn "dry-run mode: nothing will be changed"

cat <<EOF

  This will:
    1. back up your current configs to ${BACKUP_DIR/#$HOME/\~}
    2. install the needed packages (pacman + AUR)
    3. install the dots into ${CONFIG_DIR/#$HOME/\~} and ~/Pictures/wallpapers
EOF
ask "Continue?" y || { echo "Aborted."; exit 0; }

# ─── 1. backup ────────────────────────────────────────────────────────────────
backup() {
    step "1/3  Backing up existing configs"
    if ((SKIP_BACKUP)); then
        warn "skipped (--no-backup)"
        return
    fi

    local entry src dst mode rel count=0
    for entry in "${DOTS[@]}"; do
        IFS='|' read -r src dst mode <<<"$entry"
        [[ -d "$DOTS_DIR/$src" ]] || continue
        [[ -e "$dst" || -L "$dst" ]] || continue

        # don't copy the whole wallpaper collection, only files the dots would overwrite
        if [[ "$src" == "Pictures/wallpapers" ]]; then
            while IFS= read -r -d '' f; do
                rel="${f#"$DOTS_DIR/$src/"}"
                if [[ -e "$dst/$rel" ]]; then
                    run mkdir -p "$BACKUP_DIR/wallpapers/$(dirname -- "$rel")"
                    run cp -a -- "$dst/$rel" "$BACKUP_DIR/wallpapers/$rel"
                fi
            done < <(find "$DOTS_DIR/$src" -type f -print0)
            continue
        fi

        rel="${dst#"$HOME/"}"
        run mkdir -p "$BACKUP_DIR/$(dirname -- "$rel")"
        run cp -a -- "$dst" "$BACKUP_DIR/$rel"
        info "~/$rel"
        count=$((count + 1))
    done

    if ((count == 0)) && [[ ! -d "$BACKUP_DIR" ]]; then
        info "nothing to back up, clean system"
        return
    fi

    if ((!DRY_RUN)); then
        cat >"$BACKUP_DIR/RESTORE.txt" <<EOF
Backup made by the Chizus-dots installer on $(date).
Folders here mirror their location relative to your home folder.
To restore one, e.g. hypr:
    rm -rf ~/.config/hypr && cp -a "$BACKUP_DIR/.config/hypr" ~/.config/
EOF
    fi
    info "backup saved to $BACKUP_DIR"
}

# ─── 2. dependencies ──────────────────────────────────────────────────────────
AUR_HELPER=""

find_aur_helper() {
    local h
    for h in paru yay; do
        if command -v "$h" >/dev/null; then AUR_HELPER="$h"; return 0; fi
    done
    return 1
}

install_yay() {
    info "no AUR helper found, building yay-bin"
    run sudo pacman -S --needed --noconfirm git base-devel
    if ((DRY_RUN)); then AUR_HELPER="yay"; return; fi
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    AUR_HELPER="yay"
}

in_repos() { pacman -Si -- "$1" &>/dev/null; }
in_aur()   { [[ -n "$AUR_HELPER" ]] && "$AUR_HELPER" -Si --aur -- "$1" &>/dev/null; }

install_deps() {
    step "2/3  Installing dependencies"
    if ((SKIP_DEPS)); then
        warn "skipped (--no-deps)"
        return
    fi

    # refresh databases + full upgrade first (partial upgrades break Arch)
    info "updating the system (pacman -Syu)"
    run sudo pacman -Syu --noconfirm

    find_aur_helper || install_yay
    info "AUR helper: $AUR_HELPER"

    local pkg alt chosen repo_pkgs=() aur_pkgs=() missing=()
    for pkg in "${PACKAGES[@]}"; do
        chosen=""
        # already installed (also catches -git/-bin variants that provide it)
        if pacman -Qq -- "$pkg" &>/dev/null || pacman -Qqs "^${pkg}(-git|-bin)?\$" &>/dev/null; then
            continue
        fi
        for alt in "$pkg" ${ALTERNATIVES[$pkg]:-}; do
            if in_repos "$alt"; then repo_pkgs+=("$alt"); chosen="$alt"; break; fi
            if in_aur "$alt";   then aur_pkgs+=("$alt");  chosen="$alt"; break; fi
        done
        [[ -n "$chosen" ]] || missing+=("$pkg")
    done

    if ((${#repo_pkgs[@]})); then
        info "from repos: ${repo_pkgs[*]}"
        run sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
    fi
    if ((${#aur_pkgs[@]})); then
        info "from AUR:   ${aur_pkgs[*]}"
        run "$AUR_HELPER" -S --needed --noconfirm "${aur_pkgs[@]}"
    fi
    ((${#repo_pkgs[@]} + ${#aur_pkgs[@]})) || info "everything is already installed"
    ((${#missing[@]})) && warn "couldn't find these packages, install them manually: ${missing[*]}"

    # optional extra fonts shipped with the dots (e.g. Helvetica Rounded, Rubik)
    if [[ -d "$DOTS_DIR/fonts" ]]; then
        info "installing fonts from the dots into ~/.local/share/fonts"
        run mkdir -p "$HOME/.local/share/fonts"
        run cp -a -- "$DOTS_DIR/fonts/." "$HOME/.local/share/fonts/"
        run fc-cache -f
    fi
    return 0
}

# ─── 3. install dots ──────────────────────────────────────────────────────────
copy_tree() {   # copy_tree <repo subfolder> <destination>
    local src="$1" dst="$2" f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$DOTS_DIR/"}"
        is_excluded "$rel" && continue
        local out="$dst/${f#"$DOTS_DIR/$src/"}"
        if ((DRY_RUN)); then continue; fi
        mkdir -p -- "$(dirname -- "$out")"
        cp -a -- "$f" "$out"
    done < <(find "$DOTS_DIR/$src" \( -type f -o -type l \) -print0)
}

install_dots() {
    step "3/3  Installing dot files"

    local entry src dst mode
    for entry in "${DOTS[@]}"; do
        IFS='|' read -r src dst mode <<<"$entry"
        if [[ ! -d "$DOTS_DIR/$src" ]]; then
            warn "$src not found in the repo, skipping"
            continue
        fi
        if [[ "$mode" == replace && ( -e "$dst" || -L "$dst" ) ]]; then
            run rm -rf -- "$dst"
        fi
        run mkdir -p -- "$dst"
        copy_tree "$src" "$dst"
        info "$src -> ${dst/#$HOME/\~}"
    done

    ((DRY_RUN)) && return 0

    # rewrite hardcoded /home/chizuko paths to this user's home
    if [[ "$HOME" != "$ORIGINAL_HOME" ]]; then
        info "rewriting $ORIGINAL_HOME -> $HOME in config files"
        for entry in "${DOTS[@]}"; do
            IFS='|' read -r src dst mode <<<"$entry"
            [[ "$src" == Pictures/* || ! -d "$dst" ]] && continue
            grep -rlIZ --fixed-strings -- "$ORIGINAL_HOME" "$dst" 2>/dev/null \
                | xargs -0 -r sed -i "s|$ORIGINAL_HOME|$HOME|g" || true
        done
    fi

    # scripts must be executable
    find "$CONFIG_DIR/rice_scripts" "$CONFIG_DIR/matugen/post-hook-scripts" \
        -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
}

# ─── post install: wallpaper, colors, hardware ────────────────────────────────
setup_wallpaper() {
    step "Setting up wallpaper and colors"
    local walls="$HOME/Pictures/wallpapers/W39" wanted="" wall=""

    # use the same wallpaper as in the repo if possible
    if [[ -L "$DOTS_DIR/hypr/current_wallpaper" ]]; then
        wanted="$(basename -- "$(readlink "$DOTS_DIR/hypr/current_wallpaper")")"
        [[ -f "$walls/$wanted" ]] && wall="$walls/$wanted"
    fi
    if [[ -z "$wall" && -d "$walls" ]]; then
        wall="$(find "$walls" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort | head -n1)"
    fi
    if [[ -z "$wall" ]]; then
        warn "no wallpapers found in $walls, pick one later with the wallpaper picker"
        return 0
    fi

    run ln -sfn -- "$wall" "$CONFIG_DIR/hypr/current_wallpaper"
    info "wallpaper: $(basename -- "$wall")"

    if command -v matugen >/dev/null; then
        info "generating color scheme with matugen"
        run matugen image "$wall" --source-color-index 0 >/dev/null 2>&1 \
            || warn "matugen failed, colors will be generated on the first wallpaper change"
    fi
}

setup_hardware() {
    step "Adapting to this PC"
    local env_lua="$CONFIG_DIR/hypr/modules/env.lua" mon_lua="$CONFIG_DIR/hypr/modules/monitor.lua"

    # NVIDIA env vars break non-NVIDIA GPUs
    if [[ -f "$env_lua" ]] && grep -qi nvidia "$env_lua"; then
        if grep -qs 0x10de /sys/bus/pci/devices/*/vendor; then
            info "NVIDIA GPU found, keeping NVIDIA env vars"
        else
            info "no NVIDIA GPU, disabling NVIDIA env vars in env.lua"
            run sed -i -E '/nvidia/I s/^([[:space:]]*)(hl\.env)/\1-- \2/' "$env_lua"
        fi
    fi

    # the original monitor config is for one specific 1080p 144Hz HDMI screen
    if [[ -f "$mon_lua" ]] && ask "Replace the author's monitor setup (HDMI-A-1 1920x1080@144) with auto-detect?" y; then
        if ((!DRY_RUN)); then
            cat >"$mon_lua" <<'EOF'
-- Generic monitor setup: every monitor at its preferred mode, placed automatically.
-- Run `hyprctl monitors` to see your outputs and tune this to your liking.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})
EOF
        fi
        info "monitor.lua set to auto-detect"
    fi
    return 0
}

setup_theme() {
    step "Applying GTK / cursor / icon theme"
    if ! command -v gsettings >/dev/null; then
        warn "gsettings not found, skipping"
        return 0
    fi
    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    run gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || true
    run gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' || true
    run gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || true
    run gsettings set org.gnome.desktop.interface cursor-size 12 || true
    info "done"
}

check_fonts() {
    command -v fc-list >/dev/null || return 0
    if ! fc-list | grep -qi 'Helvetica Rounded'; then
        warn "font 'Helvetica Rounded' is not installed (used by quickshell)."
        warn "it's not in the repos - drop the .otf into ~/.local/share/fonts and run 'fc-cache -f'."
    fi
}

# ─── main ─────────────────────────────────────────────────────────────────────
backup
install_deps
install_dots
setup_wallpaper
setup_hardware
setup_theme
check_fonts

step "All done!"
cat <<EOF
  ${C_GREEN}Chizu's dots are installed.${C_OFF}

  - Log out and pick ${C_BLUE}Hyprland${C_OFF} in your display manager (or run 'start-hyprland' / 'Hyprland' from a TTY).
  - Keyboard layouts are us,ru,ua (Alt+Shift to switch): ~/.config/hypr/modules/input.lua
  - Keybinds: ~/.config/hypr/modules/binds.lua  (Super+Space launcher, Alt+Q terminal)
  - Music widgets need mpd:  systemctl --user enable --now mpd
EOF
[[ -d "$BACKUP_DIR" ]] && echo "  - Your old configs are in: $BACKUP_DIR"
exit 0
