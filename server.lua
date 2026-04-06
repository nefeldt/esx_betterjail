local ESX = exports['es_extended']:getSharedObject()

-- ─── Auto-create jail_logs table ────────────────────────────────────────────

MySQL.ready(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `jail_logs` (
            `id`                  INT AUTO_INCREMENT PRIMARY KEY,
            `action`              VARCHAR(20)  NOT NULL,
            `officer_name`        VARCHAR(255) DEFAULT NULL,
            `officer_identifier`  VARCHAR(255) DEFAULT NULL,
            `prisoner_name`       VARCHAR(255) NOT NULL,
            `prisoner_identifier` VARCHAR(255) NOT NULL,
            `duration`            INT          DEFAULT 0,
            `reason`              VARCHAR(500) DEFAULT NULL,
            `created_at`          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_prisoner (`prisoner_identifier`),
            INDEX idx_created  (`created_at`)
        )
    ]], {})
end)

-- ─── DB helpers ──────────────────────────────────────────────────────────────

local function setJailTime(identifier, time)
    MySQL.Async.execute('UPDATE users SET jail_time = @time WHERE identifier = @identifier', {
        ['@time'] = time,
        ['@identifier'] = identifier
    })
end

local function getJailTime(identifier, cb)
    MySQL.Async.fetchScalar('SELECT jail_time FROM users WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(jailTime)
        cb(jailTime or 0)
    end)
end

-- ─── Log helper ──────────────────────────────────────────────────────────────

local function writeJailLog(action, officerName, officerIdentifier, prisonerName, prisonerIdentifier, duration, reason)
    MySQL.Async.execute(
        'INSERT INTO jail_logs (action, officer_name, officer_identifier, prisoner_name, prisoner_identifier, duration, reason) VALUES (@action, @officerName, @officerIdentifier, @prisonerName, @prisonerIdentifier, @duration, @reason)',
        {
            ['@action']              = action,
            ['@officerName']         = officerName or nil,
            ['@officerIdentifier']   = officerIdentifier or nil,
            ['@prisonerName']        = prisonerName,
            ['@prisonerIdentifier']  = prisonerIdentifier,
            ['@duration']            = duration or 0,
            ['@reason']              = (reason and reason ~= '') and reason or nil,
        }
    )
end

