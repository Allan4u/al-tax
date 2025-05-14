local ESX = exports['es_extended']:getSharedObject()
local taxScheduler = nil
local taxAuditScheduler = nil

Citizen.CreateThread(function()
    InitializeTaxSystem()
end)

-- Fungsi utama untuk inisialisasi sistem pajak
function InitializeTaxSystem()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `altax_records` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `last_tax_date` timestamp NOT NULL DEFAULT current_timestamp(),
            `next_tax_date` timestamp NOT NULL DEFAULT current_timestamp(),
            `total_tax_paid` int(11) NOT NULL DEFAULT 0,
            `tax_bracket` varchar(50) NOT NULL DEFAULT 'Miskin',
            `tax_rate` float NOT NULL DEFAULT 5.0,
            `overdue_amount` int(11) NOT NULL DEFAULT 0,
            `late_fees` int(11) NOT NULL DEFAULT 0,
            `audit_count` int(11) NOT NULL DEFAULT 0,
            `last_audit_date` timestamp NULL DEFAULT NULL,
            `tax_incentives` longtext DEFAULT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    ScheduleTaxCollection()
    
    if Config.TaxAuditEnabled then
        ScheduleTaxAudits()
    end
    
    SetupEventHandlers()
    
    print('[ALTAX] Tax system initialized successfully')
end

function ScheduleTaxCollection()
    if taxScheduler ~= nil then
        ESX.ClearTimeout(taxScheduler)
    end
    
    taxScheduler = ESX.SetTimeout(60000, function()
        ProcessScheduledTax()
        ScheduleTaxCollection()
    end)
end

function ProcessScheduledTax()
    local currentTime = os.time()
    local currentHour = tonumber(os.date('%H', currentTime))
    
    if currentHour == Config.TaxCollectionHour then
        local results = MySQL.query.await('SELECT * FROM altax_records WHERE DATE(next_tax_date) = CURDATE()')
        
        if results and #results > 0 then
            for _, taxRecord in ipairs(results) do
                ProcessPlayerTax(taxRecord.identifier)
            end
        end
    end
    SendTaxDueWarnings()
end

function SendTaxDueWarnings()
    local warningDays = 2 
    local dueDate = os.date('%Y-%m-%d', os.time() + (warningDays * 86400))
    
    local records = MySQL.query.await('SELECT * FROM altax_records WHERE DATE(next_tax_date) = ?', {
        dueDate
    })
    
    if records and #records > 0 then
        for _, record in ipairs(records) do
            local xPlayer = ESX.GetPlayerFromIdentifier(record.identifier)
            
            if xPlayer then
                local totalTax = CalculateTotalTax(xPlayer)
                TriggerClientEvent('altax:taxDueWarning', xPlayer.source, totalTax, warningDays)
                
                if Config.SendSMSNotification then
                    local message = _U('tax_due_soon', ESX.Math.GroupDigits(totalTax), warningDays)
                    SendTaxSMS(xPlayer.source, message)
                end
            end
        end
    end
end

