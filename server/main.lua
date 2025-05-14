-- server/main.lua
-- Main server file for ALTAX tax system

local ESX = exports['es_extended']:getSharedObject()
local taxScheduler = nil
local taxAuditScheduler = nil

-- Inisialisasi sistem pajak
Citizen.CreateThread(function()
    InitializeTaxSystem()
end)

-- Fungsi utama untuk inisialisasi sistem pajak
function InitializeTaxSystem()
    -- Membuat tabel database jika belum ada
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

    -- Setup jadwal untuk memproses pajak
    ScheduleTaxCollection()
    
    -- Setup jadwal untuk audit pajak acak
    if Config.TaxAuditEnabled then
        ScheduleTaxAudits()
    end
    
    -- Setup event handlers
    SetupEventHandlers()
    
    -- Log inisialisasi sukses
    print('[ALTAX] Tax system initialized successfully')
end

-- Jadwalkan koleksi pajak
function ScheduleTaxCollection()
    -- Hentikan scheduler lama jika ada
    if taxScheduler ~= nil then
        ESX.ClearTimeout(taxScheduler)
    end
    
    -- Cek dan proses pajak setiap menit (untuk cek apakah sudah waktunya memproses pajak)
    taxScheduler = ESX.SetTimeout(60000, function()
        ProcessScheduledTax()
        ScheduleTaxCollection() -- Reschedule the function
    end)
end

-- Proses pajak terjadwal
function ProcessScheduledTax()
    local currentTime = os.time()
    local currentHour = tonumber(os.date('%H', currentTime))
    
    -- Hanya proses pajak pada jam yang ditentukan di config
    if currentHour == Config.TaxCollectionHour then
        local results = MySQL.query.await('SELECT * FROM altax_records WHERE DATE(next_tax_date) = CURDATE()')
        
        -- Jika ada pajak yang jatuh tempo hari ini
        if results and #results > 0 then
            for _, taxRecord in ipairs(results) do
                -- Proses pajak untuk identifier ini
                ProcessPlayerTax(taxRecord.identifier)
            end
        end
    end
    
    -- Kirim peringatan untuk pajak yang mendekati jatuh tempo
    SendTaxDueWarnings()
end

-- Kirim peringatan pajak yang akan jatuh tempo
function SendTaxDueWarnings()
    local warningDays = 2 -- Hari sebelum jatuh tempo untuk mengirim peringatan
    local dueDate = os.date('%Y-%m-%d', os.time() + (warningDays * 86400))
    
    local records = MySQL.query.await('SELECT * FROM altax_records WHERE DATE(next_tax_date) = ?', {
        dueDate
    })
    
    if records and #records > 0 then
        for _, record in ipairs(records) do
            local xPlayer = ESX.GetPlayerFromIdentifier(record.identifier)
            
            -- Jika player online, kirim notifikasi
            if xPlayer then
                local totalTax = CalculateTotalTax(xPlayer)
                TriggerClientEvent('altax:taxDueWarning', xPlayer.source, totalTax, warningDays)
                
                -- Kirim SMS jika diaktifkan
                if Config.SendSMSNotification then
                    local message = _U('tax_due_soon', ESX.Math.GroupDigits(totalTax), warningDays)
                    SendTaxSMS(xPlayer.source, message)
                end
            end
        end
    end
end