ESX.RegisterServerCallback('esx_jail:getNearbyPlayers', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then
        print('[esx_jail] ERROR: xPlayer is nil for source ' .. source)
        cb({})
        return
    end
    
    if not xPlayer.job then
        print('[esx_jail] ERROR: xPlayer.job is nil for ' .. xPlayer.getName())
        cb({})
        return
    end
    
    print('[esx_jail] Player ' .. xPlayer.getName() .. ' job: ' .. xPlayer.job.name)
    
    if not Config.jobsThatCanJail[xPlayer.job.name] then
        print('[esx_jail] Player ' .. xPlayer.getName() .. ' does not have permission (job: ' .. xPlayer.job.name .. ')')
        xPlayer.showNotification(T('no_permission_plain'))
        cb({})
        return
    end

    local srcCoords = GetEntityCoords(GetPlayerPed(source))
    local nearby    = {}

    for _, playerId in ipairs(GetPlayers()) do
        local dist = #(srcCoords - GetEntityCoords(GetPlayerPed(playerId)))
        if dist < 5.0 then
            local t = ESX.GetPlayerFromId(playerId)
            if t then
                table.insert(nearby, { id = tonumber(playerId), xp = t })
            end
        end
    end

    if #nearby == 0 then 
        print('[esx_jail] No nearby players found')
        cb({}) 
        return 
    end

    local results = {}
    local checked = 0
    local total   = #nearby

    for i = 1, total do
        local entry = nearby[i]
        getJailTime(entry.xp.identifier, function(jailTime)
            table.insert(results, {
                name     = entry.xp.getName(),
                serverId = entry.id,
                jailTime = tonumber(jailTime) or 0,
            })
            checked = checked + 1
            if checked >= total then 
                print('[esx_jail] Returning ' .. #results .. ' nearby players')
                cb(results) 
            end
        end)
    end
end)

RegisterNetEvent('esx_jail:jailPlayer', function(targetId, jailTime, reason)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not (xPlayer and xPlayer.job and Config.jobsThatCanJail[xPlayer.job.name]) then
        print(('esx_jail: %s tried to jail without permission!'):format(source))
        return
    end
    local target = ESX.GetPlayerFromId(targetId)
    if not target then xPlayer.showNotification(T('player_not_found')) return end

    getJailTime(target.identifier, function(existing)
        if (tonumber(existing) or 0) > 0 then
            xPlayer.showNotification(T('player_already_jailed'))
            return
        end
        setJailTime(target.identifier, jailTime)
        TriggerClientEvent('esx_jail:goToJail', targetId, jailTime)
        xPlayer.showNotification(T('player_jailed'))
        local reasonText = (reason and reason ~= '') and (' · ' .. reason) or ''
        for _, playerId in ipairs(GetPlayers()) do
            local police = ESX.GetPlayerFromId(playerId)
            if police and police.job and Config.jobsThatCanJail[police.job.name] then
                TriggerClientEvent('esx:showNotification', playerId,
                    T('broadcast_jailed', target.getName(), jailTime, reasonText))
            end
        end
        writeJailLog('jailed', xPlayer.getName(), xPlayer.identifier,
            target.getName(), target.identifier, jailTime, reason)
        print(('[JAIL] %s jailed %s for %d minutes. Reason: %s'):format(
            xPlayer.getName(), target.getName(), jailTime, reason or 'none'))
    end)
end)

-- Add time to an already-jailed player's sentence
RegisterNetEvent('esx_jail:addJailTime')
AddEventHandler('esx_jail:addJailTime', function(targetId, addMinutes, reason)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not (xPlayer and xPlayer.job and Config.jobsThatCanJail[xPlayer.job.name]) then return end

    local target = ESX.GetPlayerFromId(targetId)
    if not target then xPlayer.showNotification(T('player_not_found')) return end

    getJailTime(target.identifier, function(existing)
        existing = tonumber(existing) or 0
        if existing <= 0 then
            xPlayer.showNotification(T('player_not_jailed'))
            return
        end
        local newTime = math.min(existing + addMinutes, Config.jailtimeMax)
        setJailTime(target.identifier, newTime)
        TriggerClientEvent('esx_jail:updateJailTime', targetId, newTime)
        xPlayer.showNotification(T('added_time', addMinutes, newTime))
        for _, playerId in ipairs(GetPlayers()) do
            local police = ESX.GetPlayerFromId(playerId)
            if police and police.job and Config.jobsThatCanJail[police.job.name] then
                TriggerClientEvent('esx:showNotification', playerId,
                    T('broadcast_extended', target.getName(), addMinutes, newTime))
            end
        end
        writeJailLog('extended', xPlayer.getName(), xPlayer.identifier,
            target.getName(), target.identifier, addMinutes, reason)
        print(('[JAIL] %s added %dm to %s (total: %dm)'):format(
            xPlayer.getName(), addMinutes, target.getName(), newTime))
    end)
end)

CreateThread(function()
    while true do
        Wait(60000)
        for _, playerId in ipairs(GetPlayers()) do
            local xPlayer = ESX.GetPlayerFromId(playerId)
            if xPlayer then
                getJailTime(xPlayer.identifier, function(jailTime)
                    if jailTime and jailTime > 0 then
                        local newTime = jailTime - 1
                        if newTime < 0 then newTime = 0 end
                        setJailTime(xPlayer.identifier, newTime)
                        if newTime == 0 then
                            TriggerClientEvent('esx_jail:release', playerId)
                        end
                    end
                end)
            end
        end
    end
end)


AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    getJailTime(xPlayer.identifier, function(jailTime)
        if jailTime and jailTime > 0 then
            TriggerClientEvent('esx_jail:goToJail', playerId, jailTime)
        end
    end)
end)

-- Called by client after the player has fully respawned following death
RegisterNetEvent('esx_jail:checkAndRejail')
AddEventHandler('esx_jail:checkAndRejail', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then
        getJailTime(xPlayer.identifier, function(jailTime)
            if jailTime and jailTime > 0 then
                TriggerClientEvent('esx_jail:goToJail', src, jailTime)
            end
        end)
    end
end)

