fx_version 'cerulean'
game 'gta5'

description 'esx_betterjail'
author 'Noah'

lua54 'yes'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_scripts {
    '@es_extended/imports.lua',
    '@es_extended/locale.lua',
    'config.lua',
    'locales/en.lua',
    'locales/de.lua',
    'locales/ru.lua',
    'locales/locale.lua',
}

client_scripts {
    'client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'es_extended'
}
