-- server/taxaudit.lua
-- Sistem audit pajak untuk ALTAX

local ESX = exports['es_extended']:getSharedObject()
local activeAudits = {}

-- Inisialisasi sistem audit pajak
Citizen.CreateThread(function()
    if Config.TaxAuditEnabled then
        InitializeAuditSystem()
    end
end)

function InitializeAuditSystem()
    -- Buat tabel audit jika belum ada
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `altax_audit_logs` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `audit_date` timestamp NOT NULL DEFAULT current_timestamp(),
            `audit_result` varchar(30) NOT NULL DEFAULT 'pending',
            `tax_owed` int(11) NOT NULL DEFAULT 0,
            `penalties` int(11) NOT NULL DEFAULT 0,
            `audit_officer` varchar(60) DEFAULT NULL,
            `notes` text DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    
    -- Jadwalkan proses audit acak
    ScheduleRandomAudits()
end

-- Jadwalkan audit acak
function ScheduleRandomAudits()
    -- Jalankan setiap 24 jam
    Citizen.CreateThread(function()
        while true do
            -- Lakukan audit pajak acak
            PerformRandomAudits()
            
            -- Tunggu 24 jam
            Citizen.Wait(24 * 60 * 60 * 1000)
        end
    end)
end

-- Lakukan audit pajak acak
function PerformRandomAudits()
    -- Dapatkan semua player dengan catatan pajak
    local players = MySQL.query.await('SELECT * FROM altax_records')
    
    if not players or #players == 0 then
        return
    end
    
    -- Loop melalui semua player
    for _, player in ipairs(players) do
        -- Kemungkinan random untuk audit
        if math.random(1, 100) <= Config.AuditChance then
            -- Mulai audit untuk player ini
            StartAudit(player.identifier)
        end
    end
end

-- Mulai audit untuk player
function StartAudit(identifier)
    -- Periksa apakah player sudah diaudit dalam 30 hari terakhir
    local lastAudit = MySQL.query.await('SELECT last_audit_date FROM altax_records WHERE identifier = ? AND last_audit_date > DATE_SUB(NOW(), INTERVAL 30 DAY)', {
        identifier
    })
    
    if lastAudit and #lastAudit > 0 then
        -- Player sudah diaudit baru-baru ini, lewati
        return
    end
    
    -- Buat record audit baru
    local auditId = MySQL.insert.await('INSERT INTO altax_audit_logs (identifier, audit_result) VALUES (?, "pending")', {
        identifier
    })
    
    -- Update tanggal audit terakhir player
    MySQL.update('UPDATE altax_records SET last_audit_date = NOW(), audit_count = audit_count + 1 WHERE identifier = ?', {
        identifier
    })
    
    -- Tambahkan ke daftar audit aktif
    activeAudits[identifier] = {
        id = auditId,
        startDate = os.time(),
        status = 'pending'
    }
    
    -- Beritahu player jika online
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if xPlayer then
        TriggerClientEvent('altax:auditNotice', xPlayer.source)
    end
    
    -- Jadwalkan penyelesaian audit (3-7 hari)
    local auditDuration = math.random(3, 7) * 24 * 60 * 60
    
    -- Buat thread untuk menyelesaikan audit
    Citizen.CreateThread(function()
        Citizen.Wait(auditDuration * 1000)
        CompleteAudit(identifier)
    end)
end