-- Proses pajak untuk pemain tertentu
function ProcessPlayerTax(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    local isOnline = (xPlayer ~= nil)
    
    -- Jika pemain online, proses langsung
    if isOnline then
        CollectPlayerTax(xPlayer)
    else
        -- Jika pemain offline, simpan pajak yang harus dibayar untuk dibayar nanti
        local totalTax = CalculateOfflinePlayerTax(identifier)
        if totalTax > 0 then
            -- Perbarui catatan pajak untuk membuat pajak terutang
            UpdateOverdueTax(identifier, totalTax)
        end
    end
end

-- Hitung pajak untuk pemain offline
function CalculateOfflinePlayerTax(identifier)
    local result = MySQL.query.await('SELECT accounts FROM users WHERE identifier = ?', {
        identifier
    })
    
    if not result or #result == 0 then return 0 end
    
    local accounts = json.decode(result[1].accounts)
    local money = accounts.bank or 0
    local cash = accounts.money or 0
    
    -- Get job data
    local jobResult = MySQL.query.await('SELECT job, job_grade FROM users WHERE identifier = ?', {
        identifier
    })
    
    local job = 'unemployed'
    if jobResult and #jobResult > 0 then
        job = jobResult[1].job
    end
    
    -- Cek apakah job exempt dari pajak
    local isExempt = IsJobExemptFromTax(job, 'income')
    if isExempt then
        return 0
    end
    
    -- Tentukan bracket pajak berdasarkan uang
    local taxBracket = GetTaxBracket(money)
    local taxRate = taxBracket.taxRate
    
    -- Hitung pajak penghasilan
    local incomeTax = CalculateIncomeTax(money, taxRate)
    
    -- Hitung pajak properti
    local propertyTax = 0
    if Config.PropertyTaxEnabled then
        propertyTax = CalculateOfflinePropertyTax(identifier)
    end
    
    -- Hitung pajak kendaraan
    local vehicleTax = 0
    local vehicleCountTax = 0
    if Config.VehicleTaxEnabled then
        local vehicleData = CalculateOfflineVehicleTax(identifier)
        vehicleTax = vehicleData.vehicleTax
        vehicleCountTax = vehicleData.vehicleCountTax
    end
    
    -- Total pajak
    local totalTax = incomeTax + propertyTax + vehicleTax + vehicleCountTax
    
    -- Update tax bracket in database
    MySQL.update('UPDATE altax_records SET tax_bracket = ?, tax_rate = ? WHERE identifier = ?', {
        taxBracket.name,
        taxRate,
        identifier
    })
    
    return totalTax
end

-- Kumpulkan pajak dari pemain
function CollectPlayerTax(xPlayer)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    local money = xPlayer.getAccount('bank').money
    local cash = xPlayer.getMoney()
    local job = xPlayer.getJob().name
    
    -- Cek jika player exempt dari pajak penghasilan
    local incomeExempt = IsJobExemptFromTax(job, 'income')
    local propertyExempt = IsJobExemptFromTax(job, 'property')
    local vehicleExempt = IsJobExemptFromTax(job, 'vehicle')
    
    -- Tentukan bracket pajak berdasarkan uang bank
    local taxBracket = GetTaxBracket(money)
    local taxRate = taxBracket.taxRate
    
    -- Beritahu player tentang bracket pajak mereka
    TriggerClientEvent('altax:notifyTaxBracket', xPlayer.source, taxBracket.name, taxRate)
    
    -- Hitung pajak penghasilan
    local incomeTax = 0
    if not incomeExempt then
        incomeTax = CalculateIncomeTax(money, taxRate)
    else
        TriggerClientEvent('altax:taxExempt', xPlayer.source, 'income')
    end
    
    -- Hitung pajak properti
    local propertyTax = 0
    if Config.PropertyTaxEnabled and not propertyExempt then
        propertyTax = CalculatePropertyTax(xPlayer)
    elseif Config.PropertyTaxEnabled and propertyExempt then
        TriggerClientEvent('altax:taxExempt', xPlayer.source, 'property')
    end
    
    -- Hitung pajak kendaraan
    local vehicleTax = 0
    local vehicleCountTax = 0
    if Config.VehicleTaxEnabled and not vehicleExempt then
        local vehicleData = CalculateVehicleTax(xPlayer)
        vehicleTax = vehicleData.vehicleTax
        vehicleCountTax = vehicleData.vehicleCountTax
    elseif Config.VehicleTaxEnabled and vehicleExempt then
        TriggerClientEvent('altax:taxExempt', xPlayer.source, 'vehicle')
    end
    
    -- Kurangi dengan insentif pajak
    local incentives = GetPlayerTaxIncentives(xPlayer.identifier)
    local totalIncentives = CalculateTaxIncentives(xPlayer, incentives, incomeTax + propertyTax + vehicleTax + vehicleCountTax)
    
    -- Total pajak setelah insentif
    local totalTax = (incomeTax + propertyTax + vehicleTax + vehicleCountTax) - totalIncentives
    
    -- Cek jika player punya pajak tertunggak
    local overdueAmount = GetOverdueTax(identifier)
    if overdueAmount > 0 then
        -- Periksa apakah ada amnesti pajak aktif
        if IsAmnestyActive() then
            local discountAmount = math.floor(overdueAmount * (Config.TaxAmnestyDiscount / 100))
            overdueAmount = overdueAmount - discountAmount
            TriggerClientEvent('altax:amnestyApplied', xPlayer.source, discountAmount)
        end
        
        totalTax = totalTax + overdueAmount
    end
    
    -- Kirim ringkasan pajak ke player
    TriggerClientEvent('altax:taxSummary', xPlayer.source, {
        incomeTax = incomeTax,
        propertyTax = propertyTax,
        vehicleTax = vehicleTax,
        vehicleCountTax = vehicleCountTax,
        incentives = totalIncentives,
        overdue = overdueAmount,
        total = totalTax
    })
    
    -- Buat receipt ID unik
    local receiptId = GenerateReceiptId(identifier)
    
    -- Coba ambil pajak dari rekening bank
    if money >= totalTax then
        xPlayer.removeAccountMoney('bank', totalTax)
        TriggerClientEvent('altax:taxCollected', xPlayer.source, totalTax, 'bank')
        
        -- Update database
        UpdateTaxRecord(identifier, totalTax, taxBracket.name, taxRate)
        
        -- Record payment
        RecordTaxPayment(identifier, totalTax, 'combined', 'bank', receiptId)
    elseif Config.AllowCashPayment and (money + cash) >= totalTax then
        -- Kurangi dari bank dulu, sisanya dari cash
        local remainingTax = totalTax - money
        
        xPlayer.removeAccountMoney('bank', money)
        xPlayer.removeMoney(remainingTax)
        
        TriggerClientEvent('altax:taxCollectedCash', xPlayer.source, totalTax, money, remainingTax)
        
        -- Update database
        UpdateTaxRecord(identifier, totalTax, taxBracket.name, taxRate)
        
        -- Record payment
        RecordTaxPayment(identifier, totalTax, 'combined', 'mixed', receiptId)
    else
        -- Tidak cukup uang untuk bayar pajak
        TriggerClientEvent('altax:notEnoughMoney', xPlayer.source, totalTax, money)
        
        -- Update overdue amount
        AddOverdueTax(identifier, totalTax)
    end
    
    -- Transfer pajak ke akun pemerintah
    local governmentAccount = Config.TaxRevenueAccount
    if governmentAccount and totalTax > 0 then
        TriggerEvent('esx_addonaccount:getSharedAccount', governmentAccount, function(account)
            if account then
                account.addMoney(totalTax)
                -- Distribusi pendapatan pajak jika diinginkan
                DistributeTaxRevenue(totalTax)
            end
        end)
    end
end

-- Hitung pajak penghasilan
function CalculateIncomeTax(money, taxRate)
    if money < Config.MinimumTaxableIncome then
        return 0 -- Tidak ada pajak untuk pendapatan di bawah minimum
    end
    
    local taxAmount = math.floor(money * (taxRate / 100))
    return taxAmount
end

-- Dapatkan tax bracket berdasarkan jumlah uang
function GetTaxBracket(money)
    for _, bracket in ipairs(Config.IncomeTaxBrackets) do
        if money >= bracket.minMoney and money <= bracket.maxMoney then
            return bracket
        end
    end
    
    -- Default ke bracket terakhir jika uang melebihi semua bracket
    return Config.IncomeTaxBrackets[#Config.IncomeTaxBrackets]
end

-- Hitung pajak properti
function CalculatePropertyTax(xPlayer)
    local identifier = xPlayer.identifier
    local totalPropertyTax = 0
    
    -- Get owned properties dari database (sesuaikan dengan sistem properti yang digunakan)
    local properties = MySQL.query.await('SELECT * FROM altax_property_tax WHERE owner = ?', {
        identifier
    })
    
    if properties and #properties > 0 then
        for _, property in ipairs(properties) do
            local propertyType = property.property_type
            local propertyValue = property.property_value
            local taxMultiplier = Config.PropertyTypes[propertyType] and Config.PropertyTypes[propertyType].taxMultiplier or 1.0
            
            -- Hitung pajak untuk properti ini
            local propertyTaxAmount = math.floor(propertyValue * (Config.PropertyTaxRate / 100) * taxMultiplier)
            totalPropertyTax = totalPropertyTax + propertyTaxAmount
            
            -- Update tanggal pajak terakhir
            MySQL.update('UPDATE altax_property_tax SET last_tax_date = NOW() WHERE id = ?', {
                property.id
            })
        end
    end
    
    return totalPropertyTax
end

-- Hitung pajak properti untuk player offline
function CalculateOfflinePropertyTax(identifier)
    local totalPropertyTax = 0
    
    -- Get owned properties dari database
    local properties = MySQL.query.await('SELECT * FROM altax_property_tax WHERE owner = ?', {
        identifier
    })
    
    if properties and #properties > 0 then
        for _, property in ipairs(properties) do
            local propertyType = property.property_type
            local propertyValue = property.property_value
            local taxMultiplier = Config.PropertyTypes[propertyType] and Config.PropertyTypes[propertyType].taxMultiplier or 1.0
            
            -- Hitung pajak untuk properti ini
            local propertyTaxAmount = math.floor(propertyValue * (Config.PropertyTaxRate / 100) * taxMultiplier)
            totalPropertyTax = totalPropertyTax + propertyTaxAmount
            
            -- Update tanggal pajak terakhir
            MySQL.update('UPDATE altax_property_tax SET last_tax_date = NOW() WHERE id = ?', {
                property.id
            })
        end
    end
    
    return totalPropertyTax
end

-- Hitung pajak kendaraan
function CalculateVehicleTax(xPlayer)
    local identifier = xPlayer.identifier
    local totalVehicleTax = 0
    local vehicleCount = 0
    
    -- Get owned vehicles dari database
    local vehicles = MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', {
        identifier
    })
    
    if vehicles and #vehicles > 0 then
        vehicleCount = #vehicles
        
        for _, vehicle in ipairs(vehicles) do
            -- Get vehicle data dari altax_vehicle_tax
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
                
                -- Skip jika kendaraan exempt dari pajak
                if not isExempt then
                    -- Tentukan vehicle class dari model (perlu function terpisah)
                    local vehClass = GetVehicleClassFromModel(vehicleModel)
                    local classMultiplier = Config.VehicleClasses[vehClass] and Config.VehicleClasses[vehClass].taxMultiplier or 1.0
                    
                    -- Hitung umur kendaraan untuk diskon
                    local vehicleAge = CalculateVehicleAge(purchaseDate)
                    local ageDiscount = math.min(0.5, vehicleAge * Config.VehicleAgeTaxDiscount) -- Max 50% discount
                    
                    -- Hitung pajak dasar
                    local baseTax = math.floor(purchasePrice * (Config.VehicleTaxBaseRate / 100))
                    
                    -- Terapkan multipliers and discounts
                    local finalTax = math.floor(baseTax * classMultiplier * taxMultiplier * (1 - ageDiscount))
                    
                    totalVehicleTax = totalVehicleTax + finalTax
                    
                    -- Update tanggal pajak terakhir
                    MySQL.update('UPDATE altax_vehicle_tax SET last_tax_date = NOW() WHERE plate = ?', {
                        vehicle.plate
                    })
                end
            end
        end
    end
    
    -- Hitung pajak tambahan berdasarkan jumlah kendaraan
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

