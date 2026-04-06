local ESX = nil
local PlayerLoaded = false

CreateThread(function()
    while ESX == nil do
        ESX = exports['es_extended']:getSharedObject()
        Wait(100)
    end
    
    print('[esx_jail] ESX loaded')
    
    -- Wait a bit for player data to be available
    Wait(1000)
    
    PlayerLoaded = true
    print('[esx_jail] Player loaded, markers can start')
end)

local jailMenuPoint     = Config.jailMenuPoint
local prisonerMenuPoint = Config.prisonerMenuPoint
local jailTimer         = nil
local isUIOpen          = false
local isJailed          = false
local isPrisonerUIOpen  = false
local lastSkin          = nil
local lastZoneStatus    = true  -- track zone status to avoid spam

print('[esx_jail] Client script loaded')
print('[esx_jail] Jail menu point: ' .. jailMenuPoint.x .. ', ' .. jailMenuPoint.y .. ', ' .. jailMenuPoint.z)

-- ─── Utility ───────────────────────────────────────────────────────────────

local function GetDistance(vec1, vec2)
    local dx = vec1.x - vec2.x
    local dy = vec1.y - vec2.y
    local dz = vec1.z - vec2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function IsInJailZone(coords)
    local center = vector3(Config.jailZoneCenter.x, Config.jailZoneCenter.y, Config.jailZoneCenter.z)
    return #(coords - center) < Config.jailZoneRadius
end

-- ─── Map Blip (police only) ─────────────────────────────────────────────────

CreateThread(function()
    while not PlayerLoaded do
        Wait(500)
    end
    
    local playerData = ESX.GetPlayerData()
    
    if playerData.job and Config.jobsThatCanJail[playerData.job.name] then
        local blip = AddBlipForCoord(jailMenuPoint.x, jailMenuPoint.y, jailMenuPoint.z)
        SetBlipSprite(blip, 123)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, 3)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Jail Management')
        EndTextCommandSetBlipName(blip)
    end
end)

-- ─── Marker & Interaction ───────────────────────────────────────────────────

CreateThread(function()
    print('[esx_jail] Marker thread starting...')
    
    while not PlayerLoaded do
        Wait(100)
    end
    
    print('[esx_jail] Starting marker loop')
    
    while true do
        local sleep = 500
        
        local playerPed = PlayerPedId()
        local coords    = GetEntityCoords(playerPed)
        local dist      = GetDistance(coords, vector3(jailMenuPoint.x, jailMenuPoint.y, jailMenuPoint.z))
        
        if dist < 30.0 then
            sleep = 0
            
            DrawMarker(1,
                jailMenuPoint.x, jailMenuPoint.y, jailMenuPoint.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                2.0, 2.0, 1.0,
                0, 100, 255, 100,
                false, true, 2, false, nil, nil, false
            )
            
            if dist < 2.0 and not isUIOpen then
                local playerData = ESX.GetPlayerData()
                
                if playerData and playerData.job and Config.jobsThatCanJail[playerData.job.name] then
                    ESX.ShowHelpNotification(T('press_manage_jail'))
                    
                    if IsControlJustReleased(0, 38) then
                        OpenJailUI()
                    end
                else
                    ESX.ShowHelpNotification(T('no_permission'))
                end
            end
        end
        
        Wait(sleep)
    end
end)

-- ─── Prisoner Menu Marker ───────────────────────────────────────────────────

CreateThread(function()
    while not PlayerLoaded do
        Wait(100)
    end
    
    print('[esx_jail] Prisoner marker thread started')
    
    while true do
        local sleep = 1000
        
        if isJailed then
            local playerPed = PlayerPedId()
            local coords    = GetEntityCoords(playerPed)
            local dist      = GetDistance(coords, vector3(
                prisonerMenuPoint.x, prisonerMenuPoint.y, prisonerMenuPoint.z))

            if dist < 30.0 then
                sleep = 0
                DrawMarker(1,
                    prisonerMenuPoint.x, prisonerMenuPoint.y, prisonerMenuPoint.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    2.0, 2.0, 1.0,
                    217, 119, 6, 120,
                    false, true, 2, false, nil, nil, false
                )
                if dist < 2.0 and not isPrisonerUIOpen then
                    ESX.ShowHelpNotification(T('press_prisoner_services'))
                    if IsControlJustReleased(0, 38) then
                        OpenPrisonerUI()
                    end
                end
            else
                sleep = 500
            end
        end
        
        Wait(sleep)
    end
end)

