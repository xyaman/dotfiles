---@type vim.lsp.Config
return {
    cmd = { "sourcekit-lsp" },
    filetypes = { "swift", "objc", "objcpp", "c", "cpp" },
    root_markers = {
        "buildServer.json",
        "*.xcodeproj",
        "*.xcworkspace",
        "compile_commands.json",
        "Package.swift",
    },
    settings = {
        serverArguments = { "--log-level", "debug" },
        trace = { server = "messages" },
    },
    capabilities = {
        textDocument = {
            diagnostic = {
                dynamicRegistration = true,
                relatedDocumentSupport = true,
            },
        },
    },
    get_language_id = function(_, ftype)
        local t = { objc = "objective-c", objcpp = "objective-cpp" }
        return t[ftype] or ftype
    end,
}