-- Called when the client-side countdown reaches zero
RegisterNetEvent('esx_jail:releaseMe')
AddEventHandler('esx_jail:releaseMe', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then
        print('[esx_jail] Player ' .. xPlayer.getName() .. ' time expired, releasing...')
        writeJailLog('expired', nil, nil, xPlayer.getName(), xPlayer.identifier, 0, nil)
        setJailTime(xPlayer.identifier, 0)
        TriggerClientEvent('esx_jail:release', src)
        print('[esx_jail] Release event sent to client')
    else
        print('[esx_jail] ERROR: xPlayer not found in releaseMe')
    end
end)

-- Called from the client release handler as cleanup (kept for safety)
RegisterNetEvent('esx_jail:resetJailTime')
AddEventHandler('esx_jail:resetJailTime', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        setJailTime(xPlayer.identifier, 0)
    end
end)

RegisterNetEvent('esx_jail:removeJailTime')
AddEventHandler('esx_jail:removeJailTime', function(identifier)
    if identifier then
        setJailTime(identifier, 0)
    end
end)

ESX.RegisterServerCallback('esx_jail:getJailedPlayers', function(source, cb)
    local allPlayers = GetPlayers()
    local total      = #allPlayers
    local players    = {}
    local checked    = 0

    if total == 0 then
        cb(players)
        return
    end

    for _, playerId in ipairs(allPlayers) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer then
            MySQL.Async.fetchScalar('SELECT jail_time FROM users WHERE identifier = @identifier', {
                ['@identifier'] = xPlayer.identifier
            }, function(jailTime)
                if jailTime and tonumber(jailTime) > 0 then
                    table.insert(players, {
                        name = xPlayer.getName(),
                        serverId = tonumber(playerId),
                        jailTime = tonumber(jailTime)
                    })
                end
                checked = checked + 1
                if checked >= total then
                    cb(players)
                end
            end)
        else
            checked = checked + 1
            if checked >= total then
                cb(players)
            end
        end
    end
end)