-- Selesaikan audit
function CompleteAudit(identifier)
    if not activeAudits[identifier] then
        return
    end
    
    local auditId = activeAudits[identifier].id
    
    -- Tentukan hasil audit
    local auditResult = DetermineAuditResult(identifier)
    
    -- Update record audit
    MySQL.update('UPDATE altax_audit_logs SET audit_result = ?, tax_owed = ?, penalties = ? WHERE id = ?', {
        auditResult.result,
        auditResult.taxOwed,
        auditResult.penalties,
        auditId
    })
    
    -- Jika player ditemukan menghindari pajak, tambahkan ke pajak tertunggak
    if auditResult.result == 'evasion_found' and auditResult.taxOwed > 0 then
        -- Tambahkan ke pajak tertunggak
        MySQL.update('UPDATE altax_records SET overdue_amount = overdue_amount + ?, late_fees = late_fees + ? WHERE identifier = ?', {
            auditResult.taxOwed,
            auditResult.penalties,
            identifier
        })
    end
    
    -- Beritahu player tentang hasil audit
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if xPlayer then
        TriggerClientEvent('altax:auditComplete', xPlayer.source, auditResult)
        
        if auditResult.result == 'evasion_found' then
            TriggerClientEvent('altax:auditPenalty', xPlayer.source, auditResult.taxOwed + auditResult.penalties)
        end
    end
    
    -- Hapus dari daftar audit aktif
    activeAudits[identifier] = nil
end

-- Tentukan hasil audit
function DetermineAuditResult(identifier)
    -- Dapatkan data player
    local playerData = MySQL.query.await('SELECT * FROM users WHERE identifier = ?', {
        identifier
    })
    
    if not playerData or #playerData == 0 then
        return {
            result = 'player_not_found',
            taxOwed = 0,
            penalties = 0
        }
    end
    
    -- Dapatkan catatan pajak
    local taxRecord = MySQL.query.await('SELECT * FROM altax_records WHERE identifier = ?', {
        identifier
    })
    
    -- Tentukan kemungkinan penghindaran pajak (simulasi)
    local evasionChance = 20 -- 20% kemungkinan default
    
    -- Kurangi kemungkinan jika player telah membayar banyak pajak
    if taxRecord and #taxRecord > 0 and taxRecord[1].total_tax_paid > 50000 then
        evasionChance = evasionChance - 10
    end
    
    -- Tingkatkan kemungkinan jika player memiliki banyak uang tapi sedikit pajak dibayar
    local accounts = json.decode(playerData[1].accounts)
    local money = accounts.bank or 0
    
    if money > 500000 and (not taxRecord or #taxRecord == 0 or taxRecord[1].total_tax_paid < 10000) then
        evasionChance = evasionChance + 20
    end
    
    -- Tentukan apakah ada penghindaran pajak
    local evasionFound = (math.random(1, 100) <= evasionChance)
    
    if evasionFound then
        -- Hitung pajak yang dihindari dan denda
        local taxOwed = math.floor(money * 0.05) -- 5% dari uang di bank
        local penalties = math.floor(taxOwed * Config.AuditPenaltyMultiplier)
        
        return {
            result = 'evasion_found',
            taxOwed = taxOwed,
            penalties = penalties
        }
    else
        return {
            result = 'compliant',
            taxOwed = 0,
            penalties = 0
        }
    end
end

-- Periksa apakah player sedang diaudit
function IsPlayerBeingAudited(identifier)
    return activeAudits[identifier] ~= nil
end

-- Dapatkan status audit player
function GetPlayerAuditStatus(identifier)
    if activeAudits[identifier] then
        return activeAudits[identifier]
    end
    
    -- Cek database untuk audit terbaru
    local result = MySQL.query.await('SELECT * FROM altax_audit_logs WHERE identifier = ? ORDER BY audit_date DESC LIMIT 1', {
        identifier
    })
    
    if result and #result > 0 then
        return {
            id = result[1].id,
            startDate = result[1].audit_date,
            status = result[1].audit_result,
            taxOwed = result[1].tax_owed,
            penalties = result[1].penalties
        }
    end
    
    return nil
end

-- Command untuk admin memulai audit
ESX.RegisterCommand('taxaudit', 'admin', function(xPlayer, args, showError)
    local targetId = args.playerId
    local action = args.action
    
    local xTarget = ESX.GetPlayerFromId(targetId)
    
    if not xTarget then
        showError('Player tidak ditemukan')
        return
    end
    
    local identifier = xTarget.identifier
    
    if action == 'start' then
        if IsPlayerBeingAudited(identifier) then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Player sudah dalam proses audit.'}
            })
            return
        end
        
        StartAudit(identifier)
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Audit pajak dimulai untuk player ' .. GetPlayerName(targetId)}
        })
    elseif action == 'complete' then
        if not IsPlayerBeingAudited(identifier) then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Player tidak sedang diaudit.'}
            })
            return
        end
        
        CompleteAudit(identifier)
        
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Audit pajak diselesaikan untuk player ' .. GetPlayerName(targetId)}
        })
    elseif action == 'status' then
        local status = GetPlayerAuditStatus(identifier)
        
        if status then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 255, 0},
                multiline = true,
                args = {'[ALTAX]', 'Status Audit untuk ' .. GetPlayerName(targetId) .. ':\n' ..
                       'Status: ' .. status.status .. '\n' ..
                       (status.taxOwed and status.taxOwed > 0 and 'Pajak Terutang: $' .. ESX.Math.GroupDigits(status.taxOwed) .. '\n' or '') ..
                       (status.penalties and status.penalties > 0 and 'Denda: $' .. ESX.Math.GroupDigits(status.penalties) .. '\n' or '')}
            })
        else
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 0, 0},
                args = {'[ALTAX]', 'Tidak ada riwayat audit untuk player ini.'}
            })
        end
    else
        showError('Tindakan tidak valid. Gunakan: start, complete, status')
    end
