-- Mini Browser — Package metadata
return {
    name = "minibrowser",
    title = "Mini Browser",
    desc = "Lightweight HTML/CSS/JS browser for CCOS. Runnable from diskette.",
    icon = "minibrowser",
    version = "1.1",
    files = {
        ["startup.lua"] = "startup",
        ["program.lua"] = "program",
    },
    install = {
        target = "/ccos/programs/minibrowser/program.lua",
        source = "program.lua",
    },
}