RegisterNetEvent('esx_jail:releasePlayer')
AddEventHandler('esx_jail:releasePlayer', function(targetId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.job and Config.jobsThatCanJail[xPlayer.job.name] then
        local target = ESX.GetPlayerFromId(targetId)
        if target then
            MySQL.Async.execute('UPDATE users SET jail_time = 0 WHERE identifier = @identifier', {
                ['@identifier'] = target.identifier
            })
            writeJailLog('released', xPlayer.getName(), xPlayer.identifier,
                target.getName(), target.identifier, 0, nil)
            TriggerClientEvent('esx_jail:release', targetId)
            xPlayer.showNotification(T('prisoner_released'))
            for _, playerId in ipairs(GetPlayers()) do
                local police = ESX.GetPlayerFromId(playerId)
                if police and police.job and Config.jobsThatCanJail[police.job.name] then
                    TriggerClientEvent('esx:showNotification', playerId, T('broadcast_released', target.getName()))
                end
            end
        else
            xPlayer.showNotification(T('player_not_found'))
        end
    end
end)

-- ─── Prisoner Services ──────────────────────────────────────────────────────

local foodRationCooldowns = {}  -- [identifier] = os.time() of last collection

-- Returns all info the prisoner menu needs in one round-trip
ESX.RegisterServerCallback('esx_jail:getPrisonerInfo', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb(nil) return end

    getJailTime(xPlayer.identifier, function(jailTime)
        jailTime = tonumber(jailTime) or 0
        local bailCost = math.floor(jailTime * Config.bail.costPerMinute)
        
        -- Check both money and bank account
        local cashMoney = xPlayer.getAccount('money').money
        local bankMoney = xPlayer.getAccount('bank').money
        local totalMoney = cashMoney + bankMoney
        
        print('[esx_jail] Player money - Cash: $' .. cashMoney .. ', Bank: $' .. bankMoney .. ', Total: $' .. totalMoney)

        local now             = os.time()
        local last            = foodRationCooldowns[xPlayer.identifier] or 0
        local cooldownSecs    = Config.foodRation.intervalMinutes * 60
        local foodCooldownSec = math.max(0, (last + cooldownSecs) - now)

        cb({
            jailTime         = jailTime,
            bailCost         = bailCost,
            money            = totalMoney,  -- Send total money (cash + bank)
            cashMoney        = cashMoney,   -- Also send individual amounts
            bankMoney        = bankMoney,
            bailEnabled      = Config.bail.enabled,
            foodEnabled      = Config.foodRation.enabled,
            foodAvailable    = foodCooldownSec == 0,
            foodCooldownSecs = foodCooldownSec,
        })
    end)
end)

-- Pay bail to get out early
RegisterNetEvent('esx_jail:payBail')
AddEventHandler('esx_jail:payBail', function()
    local src     = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    getJailTime(xPlayer.identifier, function(jailTime)
        jailTime = tonumber(jailTime) or 0
        if jailTime <= 0 then return end

        local bailCost = math.floor(jailTime * Config.bail.costPerMinute)
        local cashMoney = xPlayer.getAccount('money').money
        local bankMoney = xPlayer.getAccount('bank').money
        
        print('[esx_jail] Bail payment - Cost: $' .. bailCost .. ', Cash: $' .. cashMoney .. ', Bank: $' .. bankMoney)

        -- Try to take from cash first, then bank
        if cashMoney >= bailCost then
            xPlayer.removeAccountMoney('money', bailCost)
            print('[esx_jail] Paid bail from cash')
        elseif bankMoney >= bailCost then
            xPlayer.removeAccountMoney('bank', bailCost)
            print('[esx_jail] Paid bail from bank')
        elseif (cashMoney + bankMoney) >= bailCost then
            -- Take from both accounts
            xPlayer.removeAccountMoney('money', cashMoney)
            xPlayer.removeAccountMoney('bank', bailCost - cashMoney)
            print('[esx_jail] Paid bail from cash + bank')
        else
            TriggerClientEvent('esx_jail:prisonerNotification', src, T('bail_not_enough', bailCost, cashMoney + bankMoney))
            print('[esx_jail] Not enough money for bail')
            return
        end

        writeJailLog('bail', nil, nil, xPlayer.getName(), xPlayer.identifier, jailTime, nil)
        setJailTime(xPlayer.identifier, 0)
        TriggerClientEvent('esx_jail:release', src)
        local bailFormatted = tostring(bailCost):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
        TriggerClientEvent('esx_jail:prisonerNotification', src, T('bail_paid', bailFormatted))
        print(('[JAIL] %s paid bail of $%d for %d minutes'):format(xPlayer.getName(), bailCost, jailTime))
    end)
end)

-- Collect food ration
RegisterNetEvent('esx_jail:collectFoodRation')
AddEventHandler('esx_jail:collectFoodRation', function()
    local src     = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local now          = os.time()
    local last         = foodRationCooldowns[xPlayer.identifier] or 0
    local cooldownSecs = Config.foodRation.intervalMinutes * 60

    if (now - last) >= cooldownSecs then
        foodRationCooldowns[xPlayer.identifier] = now
        TriggerClientEvent('esx_jail:receiveFoodRation', src, {
            food  = Config.foodRation.foodAmount,
            water = Config.foodRation.waterAmount,
        })
    else
        local remaining = math.ceil(((last + cooldownSecs) - now) / 60)
        TriggerClientEvent('esx_jail:prisonerNotification', src, T('food_cooldown', remaining))
    end
end)

-- Returns the calling player's own jail time (used on resource restart to restore HUD)
ESX.RegisterServerCallback('esx_jail:getMyJailTime', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        getJailTime(xPlayer.identifier, function(jailTime)
            cb(tonumber(jailTime) or 0)
        end)
    else
        cb(0)
    end
end)

ESX.RegisterServerCallback('esx_jail:getPlayerJob', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.job then
        cb(xPlayer.job.name)
    else
        cb(nil)
    end
end)

-- ─── Jail Log ────────────────────────────────────────────────────────────────

ESX.RegisterServerCallback('esx_jail:getJailLog', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not Config.jobsThatCanJail[xPlayer.job.name] then
        cb({})
        return
    end
    MySQL.Async.fetchAll(
        'SELECT id, action, officer_name, prisoner_name, duration, reason, created_at FROM jail_logs ORDER BY created_at DESC LIMIT 100',
        {},
        function(rows)
            cb(rows or {})
        end
    )
end)
