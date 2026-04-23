local TMGCore = exports['tmg-core']:GetCoreObject()
local Zone = nil
local TextShown = false
local AcitveZone = {}
local CurrentVehicle = {}
local SpawnZone = {}
local EntityZones = {}
local occasionVehicles = {}



local function spawnOccasionsVehicles(vehicles)
    if not Zone or not vehicles then return end
    
    local oSlot = Config.Zones[Zone].VehicleSpots
    if not occasionVehicles[Zone] then occasionVehicles[Zone] = {} end
    CreateThread(function()
        for i = 1, #vehicles do
            local vehData = vehicles[i]
            local model = joaat(vehData.model) 

            RequestModel(model)
            local timeout = 0
            while not HasModelLoaded(model) and timeout < 100 do 
                Wait(10) 
                timeout = timeout + 1 
            end

            if HasModelLoaded(model) then
                local spawnPoint = oSlot[i]
                local veh = CreateVehicle(model, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false)
                
                occasionVehicles[Zone][i] = {
                    car   = veh,
                    loc   = vector3(spawnPoint.x, spawnPoint.y, spawnPoint.z),
                    price = vehData.price,
                    owner = vehData.seller,
                    model = vehData.model,
                    plate = vehData.plate,
                    oid   = vehData.occasionid,
                    desc  = vehData.description,
                    mods  = vehData.mods
                }

                SetModelAsNoLongerNeeded(model)
                SetVehicleOnGroundProperly(veh)
                SetEntityInvincible(veh, true)
                SetEntityHeading(veh, spawnPoint.w)
                SetVehicleDoorsLocked(veh, 3) 
                SetVehicleNumberPlateText(veh, vehData.occasionid)
                FreezeEntityPosition(veh, true)

                TMGCore.Functions.SetVehicleProperties(veh, json.decode(vehData.mods))

                if Config.UseTarget then
                    if not EntityZones then EntityZones = {} end
                    EntityZones[i] = exports['tmg-target']:AddTargetEntity(veh, {
                        options = {
                            {
                                type = 'client',
                                event = 'tmg-vehiclesales:client:OpenContract',
                                icon = 'fas fa-car',
                                label = Lang:t('menu.view_contract'),
                                Contract = i
                            }
                        },
                        distance = 2.0
                    })
                end
                
                Wait(50) 
            else
                print("^1[TMG VehicleSales] Error: Model " .. vehData.model .. " failed to load.^7")
            end
        end
    end)
end

local function despawnOccasionsVehicles()
    if not Zone or not occasionVehicles[Zone] then return end

    local lotVehicles = occasionVehicles[Zone]
    
    for i, data in pairs(lotVehicles) do
        if data.car and DoesEntityExist(data.car) then
            TMGCore.Functions.DeleteVehicle(data.car)
        end

        if EntityZones[i] and Config.UseTarget then
            exports['tmg-target']:RemoveTargetEntity(data.car, nil) 
            EntityZones[i] = nil 
        end
    end

    occasionVehicles[Zone] = {}
    EntityZones = {} 
end

local function openSellContract(bool)
    if not Zone or not Config.Zones[Zone] then 
        return TMGCore.Functions.Notify("Error: You are not in a valid sales zone", "error") 
    end

    local pData = TMGCore.Functions.GetPlayerData()
    if not pData or not pData.charinfo then 
        return TMGCore.Functions.Notify("Error: Character data not synced", "error") 
    end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsUsing(ped) end 
    
    if veh == 0 or not DoesEntityExist(veh) then
        return TMGCore.Functions.Notify("Error: No vehicle detected", "error")
    end

    local plate = TMGCore.Functions.GetPlate(veh)

    SetNuiFocus(bool, bool)
    SendNUIMessage({
        action = 'sellVehicle',
        showTakeBackOption = false,
        bizName = Config.Zones[Zone].BusinessName or "Used Car Lot",
        sellerData = {
            firstname = pData.charinfo.firstname or "Unknown",
            lastname = pData.charinfo.lastname or "Seller",
            account = pData.charinfo.account or "0000",
            phone = pData.charinfo.phone or "None"
        },
        plate = plate
    })