-- ─── Jail Zone Monitor ───────────────────────────────────────────────────

CreateThread(function()
    while not PlayerLoaded do
        Wait(100)
    end
    
    print('[esx_jail] Zone monitor thread started')
    
    while true do
        Wait(2000)  -- Check every 2 seconds
        
        if isJailed then
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            local dist = GetDistance(coords, vector3(
                Config.jailZoneCenter.x, 
                Config.jailZoneCenter.y, 
                Config.jailZoneCenter.z
            ))
            
            local isInside = dist <= Config.jailZoneRadius
            
            -- Only update UI if status changed
            if isInside ~= lastZoneStatus then
                lastZoneStatus = isInside
                SendNUIMessage({
                    action = 'updateZoneStatus',
                    inside = isInside
                })
                
                if not isInside then
                    print('[esx_jail] WARNING: Player outside jail zone! Distance: ' .. math.floor(dist) .. 'm')
                end
            end
        else
            -- Reset to inside when not jailed
            if not lastZoneStatus then
                lastZoneStatus = true
                SendNUIMessage({
                    action = 'updateZoneStatus',
                    inside = true
                })
            end
        end
    end
end)

function OpenPrisonerUI()
    if isPrisonerUIOpen then 
        print('[esx_jail] Prisoner UI already open')
        return 
    end
    
    print('[esx_jail] Opening prisoner UI...')
    
    -- WICHTIG: Hole IMMER frische Daten vom Server
    ESX.TriggerServerCallback('esx_jail:getPrisonerInfo', function(info)
        if not info then
            print('[esx_jail] ERROR: getPrisonerInfo returned nil')
            return
        end
        
        print('[esx_jail] Got prisoner info - Money: $' .. info.money .. ', Bail: $' .. info.bailCost)
        
        isPrisonerUIOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'openPrisonerMenu',
            info   = info,
            lang   = TUI(),
        })
        
        print('[esx_jail] Prisoner UI opened successfully')
    end)
end

-- ─── Open UI ────────────────────────────────────────────────────────────────