-- Hitung pajak kendaraan untuk player offline
function CalculateOfflineVehicleTax(identifier)
    local totalVehicleTax = 0
    local vehicleCount = 0
    
    -- Get owned vehicles dari database
    local vehicles = MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', {
        identifier
    })
    
    if vehicles and #vehicles > 0 then
        vehicleCount = #vehicles
        
        for _, vehicle in ipairs(vehicles) do
            -- Get vehicle data dari altax_vehicle_tax
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
                
                -- Skip jika kendaraan exempt dari pajak
                if not isExempt then
                    -- Tentukan vehicle class dari model
                    local vehClass = GetVehicleClassFromModel(vehicleModel)
                    local classMultiplier = Config.VehicleClasses[vehClass] and Config.VehicleClasses[vehClass].taxMultiplier or 1.0
                    
                    -- Hitung umur kendaraan untuk diskon
                    local vehicleAge = CalculateVehicleAge(purchaseDate)
                    local ageDiscount = math.min(0.5, vehicleAge * Config.VehicleAgeTaxDiscount) -- Max 50% discount
                    
                    -- Hitung pajak dasar
                    local baseTax = math.floor(purchasePrice * (Config.VehicleTaxBaseRate / 100))
                    
                    -- Terapkan multipliers and discounts
                    local finalTax = math.floor(baseTax * classMultiplier * taxMultiplier * (1 - ageDiscount))
                    
                    totalVehicleTax = totalVehicleTax + finalTax
                    
                    -- Update tanggal pajak terakhir
                    MySQL.update('UPDATE altax_vehicle_tax SET last_tax_date = NOW() WHERE plate = ?', {
                        vehicle.plate
                    })
                end
            end
        end
    end
    
    -- Hitung pajak tambahan berdasarkan jumlah kendaraan
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