end
local function openBuyContract(sellerData, vehicleData)
    if not Zone or not Config.Zones[Zone] then 
        return TMGCore.Functions.Notify("Error: Sales zone lost. Try again.", "error") 
    end

    local pData = TMGCore.Functions.GetPlayerData()
    if not pData or not pData.charinfo or not sellerData or not sellerData.charinfo then
        return TMGCore.Functions.Notify("Error: Seller data is corrupted or missing.", "error")
    end

    local isOwner = false
    if sellerData.charinfo.firstname and pData.charinfo.firstname then
        isOwner = (sellerData.charinfo.firstname == pData.charinfo.firstname and 
                   sellerData.charinfo.lastname == pData.charinfo.lastname)
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'buyVehicle',
        showTakeBackOption = isOwner,
        bizName = Config.Zones[Zone].BusinessName or "Used Car Lot",
        sellerData = {
            firstname = sellerData.charinfo.firstname or "Unknown",
            lastname = sellerData.charinfo.lastname or "Seller",
            account = sellerData.charinfo.account or "N/A",
            phone = sellerData.charinfo.phone or "N/A"
        },
        vehicleData = {
            desc = vehicleData.desc or "No description provided.",
            price = vehicleData.price or 0
        },
        plate = vehicleData.plate or "PROTOTYPE"
    })
end

local function sellVehicleWait(price)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh == 0 or not DoesEntityExist(veh) then
        return TMGCore.Functions.Notify("Error: Vehicle lost before sale", "error")
    end

    if not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
        local timeout = 0
        while not NetworkHasControlOfEntity(veh) and timeout < 50 do
            Wait(10)
            timeout = timeout + 1
        end
    end

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(10) end 

    if DoesEntityExist(veh) then
        TMGCore.Functions.DeleteVehicle(veh)
    end

    Wait(500) 
    
    DoScreenFadeIn(250)
    
    TMGCore.Functions.Notify(Lang:t('success.car_up_for_sale', { value = price }), 'success')
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
end


local function SellData(data, plate)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsUsing(ped)
    
    if veh == 0 or not DoesEntityExist(veh) then
        return TMGCore.Functions.Notify("Error: Vehicle not found. Stay in the driver seat.", "error")
    end

    local capturedMods = TMGCore.Functions.GetVehicleProperties(veh)
    local vehicleHash = GetEntityModel(veh)

    TMGCore.Functions.TriggerCallback('tmg-vehiclesales:server:CheckModelName', function(DataReturning)
        if not DataReturning then 
            return TMGCore.Functions.Notify("Error: Could not verify vehicle model.", "error")
        end

        local vehicleData = {
            ent = veh,
            model = DataReturning, 
            plate = plate,
            mods = capturedMods,   
            desc = data.desc or ""
        }

        TriggerServerEvent('tmg-occasions:server:sellVehicle', data.price, vehicleData)
        
        sellVehicleWait(data.price)
    end, vehicleHash) 
end

local listen = false
local function Listen4Control(spot)
    if listen then return end 
    
    listen = true
    CreateThread(function()
        local ped = PlayerPedId()
        
        while listen do
            Wait(5) 

            if IsControlJustReleased(0, 38) then 
                if spot then
                    TriggerEvent('tmg-vehiclesales:client:OpenContract', { Contract = spot })
                else
                    if IsPedInAnyVehicle(ped, false) then
                        listen = false 
                        TriggerEvent('tmg-occasions:client:MainMenu')
                    else
                        TMGCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
                    end
                end
            end

            if not Zone then
                listen = false
                break
            end
        end
    end)
end



local isProcessingZone = false 

local function CreateZones()
    for k, v in pairs(Config.Zones) do
        local SellSpot = PolyZone:Create(v.PolyZone, {
            name = k,
            minZ = v.MinZ,
            maxZ = v.MaxZ,
            debugPoly = false
        })

        SellSpot:onPlayerInOut(function(isPointInside)
            if isProcessingZone then return end
            
            if isPointInside then
                if Zone ~= k then
                    isProcessingZone = true
                    Zone = k
                    
                    TMGCore.Functions.TriggerCallback('tmg-occasions:server:getVehicles', function(vehicles)
                        despawnOccasionsVehicles()
                        spawnOccasionsVehicles(vehicles)
                        isProcessingZone = false 
                    end)
                end
            else
                if Zone == k then
                    isProcessingZone = true
                    despawnOccasionsVehicles()
                    Zone = nil
                    isProcessingZone = false
                end
            end
        end)
        AcitveZone[k] = SellSpot
    end
