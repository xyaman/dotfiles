return {
    "xyaman/dired.nvim",
    branch = "feature/override-cwd-opt",
    dependencies = "MunifTanjim/nui.nvim",
    opts = {
        path_separator = "/",
        show_banner = false,
        show_icons = false,
        show_hidden = true,
        show_dot_dirs = true,
        override_cwd = false,
    },
}
