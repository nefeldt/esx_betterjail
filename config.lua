Config = {
    locale            = 'en', -- Language: 'en', 'de', 'ru'

    jailtimeDefault   = 300,
    jailtimeMax       = 360,
    jailtimeMin       = 1,

    jailMenuPoint     = { x = 1690.0, y = 2592.0, z = 45.67 },
    spawnPoint        = { x = 1691.1, y = 2564.86, z = 47.37 },
    releasePoint      = { x = 1852.0, y = 2585.0, z = 45.6 },

    jobsThatCanJail   = {
        ['police'] = true,
        ['fbi']    = true,
        ['army']   = true,
    },

    -- Zone used to decide whether to teleport the player on release
    jailZoneCenter    = { x = 1691.1, y = 2564.86, z = 47.37 },
    jailZoneRadius    = 250.0,

    -- Prisoner services menu point (inside jail)
    prisonerMenuPoint = { x = 1691.67, y = 2565.49, z = 45.55 },

    -- Bail: cost = remaining minutes * costPerMinute
    bail              = {
        enabled       = true,
        costPerMinute = 500, -- $ per remaining minute
    },

    -- Food ration: prisoners can collect food/water every intervalMinutes
    foodRation        = {
        enabled         = true,
        intervalMinutes = 120,    -- 2 hours between rations
        foodAmount      = 200000, -- passed to esx_status:add 'food'
        waterAmount     = 150000, -- passed to esx_status:add 'water'
    },

    -- Prisoner outfit (for skinchanger)
    prisonerOutfit    = {
        male = {
            ['tshirt_1'] = 15,
            ['tshirt_2'] = 0,
            ['torso_1'] = 146,
            ['torso_2'] = 0,                       -- Orange prison jumpsuit
            ['arms'] = 0,
            ['pants_1'] = 3,
            ['pants_2'] = 7,                       -- Orange pants
            ['shoes_1'] = 12,
            ['shoes_2'] = 12,                      -- White sneakers
        },
        female = {
            ['tshirt_1'] = 14,
            ['tshirt_2'] = 0,
            ['torso_1'] = 142,
            ['torso_2'] = 0,                      -- Orange prison jumpsuit
            ['arms'] = 5,
            ['pants_1'] = 34,
            ['pants_2'] = 0,                      -- Orange pants
            ['shoes_1'] = 35,
            ['shoes_2'] = 0,                      -- White sneakers
        },
    },
}