-- Fungsi bantuan untuk tax calculations
function CalculateVehicleAge(purchaseDate)
    local purchaseTimestamp = os.time(os.date('*t', purchaseDate))
    local currentTimestamp = os.time()
    local ageInSeconds = currentTimestamp - purchaseTimestamp
    local ageInYears = ageInSeconds / (365.25 * 24 * 60 * 60)
    
    return math.floor(ageInYears)
end

function GetVehicleClassFromModel(model)
    -- Implementasi ini harus disesuaikan dengan cara server menyimpan kelas kendaraan
    -- Ini hanyalah contoh sederhana
    
    -- Assumed format: e.g. "adder" or "t20" (common vehicle model names)
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
    
    -- Model to lowercase for consistent comparison
    model = string.lower(model)
    
    -- Check vehicle class
    if sportsCars[model] then return 6 -- Sports
    elseif suv[model] then return 2 -- SUVs
    elseif sedans[model] then return 1 -- Sedans
    else return 1 -- Default to sedans if unknown
    end
end

-- Helper functions for tax incentives
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
    
    -- Calculate incentives
    if incentives.charityDonation then
        local charityAmount = incentives.charityDonation
        local deduction = math.min(
            charityAmount * Config.TaxIncentives.charityDonation.multiplier,
            Config.TaxIncentives.charityDonation.maxDeduction
        )
        totalDeduction = totalDeduction + deduction
        
        -- Notify player about the incentive
        TriggerClientEvent('altax:incentiveApplied', xPlayer.source, 'charity_donation', deduction)
    end
    
    if incentives.greenVehicle then
        local greenDeduction = math.floor(baseTax * (Config.TaxIncentives.greenVehicle.deduction / 100))
        totalDeduction = totalDeduction + greenDeduction
        
        -- Notify player about the incentive
        TriggerClientEvent('altax:incentiveApplied', xPlayer.source, 'green_vehicle', greenDeduction)
    end
    
    if incentives.policeCooperation then
        local policeDeduction = math.floor(baseTax * (Config.TaxIncentives.policeCooperation.deduction / 100))
        totalDeduction = totalDeduction + policeDeduction
        
        -- Notify player about the incentive
        TriggerClientEvent('altax:incentiveApplied', xPlayer.source, 'police_cooperation', policeDeduction)
    end
    
    return totalDeduction