function OpenJailUI(startTab)
    if isUIOpen then 
        print('[esx_jail] UI already open, ignoring request')
        return 
    end
    
    print('[esx_jail] Opening jail UI...')
    
    ESX.TriggerServerCallback('esx_jail:getNearbyPlayers', function(nearbyPlayers)
        if not nearbyPlayers then
            print('[esx_jail] ERROR: getNearbyPlayers returned nil')
            return
        end
        
        print('[esx_jail] Got nearby players: ' .. #nearbyPlayers)
        
        ESX.TriggerServerCallback('esx_jail:getJailedPlayers', function(jailedPlayers)
            if not jailedPlayers then
                print('[esx_jail] ERROR: getJailedPlayers returned nil')
                return
            end
            
            print('[esx_jail] Got jailed players: ' .. #jailedPlayers)
            
            isUIOpen = true
            SetNuiFocus(true, true)
            SendNUIMessage({
                action        = 'openUI',
                tab           = startTab or 'nearby',
                nearbyPlayers = nearbyPlayers,
                prisoners     = jailedPlayers,
                config        = {
                    min     = Config.jailtimeMin,
                    max     = Config.jailtimeMax,
                    default = Config.jailtimeDefault
                },
                lang          = TUI(),
            })
            
            print('[esx_jail] UI opened successfully')
        end)
    end)
end

-- ─── NUI Callbacks ──────────────────────────────────────────────────────────

-- Close button / ESC
RegisterNUICallback('closeUI', function(_, cb)
    isUIOpen = false
    SetNuiFocus(false, false)
    cb({})
end)

-- Jail a nearby player (not already jailed)
RegisterNUICallback('jailPlayer', function(data, cb)
    TriggerServerEvent('esx_jail:jailPlayer', data.serverId, data.time, data.reason or '')
    cb({})
end)

-- Add time to an already-jailed player
RegisterNUICallback('addJailTime', function(data, cb)
    TriggerServerEvent('esx_jail:addJailTime', data.serverId, data.time, data.reason or '')
    cb({})
end)

-- Release a prisoner
RegisterNUICallback('releasePlayer', function(data, cb)
    TriggerServerEvent('esx_jail:releasePlayer', data.serverId)
    cb({})
end)

-- Refresh nearby players list inside the UI
RegisterNUICallback('getNearbyPlayers', function(_, cb)
    ESX.TriggerServerCallback('esx_jail:getNearbyPlayers', function(players)
        cb(players)
    end)
end)

-- Fetch jail log for the Log tab
RegisterNUICallback('getJailLog', function(_, cb)
    ESX.TriggerServerCallback('esx_jail:getJailLog', function(logs)
        cb(logs)
    end)
end)

-- Refresh prisoner list inside the UI
RegisterNUICallback('getJailedPlayers', function(_, cb)
    ESX.TriggerServerCallback('esx_jail:getJailedPlayers', function(players)
        cb(players)
    end)
end)

-- ─── Jailed: go to jail ─────────────────────────────────────────────────────

RegisterNetEvent('esx_jail:goToJail')
AddEventHandler('esx_jail:goToJail', function(jailTime)
    isJailed = true
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, Config.spawnPoint.x, Config.spawnPoint.y, Config.spawnPoint.z)
    ESX.ShowNotification(T('jailed_for', jailTime))

    -- Jail outfit
    TriggerEvent('skinchanger:getSkin', function(skin)
        lastSkin = skin
        local jailClothes = skin.sex == 0 
            and Config.prisonerOutfit.male 
            or Config.prisonerOutfit.female
        TriggerEvent('skinchanger:loadClothes', skin, jailClothes)
    end)

    -- Cancel any existing timer
    if jailTimer then
        jailTimer = nil
    end

    -- Show prisoner HUD and start countdown (jailTime is in minutes → convert to seconds)
    local timeInSeconds = jailTime * 60
    SendNUIMessage({ action = 'showPrisonerHUD', time = timeInSeconds, totalTime = timeInSeconds, lang = TUI() })

    -- Set initial zone status
    Wait(100)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local dist = GetDistance(playerCoords, vector3(
        Config.jailZoneCenter.x, 
        Config.jailZoneCenter.y, 
        Config.jailZoneCenter.z
    ))
    lastZoneStatus = dist <= Config.jailZoneRadius
    SendNUIMessage({
        action = 'updateZoneStatus',
        inside = lastZoneStatus
    })

    jailTimer = CreateThread(function()
        local remaining = timeInSeconds
        print('[esx_jail] Starting jail timer: ' .. remaining .. ' seconds')
        while remaining > 0 and isJailed do
            Wait(1000)
            if not isJailed then
                print('[esx_jail] Timer cancelled - player released')
                break
            end
            remaining = remaining - 1
            SendNUIMessage({ action = 'updatePrisonerTime', time = remaining })
            
            -- Debug every minute
            if remaining % 60 == 0 then
                print('[esx_jail] Time remaining: ' .. (remaining / 60) .. ' minutes')
            end
        end
        if remaining <= 0 and isJailed then
            print('[esx_jail] Timer finished! Calling release...')
            TriggerServerEvent('esx_jail:releaseMe')
        end
    end)
end)

-- ─── Released ───────────────────────────────────────────────────────────────

RegisterNetEvent('esx_jail:release')
AddEventHandler('esx_jail:release', function()
    print('[esx_jail] ========= RELEASE EVENT RECEIVED =========')
    
    -- Cancel countdown - set isJailed to false FIRST so timer thread stops
    isJailed = false
    jailTimer = nil
    
    -- Hide UI immediately
    SendNUIMessage({ action = 'hidePrisonerHUD' })
    
    -- Wait for timer thread to recognize isJailed = false
    Wait(100)
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    -- Check if player is inside jail zone
    local distToJail = GetDistance(playerCoords, vector3(
        Config.jailZoneCenter.x,
        Config.jailZoneCenter.y,
        Config.jailZoneCenter.z
    ))
    
    local isInsideJail = distToJail <= Config.jailZoneRadius
    
    -- Only teleport if player is INSIDE the jail
    if isInsideJail then
        print('[esx_jail] Player inside jail zone - teleporting to release point')
        local releasePoint = Config.releasePoint
        print('[esx_jail] Release coords: ' .. releasePoint.x .. ', ' .. releasePoint.y .. ', ' .. releasePoint.z)
        
        -- Force teleport with DoScreenFadeOut for smooth transition
        DoScreenFadeOut(500)
        Wait(500)
        
        SetEntityCoords(playerPed, releasePoint.x, releasePoint.y, releasePoint.z, false, false, false, true)
        SetEntityHeading(playerPed, 0.0)
        
        Wait(500)
        DoScreenFadeIn(500)
    else
        print('[esx_jail] Player outside jail zone (' .. math.floor(distToJail) .. 'm) - no teleport needed')
    end
    
    print('[esx_jail] Release executed')
    
    ESX.ShowNotification(T('released_from_jail'))
    
    -- Restore original skin
    if lastSkin then
        print('[esx_jail] Restoring original skin')
        TriggerEvent('skinchanger:loadSkin', lastSkin)
        lastSkin = nil
    else
        print('[esx_jail] WARNING: No lastSkin saved')
    end

    TriggerServerEvent('esx_jail:resetJailTime')
    print('[esx_jail] ========= RELEASE COMPLETE =========')
end)

-- ─── Respawn in jail after death ────────────────────────────────────────────
-- Use playerSpawned (fires after ESX fully finishes its own spawn/teleport logic)
-- so our teleport-back-to-jail always runs last and wins.

AddEventHandler('playerSpawned', function()
    Citizen.CreateThread(function()
        Wait(2000)  -- let ESX hospital/spawn logic fully complete first
        TriggerServerEvent('esx_jail:checkAndRejail')
    end)
end)

-- ─── Restore state after resource restart ───────────────────────────────────

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Citizen.CreateThread(function()
        Wait(3000)  -- wait for ESX to be ready
        ESX.TriggerServerCallback('esx_jail:getMyJailTime', function(jailTime)
            if jailTime and jailTime > 0 then
                isJailed = true
                local timeInSeconds = jailTime * 60
                SendNUIMessage({ action = 'showPrisonerHUD', time = timeInSeconds, totalTime = timeInSeconds })
                if jailTimer then
                    if jailTimer.cancel then jailTimer:cancel() end
                end
                jailTimer = Citizen.CreateThread(function()
                    local remaining = timeInSeconds
                    while remaining > 0 and isJailed do
                        Wait(1000)
                        if not isJailed then
                            print('[esx_jail] Timer cancelled - player released')
                            break
                        end
                        remaining = remaining - 1
                        SendNUIMessage({ action = 'updatePrisonerTime', time = remaining })
                    end
                    if remaining <= 0 and isJailed then
                        TriggerServerEvent('esx_jail:releaseMe')
                    end
                end)
            end
        end)
    end)
end)