end

local function DeleteZones()
    for k, zone in pairs(AcitveZone) do
        if zone then zone:destroy() end
    end
    AcitveZone = {}
end

local function IsCarSpawned(CarId)
    if not Zone or not occasionVehicles[Zone] then return false end
    return occasionVehicles[Zone][CarId] ~= nil
end



RegisterNUICallback('sellVehicle', function(data, cb)
    local plate = TMGCore.Functions.GetPlate(GetVehiclePedIsUsing(PlayerPedId())) 
    SellData(data, plate)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(_, cb)
    TriggerServerEvent('tmg-occasions:server:buyVehicle', CurrentVehicle)
    cb('ok')
end)

RegisterNUICallback('takeVehicleBack', function(_, cb)
    TriggerServerEvent('tmg-occasions:server:ReturnVehicle', CurrentVehicle)
    cb('ok')
end)



RegisterNetEvent('tmg-occasions:client:BuyFinished', function(vehdata)
    if not vehdata or not vehdata.model then return end
    
    local vehmods = json.decode(vehdata.mods)
    local ped = PlayerPedId()

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(10) end

    TMGCore.Functions.TriggerCallback('TMGCore:Server:SpawnVehicle', function(netId)
        if netId == 0 then 
            DoScreenFadeIn(250)
            return TMGCore.Functions.Notify("Error: Could not spawn vehicle. Contact staff.", "error") 
        end

        local timeout = 0
        local veh = NetToVeh(netId)
        while not DoesEntityExist(veh) and timeout < 100 do
            Wait(10)
            veh = NetToVeh(netId)
            timeout = timeout + 1
        end

        if DoesEntityExist(veh) then
            SetVehicleNumberPlateText(veh, vehdata.plate)
            SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
            
            TMGCore.Functions.SetVehicleProperties(veh, vehmods)
            
            SetVehicleFuelLevel(veh, 100.0)
            SetVehicleEngineOn(veh, true, true)
            
            TaskWarpPedIntoVehicle(ped, veh, -1)
            
            TriggerEvent('vehiclekeys:client:SetOwner', vehdata.plate)
            
            TMGCore.Functions.Notify(Lang:t('success.vehicle_bought'), 'success', 2500)
        end
        
        Wait(500)
        DoScreenFadeIn(250)
    end, vehdata.model, Config.Zones[Zone].BuyVehicle, true)

    CurrentVehicle = {}
end)

RegisterNetEvent('tmg-occasions:client:SellBackCar', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh == 0 or not DoesEntityExist(veh) then
        return TMGCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
    end

    local plate = TMGCore.Functions.GetPlate(veh)
    local model = GetEntityModel(veh)

    if not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
    end

    TMGCore.Functions.TriggerCallback('tmg-occasions:server:checkVehicleOwner', function(owned, balance)
        if not DoesEntityExist(veh) then 
            return TMGCore.Functions.Notify("Error: Vehicle lost during transaction.", "error")
        end

        if owned then
            if balance < 1 then
                TMGCore.Functions.DeleteVehicle(veh)
                
                TriggerServerEvent('tmg-occasions:server:sellVehicleBack', {
                    plate = plate,
                    model = model
                })
            else
                TMGCore.Functions.Notify(Lang:t('error.finish_payments'), 'error', 3500)
            end
        else
            TMGCore.Functions.Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
        end
    end, plate)
end)

