local TMGCore = exports['tmg-core']:GetCoreObject()




local function generateOID()
    local entropy = math.random(100000, 999999)

    return 'OC' .. entropy
end



TMGCore.Functions.CreateCallback('tmg-occasions:server:getVehicles', function(source, cb)
    exports['tmgnosql']:FetchAll('occasion_vehicles', {}, function(result)
        if result and #result > 0 then
            cb(result)
        else
            cb(nil)
        end
    end)
    
    print(string.format("^5[TMG]^7 Marketplace: Synchronized %d listings for Terminal %s", #result or 0, source))
end)


TMGCore.Functions.CreateCallback('tmg-occasions:server:verifyOwnership', function(source, cb, plate)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end

    local normalizedPlate = plate:gsub("%s+", ""):upper()

    local searchCriteria = { 
        ["plate"] = normalizedPlate, 
        ["citizenid"] = Player.PlayerData.citizenid 
    }

    exports['tmgnosql']:FetchOne('player_vehicles', searchCriteria, function(result)
        if result then
            cb(true, result.balance or 0)
            
            print(string.format("^5[TMG]^7 Registry: Ownership verified for Asset [%s]", normalizedPlate))
        else
            cb(false)
        end
    end)
end)


TMGCore.Functions.CreateCallback('tmg-occasions:server:getSellerInformation', function(source, cb, citizenid)
    local OnlineSeller = TMGCore.Functions.GetPlayerByCitizenId(citizenid)
    
    if OnlineSeller then
        print(string.format("^5[TMG]^7 Marketplace: Resolved Online Identity for CID [%s]", citizenid))
        return cb(OnlineSeller.PlayerData)
    end

    exports['tmgnosql']:FetchOne('players', { ["citizenid"] = citizenid }, function(result)
        if result then
            if type(result.charinfo) == "string" then
                result.charinfo = json.decode(result.charinfo)
            end
            
            cb(result)
        else
            cb(nil)
        end
    end)
end)


TMGCore.Functions.CreateCallback('tmg-vehiclesales:server:resolveModelName', function(source, cb, plate)
    if not plate then return cb(nil) end
    
    local normalizedPlate = plate:gsub("%s+", ""):upper()

    exports['tmgnosql']:FetchOne('player_vehicles', 
        { ["plate"] = normalizedPlate }, 
        function(result)
            if result and result.vehicle then
                cb(result.vehicle)
            else
                cb(nil)
            end
        end,
        { ["vehicle"] = 1 } 
    )
end)




RegisterNetEvent('tmg-occasions:server:reclaimVehicle', function(vehicleData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not vehicleData['plate'] then return end

    local plate = vehicleData['plate']:gsub("%s+", ""):upper()
    local oid = vehicleData['oid']

    exports['tmgnosql']:FetchOne('occasion_vehicles', { ["plate"] = plate, ["occasionid"] = oid }, function(listing)
        if not listing then
            return TriggerClientEvent('TMGCore:Notify', src, "Marketplace: Asset listing not found.", 'error')
        end

        if listing.seller ~= Player.PlayerData.citizenid then
            return TriggerClientEvent('TMGCore:Notify', src, "Unauthorized: Asset belongs to another Citizen.", 'error')
        end

        local restoredVehicle = {
            ["license"] = Player.PlayerData.license,
            ["citizenid"] = Player.PlayerData.citizenid,
            ["vehicle"] = listing.model,
            ["hash"] = GetHashKey(listing.model),
            ["mods"] = listing.mods, 
            ["plate"] = plate,
            ["state"] = 0 
        }

        exports['tmgnosql']:InsertOne('player_vehicles', restoredVehicle, function(success)
            if success then
                exports['tmgnosql']:DeleteOne('occasion_vehicles', { ["occasionid"] = oid, ["plate"] = plate })

                TriggerClientEvent('tmg-occasions:client:ReturnOwnedVehicle', src, listing)
                TriggerClientEvent('tmg-occasion:client:refreshVehicles', -1)
                TriggerClientEvent('TMGCore:Notify', src, "Asset reclaimed and synchronized with Garage.", 'success')
                
                print(string.format("^5[TMG]^7 Marketplace: Asset [%s] reclaimed by CID [%s]", plate, listing.seller))
            else
                TriggerClientEvent('TMGCore:Notify', src, "Mainframe Error: Registry injection failed.", 'error')
            end
        end)
    end)
end)


RegisterNetEvent('tmg-occasions:server:sellVehicle', function(vehiclePrice, vehicleData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not vehicleData.plate then return end

    local plate = vehicleData.plate:gsub("%s+", ""):upper()
    local cid = Player.PlayerData.citizenid

    exports['tmgnosql']:FetchOne('player_vehicles', { ["plate"] = plate, ["citizenid"] = cid }, function(exists)
        if not exists then
            return TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Asset ownership verification failed.", 'error')
        end

        local listingData = {
            ["seller"] = cid,
            ["price"] = tonumber(vehiclePrice),
            ["description"] = vehicleData.desc or "No description provided.",
            ["plate"] = plate,
            ["model"] = vehicleData.model,
            ["mods"] = vehicleData.mods, 
            ["occasionid"] = generateOID(),
            ["timestamp"] = os.time()
        }

        exports['tmgnosql']:InsertOne('occasion_vehicles', listingData, function(success)
            if success then
                exports['tmgnosql']:DeleteOne('player_vehicles', { ["plate"] = plate, ["citizenid"] = cid })

                TriggerEvent('tmg-log:server:CreateLog', 'vehicleshop', 'Marketplace Listing', 'green', 
                    string.format("**%s** (CID: %s) listed %s for $%s", Player.PlayerData.name, cid, vehicleData.model, vehiclePrice))
                
                TriggerClientEvent('tmg-occasion:client:refreshVehicles', -1)
                TriggerClientEvent('TMGCore:Notify', src, "Asset successfully anchored to Marketplace Grid.", 'success')
                
                print(string.format("^5[TMG]^7 Marketplace: Asset [%s] migrated by CID [%s]", plate, cid))
            else
                TriggerClientEvent('TMGCore:Notify', src, "Mainframe Error: Failed to materialize listing.", 'error')
            end
        end)
    end)
end)


RegisterNetEvent('tmg-occasions:server:liquidateVehicle', function(vehData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not vehData.plate then return end

    local plate = vehData.plate:gsub("%s+", ""):upper()
    local model = vehData.model
    local cid = Player.PlayerData.citizenid

    local basePrice = 0
    for _, v in pairs(TMGCore.Shared.Vehicles) do
        if v['hash'] == model or v['model'] == model then
            basePrice = tonumber(v['price']) or 0
            break
        end
    end

    exports['tmgnosql']:DeleteOne('player_vehicles', { 
        ["plate"] = plate, 
        ["citizenid"] = cid, 
        ["hash"] = model 
    }, function(deletedCount)
        if deletedCount and deletedCount > 0 then
            local payout = math.floor(basePrice * 0.5)
            
            if Player.Functions.AddMoney('bank', payout, 'vehicle-liquidation-payout') then
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.sold_car_for_price', { value = payout }), 'success')
                
                TriggerEvent('tmg-log:server:CreateLog', 'vehicleshop', 'Asset Liquidation', 'red', 
                    string.format("**%s** (CID: %s) liquidated %s [%s] for $%s", 
                    Player.PlayerData.name, cid, model, plate, payout))
                
                print(string.format("^5[TMG]^7 Economy: Asset [%s] liquidated by CID [%s]", plate, cid))
            end
        else
            TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.not_your_vehicle'), 'error')
        end
    end)
end)

RegisterNetEvent('tmg-occasions:server:buyVehicle', function(vehicleData)
    local src = source
    local Buyer = TMGCore.Functions.GetPlayer(src)
    if not Buyer or not vehicleData['plate'] then return end

    local plate = vehicleData['plate']:gsub("%s+", ""):upper()
    local oid = vehicleData['oid']

    exports['tmgnosql']:FetchOne('occasion_vehicles', { ["plate"] = plate, ["occasionid"] = oid }, function(listing)
        if not listing then return end

        if Buyer.PlayerData.money.bank >= listing.price then
            local sellerCID = listing.seller
            local payoutAmount = math.ceil(listing.price * 0.77) 

            Buyer.Functions.RemoveMoney('bank', listing.price, 'used-car-purchase')

            local newVehicle = {
                ["license"] = Buyer.PlayerData.license,
                ["citizenid"] = Buyer.PlayerData.citizenid,
                ["vehicle"] = listing.model,
                ["hash"] = GetHashKey(listing.model),
                ["mods"] = listing.mods, 
                ["plate"] = plate,
                ["state"] = 0
            }

            exports['tmgnosql']:InsertOne('player_vehicles', newVehicle, function(success)
                if success then
                    local Seller = TMGCore.Functions.GetPlayerByCitizenId(sellerCID)
                    if Seller then
                        Seller.Functions.AddMoney('bank', payoutAmount, 'used-car-sale')
                    else
                        exports['tmgnosql']:UpdateOne('players', { ["citizenid"] = sellerCID }, {
                            ["$inc"] = { ["money.bank"] = payoutAmount }
                        })
                    end

                    exports['tmgnosql']:DeleteOne('occasion_vehicles', { ["plate"] = plate, ["occasionid"] = oid })

                    TriggerClientEvent('tmg-occasions:client:BuyFinished', src, listing)
                    TriggerClientEvent('tmg-occasion:client:refreshVehicles', -1)
                    
                    exports['tmg-phone']:sendNewMailToOffline(sellerCID, {
                        sender = "Marketplace Registry",
                        subject = "Asset Liquidation Complete",
                        message = string.format("Your %s [%s] has been sold. $%s has been synchronized with your bank account.", listing.model, plate, payoutAmount)
                    })

                    TriggerEvent('tmg-log:server:CreateLog', 'vehicleshop', 'Purchase', 'green', 
                        string.format("**%s** bought %s from **%s** for $%s", Buyer.PlayerData.name, plate, sellerCID, listing.price))
                else
                    Buyer.Functions.AddMoney('bank', listing.price, 'used-car-refund-error')
                    TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Asset materialization failed. Funds refunded.", 'error')
                end
            end)
        else
            TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Insufficient Bank Balance.", 'error')
        end
    end)
end)