-- ─── Update jailed player's sentence after time was added ───────────────────

RegisterNetEvent('esx_jail:updateJailTime')
AddEventHandler('esx_jail:updateJailTime', function(newJailTime)
    if jailTimer then
        if jailTimer.cancel then jailTimer:cancel() end
        jailTimer = nil
    end
    local newSeconds = newJailTime * 60
    SendNUIMessage({ action = 'showPrisonerHUD', time = newSeconds, totalTime = newSeconds })
    jailTimer = Citizen.CreateThread(function()
        local remaining = newSeconds
        while remaining > 0 and isJailed do
            Wait(1000)
            if not isJailed then
                print('[esx_jail] Timer cancelled - player released')
                break
            end
            remaining = remaining - 1
            SendNUIMessage({ action = 'updatePrisonerTime', time = remaining })
        end
        if remaining <= 0 and isJailed then
            TriggerServerEvent('esx_jail:releaseMe')
        end
    end)
end)

-- ─── Prisoner Menu NUI Callbacks ────────────────────────────────────────────

RegisterNUICallback('closePrisonerUI', function(_, cb)
    isPrisonerUIOpen = false
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('payBail', function(_, cb)
    TriggerServerEvent('esx_jail:payBail')
    cb({})
end)

RegisterNUICallback('collectFoodRation', function(_, cb)
    TriggerServerEvent('esx_jail:collectFoodRation')
    cb({})
end)

-- Server sends a text notification to display inside the prisoner panel
RegisterNetEvent('esx_jail:prisonerNotification')
AddEventHandler('esx_jail:prisonerNotification', function(msg)
    if isPrisonerUIOpen then
        SendNUIMessage({ action = 'prisonerNotification', message = msg })
    else
        ESX.ShowNotification(msg)
    end
end)

-- Apply food/water from ration (uses esx_status if available)
RegisterNetEvent('esx_jail:receiveFoodRation')
AddEventHandler('esx_jail:receiveFoodRation', function(ration)
    TriggerEvent('esx_status:add', 'food',  ration.food)
    TriggerEvent('esx_status:add', 'water', ration.water)
    SendNUIMessage({ action = 'prisonerNotification', message = T('food_collected') })
    SendNUIMessage({ action = 'foodRationUsed', cooldownSecs = Config.foodRation.intervalMinutes * 60 })
end)

-- ─── /jailzone admin visualizer ─────────────────────────────────────────────

local jailZoneVisible = false

RegisterCommand('jailzone', function(source, args)
    local group = ESX.GetPlayerData().group
    if group ~= 'admin' and group ~= 'superadmin' then
        ESX.ShowNotification(T('no_permission'))
        return
    end

    -- Optional: /jailzone [radius] to test a different radius visually
    local previewRadius = tonumber(args[1]) or Config.jailZoneRadius

    if jailZoneVisible then
        jailZoneVisible = false
        ESX.ShowNotification(T('jailzone_hidden'))
        return
    end

    jailZoneVisible = true
    local center = Config.jailZoneCenter

    ESX.ShowNotification(T('jailzone_visible', center.x, center.y, center.z, previewRadius))

    Citizen.CreateThread(function()
        while jailZoneVisible do
            Wait(0)

            -- Boundary circle (72 markers = one every 5°)
            for i = 0, 71 do
                local angle = (i / 72) * 2 * math.pi
                local x = center.x + previewRadius * math.cos(angle)
                local y = center.y + previewRadius * math.sin(angle)
                DrawMarker(28,
                    x, y, center.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    0.5, 0.5, 1.8,
                    255, 165, 0, 200,
                    false, false, 2, false, nil, nil, false)
            end

            -- Center marker (green)
            DrawMarker(1,
                center.x, center.y, center.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                4.0, 4.0, 1.0,
                0, 255, 0, 160,
                false, false, 2, false, nil, nil, false)

            -- Floating label above center
            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(center.x, center.y, center.z + 3.0)
            if onScreen then
                SetTextScale(0.0, 0.4)
                SetTextFont(4)
                SetTextColour(255, 200, 0, 255)
                SetTextOutline()
                SetTextEntry('STRING')
                AddTextComponentString(('Jail Zone  r=%.0fm'):format(previewRadius))
                DrawText(sx, sy)
            end
        end
    end)
end, false)

-- ─── /jaillist command ──────────────────────────────────────────────────────

RegisterCommand('jaillist', function()
    ESX.TriggerServerCallback('esx_jail:getPlayerJob', function(jobName)
        if Config.jobsThatCanJail[jobName] then
            OpenJailUI('prisoners')
        else
            ESX.ShowNotification(T('no_permission_plain'))
        end
    end)
end, false)

-- ─── /jailtp command (teleport to jail management for testing) ──────────────

RegisterCommand('jailtp', function()
    local group = ESX.GetPlayerData().group
    if group ~= 'admin' and group ~= 'superadmin' then
        ESX.ShowNotification(T('admin_only'))
        return
    end
    
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, jailMenuPoint.x, jailMenuPoint.y, jailMenuPoint.z)
    ESX.ShowNotification(T('teleported_jail'))
end, false)

-- ─── /jailmenu command (force open jail menu for testing) ───────────────────

RegisterCommand('jailmenu', function()
    local group = ESX.GetPlayerData().group
    if group ~= 'admin' and group ~= 'superadmin' then
        ESX.ShowNotification(T('admin_only'))
        return
    end
    
    local playerData = ESX.GetPlayerData()
    print('[esx_jail] Manual menu open requested')
    print('[esx_jail] Job: ' .. (playerData.job and playerData.job.name or 'NONE'))
    
    if playerData and playerData.job and Config.jobsThatCanJail[playerData.job.name] then
        OpenJailUI()
    else
        ESX.ShowNotification(T('need_police_job'))
        print('[esx_jail] Job not authorized: ' .. (playerData.job and playerData.job.name or 'NONE'))
    end
end, false)
