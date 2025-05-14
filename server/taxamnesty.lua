
local ESX = exports['es_extended']:getSharedObject()
local activeAmnesty = nil


Citizen.CreateThread(function()
    InitializeAmnestySystem()
end)

function InitializeAmnestySystem()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `altax_amnesty` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `name` varchar(100) NOT NULL,
            `description` text DEFAULT NULL,
            `discount_percentage` int(11) NOT NULL DEFAULT 50,
            `start_date` timestamp NOT NULL DEFAULT current_timestamp(),
            `end_date` timestamp NOT NULL DEFAULT current_timestamp(),
            `active` tinyint(1) NOT NULL DEFAULT 1,
            `created_by` varchar(60) DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    

    local result = MySQL.query.await('SELECT * FROM altax_amnesty WHERE active = 1 AND end_date > NOW() LIMIT 1')
    
    if result and #result > 0 then
        activeAmnesty = result[1]
        print('[ALTAX] Active tax amnesty program found: ' .. activeAmnesty.name)
    end
end


function StartTaxAmnesty(name, description, discountPercentage, durationDays, createdBy)

    name = name or 'Tax Amnesty Program'
    description = description or 'Pay your overdue taxes with a discount'
    discountPercentage = discountPercentage or Config.TaxAmnestyDiscount
    durationDays = durationDays or Config.TaxAmnestyDuration
    
    
    local startDate = os.date('%Y-%m-%d %H:%M:%S')
    local endDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (durationDays * 86400))
    
   
    MySQL.update('UPDATE altax_amnesty SET active = 0 WHERE active = 1')
    
   
    local id = MySQL.insert.await('INSERT INTO altax_amnesty (name, description, discount_percentage, start_date, end_date, active, created_by) VALUES (?, ?, ?, ?, ?, 1, ?)', {
        name,
        description,
        discountPercentage,
        startDate,
        endDate,
        createdBy
    })

    activeAmnesty = {
        id = id,
        name = name,
        description = description,
        discount_percentage = discountPercentage,
        start_date = startDate,
        end_date = endDate,
        active = 1,
        created_by = createdBy
    }
    
    
    TriggerClientEvent('altax:amnestyAnnouncement', -1, {
        name = name,
        description = description,
        discount = discountPercentage,
        endDate = endDate
    })
    
    return id
end


function EndTaxAmnesty(amnestyId)

    if not amnestyId and activeAmnesty then
        amnestyId = activeAmnesty.id
    end
    
    if amnestyId then
        MySQL.update('UPDATE altax_amnesty SET active = 0 WHERE id = ?', {
            amnestyId
        })
        
        if activeAmnesty and activeAmnesty.id == amnestyId then
            TriggerClientEvent('altax:amnestyEnded', -1, activeAmnesty.name)
            activeAmnesty = nil
        end
        
        return true
    end
    
    return false
end


function IsAmnestyActive()
    if activeAmnesty then

        local currentTime = os.time()
        local endTime = ConvertMySQLTimeToTimestamp(activeAmnesty.end_date)
        
        if currentTime > endTime then
            EndTaxAmnesty(activeAmnesty.id)
            return false
        end
        
        return true
    end
    
    local result = MySQL.query.await('SELECT * FROM altax_amnesty WHERE active = 1 AND end_date > NOW() LIMIT 1')
    
    if result and #result > 0 then
        activeAmnesty = result[1]
        return true
    end
    
    return false
end

function GetAmnestyDiscount()
    if IsAmnestyActive() then
        return activeAmnesty.discount_percentage
    end
    
    return 0
end

function GetActiveAmnestyInfo()
    if IsAmnestyActive() then
        return activeAmnesty
    end
    
    return nil
end