end, true, {help = 'Manajemen audit pajak', validate = true, arguments = {
    {name = 'playerId', help = 'ID Player', type = 'number'},
    {name = 'action', help = 'Tindakan: start, complete, status', type = 'string'}
}})

-- Command untuk player melihat status audit mereka
ESX.RegisterCommand('myaudit', 'user', function(xPlayer, args, showError)
    local identifier = xPlayer.identifier
    local status = GetPlayerAuditStatus(identifier)
    
    if status then
        if status.status == 'pending' then
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 255, 0},
                args = {'[ALTAX]', 'Anda sedang dalam proses audit pajak. Hasil akan diinformasikan setelah selesai.'}
            })
        else
            TriggerClientEvent('chat:addMessage', xPlayer.source, {
                color = {255, 255, 0},
                multiline = true,
                args = {'[ALTAX]', 'Status Audit Terakhir:\n' ..
                       'Hasil: ' .. TranslateAuditResult(status.status) .. '\n' ..
                       (status.taxOwed and status.taxOwed > 0 and 'Pajak Terutang: $' .. ESX.Math.GroupDigits(status.taxOwed) .. '\n' or '') ..
                       (status.penalties and status.penalties > 0 and 'Denda: $' .. ESX.Math.GroupDigits(status.penalties) .. '\n' or '')}
            })
        end
    else
        TriggerClientEvent('chat:addMessage', xPlayer.source, {
            color = {0, 255, 0},
            args = {'[ALTAX]', 'Anda tidak memiliki riwayat audit pajak.'}
        })
    end
end, false, {help = 'Cek status audit pajak Anda'})

-- Helper function untuk mentranslate hasil audit
function TranslateAuditResult(result)
    local translations = {
        pending = 'Dalam Proses',
        compliant = 'Patuh Pajak',
        evasion_found = 'Penghindaran Pajak Ditemukan',
        player_not_found = 'Data Tidak Ditemukan'
    }
    
    return translations[result] or result
end

-- Event handler untuk client yang meminta status audit
RegisterServerEvent('altax:requestAuditStatus')
AddEventHandler('altax:requestAuditStatus', function()
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    local identifier = xPlayer.identifier
    local status = GetPlayerAuditStatus(identifier)
    
    if status then
        TriggerClientEvent('altax:updateAuditStatus', source, status)
    end
end)

-- Export fungsi-fungsi untuk resource lain
exports('StartAudit', StartAudit)
exports('CompleteAudit', CompleteAudit)
exports('IsPlayerBeingAudited', IsPlayerBeingAudited)
exports('GetPlayerAuditStatus', GetPlayerAuditStatus)