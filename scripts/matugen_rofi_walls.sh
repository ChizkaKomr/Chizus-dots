#!/usr/bin/bash

WALLS="$HOME/Pictures/wallpapers/W39/"

IMAGE_PICKER_CONFIG="$HOME/.config/rofi/wallpaperpicker.rasi"                                # razi config
WALLPAPER_FILES=$(find "$WALLS" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \)) # add other like gif ...
CURRENT_WALLPAPER_FILE=$(basename "$(awww query | awk '{print $NF}')")
ROFI_MENU=""

while IFS= read -r WALLPAPER_PATH; do
  WALLPAPER_NAME=$(basename "$WALLPAPER_PATH")
  if [[ "$WALLPAPER_NAME" == "$CURRENT_WALLPAPER_FILE" ]]; then
    ROFI_MENU+="${WALLPAPER_NAME} (current)\0icon\x1f${WALLPAPER_PATH}\n"
  else
    ROFI_MENU+="${WALLPAPER_NAME}\0icon\x1f${WALLPAPER_PATH}\n"
  fi
done <<<"$WALLPAPER_FILES"

SELECTED_WALLPAPER=$(echo -e "$ROFI_MENU" | rofi -dmenu \
  -p "Select Wallpaper:" \
  -theme "$IMAGE_PICKER_CONFIG" \
  -markup-rows)

SELECTED_WALLPAPER_NAME=$(echo "$SELECTED_WALLPAPER" | sed 's/ (current)//')

if [[ -n "$SELECTED_WALLPAPER_NAME" ]]; then
  awww img "$WALLS/$SELECTED_WALLPAPER_NAME"  --transition-type wipe --transition-duration 0.95  --transition-fps 144 --transition-angle 45
  matugen image "$WALLS/$SELECTED_WALLPAPER_NAME" --source-color-index 0

  FULL_PATH="$WALLS/$SELECTED_WALLPAPER_NAME"
  ln -sf "$FULL_PATH" "$HOME/.config/hypr/current_wallpaper"

  killall -9 waybar
  waybar &
  killall -9 swaync
  swaync &
fi
