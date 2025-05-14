RegisterServerCallback('altax:getOwnedVehicles', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then 
        cb({})
        return
    end
    
    local vehicles = MySQL.query.await('SELECT ov.*, avt.tax_class, avt.tax_multiplier, avt.tax_exemption FROM owned_vehicles ov LEFT JOIN altax_vehicle_tax avt ON ov.plate = avt.plate WHERE ov.owner = ?', {
        xPlayer.identifier
    })
    
    cb(vehicles or {})
end)

RegisterServerEvent('altax:registerGreenVehicle')
AddEventHandler('altax:registerGreenVehicle', function(plate)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local registrationFee = 5000
    
    if xPlayer.getAccount('bank').money < registrationFee then
        TriggerClientEvent('esx:showNotification', source, 'Anda tidak memiliki cukup uang untuk mendaftarkan kendaraan ramah lingkungan')
        return
    end
    
    local vehicle = MySQL.query.await('SELECT * FROM owned_vehicles WHERE plate = ? AND owner = ?', {
        plate,
        xPlayer.identifier
    })
    
    if not vehicle or #vehicle == 0 then
        TriggerClientEvent('esx:showNotification', source, 'Kendaraan tidak ditemukan atau bukan milik Anda')
        return
    end
    
    xPlayer.removeAccountMoney('bank', registrationFee)
    
    MySQL.update('UPDATE owned_vehicles SET is_green = 1 WHERE plate = ?', {
        plate
    })
    
    TriggerEvent('altax:addGreenVehicleIncentive', source)
    
    TriggerClientEvent('esx:showNotification', source, 'Kendaraan ' .. plate .. ' telah terdaftar sebagai ramah lingkungan')
end)

RegisterServerEvent('altax:checkTaxStatus')
AddEventHandler('altax:checkTaxStatus', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    
    local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        local taxRecord = result[1]
        local taxBracket = taxRecord.tax_bracket
        local taxRate = taxRecord.tax_rate
        local totalPaid = taxRecord.total_tax_paid
        local overdueAmount = taxRecord.overdue_amount or 0
        local lateFees = taxRecord.late_fees or 0
        local nextTaxDate = taxRecord.next_tax_date
        
        local estimatedTax = exports.altax:CalculatePlayerTax(xPlayer)
        
        local nextTaxDateFormatted = os.date('%d/%m/%Y', ConvertMySQLTimeToTimestamp(nextTaxDate))
        
        local message = 'Informasi Pajak Anda:\n' ..
                       'Kategori: ' .. taxBracket .. ' (' .. taxRate .. '%)\n' ..
                       'Total Pajak Dibayar: $' .. ESX.Math.GroupDigits(totalPaid) .. '\n' ..
                       'Estimasi Pajak Berikutnya: $' .. ESX.Math.GroupDigits(estimatedTax) .. '\n' ..
                       'Pajak Tertunggak: $' .. ESX.Math.GroupDigits(overdueAmount + lateFees) .. '\n' ..
                       'Tanggal Pajak Berikutnya: ' .. nextTaxDateFormatted
        
        TriggerClientEvent('esx:showAdvancedNotification', source, 'Direktorat Pajak', 'Status Pajak', message, 'CHAR_BANK_MAZE', 9)
    else
        TriggerClientEvent('esx:showNotification', source, 'Anda belum memiliki catatan pajak')
    end
end)