function ProcessPlayerTax(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    local isOnline = (xPlayer ~= nil)
    
    if isOnline then
        CollectPlayerTax(xPlayer)
    else
        local totalTax = CalculateOfflinePlayerTax(identifier)
        if totalTax > 0 then
            UpdateOverdueTax(identifier, totalTax)
        end
    end
end

function CalculateOfflinePlayerTax(identifier)
    local result = MySQL.query.await('SELECT accounts FROM users WHERE identifier = ?', {
        identifier
    })
    
    if not result or #result == 0 then return 0 end
    
    local accounts = json.decode(result[1].accounts)
    local money = accounts.bank or 0
    local cash = accounts.money or 0
    
    local jobResult = MySQL.query.await('SELECT job, job_grade FROM users WHERE identifier = ?', {
        identifier
    })
    
    local job = 'unemployed'
    if jobResult and #jobResult > 0 then
        job = jobResult[1].job
    end
    
    local isExempt = IsJobExemptFromTax(job, 'income')
    if isExempt then
        return 0
    end
    
    local taxBracket = GetTaxBracket(money)
    local taxRate = taxBracket.taxRate
    
    local incomeTax = CalculateIncomeTax(money, taxRate)
    
    local propertyTax = 0
    if Config.PropertyTaxEnabled then
        propertyTax = CalculateOfflinePropertyTax(identifier)
    end
    
    local vehicleTax = 0
    local vehicleCountTax = 0
    if Config.VehicleTaxEnabled then
        local vehicleData = CalculateOfflineVehicleTax(identifier)
        vehicleTax = vehicleData.vehicleTax
        vehicleCountTax = vehicleData.vehicleCountTax
    end
    local totalTax = incomeTax + propertyTax + vehicleTax + vehicleCountTax
    
    MySQL.update('UPDATE altax_records SET tax_bracket = ?, tax_rate = ? WHERE identifier = ?', {
        taxBracket.name,
        taxRate,
        identifier
    })
    
    return totalTax
end

function CollectPlayerTax(xPlayer)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    local money = xPlayer.getAccount('bank').money
    local cash = xPlayer.getMoney()
    local job = xPlayer.getJob().name
    
    local incomeExempt = IsJobExemptFromTax(job, 'income')
    local propertyExempt = IsJobExemptFromTax(job, 'property')
    local vehicleExempt = IsJobExemptFromTax(job, 'vehicle')
    
    local taxBracket = GetTaxBracket(money)
    local taxRate = taxBracket.taxRate
    
    TriggerClientEvent('altax:notifyTaxBracket', xPlayer.source, taxBracket.name, taxRate)
    
  
    local incomeTax = 0
    if not incomeExempt then
        incomeTax = CalculateIncomeTax(money, taxRate)
    else
        TriggerClientEvent('altax:taxExempt', xPlayer.source, 'income')
    end
    

    local propertyTax = 0
    if Config.PropertyTaxEnabled and not propertyExempt then
        propertyTax = CalculatePropertyTax(xPlayer)
    elseif Config.PropertyTaxEnabled and propertyExempt then
        TriggerClientEvent('altax:taxExempt', xPlayer.source, 'property')
    end
    

    local vehicleTax = 0
    local vehicleCountTax = 0
    if Config.VehicleTaxEnabled and not vehicleExempt then
        local vehicleData = CalculateVehicleTax(xPlayer)
        vehicleTax = vehicleData.vehicleTax
        vehicleCountTax = vehicleData.vehicleCountTax
    elseif Config.VehicleTaxEnabled and vehicleExempt then
        TriggerClientEvent('altax:taxExempt', xPlayer.source, 'vehicle')
    end
    

    local incentives = GetPlayerTaxIncentives(xPlayer.identifier)
    local totalIncentives = CalculateTaxIncentives(xPlayer, incentives, incomeTax + propertyTax + vehicleTax + vehicleCountTax)
    

    local totalTax = (incomeTax + propertyTax + vehicleTax + vehicleCountTax) - totalIncentives
    

    local overdueAmount = GetOverdueTax(identifier)
    if overdueAmount > 0 then

        if IsAmnestyActive() then
            local discountAmount = math.floor(overdueAmount * (Config.TaxAmnestyDiscount / 100))
            overdueAmount = overdueAmount - discountAmount
            TriggerClientEvent('altax:amnestyApplied', xPlayer.source, discountAmount)
        end
        
        totalTax = totalTax + overdueAmount
    end
    

    TriggerClientEvent('altax:taxSummary', xPlayer.source, {
        incomeTax = incomeTax,
        propertyTax = propertyTax,
        vehicleTax = vehicleTax,
        vehicleCountTax = vehicleCountTax,
        incentives = totalIncentives,
        overdue = overdueAmount,
        total = totalTax
    })
    

    local receiptId = GenerateReceiptId(identifier)
    

    if money >= totalTax then
        xPlayer.removeAccountMoney('bank', totalTax)
        TriggerClientEvent('altax:taxCollected', xPlayer.source, totalTax, 'bank')
        

        UpdateTaxRecord(identifier, totalTax, taxBracket.name, taxRate)
        

        RecordTaxPayment(identifier, totalTax, 'combined', 'bank', receiptId)
    elseif Config.AllowCashPayment and (money + cash) >= totalTax then

        local remainingTax = totalTax - money
        
        xPlayer.removeAccountMoney('bank', money)
        xPlayer.removeMoney(remainingTax)
        
        TriggerClientEvent('altax:taxCollectedCash', xPlayer.source, totalTax, money, remainingTax)
        

        UpdateTaxRecord(identifier, totalTax, taxBracket.name, taxRate)
        
        
        RecordTaxPayment(identifier, totalTax, 'combined', 'mixed', receiptId)
    else
       
        TriggerClientEvent('altax:notEnoughMoney', xPlayer.source, totalTax, money)
        

        AddOverdueTax(identifier, totalTax)
    end
    
 
    local governmentAccount = Config.TaxRevenueAccount
    if governmentAccount and totalTax > 0 then
        TriggerEvent('esx_addonaccount:getSharedAccount', governmentAccount, function(account)
            if account then
                account.addMoney(totalTax)
              
                DistributeTaxRevenue(totalTax)
            end
        end)
    end
end

function CalculateIncomeTax(money, taxRate)
    if money < Config.MinimumTaxableIncome then
        return 0 
    end
    
    local taxAmount = math.floor(money * (taxRate / 100))
    return taxAmount
end

function GetTaxBracket(money)
    for _, bracket in ipairs(Config.IncomeTaxBrackets) do
        if money >= bracket.minMoney and money <= bracket.maxMoney then
            return bracket
        end
    end
    
    return Config.IncomeTaxBrackets[#Config.IncomeTaxBrackets]
end


function CalculatePropertyTax(xPlayer)
    local identifier = xPlayer.identifier
    local totalPropertyTax = 0
    
    local properties = MySQL.query.await('SELECT * FROM altax_property_tax WHERE owner = ?', {
        identifier
    })
    
    if properties and #properties > 0 then
        for _, property in ipairs(properties) do
            local propertyType = property.property_type
            local propertyValue = property.property_value
            local taxMultiplier = Config.PropertyTypes[propertyType] and Config.PropertyTypes[propertyType].taxMultiplier or 1.0
            
            local propertyTaxAmount = math.floor(propertyValue * (Config.PropertyTaxRate / 100) * taxMultiplier)
            totalPropertyTax = totalPropertyTax + propertyTaxAmount
            
            MySQL.update('UPDATE altax_property_tax SET last_tax_date = NOW() WHERE id = ?', {
                property.id
            })
        end
    end
    
    return totalPropertyTax
end

function CalculateOfflinePropertyTax(identifier)
    local totalPropertyTax = 0
    
    local properties = MySQL.query.await('SELECT * FROM altax_property_tax WHERE owner = ?', {
        identifier
    })
    
    if properties and #properties > 0 then
        for _, property in ipairs(properties) do
            local propertyType = property.property_type
            local propertyValue = property.property_value
            local taxMultiplier = Config.PropertyTypes[propertyType] and Config.PropertyTypes[propertyType].taxMultiplier or 1.0
            
    
            local propertyTaxAmount = math.floor(propertyValue * (Config.PropertyTaxRate / 100) * taxMultiplier)
            totalPropertyTax = totalPropertyTax + propertyTaxAmount
            
            
            MySQL.update('UPDATE altax_property_tax SET last_tax_date = NOW() WHERE id = ?', {
                property.id
            })
        end
    end
    
    return totalPropertyTax
end
function CalculateVehicleTax(xPlayer)
    local identifier = xPlayer.identifier
    local totalVehicleTax = 0
    local vehicleCount = 0
    

    local vehicles = MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', {
        identifier
    })
    
    if vehicles and #vehicles > 0 then
        vehicleCount = #vehicles
        
        for _, vehicle in ipairs(vehicles) do
           
            local vehicleTaxData = MySQL.query.await('SELECT * FROM altax_vehicle_tax WHERE plate = ?', {
                vehicle.plate
            })
            
            if vehicleTaxData and #vehicleTaxData > 0 then
                local vehicleModel = vehicleTaxData[1].vehicle_model
                local purchasePrice = vehicleTaxData[1].purchase_price
                local purchaseDate = vehicleTaxData[1].purchase_date
                local taxClass = vehicleTaxData[1].tax_class
                local isExempt = vehicleTaxData[1].tax_exemption == 1
                local taxMultiplier = vehicleTaxData[1].tax_multiplier
                
              
                if not isExempt then
                    
                    local vehClass = GetVehicleClassFromModel(vehicleModel)
                    local classMultiplier = Config.VehicleClasses[vehClass] and Config.VehicleClasses[vehClass].taxMultiplier or 1.0
                    
                 
                    local vehicleAge = CalculateVehicleAge(purchaseDate)
                    local ageDiscount = math.min(0.5, vehicleAge * Config.VehicleAgeTaxDiscount) -- Max 50% discount
                    
                 
                    local baseTax = math.floor(purchasePrice * (Config.VehicleTaxBaseRate / 100))
                    
                 
                    local finalTax = math.floor(baseTax * classMultiplier * taxMultiplier * (1 - ageDiscount))
                    
                    totalVehicleTax = totalVehicleTax + finalTax
                    
              
                    MySQL.update('UPDATE altax_vehicle_tax SET last_tax_date = NOW() WHERE plate = ?', {
                        vehicle.plate
                    })
                end
            end
        end
    end
    

    local vehicleCountTax = 0
    if vehicleCount > 1 then
        local additionalTaxRate = Config.VehicleCountTaxMultiplier * (vehicleCount - 1)
        vehicleCountTax = math.floor(totalVehicleTax * additionalTaxRate)
    end
    
    return {
        vehicleTax = totalVehicleTax,
        vehicleCountTax = vehicleCountTax
    }
