local ESX = exports['es_extended']:getSharedObject()

ESX.RegisterCommand('tax', 'admin', function(xPlayer, args, showError)
    local action = args.action
    
    if action == 'info' then
        local targetId = args.playerId
        
        if not targetId then
            showError('Player ID diperlukan')
            return
        end
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        if not xTarget then
            showError('Player tidak ditemukan')
            return
        end
        
        GetPlayerTaxInfo(xPlayer, xTarget)
    elseif action == 'set' then
        local targetId = args.playerId
        local taxType = args.taxType
        local amount = args.amount
        
        if not targetId or not taxType or not amount then
            showError('Semua parameter diperlukan: playerId, taxType, amount')
            return
        end
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        if not xTarget then
            showError('Player tidak ditemukan')
            return
        end
        
        SetPlayerTax(xPlayer, xTarget, taxType, amount)
    elseif action == 'exempt' then
        local targetId = args.playerId
        local taxType = args.taxType
        
        if not targetId or not taxType then
            showError('Player ID dan tax type diperlukan')
            return
        end
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        if not xTarget then
            showError('Player tidak ditemukan')
            return
        end
        
        ExemptPlayerFromTax(xPlayer, xTarget, taxType)
    elseif action == 'collect' then
        local targetId = args.playerId
        
        if not targetId then
            showError('Player ID diperlukan')
            return
        end
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        if not xTarget then
            showError('Player tidak ditemukan')
            return
        end
        
        CollectPlayerTaxManually(xPlayer, xTarget)
    elseif action == 'incentive' then
        local targetId = args.playerId
        local incentiveType = args.incentiveType
        local value = args.value
        
        if not targetId or not incentiveType then
            showError('Player ID dan incentive type diperlukan')
            return
        end
        
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        if not xTarget then
            showError('Player tidak ditemukan')
            return
        end
        
        AddTaxIncentiveManually(xPlayer, xTarget, incentiveType, value)
    elseif action == 'stats' then
        ShowTaxStats(xPlayer)
    else
        showError('Tindakan tidak valid. Gunakan: info, set, exempt, collect, incentive, stats')
    end
end, true, {help = 'Manajemen pajak player', validate = true, arguments = {
    {name = 'action', help = 'Tindakan: info, set, exempt, collect, incentive, stats', type = 'string'},
    {name = 'playerId', help = 'ID Player', type = 'number', optional = true},
    {name = 'taxType', help = 'Tipe pajak: income, property, vehicle, all', type = 'string', optional = true},
    {name = 'amount', help = 'Jumlah atau persentase', type = 'number', optional = true},
    {name = 'incentiveType', help = 'Tipe insentif: charity, green, police', type = 'string', optional = true},
    {name = 'value', help = 'Nilai untuk insentif', type = 'any', optional = false}
}})

ESX.RegisterCommand('mytax', 'user', function(xPlayer, args, showError)
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
        local money = xPlayer.getAccount('bank').money
        local estimatedTax = math.floor(money * (taxRate / 100))
        local nextTaxDateFormatted = os.date('%d/%m/%Y', ConvertMySQLTimeToTimestamp(nextTaxDate))
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 255, 0},
            multiline = true,
            args = {'[ALTAX]', 'Informasi Pajak Anda:\n' ..
                   'Kategori: ' .. taxBracket .. ' (' .. taxRate .. '%)\n' ..
                   'Total Pajak Dibayar: $' .. ESX.Math.GroupDigits(totalPaid) .. '\n' ..
                   'Estimasi Pajak Berikutnya: $' .. ESX.Math.GroupDigits(estimatedTax) .. '\n' ..
                   'Pajak Tertunggak: $' .. ESX.Math.GroupDigits(overdueAmount + lateFees) .. '\n' ..
                   'Tanggal Pajak Berikutnya: ' .. nextTaxDateFormatted}
        })
        
        GetPlayerVehicleTaxInfo(xPlayer)
        
        GetPlayerPropertyTaxInfo(xPlayer)
    else
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 0, 0},
            args = {'[ALTAX]', 'Anda belum memiliki catatan pajak.'}
        })
    end
