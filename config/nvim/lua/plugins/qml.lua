return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      qmlls = {
        -- -E: importPaths zusaetzlich aus QML_IMPORT_PATH lesen.
        -- -d: Qt-Doku fuer Hover-Hints. Braucht das Paket qt6-doc; ohne die
        --     .qch-Dateien dort liefert qmlls grundsaetzlich leeren Hover-Text.
        cmd = { "qmlls6", "-E", "-d", "/usr/share/doc/qt6" },
        -- Quickshell legt pro Config eine .qmlls.ini an (importPaths + buildDir mit synthetisiertem qmldir).
        -- Ohne diesen Marker landet qmlls im Single-File-Modus und kennt weder Quickshell-Typen noch Singletons.
        -- Die .qmlls.ini muss als (auch leere) Datei existieren, bevor qs startet -- sonst schaltet
        -- Quickshell das Tooling gar nicht erst ein und ersetzt sie nicht durch den Symlink in den VFS.
        root_markers = { ".qmlls.ini", ".git" },
      },
    },
  },
}