RegisterNetEvent('tmg-occasions:client:ReturnOwnedVehicle', function(vehdata)
    if not vehdata or not vehdata.model then return end
    
    local vehmods = json.decode(vehdata.mods)
    local ped = PlayerPedId()

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(10) end

    TMGCore.Functions.TriggerCallback('TMGCore:Server:SpawnVehicle', function(netId)
        if not netId or netId == 0 then 
            DoScreenFadeIn(250)
            return TMGCore.Functions.Notify("Error: Mainframe failed to manifest vehicle.", "error") 
        end

        local veh = NetToVeh(netId)
        local timeout = 0
        while not DoesEntityExist(veh) and timeout < 100 do
            Wait(10)
            veh = NetToVeh(netId)
            timeout = timeout + 1
        end

        if DoesEntityExist(veh) then
            SetVehicleNumberPlateText(veh, vehdata.plate)
            SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
            
            TMGCore.Functions.SetVehicleProperties(veh, vehmods)
            
            SetVehicleFuelLevel(veh, 100.0)
            SetVehicleEngineOn(veh, true, true)
            
            TaskWarpPedIntoVehicle(ped, veh, -1)
            
            TriggerEvent('vehiclekeys:client:SetOwner', vehdata.plate)
            
            TMGCore.Functions.Notify(Lang:t('info.vehicle_returned'), 'success')
        end

        Wait(400) 
        DoScreenFadeIn(250)
    end, vehdata.model, Config.Zones[Zone].BuyVehicle, true)

    CurrentVehicle = {}
end)

local isRefreshing = false

RegisterNetEvent('tmg-occasion:client:refreshVehicles', function()
    if not Zone or isRefreshing then return end
    
    isRefreshing = true
    Wait(math.random(0, 500))

    TMGCore.Functions.TriggerCallback('tmg-occasions:server:getVehicles', function(vehicles)
        if Zone then
            despawnOccasionsVehicles()
            spawnOccasionsVehicles(vehicles)
        end
        
        SetTimeout(2000, function()
            isRefreshing = false
        end)
    end)
end)


local isCheckingSale = false

RegisterNetEvent('tmg-vehiclesales:client:SellVehicle', function()
    if isCheckingSale then return end
    
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh == 0 or not DoesEntityExist(veh) then
        return TMGCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
    end

    local plate = TMGCore.Functions.GetPlate(veh)
    isCheckingSale = true

    TMGCore.Functions.TriggerCallback('tmg-occasions:server:checkVehicleOwner', function(owned, balance)
        if not owned then
            TMGCore.Functions.Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
            isCheckingSale = false
            return
        end

        if balance > 0 then
            TMGCore.Functions.Notify(Lang:t('error.finish_payments'), 'error', 3500)
            isCheckingSale = false
            return
        end

        TMGCore.Functions.TriggerCallback('tmg-occasions:server:getVehicles', function(vehicles)
            local currentVeh = GetVehiclePedIsIn(ped, false)
            
            if currentVeh == veh and DoesEntityExist(veh) then
                local maxSpots = #Config.Zones[Zone].VehicleSpots
                if vehicles == nil or #vehicles < maxSpots then
                    openSellContract(true)
                else
                    TMGCore.Functions.Notify(Lang:t('error.no_space_on_lot'), 'error', 3500)
                end
            else
                TMGCore.Functions.Notify("Error: Transaction cancelled (Vehicle Mismatch)", "error")
            end
            
            isCheckingSale = false
        end)
    end, plate)
end)

RegisterNetEvent('tmg-vehiclesales:client:OpenContract', function(data)
    local vehicleIndex = data.Contract
    local selectedVehicle = (Zone and occasionVehicles[Zone]) and occasionVehicles[Zone][vehicleIndex] or nil

    if not selectedVehicle then
        return TMGCore.Functions.Notify(Lang:t('error.not_for_sale'), 'error', 7500)
    end

    CurrentVehicle = selectedVehicle

    TMGCore.Functions.TriggerCallback('tmg-occasions:server:getSellerInformation', function(info)
        local sanitizedInfo = {
            charinfo = {
                firstname = Lang:t('charinfo.firstname') or "Unknown",
                lastname = Lang:t('charinfo.lastname') or "Seller",
                account = Lang:t('charinfo.account') or "N/A",
                phone = Lang:t('charinfo.phone') or "N/A"
            }
        }

        if info and info.charinfo then
            local ok, decoded = pcall(json.decode, info.charinfo)
            if ok and decoded then
                sanitizedInfo.charinfo = decoded
            elseif type(info.charinfo) == "table" then
                sanitizedInfo.charinfo = info.charinfo
            end
        end

        openBuyContract(sanitizedInfo, selectedVehicle)
        
    end, selectedVehicle.owner)
end)


