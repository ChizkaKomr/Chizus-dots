local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})


hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.window_rule({
    name  = "telegram-media-viewer",
    match = { title = "^(Media viewer)$" },
    float = true,
})


hl.window_rule({
    name  = "Steam galery float",
    match = { title = "^(Recordings & Screenshots)$" },
    float = true,
})

hl.window_rule({
    name  = "zen-picture in picture",
    match = { title = "^(Picture-in-Picture)$" },
    float = true,
})



hl.layer_rule({ match = { namespace = "waybar" }, blur = true, xray = true })
hl.layer_rule({ match = { namespace = "rofi" }, blur = true, xray = false })

hl.window_rule({
    name  = "bitward",
    match = { title = "^(Extension: (Bitwarden Password Manager) - Bitwarden — Zen Browser)$" },
    float = true,
})