end


function CalculateOfflineVehicleTax(identifier)
    local totalVehicleTax = 0
    local vehicleCount = 0
    

    local vehicles = MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', {
        identifier
    })
    
    if vehicles and #vehicles > 0 then
        vehicleCount = #vehicles
        
        for _, vehicle in ipairs(vehicles) do
            local vehicleTaxData = MySQL.query.await('SELECT * FROM altax_vehicle_tax WHERE plate = ?', {
                vehicle.plate
            })
            
            if vehicleTaxData and #vehicleTaxData > 0 then
                local vehicleModel = vehicleTaxData[1].vehicle_model
                local purchasePrice = vehicleTaxData[1].purchase_price
                local purchaseDate = vehicleTaxData[1].purchase_date
                local taxClass = vehicleTaxData[1].tax_class
                local isExempt = vehicleTaxData[1].tax_exemption == 1
                local taxMultiplier = vehicleTaxData[1].tax_multiplier
                
      
                if not isExempt then
               
                    local vehClass = GetVehicleClassFromModel(vehicleModel)
                    local classMultiplier = Config.VehicleClasses[vehClass] and Config.VehicleClasses[vehClass].taxMultiplier or 1.0
                    
                 
                    local vehicleAge = CalculateVehicleAge(purchaseDate)
                    local ageDiscount = math.min(0.5, vehicleAge * Config.VehicleAgeTaxDiscount) -- Max 50% discount
                    
                
                    local baseTax = math.floor(purchasePrice * (Config.VehicleTaxBaseRate / 100))
                    
                   
                    local finalTax = math.floor(baseTax * classMultiplier * taxMultiplier * (1 - ageDiscount))
                    
                    totalVehicleTax = totalVehicleTax + finalTax
                   
                    MySQL.update('UPDATE altax_vehicle_tax SET last_tax_date = NOW() WHERE plate = ?', {
                        vehicle.plate
                    })
                end
            end
        end
    end
    

    local vehicleCountTax = 0
    if vehicleCount > 1 then
        local additionalTaxRate = Config.VehicleCountTaxMultiplier * (vehicleCount - 1)
        vehicleCountTax = math.floor(totalVehicleTax * additionalTaxRate)
    end
    
    return {
        vehicleTax = totalVehicleTax,
        vehicleCountTax = vehicleCountTax
    }