end, false, {help = 'Lihat informasi pajak Anda'})
ESX.RegisterCommand('paytax', 'user', function(xPlayer, args, showError)
    local identifier = xPlayer.identifier
    local result = MySQL.query.await('SELECT overdue_amount, late_fees FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        local overdueAmount = result[1].overdue_amount or 0
        local lateFees = result[1].late_fees or 0
        local totalOverdue = overdueAmount + lateFees
        
        if totalOverdue <= 0 then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {0, 255, 0},
                args = {'[ALTAX]', 'Anda tidak memiliki pajak tertunggak.'}
            })
            return
        end
        local amnestyDiscount = 0
        if exports.altax:IsAmnestyActive() then
            amnestyDiscount = exports.altax:GetAmnestyDiscount()
            
            if amnestyDiscount > 0 then
                local discountAmount = math.floor(totalOverdue * (amnestyDiscount / 100))
                totalOverdue = totalOverdue - discountAmount
                
                TriggerClientEvent('chat:addMessage', xPlayer.source, {
                    color = {0, 255, 0},
                    args = {'[ALTAX]', 'Program Amnesti Pajak aktif! Anda mendapatkan diskon ' .. amnestyDiscount .. '% ($' .. ESX.Math.GroupDigits(discountAmount) .. ')'}
                })
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
                exports.altax:RecordAmnestyUsage(identifier, overdueAmount + lateFees, totalOverdue - (overdueAmount + lateFees))
            end
            
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {0, 255, 0},
                args = {'[ALTAX]', 'Pajak tertunggak sebesar $' .. ESX.Math.GroupDigits(totalOverdue) .. ' telah dibayar.'}
            })
        else
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Anda tidak memiliki cukup uang untuk membayar pajak tertunggak sebesar $' .. ESX.Math.GroupDigits(totalOverdue)}
            })
        end
    else
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 0, 0},
            args = {'[ALTAX]', 'Anda tidak memiliki catatan pajak.'}
        })
    end
end, false, {help = 'Bayar pajak tertunggak'})

ESX.RegisterCommand('processtax', 'admin', function(xPlayer, args, showError)
    local targetId = args.playerId
    
    if targetId then
        local xTarget = ESX.GetPlayerFromId(targetId)
        
        if not xTarget then
            showError('Player tidak ditemukan')
            return
        end
        
        CollectPlayerTaxManually(xPlayer, xTarget)
    else
        local onlinePlayers = ESX.GetPlayers()
        
        if #onlinePlayers == 0 then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Tidak ada player online.'}
            })
            return
        end
        
        local processedCount = 0
        
        for _, playerId in ipairs(onlinePlayers) do
            local xTarget = ESX.GetPlayerFromId(playerId)
            
            if xTarget then
                exports.altax:ProcessTax(xTarget)
                processedCount = processedCount + 1
            end
        end
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Pajak telah diproses untuk ' .. processedCount .. ' player.'}
        })
    end
end, true, {help = 'Proses pajak untuk semua player atau player tertentu', validate = true, arguments = {
    {name = 'playerId', help = 'ID Player (opsional)', type = 'number', optional = true}
}})


function GetPlayerTaxInfo(xAdmin, xTarget)
    local identifier = xTarget.identifier
    
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
        local incentives = taxRecord.tax_incentives
        
        local nextTaxDateFormatted = os.date('%d/%m/%Y', ConvertMySQLTimeToTimestamp(nextTaxDate))
        
        local vehicleCount = exports.altax:GetPlayerVehicleCount(identifier)
        
        local propertyCount = GetPlayerPropertyCount(identifier)
        
        local money = xTarget.getAccount('bank').money
        local cash = xTarget.getMoney()
        local estimatedTax = exports.altax:CalculatePlayerTax(xTarget)
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {255, 255, 0},
            multiline = true,
            args = {'[ALTAX]', 'Informasi Pajak untuk ' .. GetPlayerName(xTarget.source) .. ':\n' ..
                   'Kategori: ' .. taxBracket .. ' (' .. taxRate .. '%)\n' ..
                   'Uang di Bank: $' .. ESX.Math.GroupDigits(money) .. '\n' ..
                   'Uang Tunai: $' .. ESX.Math.GroupDigits(cash) .. '\n' ..
                   'Total Pajak Dibayar: $' .. ESX.Math.GroupDigits(totalPaid) .. '\n' ..
                   'Kendaraan: ' .. vehicleCount .. '\n' ..
                   'Properti: ' .. propertyCount .. '\n' ..
                   'Pajak Tertunggak: $' .. ESX.Math.GroupDigits(overdueAmount + lateFees) .. '\n' ..
                   'Estimasi Pajak Berikutnya: $' .. ESX.Math.GroupDigits(estimatedTax) .. '\n' ..
                   'Tanggal Pajak Berikutnya: ' .. nextTaxDateFormatted}
        })
    else
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {255, 0, 0},
            args = {'[ALTAX]', 'Player belum memiliki catatan pajak.'}
        })
    end
