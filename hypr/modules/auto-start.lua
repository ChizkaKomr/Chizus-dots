
hl.on("hyprland.start", function () 
  hl.exec_cmd("kitty")
  hl.exec_cmd("systemctl --user --no-block start graphical-session.target")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("systemctl --user start hyprpolkitagent")
  hl.exec_cmd("waybar & awww-daemon")
end)