function ApplyAmnestyToOverdueTax(xPlayer)
    if not xPlayer or not IsAmnestyActive() then return 0 end
    
    local identifier = xPlayer.identifier
    
    local result = MySQL.query.await('SELECT overdue_amount, late_fees FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    if result and #result > 0 then
        local overdueAmount = result[1].overdue_amount or 0
        local lateFees = result[1].late_fees or 0
        local totalOverdue = overdueAmount + lateFees
        
        if totalOverdue <= 0 then return 0 end
        
        local discountAmount = math.floor(totalOverdue * (activeAmnesty.discount_percentage / 100))
        local amountAfterDiscount = totalOverdue - discountAmount
        
        MySQL.update('UPDATE altax_records SET overdue_amount = ?, late_fees = 0 WHERE identifier = ?', {
            amountAfterDiscount,
            identifier
        })
        
        RecordAmnestyUsage(identifier, totalOverdue, discountAmount)
        
        return discountAmount
    end
    
    return 0
end

function RecordAmnestyUsage(identifier, originalAmount, discountAmount)
    if not activeAmnesty then return end
    
    MySQL.insert('INSERT INTO altax_amnesty_usage (identifier, amnesty_id, original_amount, discount_amount, usage_date) VALUES (?, ?, ?, ?, NOW())', {
        identifier,
        activeAmnesty.id,
        originalAmount,
        discountAmount
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

RegisterServerEvent('altax:requestAmnesty')
AddEventHandler('altax:requestAmnesty', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    if IsAmnestyActive() then
        local discountAmount = ApplyAmnestyToOverdueTax(xPlayer)
        
        if discountAmount > 0 then
            TriggerClientEvent('altax:amnestyApplied', source, discountAmount)
        else
            TriggerClientEvent('esx:showNotification', source, 'Anda tidak memiliki pajak tertunggak yang dapat diamnestikan')
        end
    else
        TriggerClientEvent('esx:showNotification', source, 'Tidak ada program amnesti pajak yang aktif saat ini')
    end
end)

ESX.RegisterCommand('taxamnesty', 'admin', function(xPlayer, args, showError)
    local action = args.action
    
    if action == 'start' then
        local name = args.name or 'Tax Amnesty Program'
        local discount = args.discount or Config.TaxAmnestyDiscount
        local duration = args.duration or Config.TaxAmnestyDuration
        
        local id = StartTaxAmnesty(name, nil, discount, duration, xPlayer.identifier)
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Program amnesti pajak "' .. name .. '" telah dimulai dengan diskon ' .. discount .. '% untuk ' .. duration .. ' hari.'}
        })
    elseif action == 'end' then
        if EndTaxAmnesty() then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {0, 255, 0},
                args = {'[ALTAX]', 'Program amnesti pajak telah diakhiri.'}
            })
        else
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Tidak ada program amnesti pajak aktif untuk diakhiri.'}
            })
        end
    elseif action == 'info' then
        local amnestyInfo = GetActiveAmnestyInfo()
        
        if amnestyInfo then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 128, 0},
                multiline = true,
                args = {'[ALTAX]', 'Program Amnesti Pajak Aktif: ' .. amnestyInfo.name .. '\n' ..
                       'Deskripsi: ' .. (amnestyInfo.description or 'Tidak ada deskripsi') .. '\n' ..
                       'Diskon: ' .. amnestyInfo.discount_percentage .. '%\n' ..
                       'Mulai: ' .. amnestyInfo.start_date .. '\n' ..
                       'Berakhir: ' .. amnestyInfo.end_date .. '\n' ..
                       'Dibuat oleh: ' .. (amnestyInfo.created_by or 'Admin')}
            })
        else
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Tidak ada program amnesti pajak yang aktif saat ini.'}
            })
        end
    else
        showError('Tindakan tidak valid. Gunakan: start, end, info')
    end
end, true, {help = 'Manajemen program amnesti pajak', validate = true, arguments = {
    {name = 'action', help = 'Tindakan: start, end, info', type = 'string'},
    {name = 'name', help = 'Nama program (untuk start)', type = 'string', optional = true},
    {name = 'discount', help = 'Persentase diskon (untuk start)', type = 'number', optional = true},
    {name = 'duration', help = 'Durasi dalam hari (untuk start)', type = 'number', optional = true}
}})

Citizen.CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `altax_amnesty_usage` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `amnesty_id` int(11) NOT NULL,
            `original_amount` int(11) NOT NULL,
            `discount_amount` int(11) NOT NULL,
            `usage_date` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

exports('StartTaxAmnesty', StartTaxAmnesty)
exports('EndTaxAmnesty', EndTaxAmnesty)
exports('IsAmnestyActive', IsAmnestyActive)
exports('GetAmnestyDiscount', GetAmnestyDiscount)
exports('ApplyAmnestyToOverdueTax', ApplyAmnestyToOverdueTax)