RegisterNetEvent('tmg-occasions:client:MainMenu', function()
    if not Zone or not Config.Zones[Zone] then 
        return TMGCore.Functions.Notify("Error: Transaction zone no longer active.", "error") 
    end

    local businessName = Config.Zones[Zone].BusinessName or "Used Car Lot"
    local MainMenu = {
        {
            isMenuHeader = true,
            header = businessName,
            icon = "fas fa-warehouse" 
        },
        {
            header = Lang:t('menu.sell_vehicle'),
            txt = Lang:t('menu.sell_vehicle_help'),
            params = {
                event = 'tmg-vehiclesales:client:SellVehicle',
            }
        },
        {
            header = Lang:t('menu.sell_back'),
            txt = Lang:t('menu.sell_back_help'),
            params = {
                event = 'tmg-occasions:client:SellBackCar',
            }
        },
        {
            header = "❌ " .. Lang:t('menu.close') or "Close",
            params = {
                event = "tmg-menu:client:closeMenu"
            }
        }
    }

    exports['tmg-menu']:closeMenu() 
    Wait(10) 
    exports['tmg-menu']:openMenu(MainMenu)
end)





local Blips = {}

CreateThread(function()
    for k, cars in pairs(Config.Zones) do
        local OccasionBlip = AddBlipForCoord(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z)
        SetBlipSprite(OccasionBlip, 326)
        SetBlipDisplay(OccasionBlip, 4)
        SetBlipScale(OccasionBlip, 0.75)
        SetBlipAsShortRange(OccasionBlip, true)
        SetBlipColour(OccasionBlip, 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Lang:t('info.used_vehicle_lot'))
        EndTextCommandSetBlipName(OccasionBlip)
        
        Blips[k] = OccasionBlip 
    end
end)

CreateThread(function()
    for k, cars in pairs(Config.Zones) do
        SpawnZone[k] = CircleZone:Create(vector3(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z), 3.0, {
            name = 'OCSell' .. k,
            debugPoly = false,
        })

        SpawnZone[k]:onPlayerInOut(function(isPointInside)
            if isPointInside then
                if IsPedInAnyVehicle(PlayerPedId(), false) then
                    exports['tmg-core']:DrawText(Lang:t('menu.interaction'), 'left')
                    TextShown = true
                    Listen4Control()
                end
            else
                listen = false
                if TextShown then
                    TextShown = false
                    exports['tmg-core']:HideText()
                end
            end
        end)

        if not Config.UseTarget then
            for k2, v in pairs(cars.VehicleSpots) do
                local zoneName = 'VehicleSpot' .. k .. k2
                local spotZone = BoxZone:Create(vector3(v.x, v.y, v.z), 4.3, 3.6, {
                    name = zoneName,
                    debugPoly = false,
                    minZ = v.z - 2,
                    maxZ = v.z + 2,
                })

                spotZone:onPlayerInOut(function(isPointInside)
                    if isPointInside and IsCarSpawned(k2) then
                        exports['tmg-core']:DrawText(Lang:t('menu.view_contract_int'), 'left')
                        TextShown = true
                        Listen4Control(k2)
                    else
                        
                        if TextShown then
                            listen = false
                            TextShown = false
                            exports['tmg-core']:HideText()
                        end
                    end
                end)
                
                EntityZones[zoneName] = spotZone 
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for _, blip in pairs(Blips) do RemoveBlip(blip) end
    end
end)





RegisterNetEvent('TMGCore:Client:OnPlayerLoaded', function()
    Wait(1000) 
    DeleteZones() 
    CreateZones()
end)

RegisterNetEvent('TMGCore:Client:OnPlayerUnload', function()
    DeleteZones()
    despawnOccasionsVehicles() 
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    DeleteZones() 
    CreateZones()
    
    if Zone then
        TMGCore.Functions.TriggerCallback('tmg-occasions:server:getVehicles', function(vehicles)
            spawnOccasionsVehicles(vehicles)
        end)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    DeleteZones()
    despawnOccasionsVehicles()
    
    if TextShown then
        exports['tmg-core']:HideText()
    end
end)