end

function SetPlayerTax(xAdmin, xTarget, taxType, amount)
    local identifier = xTarget.identifier
    
    if taxType == 'income' then
        local result = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
            identifier
        })
        
        if result and #result > 0 then
            MySQL.update('UPDATE altax_records SET tax_rate = ? WHERE identifier = ?', {
                amount,
                identifier
            })
            
            TriggerClientEvent('chat:addMessage', xAdmin.source, {
                color = {0, 255, 0},
                args = {'[ALTAX]', 'Tarif pajak penghasilan untuk ' .. GetPlayerName(xTarget.source) .. ' disetel ke ' .. amount .. '%'}
            })
        else
            MySQL.insert('INSERT INTO altax_records (identifier, tax_rate) VALUES (?, ?)', {
                identifier,
                amount
            })
            
            TriggerClientEvent('chat:addMessage', xAdmin.source, {
                color = {0, 255, 0},
                args = {'[ALTAX]', 'Catatan pajak baru dibuat untuk ' .. GetPlayerName(xTarget.source) .. ' dengan tarif ' .. amount .. '%'}
            })
        end
    elseif taxType == 'property' then
        MySQL.update('UPDATE altax_property_tax SET tax_multiplier = ? WHERE owner = ?', {
            amount / 100,
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Pengali pajak properti untuk ' .. GetPlayerName(xTarget.source) .. ' disetel ke ' .. amount .. '%'}
        })
    elseif taxType == 'vehicle' then
        MySQL.update('UPDATE altax_vehicle_tax SET tax_multiplier = ? WHERE owner = ?', {
            amount / 100, 
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Pengali pajak kendaraan untuk ' .. GetPlayerName(xTarget.source) .. ' disetel ke ' .. amount .. '%'}
        })
    elseif taxType == 'overdue' then
        MySQL.update('UPDATE altax_records SET overdue_amount = ? WHERE identifier = ?', {
            amount,
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Jumlah pajak tertunggak untuk ' .. GetPlayerName(xTarget.source) .. ' disetel ke $' .. ESX.Math.GroupDigits(amount)}
        })
    elseif taxType == 'bracket' then
        if amount > 0 and amount <= #Config.IncomeTaxBrackets then
            local bracket = Config.IncomeTaxBrackets[amount]
            
            MySQL.update('UPDATE altax_records SET tax_bracket = ?, tax_rate = ? WHERE identifier = ?', {
                bracket.name,
                bracket.taxRate,
                identifier
            })
            
            TriggerClientEvent('chat:addMessage', xAdmin.source, {
                color = {0, 255, 0},
                args = {'[ALTAX]', 'Kategori pajak untuk ' .. GetPlayerName(xTarget.source) .. ' disetel ke ' .. bracket.name .. ' (' .. bracket.taxRate .. '%)'}
            })
        else
            TriggerClientEvent('chat:addMessage', xAdmin.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Indeks kategori pajak tidak valid. Gunakan 1-' .. #Config.IncomeTaxBrackets}
            })
        end
    elseif taxType == 'next' then
        
        MySQL.update('UPDATE altax_records SET next_tax_date = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE identifier = ?', {
            amount,
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Tanggal pajak berikutnya untuk ' .. GetPlayerName(xTarget.source) .. ' disetel ke ' .. amount .. ' hari dari sekarang'}
        })
    else
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {255, 0, 0},
            args = {'[ALTAX]', 'Tipe pajak tidak valid. Gunakan: income, property, vehicle, overdue, bracket, next'}
        })
    end
end