end

-- Helper functions for overdue tax
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
    
    -- Tambahkan denda jika overdue sudah ada sebelumnya
    local result = MySQL.query.await('SELECT overdue_amount FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 and result[1].overdue_amount > amount then
        -- Ini berarti sudah ada pajak tertunggak sebelumnya, tambahkan late fee
        local lateFee = math.floor(amount * (Config.LateFeePercentage / 100))
        
        MySQL.update('UPDATE altax_records SET late_fees = late_fees + ? WHERE identifier = ?', {
            lateFee,
            identifier
        })
    end
end

function UpdateOverdueTax(identifier, amount)
    -- Cek apakah player sudah ada di database
    local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        -- Update jumlah tertunggak
        MySQL.update('UPDATE altax_records SET overdue_amount = overdue_amount + ? WHERE identifier = ?', {
            amount,
            identifier
        })
    else
        -- Buat record baru
        MySQL.insert('INSERT INTO altax_records (identifier, overdue_amount) VALUES (?, ?)', {
            identifier,
            amount
        })
    end
    
    -- Update next tax date
    UpdateNextTaxDate(identifier)
end

-- Database helper functions
function UpdateTaxRecord(identifier, amount, taxBracket, taxRate)
    -- Check if player already has a record
    local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        -- Update existing record
        MySQL.update('UPDATE altax_records SET last_tax_date = NOW(), next_tax_date = DATE_ADD(NOW(), INTERVAL ? DAY), total_tax_paid = total_tax_paid + ?, tax_bracket = ?, tax_rate = ?, overdue_amount = 0, late_fees = 0 WHERE identifier = ?', {
            Config.TaxInterval,
            amount,
            taxBracket,
            taxRate,
            identifier
        })
    else
        -- Create new record
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

-- Distribusi pendapatan pajak
function DistributeTaxRevenue(amount)
    if not Config.TaxDistribution then return end
    
    for account, percentage in pairs(Config.TaxDistribution) do
        if account ~= 'government' then -- Government already got full amount initially
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

-- Job exemption helper
function IsJobExemptFromTax(job, taxType)
    if Config.ExemptJobs[job] and Config.ExemptJobs[job][taxType] then
        return true
    end
    return false
end

-- Utility to calculate total tax
function CalculateTotalTax(xPlayer)
    local money = xPlayer.getAccount('bank').money
    local taxBracket = GetTaxBracket(money)
    local incomeTax = CalculateIncomeTax(money, taxBracket.taxRate)
    local propertyTax = Config.PropertyTaxEnabled and CalculatePropertyTax(xPlayer) or 0
    
    local vehicleTaxData = Config.VehicleTaxEnabled and CalculateVehicleTax(xPlayer) or { vehicleTax = 0, vehicleCountTax = 0 }
    local vehicleTax = vehicleTaxData.vehicleTax
    local vehicleCountTax = vehicleTaxData.vehicleCountTax
    
    -- Juga dapatkan pajak tertunggak
    local overdueAmount = GetOverdueTax(xPlayer.identifier)
    
    return incomeTax + propertyTax + vehicleTax + vehicleCountTax + overdueAmount
end

-- Send SMS notification
function SendTaxSMS(target, message)
    TriggerClientEvent('altax:sendSMS', target, Config.TaxServiceNumber, message)
end

-- Setup event handlers
function SetupEventHandlers()
    -- When player joins server, check if they need to pay taxes
    AddEventHandler('esx:playerLoaded', function(source, xPlayer)
        Citizen.Wait(10000) -- Wait 10 seconds to make sure everything is loaded
        
        local identifier = xPlayer.identifier
        
        -- Check for overdue tax
        local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ? AND overdue_amount > 0', {
            identifier
        })
        
        if result and #result > 0 then
            local overdueAmount = result[1].overdue_amount + (result[1].late_fees or 0)
            
            -- Inform player about overdue tax
            TriggerClientEvent('altax:overdueNotice', source, overdueAmount)
            
            -- Check if amnesty is active
            if IsAmnestyActive() then
                TriggerClientEvent('altax:amnestyAvailable', source, Config.TaxAmnestyDiscount)
            end
        end
        
        -- Get next tax date
        local taxDateResult = MySQL.query.await('SELECT next_tax_date FROM altax_records WHERE identifier = ?', {
            identifier
        })
        
        if taxDateResult and #taxDateResult > 0 then
            TriggerClientEvent('altax:nextTaxDate', source, taxDateResult[1].next_tax_date)
        end
    end)
    
    -- When player buys vehicle, register it for tax
    AddEventHandler('esx_vehicleshop:setVehicleOwned', function(source, vehicleProps, vehiclePrice, model)
        RegisterVehicleForTax(source, vehicleProps, vehiclePrice, model)
    end)
    
    -- When player buys property, register it for tax
    AddEventHandler('esx_property:bought', function(source, propertyId, price, propertyType)
        RegisterPropertyForTax(source, propertyId, price, propertyType or 'apartment')
    end)
    
    -- Tax incentive events
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