RegisterServerEvent('altax:payOverdueTax')
AddEventHandler('altax:payOverdueTax', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    
    local result = MySQL.query.await('SELECT overdue_amount, late_fees FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        local overdueAmount = result[1].overdue_amount or 0
        local lateFees = result[1].late_fees or 0
        local totalOverdue = overdueAmount + lateFees
        
        if totalOverdue <= 0 then
            TriggerClientEvent('esx:showNotification', source, 'Anda tidak memiliki pajak tertunggak')
            return
        end
        
        local amnestyDiscount = 0
        if exports.altax:IsAmnestyActive() then
            amnestyDiscount = exports.altax:GetAmnestyDiscount()
            
            if amnestyDiscount > 0 then
                local discountAmount = math.floor(totalOverdue * (amnestyDiscount / 100))
                totalOverdue = totalOverdue - discountAmount
                
                TriggerClientEvent('esx:showNotification', source, 'Program Amnesti Pajak aktif! Anda mendapatkan diskon ' .. amnestyDiscount .. '% ($' .. ESX.Math.GroupDigits(discountAmount) .. ')')
            end
        end
        
        local money = xPlayer.getAccount('bank').money
        
        if money >= totalOverdue then
            xPlayer.removeAccountMoney('bank', totalOverdue)
            
            MySQL.update('UPDATE altax_records SET overdue_amount = 0, late_fees = 0 WHERE identifier = ?', {
                identifier
            })
            
            local receiptId = GenerateReceiptId(identifier)
            RecordTaxPayment(identifier, totalOverdue, 'overdue', 'bank', receiptId)
            
            local governmentAccount = Config.TaxRevenueAccount
            if governmentAccount then
                TriggerEvent('esx_addonaccount:getSharedAccount', governmentAccount, function(account)
                    if account then
                        account.addMoney(totalOverdue)
                    end
                end)
            end
            
            if amnestyDiscount > 0 then
                exports.altax:RecordAmnestyUsage(identifier, overdueAmount + lateFees, overdueAmount + lateFees - totalOverdue)
            end
            
            TriggerClientEvent('esx:showNotification', source, 'Pajak tertunggak sebesar $' .. ESX.Math.GroupDigits(totalOverdue) .. ' telah dibayar')
            
            TriggerClientEvent('altax:showReceipt', source, {
                id = receiptId,
                date = os.date('%Y-%m-%d %H:%M:%S'),
                amount = totalOverdue,
                type = 'Overdue Tax',
                method = 'bank'
            })
        else
            TriggerClientEvent('esx:showNotification', source, 'Anda tidak memiliki cukup uang untuk membayar pajak tertunggak sebesar $' .. ESX.Math.GroupDigits(totalOverdue))
        end
    else
        TriggerClientEvent('esx:showNotification', source, 'Anda tidak memiliki catatan pajak')
    end
end)

RegisterServerEvent('altax:getPaymentHistory')
AddEventHandler('altax:getPaymentHistory', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    
    local payments = MySQL.query.await('SELECT * FROM altax_payments WHERE identifier = ? ORDER BY payment_date DESC LIMIT 10', {
        identifier
    })
    
    TriggerClientEvent('altax:receivePaymentHistory', source, payments or {})
end)

RegisterServerEvent('altax:checkAmnestyStatus')
AddEventHandler('altax:checkAmnestyStatus', function()
    local source = source
    
    if exports.altax:IsAmnestyActive() then
        local amnestyInfo = exports.altax:GetActiveAmnestyInfo()
        
        if amnestyInfo then
            local message = 'Program Amnesti Pajak Aktif!\n' ..
                           'Nama: ' .. amnestyInfo.name .. '\n' ..
                           'Diskon: ' .. amnestyInfo.discount_percentage .. '%\n' ..
                           'Berakhir: ' .. os.date('%d/%m/%Y', ConvertMySQLTimeToTimestamp(amnestyInfo.end_date))
            
            TriggerClientEvent('esx:showAdvancedNotification', source, 'Direktorat Pajak', 'Program Amnesti Pajak', message, 'CHAR_BANK_MAZE', 2)
        end
    else
        TriggerClientEvent('esx:showNotification', source, 'Tidak ada program amnesti pajak yang aktif saat ini')
    end
end)

RegisterServerEvent('altax:registerPlayer')
AddEventHandler('altax:registerPlayer', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    
    local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if not result or #result == 0 then
        local money = xPlayer.getAccount('bank').money
        local taxBracket = GetTaxBracket(money)
        
        MySQL.insert('INSERT INTO altax_records (identifier, next_tax_date, tax_bracket, tax_rate) VALUES (?, DATE_ADD(NOW(), INTERVAL ? DAY), ?, ?)', {
            identifier,
            Config.TaxInterval,
            taxBracket.name,
            taxBracket.taxRate
        })
        
        if Config.Debug then
            print('[ALTAX] New tax record created for ' .. GetPlayerName(source))
        end
    else
        if Config.Debug then
            print('[ALTAX] Player ' .. GetPlayerName(source) .. ' already has a tax record')
        end
    end
end)

function GenerateReceiptId(identifier)
    local timestamp = os.time()
    local randomPart = math.random(10000, 99999)
    return string.format('TX-%s-%d-%d', string.sub(identifier, -5), timestamp, randomPart)
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

function ConvertMySQLTimeToTimestamp(mysqlTime)
    local pattern = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = mysqlTime:match(pattern)
    
    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = min,
        sec = sec
    })
end

function GetTaxBracket(money)
    for _, bracket in ipairs(Config.IncomeTaxBrackets) do
        if money >= bracket.minMoney and money <= bracket.maxMoney then
            return bracket
        end
    end
    
    return Config.IncomeTaxBrackets[#Config.IncomeTaxBrackets]
end
