fx_version 'cerulean'
game 'gta5'

author 'Al Dev'
description 'ALTAX - Advanced Tax System'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'locales/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua', 
    'server/commands.lua',
    'server/taxaudit.lua',
    'server/taxamnesty.lua',
    'server/vehicles.lua'
}

client_scripts {
    'client/main.lua',
    'client/notifications.lua'
}

dependencies {
    'es_extended',
    'oxmysql'
}

lua54 'yes'