-- Add tax incentive
function AddTaxIncentive(source, incentiveType, value)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    
    -- Get current incentives
    local results = MySQL.query.await('SELECT tax_incentives FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    local incentives = {}
    if results and #results > 0 and results[1].tax_incentives then
        incentives = json.decode(results[1].tax_incentives)
    end
    
    -- Add or update incentive
    if incentiveType == 'charityDonation' then
        incentives.charityDonation = (incentives.charityDonation or 0) + value
    elseif incentiveType == 'greenVehicle' then
        incentives.greenVehicle = true
    elseif incentiveType == 'policeCooperation' then
        incentives.policeCooperation = true
    end
    
    -- Save to database
    MySQL.update('UPDATE altax_records SET tax_incentives = ? WHERE identifier = ?', {
        json.encode(incentives),
        identifier
    })
    
    if not results or #results == 0 then
        -- Insert new record if it doesn't exist
        MySQL.insert('INSERT INTO altax_records (identifier, tax_incentives) VALUES (?, ?)', {
            identifier,
            json.encode(incentives)
        })
    end
    
    TriggerClientEvent('altax:incentiveAdded', source, incentiveType)
end

-- Register vehicle for tax
function RegisterVehicleForTax(source, vehicleProps, vehiclePrice, model)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    local plate = vehicleProps.plate
    
    -- Cek apakah kendaraan sudah terdaftar
    local vehCheck = MySQL.query.await('SELECT * FROM altax_vehicle_tax WHERE plate = ?', {
        plate
    })
    
    if vehCheck and #vehCheck > 0 then
        -- Update data kendaraan
        MySQL.update('UPDATE altax_vehicle_tax SET owner = ?, vehicle_model = ?, purchase_price = ?, purchase_date = NOW() WHERE plate = ?', {
            identifier,
            model,
            vehiclePrice,
            plate
        })
    else
        -- Tambahkan kendaraan baru
        MySQL.insert('INSERT INTO altax_vehicle_tax (plate, owner, vehicle_model, purchase_price, purchase_date) VALUES (?, ?, ?, ?, NOW())', {
            plate,
            identifier,
            model,
            vehiclePrice
        })
    end
end

-- Register property for tax
function RegisterPropertyForTax(source, propertyId, price, propertyType)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    
    -- Cek apakah properti sudah terdaftar
    local propCheck = MySQL.query.await('SELECT * FROM altax_property_tax WHERE property_id = ?', {
        propertyId
    })
    
    if propCheck and #propCheck > 0 then
        -- Update data properti
        MySQL.update('UPDATE altax_property_tax SET owner = ?, property_value = ?, property_type = ?, purchase_date = NOW() WHERE property_id = ?', {
            identifier,
            price,
            propertyType,
            propertyId
        })
    else
        -- Tambahkan properti baru
        MySQL.insert('INSERT INTO altax_property_tax (property_id, owner, property_value, property_type, purchase_date) VALUES (?, ?, ?, ?, NOW())', {
            propertyId,
            identifier,
            price,
            propertyType
        })
    end
end

-- Check if amnesty is active
function IsAmnestyActive()
    if not Config.TaxAmnestyEnabled then
        return false
    end
    
    -- Check if there's an active amnesty program record
    local result = MySQL.query.await('SELECT * FROM altax_amnesty WHERE start_date <= NOW() AND end_date >= NOW() AND active = 1 LIMIT 1')
    
    return result and #result > 0
end

-- Export functions for other resources
exports('CalculatePlayerTax', CalculateTotalTax)
exports('ProcessTax', CollectPlayerTax)
exports('AddTaxIncentive', AddTaxIncentive)
exports('RegisterVehicleForTax', RegisterVehicleForTax)
exports('RegisterPropertyForTax', RegisterPropertyForTax)