function ExemptPlayerFromTax(xAdmin, xTarget, taxType)
    local identifier = xTarget.identifier
    
    if taxType == 'income' then
        MySQL.update('UPDATE altax_records SET tax_rate = 0 WHERE identifier = ?', {
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', GetPlayerName(xTarget.source) .. ' dibebaskan dari pajak penghasilan'}
        })
    elseif taxType == 'property' then
        MySQL.update('UPDATE altax_property_tax SET tax_exemption = 1 WHERE owner = ?', {
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', GetPlayerName(xTarget.source) .. ' dibebaskan dari pajak properti'}
        })
    elseif taxType == 'vehicle' then
        MySQL.update('UPDATE altax_vehicle_tax SET tax_exemption = 1 WHERE owner = ?', {
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', GetPlayerName(xTarget.source) .. ' dibebaskan dari pajak kendaraan'}
        })
    elseif taxType == 'all' then
        MySQL.update('UPDATE altax_records SET tax_rate = 0 WHERE identifier = ?', {
            identifier
        })
        
        MySQL.update('UPDATE altax_property_tax SET tax_exemption = 1 WHERE owner = ?', {
            identifier
        })
        
        MySQL.update('UPDATE altax_vehicle_tax SET tax_exemption = 1 WHERE owner = ?', {
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', GetPlayerName(xTarget.source) .. ' dibebaskan dari semua pajak'}
        })
    elseif taxType == 'overdue' then
        MySQL.update('UPDATE altax_records SET overdue_amount = 0, late_fees = 0 WHERE identifier = ?', {
            identifier
        })
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Pajak tertunggak untuk ' .. GetPlayerName(xTarget.source) .. ' telah dihapus'}
        })
    else
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {255, 0, 0},
            args = {'[ALTAX]', 'Tipe pajak tidak valid. Gunakan: income, property, vehicle, all, overdue'}
        })
    end
end

function CollectPlayerTaxManually(xAdmin, xTarget)
    exports.altax:ProcessTax(xTarget)
    
    TriggerClientEvent('chat:addMessage', xAdmin.source, {
        color = {0, 255, 0},
        args = {'[ALTAX]', 'Pajak telah dipungut dari ' .. GetPlayerName(xTarget.source)}
    })
end

function AddTaxIncentiveManually(xAdmin, xTarget, incentiveType, value)
    local identifier = xTarget.identifier
    
    if incentiveType == 'charity' then
        exports.altax:AddTaxIncentive(xTarget.source, 'charityDonation', value or 10000)
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Insentif donasi amal sebesar $' .. ESX.Math.GroupDigits(value or 10000) .. ' ditambahkan untuk ' .. GetPlayerName(xTarget.source)}
        })
    elseif incentiveType == 'green' then
        exports.altax:AddTaxIncentive(xTarget.source, 'greenVehicle', true)
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Insentif kendaraan ramah lingkungan ditambahkan untuk ' .. GetPlayerName(xTarget.source)}
        })
    elseif incentiveType == 'police' then
        exports.altax:AddTaxIncentive(xTarget.source, 'policeCooperation', true)
        
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Insentif kerjasama dengan kepolisian ditambahkan untuk ' .. GetPlayerName(xTarget.source)}
        })
    else
        TriggerClientEvent('chat:addMessage', xAdmin.source, {
            color = {255, 0, 0},
            args = {'[ALTAX]', 'Tipe insentif tidak valid. Gunakan: charity, green, police'}
        })
    end
end

