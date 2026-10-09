# Theme packs

Extra themes that aren't installed by default. Each folder is a pack; each
folder inside it is an ordinary theme (a `theme.conf`, see the manual's
theme chapter). `pack.conf` gives the pack's name and description. There are
no packs at the moment: the anarchism themes, a pack until 1.1.1, now come with
an4rch (in `themes/`).

    anarch theme packs            list the packs
    anarch theme get PACK         add every theme in a pack
    anarch theme get NAME         add one theme from a pack
    anarch theme drop PACK        remove a pack's themes again

A theme can describe its wallpaper gradient CSS-style, and gets gradient
wallpapers painted from it (plus the usual abstract ones):

    gradient       = #0b0b0b 0%, #2a070d 40%, #7a0a1c 70%, #c8102e 100%
    gradient_angle = 135
