-- server/vehicles.lua
-- Handling vehicle tax operations

-- Obtain ESX object
local ESX = exports['es_extended']:getSharedObject()

-- Function to get all vehicles owned by a player
function GetPlayerVehicles(identifier)
    local vehicles = MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', {
        identifier
    })
    
    return vehicles or {}
end

-- Function to get the number of vehicles owned by a player
function GetPlayerVehicleCount(identifier)
    local result = MySQL.query.await('SELECT COUNT(*) as count FROM owned_vehicles WHERE owner = ?', {
        identifier
    })
    
    if result and #result > 0 then
        return result[1].count
    end
    
    return 0
end

-- Function to get specific vehicle data
function GetVehicleData(plate)
    local result = MySQL.query.await('SELECT * FROM owned_vehicles WHERE plate = ?', {
        plate
    })
    
    if result and #result > 0 then
        return result[1]
    end
    
    return nil
end

-- Function to get vehicle tax data
function GetVehicleTaxData(plate)
    local result = MySQL.query.await('SELECT * FROM altax_vehicle_tax WHERE plate = ?', {
        plate
    })
    
    if result and #result > 0 then
        return result[1]
    end
    
    return nil
end

-- Function to update vehicle tax class (for admin purposes)
function UpdateVehicleTaxClass(plate, taxClass, taxMultiplier)
    MySQL.update('UPDATE altax_vehicle_tax SET tax_class = ?, tax_multiplier = ? WHERE plate = ?', {
        taxClass,
        taxMultiplier,
        plate
    })
end

-- Function to set a vehicle as tax exempt
function SetVehicleTaxExemption(plate, isExempt)
    MySQL.update('UPDATE altax_vehicle_tax SET tax_exemption = ? WHERE plate = ?', {
        isExempt and 1 or 0,
        plate
    })
end

-- Function to set a vehicle as green (eco-friendly)
function SetVehicleGreenStatus(plate, isGreen)
    MySQL.update('UPDATE owned_vehicles SET is_green = ? WHERE plate = ?', {
        isGreen and 1 or 0,
        plate
    })
    
    -- Jika eco-friendly, beri insentif pajak
    if isGreen then
        local vehicleData = GetVehicleData(plate)
        if vehicleData then
            local xPlayer = ESX.GetPlayerFromIdentifier(vehicleData.owner)
            if xPlayer then
                TriggerEvent('altax:addGreenVehicleIncentive', xPlayer.source)
            end
        end
    end
end

-- Function to sync vehicle data with tax system when a new vehicle is registered
function SyncVehicleWithTaxSystem(plate, model, price, owner)
    local vehicleTaxData = GetVehicleTaxData(plate)
    
    if vehicleTaxData then
        -- Update existing tax data
        MySQL.update('UPDATE altax_vehicle_tax SET vehicle_model = ?, purchase_price = ?, owner = ? WHERE plate = ?', {
            model,
            price,
            owner,
            plate
        })
    else
        -- Create new tax record
        MySQL.insert('INSERT INTO altax_vehicle_tax (plate, owner, vehicle_model, purchase_price, purchase_date) VALUES (?, ?, ?, ?, NOW())', {
            plate,
            owner,
            model,
            price
        })
    end
end

-- Function to calculate tax based on vehicle model
function CalculateModelTax(model, basePrice)
    local taxRate = Config.VehicleTaxBaseRate
    local vehClass = GetVehicleClassFromModel(model)
    local classMultiplier = Config.VehicleClasses[vehClass] and Config.VehicleClasses[vehClass].taxMultiplier or 1.0
    
    return math.floor(basePrice * (taxRate / 100) * classMultiplier)
end

-- Function to update purchase price for existing vehicle
function UpdateVehiclePurchasePrice(plate, price)
    MySQL.update('UPDATE altax_vehicle_tax SET purchase_price = ? WHERE plate = ?', {
        price,
        plate
    })
    
    MySQL.update('UPDATE owned_vehicles SET purchase_price = ? WHERE plate = ?', {
        price,
        plate
    })
end