function ShowTaxStats(xAdmin)
    local totalResult = MySQL.query.await('SELECT SUM(total_tax_paid) as total FROM altax_records')
    local totalTaxPaid = totalResult and totalResult[1].total or 0
    
    local bracketCounts = {}
    local brackets = MySQL.query.await('SELECT tax_bracket, COUNT(*) as count FROM altax_records GROUP BY tax_bracket')
    
    if brackets then
        for _, bracket in ipairs(brackets) do
            bracketCounts[bracket.tax_bracket] = bracket.count
        end
    end
    
    local overdueResult = MySQL.query.await('SELECT SUM(overdue_amount) as overdue, SUM(late_fees) as fees FROM altax_records')
    local totalOverdue = (overdueResult and overdueResult[1].overdue or 0) + (overdueResult and overdueResult[1].fees or 0)
    
    local vehicleCount = MySQL.query.await('SELECT COUNT(*) as count FROM altax_vehicle_tax')
    local propertyCount = MySQL.query.await('SELECT COUNT(*) as count FROM altax_property_tax')
    
    local message = 'Statistik Pajak Global:\n' ..
                    'Total Pajak Terkumpul: $' .. ESX.Math.GroupDigits(totalTaxPaid) .. '\n' ..
                    'Total Pajak Tertunggak: $' .. ESX.Math.GroupDigits(totalOverdue) .. '\n' ..
                    'Jumlah Kendaraan Terdaftar: ' .. (vehicleCount and vehicleCount[1].count or 0) .. '\n' ..
                    'Jumlah Properti Terdaftar: ' .. (propertyCount and propertyCount[1].count or 0) .. '\n\n' ..
                    'Pembagian Wajib Pajak:\n'
    
    for _, bracket in ipairs(Config.IncomeTaxBrackets) do
        local count = bracketCounts[bracket.name] or 0
        message = message .. bracket.name .. ': ' .. count .. '\n'
    end
    
    TriggerClientEvent('chat:addMessage', xAdmin.source, {
        color = {255, 255, 0},
        multiline = true,
        args = {'[ALTAX]', message}
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

function GetPlayerPropertyCount(identifier)
    local result = MySQL.query.await('SELECT COUNT(*) as count FROM altax_property_tax WHERE owner = ?', {
        identifier
    })
    
    if result and #result > 0 then
        return result[1].count
    end
    
    return 0
end

function GetPlayerVehicleTaxInfo(xPlayer)
    local identifier = xPlayer.identifier
    
    local vehicles = exports.altax:GetPlayerVehicles(identifier)
    
    if vehicles and #vehicles > 0 then
        local message = 'Informasi Pajak Kendaraan:\n'
        
        for i, vehicle in ipairs(vehicles) do
            if i > 5 then
                message = message .. '... dan ' .. (#vehicles - 5) .. ' kendaraan lainnya\n'
                break
            end
            
            local taxData = exports.altax:GetVehicleTaxData(vehicle.plate)
            
            if taxData then
                local taxAmount = CalculateVehicleTaxAmount(taxData)
                local isExempt = taxData.tax_exemption == 1
                
                message = message .. vehicle.plate .. ' - ' .. 
                          (isExempt and 'Bebas Pajak' or '$' .. ESX.Math.GroupDigits(taxAmount)) .. '\n'
            else
                message = message .. vehicle.plate .. ' - Belum Ada Data Pajak\n'
            end
        end
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 255, 0},
            multiline = true,
            args = {'[ALTAX]', message}
        })
    else
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 255, 0},
            args = {'[ALTAX]', 'Anda tidak memiliki kendaraan terdaftar.'}
        })
    end
end

function GetPlayerPropertyTaxInfo(xPlayer)
    local identifier = xPlayer.identifier
    
    local properties = MySQL.query.await('SELECT * FROM altax_property_tax WHERE owner = ?', {
        identifier
    })
    
    if properties and #properties > 0 then
        local message = 'Informasi Pajak Properti:\n'
        
        for i, property in ipairs(properties) do
            if i > 5 then
                message = message .. '... dan ' .. (#properties - 5) .. ' properti lainnya\n'
                break
            end
            
            local propertyType = property.property_type
            local propertyValue = property.property_value
            local taxMultiplier = property.tax_multiplier
            local isExempt = property.tax_exemption == 1
            
            local taxAmount = 0
            if not isExempt then
                taxAmount = math.floor(propertyValue * (Config.PropertyTaxRate / 100) * taxMultiplier)
            end
            
            message = message .. 'ID: ' .. property.property_id .. ' - ' .. 
                      propertyType .. ' - ' ..
                      (isExempt and 'Bebas Pajak' or '$' .. ESX.Math.GroupDigits(taxAmount)) .. '\n'
        end
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 255, 0},
            multiline = true,
            args = {'[ALTAX]', message}
        })
    else
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {255, 255, 0},
            args = {'[ALTAX]', 'Anda tidak memiliki properti terdaftar.'}
        })
    end
end

function CalculateVehicleTaxAmount(taxData)
    if not taxData or taxData.tax_exemption == 1 then
        return 0
    end
    
    local purchasePrice = taxData.purchase_price or 0
    local taxMultiplier = taxData.tax_multiplier or 1.0
    
    local vehicleModel = taxData.vehicle_model
    local vehClass = GetVehicleClassFromModel(vehicleModel)
    local classMultiplier = Config.VehicleClasses[vehClass] and Config.VehicleClasses[vehClass].taxMultiplier or 1.0
    
    local purchaseDate = taxData.purchase_date
    local vehicleAge = CalculateVehicleAge(purchaseDate)
    local ageDiscount = math.min(0.5, vehicleAge * Config.VehicleAgeTaxDiscount) -- Max 50% discount
    
    local baseTax = math.floor(purchasePrice * (Config.VehicleTaxBaseRate / 100))
    local finalTax = math.floor(baseTax * classMultiplier * taxMultiplier * (1 - ageDiscount))
    
    return finalTax
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
    
    model = string.lower(tostring(model))
    
    -- Check vehicle class
    if sportsCars[model] then return 6 
    elseif suv[model] then return 2 
    elseif sedans[model] then return 1 
    else return 1 
    end
end