end

function CalculateVehicleAge(purchaseDate)
    local purchaseTimestamp = os.time(os.date('*t', purchaseDate))
    local currentTimestamp = os.time()
    local ageInSeconds = currentTimestamp - purchaseTimestamp
    local ageInYears = ageInSeconds / (365.25 * 24 * 60 * 60)
    
    return math.floor(ageInYears)
end

function GetVehicleClassFromModel(model)
    local sportsCars = {
        adder = true, t20 = true, zentorno = true, turismor = true,
        osiris = true, cheetah = true, entityxf = true, sheava = true
    }
    
    local suv = {
        baller = true, cavalcade = true, granger = true, xls = true,
        huntley = true, mesa = true, patriot = true, radi = true
    }
    
    local sedans = {
        asea = true, asterope = true, cognoscenti = true, emperor = true,
        fugitive = true, glendale = true, ingot = true, intruder = true
    }
    
    model = string.lower(model)
    
    if sportsCars[model] then return 6 -- Sports
    elseif suv[model] then return 2 -- SUVs
    elseif sedans[model] then return 1 -- Sedans
    else return 1 -- Default to sedans if unknown
    end
end

function GetPlayerTaxIncentives(identifier)
    local results = MySQL.query.await('SELECT tax_incentives FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if results and #results > 0 and results[1].tax_incentives then
        return json.decode(results[1].tax_incentives)
    end
    
    return {}
end

function CalculateTaxIncentives(xPlayer, incentives, baseTax)
    local totalDeduction = 0
    

    if incentives.charityDonation then
        local charityAmount = incentives.charityDonation
        local deduction = math.min(
            charityAmount * Config.TaxIncentives.charityDonation.multiplier,
            Config.TaxIncentives.charityDonation.maxDeduction
        )
        totalDeduction = totalDeduction + deduction
        
      
        TriggerClientEvent('altax:incentiveApplied', xPlayer.source, 'charity_donation', deduction)
    end
    
    if incentives.greenVehicle then
        local greenDeduction = math.floor(baseTax * (Config.TaxIncentives.greenVehicle.deduction / 100))
        totalDeduction = totalDeduction + greenDeduction
        
      
        TriggerClientEvent('altax:incentiveApplied', xPlayer.source, 'green_vehicle', greenDeduction)
    end
    
    if incentives.policeCooperation then
        local policeDeduction = math.floor(baseTax * (Config.TaxIncentives.policeCooperation.deduction / 100))
        totalDeduction = totalDeduction + policeDeduction
        
       
        TriggerClientEvent('altax:incentiveApplied', xPlayer.source, 'police_cooperation', policeDeduction)
    end
    
    return totalDeduction
end


function GetOverdueTax(identifier)
    local result = MySQL.query.await('SELECT overdue_amount, late_fees FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        return (result[1].overdue_amount or 0) + (result[1].late_fees or 0)
    end
    
    return 0
end

function AddOverdueTax(identifier, amount)
    MySQL.update('UPDATE altax_records SET overdue_amount = overdue_amount + ? WHERE identifier = ?', {
        amount,
        identifier
    })
    
  
    local result = MySQL.query.await('SELECT overdue_amount FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 and result[1].overdue_amount > amount then
      
        local lateFee = math.floor(amount * (Config.LateFeePercentage / 100))
        
        MySQL.update('UPDATE altax_records SET late_fees = late_fees + ? WHERE identifier = ?', {
            lateFee,
            identifier
        })
    end
end

function UpdateOverdueTax(identifier, amount)
  
    local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
       
        MySQL.update('UPDATE altax_records SET overdue_amount = overdue_amount + ? WHERE identifier = ?', {
            amount,
            identifier
        })
    else
       
        MySQL.insert('INSERT INTO altax_records (identifier, overdue_amount) VALUES (?, ?)', {
            identifier,
            amount
        })
    end
    
   
    UpdateNextTaxDate(identifier)
end


function UpdateTaxRecord(identifier, amount, taxBracket, taxRate)
    
    local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        
        MySQL.update('UPDATE altax_records SET last_tax_date = NOW(), next_tax_date = DATE_ADD(NOW(), INTERVAL ? DAY), total_tax_paid = total_tax_paid + ?, tax_bracket = ?, tax_rate = ?, overdue_amount = 0, late_fees = 0 WHERE identifier = ?', {
            Config.TaxInterval,
            amount,
            taxBracket,
            taxRate,
            identifier
        })
    else
      
        MySQL.insert('INSERT INTO altax_records (identifier, last_tax_date, next_tax_date, total_tax_paid, tax_bracket, tax_rate) VALUES (?, NOW(), DATE_ADD(NOW(), INTERVAL ? DAY), ?, ?, ?)', {
            identifier,
            Config.TaxInterval,
            amount,
            taxBracket,
            taxRate
        })
    end
end

function UpdateNextTaxDate(identifier)
    MySQL.update('UPDATE altax_records SET next_tax_date = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE identifier = ?', {
        Config.TaxInterval,
        identifier
    })
end

function RecordTaxPayment(identifier, amount, taxType, paymentMethod, receiptId)
    MySQL.insert('INSERT INTO altax_payments (identifier, amount, tax_type, payment_method, receipt_id, tax_period_start, tax_period_end) VALUES (?, ?, ?, ?, ?, DATE_SUB(NOW(), INTERVAL ? DAY), NOW())', {
        identifier,
        amount,
        taxType,
        paymentMethod,
        receiptId,
        Config.TaxInterval
    })
end

function GenerateReceiptId(identifier)
    local timestamp = os.time()
    local randomPart = math.random(10000, 99999)
    return string.format('TX-%s-%d-%d', string.sub(identifier, -5), timestamp, randomPart)
end


function DistributeTaxRevenue(amount)
    if not Config.TaxDistribution then return end
    
    for account, percentage in pairs(Config.TaxDistribution) do
        if account ~= 'government' then
            local shareAmount = math.floor(amount * (percentage / 100))
            
            if shareAmount > 0 then
                local societyAccount = 'society_' .. account
                
                TriggerEvent('esx_addonaccount:getSharedAccount', societyAccount, function(account)
                    if account then
                        account.addMoney(shareAmount)
                        if Config.Debug then
                            print('[ALTAX] Distributed ' .. shareAmount .. ' to ' .. societyAccount)
                        end
                    end
                end)
            end
        end
    end
end


function IsJobExemptFromTax(job, taxType)
    if Config.ExemptJobs[job] and Config.ExemptJobs[job][taxType] then
        return true
    end
    return false
end

function CalculateTotalTax(xPlayer)
    local money = xPlayer.getAccount('bank').money
    local taxBracket = GetTaxBracket(money)
    local incomeTax = CalculateIncomeTax(money, taxBracket.taxRate)
    local propertyTax = Config.PropertyTaxEnabled and CalculatePropertyTax(xPlayer) or 0
    
    local vehicleTaxData = Config.VehicleTaxEnabled and CalculateVehicleTax(xPlayer) or { vehicleTax = 0, vehicleCountTax = 0 }
    local vehicleTax = vehicleTaxData.vehicleTax
    local vehicleCountTax = vehicleTaxData.vehicleCountTax

    local overdueAmount = GetOverdueTax(xPlayer.identifier)
    
    return incomeTax + propertyTax + vehicleTax + vehicleCountTax + overdueAmount
end

function SendTaxSMS(target, message)
    TriggerClientEvent('altax:sendSMS', target, Config.TaxServiceNumber, message)
end


function SetupEventHandlers()

    AddEventHandler('esx:playerLoaded', function(source, xPlayer)
        Citizen.Wait(10000) 
        
        local identifier = xPlayer.identifier
        
        local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ? AND overdue_amount > 0', {
            identifier
        })
        
        if result and #result > 0 then
            local overdueAmount = result[1].overdue_amount + (result[1].late_fees or 0)
            
    
            TriggerClientEvent('altax:overdueNotice', source, overdueAmount)
            
    
            if IsAmnestyActive() then
                TriggerClientEvent('altax:amnestyAvailable', source, Config.TaxAmnestyDiscount)
            end
        end
        
   
        local taxDateResult = MySQL.query.await('SELECT next_tax_date FROM altax_records WHERE identifier = ?', {
            identifier
        })
        
        if taxDateResult and #taxDateResult > 0 then
            TriggerClientEvent('altax:nextTaxDate', source, taxDateResult[1].next_tax_date)
        end
    end)
    

    AddEventHandler('esx_vehicleshop:setVehicleOwned', function(source, vehicleProps, vehiclePrice, model)
        RegisterVehicleForTax(source, vehicleProps, vehiclePrice, model)
    end)
    

    AddEventHandler('esx_property:bought', function(source, propertyId, price, propertyType)
        RegisterPropertyForTax(source, propertyId, price, propertyType or 'apartment')
    end)
    

    AddEventHandler('altax:addCharityIncentive', function(source, amount)
        AddTaxIncentive(source, 'charityDonation', amount)
    end)
    
    AddEventHandler('altax:addGreenVehicleIncentive', function(source)
        AddTaxIncentive(source, 'greenVehicle', true)
    end)
    
    AddEventHandler('altax:addPoliceCooperationIncentive', function(source)
        AddTaxIncentive(source, 'policeCooperation', true)
    end)
end


function AddTaxIncentive(source, incentiveType, value)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    

    local results = MySQL.query.await('SELECT tax_incentives FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    local incentives = {}
    if results and #results > 0 and results[1].tax_incentives then
        incentives = json.decode(results[1].tax_incentives)
    end
    

    if incentiveType == 'charityDonation' then
        incentives.charityDonation = (incentives.charityDonation or 0) + value
    elseif incentiveType == 'greenVehicle' then
        incentives.greenVehicle = true
    elseif incentiveType == 'policeCooperation' then
        incentives.policeCooperation = true
    end
    

    MySQL.update('UPDATE altax_records SET tax_incentives = ? WHERE identifier = ?', {
        json.encode(incentives),
        identifier
    })
    
    if not results or #results == 0 then

        MySQL.insert('INSERT INTO altax_records (identifier, tax_incentives) VALUES (?, ?)', {
            identifier,
            json.encode(incentives)
        })
    end
    
    TriggerClientEvent('altax:incentiveAdded', source, incentiveType)
end


function RegisterVehicleForTax(source, vehicleProps, vehiclePrice, model)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    local plate = vehicleProps.plate
    

    local vehCheck = MySQL.query.await('SELECT * FROM altax_vehicle_tax WHERE plate = ?', {
        plate
    })
    
    if vehCheck and #vehCheck > 0 then

        MySQL.update('UPDATE altax_vehicle_tax SET owner = ?, vehicle_model = ?, purchase_price = ?, purchase_date = NOW() WHERE plate = ?', {
            identifier,
            model,
            vehiclePrice,
            plate
        })
    else
     
        MySQL.insert('INSERT INTO altax_vehicle_tax (plate, owner, vehicle_model, purchase_price, purchase_date) VALUES (?, ?, ?, ?, NOW())', {
            plate,
            identifier,
            model,
            vehiclePrice
        })
    end
end


function RegisterPropertyForTax(source, propertyId, price, propertyType)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    

    local propCheck = MySQL.query.await('SELECT * FROM altax_property_tax WHERE property_id = ?', {
        propertyId
    })
    
    if propCheck and #propCheck > 0 then
    
        MySQL.update('UPDATE altax_property_tax SET owner = ?, property_value = ?, property_type = ?, purchase_date = NOW() WHERE property_id = ?', {
            identifier,
            price,
            propertyType,
            propertyId
        })
    else
     
        MySQL.insert('INSERT INTO altax_property_tax (property_id, owner, property_value, property_type, purchase_date) VALUES (?, ?, ?, ?, NOW())', {
            propertyId,
            identifier,
            price,
            propertyType
        })
    end
end


function IsAmnestyActive()
    if not Config.TaxAmnestyEnabled then
        return false
    end
    
  
    local result = MySQL.query.await('SELECT * FROM altax_amnesty WHERE start_date <= NOW() AND end_date >= NOW() AND active = 1 LIMIT 1')
    
    return result and #result > 0
end


exports('CalculatePlayerTax', CalculateTotalTax)
exports('ProcessTax', CollectPlayerTax)
exports('AddTaxIncentive', AddTaxIncentive)
exports('RegisterVehicleForTax', RegisterVehicleForTax)
exports('RegisterPropertyForTax', RegisterPropertyForTax)