-- Setup event handlers
Citizen.CreateThread(function()
    -- Event when a vehicle is purchased
    AddEventHandler('esx_vehicleshop:setVehicleOwned', function(source, vehicleProps, vehiclePrice)
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return end
        
        local identifier = xPlayer.identifier
        local plate = vehicleProps.plate
        local model = vehicleProps.model
        
        -- Register vehicle for tax
        SyncVehicleWithTaxSystem(plate, model, vehiclePrice, identifier)
        
        -- Check if it's a green vehicle (e.g., electric)
        local greenVehicles = {
            -- Add electric/hybrid car models here, example:
            [-1622444098] = true, -- voltic (electric sports car)
            [-1403128555] = true, -- dilettante (hybrid compact car)
            [-1130810103] = true  -- Khamelion (electric sports car)
        }
        
        if greenVehicles[model] then
            SetVehicleGreenStatus(plate, true)
            TriggerEvent('altax:addGreenVehicleIncentive', source)
        end
    end)
    
    -- Event when a vehicle is sold to another player
    AddEventHandler('esx_vehicleshop:resellVehicle', function(target, plate, price)
        local xTarget = ESX.GetPlayerFromId(target)
        if not xTarget then return end
        
        local vehicle = GetVehicleData(plate)
        if vehicle then
            SyncVehicleWithTaxSystem(plate, vehicle.model, price, xTarget.identifier)
        end
    end)
end)

-- Register commands for admins
ESX.RegisterCommand('vehicletax', 'admin', function(xPlayer, args, showError)
    local action = args.action
    local targetPlate = args.plate
    
    if action == 'info' then
        local taxData = GetVehicleTaxData(targetPlate)
        if taxData then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 128, 0},
                multiline = true,
                args = {'[ALTAX]', 'Vehicle Tax Info for ' .. targetPlate .. '\n' ..
                       'Model: ' .. taxData.vehicle_model .. '\n' ..
                       'Owner: ' .. taxData.owner .. '\n' ..
                       'Purchase Price: $' .. ESX.Math.GroupDigits(taxData.purchase_price) .. '\n' ..
                       'Tax Class: ' .. taxData.tax_class .. '\n' ..
                       'Tax Multiplier: ' .. taxData.tax_multiplier .. '\n' ..
                       'Exempt: ' .. (taxData.tax_exemption == 1 and 'Yes' or 'No')}
            })
        else
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Vehicle not found in tax database.'}
            })
        end
    elseif action == 'exempt' then
        SetVehicleTaxExemption(targetPlate, true)
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Vehicle ' .. targetPlate .. ' is now tax exempt.'}
        })
    elseif action == 'unexempt' then
        SetVehicleTaxExemption(targetPlate, false)
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Vehicle ' .. targetPlate .. ' is no longer tax exempt.'}
        })
    elseif action == 'setclass' then
        local taxClass = args.taxClass
        local taxMultiplier = args.multiplier
        
        if not taxClass or not taxMultiplier then
            showError('Usage: /vehicletax setclass [plate] [class] [multiplier]')
            return
        end
        
        UpdateVehicleTaxClass(targetPlate, taxClass, taxMultiplier)
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Vehicle ' .. targetPlate .. ' tax class updated to ' .. taxClass .. ' with multiplier ' .. taxMultiplier}
        })
    elseif action == 'setprice' then
        local price = args.price
        
        if not price then
            showError('Usage: /vehicletax setprice [plate] [price]')
            return
        end
        
        UpdateVehiclePurchasePrice(targetPlate, price)
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Vehicle ' .. targetPlate .. ' purchase price updated to $' .. ESX.Math.GroupDigits(price)}
        })
    else
        showError('Invalid action. Use: info, exempt, unexempt, setclass, setprice')
    end
end, true, {help = 'Vehicle tax management', validate = true, arguments = {
    {name = 'action', help = 'Action: info, exempt, unexempt, setclass, setprice', type = 'string'},
    {name = 'plate', help = 'Vehicle plate', type = 'string'},
    {name = 'taxClass', help = 'Tax class (for setclass)', type = 'string', optional = true},
    {name = 'multiplier', help = 'Tax multiplier (for setclass)', type = 'number', optional = true},
    {name = 'price', help = 'Purchase price (for setprice)', type = 'number', optional = true}
}})

-- Export functions for other resources
exports('GetPlayerVehicles', GetPlayerVehicles)
exports('GetPlayerVehicleCount', GetPlayerVehicleCount)
exports('GetVehicleData', GetVehicleData)
exports('GetVehicleTaxData', GetVehicleTaxData)
exports('UpdateVehicleTaxClass', UpdateVehicleTaxClass)
exports('SetVehicleTaxExemption', SetVehicleTaxExemption)
exports('SetVehicleGreenStatus', SetVehicleGreenStatus)
exports('CalculateModelTax', CalculateModelTax)