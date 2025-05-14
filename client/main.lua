-- client/main.lua
-- Client-side main file for ALTAX tax system

ESX = exports['es_extended']:getSharedObject()

-- Local variables
local isShowingTaxUI = false
local currentTaxInfo = nil
local isBeingAudited = false

-- Display a notification when taxes are collected
RegisterNetEvent('altax:taxCollected')
AddEventHandler('altax:taxCollected', function(amount, source)
    local message = _U('tax_collected', ESX.Math.GroupDigits(amount))
    ShowNotification(message)
end)

-- Display a notification when taxes are collected from cash
RegisterNetEvent('altax:taxCollectedCash')
AddEventHandler('altax:taxCollectedCash', function(totalAmount, bankAmount, cashAmount)
    local message = _U('tax_collected', ESX.Math.GroupDigits(bankAmount))
    ShowNotification(message)
    
    local cashMessage = _U('tax_collected_cash', ESX.Math.GroupDigits(cashAmount))
    ShowNotification(cashMessage)
end)

-- Display a warning when taxes are due soon
RegisterNetEvent('altax:taxDueWarning')
AddEventHandler('altax:taxDueWarning', function(amount, days)
    local message = _U('tax_due_soon', ESX.Math.GroupDigits(amount), days)
    ShowNotification(message)
    
    TriggerEvent('altax:displayTaxWarningUI', amount, days)
end)

-- Display notification about overdue taxes
RegisterNetEvent('altax:overdueNotice')
AddEventHandler('altax:overdueNotice', function(amount)
    local message = _U('tax_overdue', ESX.Math.GroupDigits(amount), Config.LateFeePercentage)
    ShowNotification(message)
    
    TriggerEvent('altax:displayOverdueUI', amount)
end)

-- Display a notification about tax bracket
RegisterNetEvent('altax:notifyTaxBracket')
AddEventHandler('altax:notifyTaxBracket', function(bracketName, taxRate)
    local message = _U('tax_bracket', bracketName, taxRate)
    ShowNotification(message)
end)

-- Display a notification when exempt from a tax type
RegisterNetEvent('altax:taxExempt')
AddEventHandler('altax:taxExempt', function(taxType)
    local message = _U('tax_exempt', taxType)
    ShowNotification(message)
end)

-- Display a notification when not enough money for taxes
RegisterNetEvent('altax:notEnoughMoney')
AddEventHandler('altax:notEnoughMoney', function(amount, available)
    local message = _U('not_enough_money')
    ShowNotification(message)
end)

-- Display the tax summary
RegisterNetEvent('altax:taxSummary')
AddEventHandler('altax:taxSummary', function(taxInfo)
    currentTaxInfo = taxInfo
    
    local message = _U('tax_summary') .. '\n'
    
    if taxInfo.incomeTax > 0 then
        message = message .. _U('income_tax', ESX.Math.GroupDigits(taxInfo.incomeTax)) .. '\n'
    end
    
    if taxInfo.propertyTax > 0 then
        message = message .. _U('property_tax', ESX.Math.GroupDigits(taxInfo.propertyTax)) .. '\n'
    end
    
    if taxInfo.vehicleTax > 0 then
        message = message .. _U('vehicle_tax', ESX.Math.GroupDigits(taxInfo.vehicleTax)) .. '\n'
    end
    
    if taxInfo.vehicleCountTax > 0 then
        message = message .. _U('vehicle_count_tax', ESX.Math.GroupDigits(taxInfo.vehicleCountTax)) .. '\n'
    end
    
    if taxInfo.incentives > 0 then
        message = message .. _U('tax_incentive_applied', 'Total', ESX.Math.GroupDigits(taxInfo.incentives)) .. '\n'
    end
    
    if taxInfo.overdue > 0 then
        message = message .. 'Pajak Tertunggak: $' .. ESX.Math.GroupDigits(taxInfo.overdue) .. '\n'
    end
    
    message = message .. '-------------------\n'
    message = message .. 'Total: $' .. ESX.Math.GroupDigits(taxInfo.total)
    
    ShowAdvancedNotification('Tax Receipt', _U('tax_receipt', math.random(10000, 99999)), message, 'CHAR_BANK_MAZE', 9)
    
    -- Display tax UI if enabled
    TriggerEvent('altax:displayTaxSummaryUI', taxInfo)
end)

-- Tax incentive applied notification
RegisterNetEvent('altax:incentiveApplied')
AddEventHandler('altax:incentiveApplied', function(incentiveType, amount)
    local incentiveNames = {
        charity_donation = 'Donasi Amal',
        green_vehicle = 'Kendaraan Ramah Lingkungan',
        police_cooperation = 'Kerjasama dengan Kepolisian'
    }
    
    local name = incentiveNames[incentiveType] or incentiveType
    
    local message = _U('tax_incentive_applied', name, ESX.Math.GroupDigits(amount))
    ShowNotification(message)
end)

-- Tax incentive added notification
RegisterNetEvent('altax:incentiveAdded')
AddEventHandler('altax:incentiveAdded', function(incentiveType)
    local incentiveNames = {
        charityDonation = 'Donasi Amal',
        greenVehicle = 'Kendaraan Ramah Lingkungan',
        policeCooperation = 'Kerjasama dengan Kepolisian'
    }
    
    local name = incentiveNames[incentiveType] or incentiveType
    
    ShowNotification('Insentif pajak baru ditambahkan: ' .. name)
end)

-- Display next tax date
RegisterNetEvent('altax:nextTaxDate')
AddEventHandler('altax:nextTaxDate', function(date)
    local nextDate = FormatMySQLDate(date)
    local message = _U('next_tax_date', nextDate)
    ShowNotification(message)
end)

-- Tax audit events
RegisterNetEvent('altax:auditNotice')
AddEventHandler('altax:auditNotice', function()
    local message = _U('audit_notice')
    ShowAdvancedNotification('Direktorat Pajak', 'Pemberitahuan Audit', message, 'CHAR_BANK_MAZE', 1)
    
    -- Update audit status
    isBeingAudited = true
    
    -- Send UI notification
    TriggerEvent('altax:displayAuditUI', true)
end)

RegisterNetEvent('altax:auditComplete')
AddEventHandler('altax:auditComplete', function(auditResult)
    local resultText = ''
    
    if auditResult.result == 'compliant' then
        resultText = 'Patuh Pajak'
    elseif auditResult.result == 'evasion_found' then
        resultText = 'Penghindaran Pajak Ditemukan'
    else
        resultText = auditResult.result
    end
    
    local message = _U('audit_complete', resultText)
    ShowAdvancedNotification('Direktorat Pajak', 'Hasil Audit', message, 'CHAR_BANK_MAZE', 1)
    
    -- Update audit status
    isBeingAudited = false
    
    -- Send UI notification
    TriggerEvent('altax:displayAuditUI', false, auditResult)
end)

RegisterNetEvent('altax:auditPenalty')
AddEventHandler('altax:auditPenalty', function(amount)
    local message = _U('audit_penalty', ESX.Math.GroupDigits(amount))
    ShowAdvancedNotification('Direktorat Pajak', 'Denda Audit', message, 'CHAR_BANK_MAZE', 1)
end)

RegisterNetEvent('altax:updateAuditStatus')
AddEventHandler('altax:updateAuditStatus', function(status)
    isBeingAudited = (status.status == 'pending')
    
    if isBeingAudited then
        ShowNotification('Anda sedang dalam proses audit pajak')
    end
end)

-- Tax amnesty events
RegisterNetEvent('altax:amnestyAvailable')
AddEventHandler('altax:amnestyAvailable', function(discountPercentage)
    local message = _U('amnesty_available', discountPercentage)
    ShowAdvancedNotification('Direktorat Pajak', 'Program Amnesti Pajak', message, 'CHAR_BANK_MAZE', 2)
    
    -- Send UI notification
    TriggerEvent('altax:displayAmnestyUI', discountPercentage)
end)

RegisterNetEvent('altax:amnestyApplied')
AddEventHandler('altax:amnestyApplied', function(savedAmount)
    local message = _U('amnesty_applied', ESX.Math.GroupDigits(savedAmount))
    ShowAdvancedNotification('Direktorat Pajak', 'Amnesti Pajak Diterapkan', message, 'CHAR_BANK_MAZE', 2)
end)

RegisterNetEvent('altax:amnestyAnnouncement')
AddEventHandler('altax:amnestyAnnouncement', function(amnestyInfo)
    local message = 'Program Amnesti Pajak telah dimulai!\n' ..
                   'Dapatkan diskon ' .. amnestyInfo.discount .. '% untuk pajak tertunggak.\n' ..
                   'Berakhir pada: ' .. FormatMySQLDate(amnestyInfo.endDate)
    
    ShowAdvancedNotification('Direktorat Pajak', amnestyInfo.name, message, 'CHAR_BANK_MAZE', 2)
    
    -- Send UI notification
    TriggerEvent('altax:displayAmnestyUI', amnestyInfo.discount)
end)

RegisterNetEvent('altax:amnestyEnded')
AddEventHandler('altax:amnestyEnded', function(name)
    local message = 'Program Amnesti Pajak "' .. name .. '" telah berakhir.'
    ShowAdvancedNotification('Direktorat Pajak', 'Amnesti Pajak Berakhir', message, 'CHAR_BANK_MAZE', 2)
    
    -- Remove amnesty UI
    TriggerEvent('altax:hideAmnestyUI')
end)

-- Send SMS notification
RegisterNetEvent('altax:sendSMS')
AddEventHandler('altax:sendSMS', function(sender, message)
    if Config.SendSMSNotification then
        TriggerEvent('esx_phone:send', sender, message)
        -- Fallback for other phone resources
        TriggerEvent('gcPhone:sendMessage', sender, message)
        TriggerEvent('qs-smartphone:sendMessage', sender, message)
    end
end)

-- Receipt event
RegisterNetEvent('altax:showReceipt')
AddEventHandler('altax:showReceipt', function(receiptData)
    if not receiptData then return end
    
    local message = '=== TANDA TERIMA PAJAK ===\n' ..
                   'ID: ' .. receiptData.id .. '\n' ..
                   'Tanggal: ' .. FormatMySQLDate(receiptData.date) .. '\n' ..
                   'Jumlah: $' .. ESX.Math.GroupDigits(receiptData.amount) .. '\n' ..
                   'Tipe: ' .. receiptData.type .. '\n' ..
                   'Metode: ' .. receiptData.method .. '\n' ..
                   '---------------------------\n' ..
                   'Terima kasih atas kepatuhan Anda!'
    
    ShowAdvancedNotification('Direktorat Pajak', 'Tanda Terima Pajak', message, 'CHAR_BANK_MAZE', 9)
end)

-- Format MySQL date for display
function FormatMySQLDate(mysqlDate)
    if not mysqlDate then return 'N/A' end
    
    local pattern = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = mysqlDate:match(pattern)
    
    if not year then return mysqlDate end
    
    return day .. '/' .. month .. '/' .. year .. ' ' .. hour .. ':' .. min
end

-- Check audit status on spawn
Citizen.CreateThread(function()
    -- Wait for ESX to be ready
    Citizen.Wait(5000)
    
    -- Check if player is being audited
    TriggerServerEvent('altax:requestAuditStatus')
end)

-- UI Events for tax display
RegisterNetEvent('altax:displayTaxSummaryUI')
AddEventHandler('altax:displayTaxSummaryUI', function(taxInfo)
    -- This would be implemented by a UI resource
    -- For now, it just logs to console
    if Config.Debug then
        print('Tax Summary UI would be displayed here')
    end
end)

RegisterNetEvent('altax:displayTaxWarningUI')
AddEventHandler('altax:displayTaxWarningUI', function(amount, days)
    -- This would be implemented by a UI resource
    if Config.Debug then
        print('Tax Warning UI would be displayed here')
    end
end)

RegisterNetEvent('altax:displayOverdueUI')
AddEventHandler('altax:displayOverdueUI', function(amount)
    -- This would be implemented by a UI resource
    if Config.Debug then
        print('Tax Overdue UI would be displayed here')
    end
end)

RegisterNetEvent('altax:displayAuditUI')
AddEventHandler('altax:displayAuditUI', function(isActive, results)
    -- This would be implemented by a UI resource
    if Config.Debug then
        print('Audit UI would be displayed here, active:', isActive)
    end
end)

RegisterNetEvent('altax:displayAmnestyUI')
AddEventHandler('altax:displayAmnestyUI', function(discountPercentage)
    -- This would be implemented by a UI resource
    if Config.Debug then
        print('Amnesty UI would be displayed here, discount:', discountPercentage)
    end
end)

RegisterNetEvent('altax:hideAmnestyUI')
AddEventHandler('altax:hideAmnestyUI', function()
    -- This would be implemented by a UI resource
    if Config.Debug then
        print('Amnesty UI would be hidden here')
    end
end)

-- Display map blip for tax office
Citizen.CreateThread(function()
    -- Optional: add a blip for the tax office
    -- This is just an example location, change it for your server
    local blipCoords = vector3(-17.51, -1037.09, 28.85) -- Maze Bank Downtown
    
    local blip = AddBlipForCoord(blipCoords)
    SetBlipSprite(blip, 500) -- Use whatever sprite fits best
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 5) -- Yellow
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Kantor Pajak")
    EndTextCommandSetBlipName(blip)
end)

-- Optional NPC at the tax office for interactions
Citizen.CreateThread(function()
    -- Optional: add an NPC for the tax office
    -- This is just an example location, change it for your server
    local npcCoords = vector4(-17.51, -1037.09, 28.85, 240.0) -- Maze Bank Downtown
    
    -- Create NPC
    RequestModel(`a_m_m_business_01`)
    while not HasModelLoaded(`a_m_m_business_01`) do
        Citizen.Wait(1)
    end
    
    local ped = CreatePed(4, `a_m_m_business_01`, npcCoords.x, npcCoords.y, npcCoords.z - 1.0, npcCoords.w, false, true)
    SetEntityHeading(ped, npcCoords.w)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    
    -- Add interaction marker
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local dist = #(playerCoords - vector3(npcCoords.x, npcCoords.y, npcCoords.z))
            
            if dist < 5.0 then
                DrawMarker(1, npcCoords.x, npcCoords.y, npcCoords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.8, 255, 255, 0, 100, false, true, 2, nil, nil, false)
                
                if dist < 2.0 then
                    ESX.ShowHelpNotification('Tekan ~INPUT_CONTEXT~ untuk berbicara dengan petugas pajak')
                    
                    if IsControlJustReleased(0, 38) then -- E key
                        OpenTaxMenu()
                    end
                end
            else
                Citizen.Wait(500)
            end
        end
    end)
end)

-- Tax interaction menu
function OpenTaxMenu()
    ESX.UI.Menu.CloseAll()
    
    ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'tax_menu', {
        title    = 'Kantor Pajak',
        align    = 'top-left',
        elements = {
            {label = 'Cek Status Pajak', value = 'check_status'},
            {label = 'Bayar Pajak Tertunggak', value = 'pay_overdue'},
            {label = 'Lihat Riwayat Pembayaran', value = 'view_history'},
            {label = 'Tanyakan tentang Amnesti', value = 'ask_amnesty'},
            {label = 'Daftar Kendaraan Ramah Lingkungan', value = 'register_green'}
        }
    }, function(data, menu)
        if data.current.value == 'check_status' then
            TriggerServerEvent('altax:checkTaxStatus')
            menu.close()
        elseif data.current.value == 'pay_overdue' then
            TriggerServerEvent('altax:payOverdueTax')
            menu.close()
        elseif data.current.value == 'view_history' then
            TriggerServerEvent('altax:getPaymentHistory')
            menu.close()
        elseif data.current.value == 'ask_amnesty' then
            TriggerServerEvent('altax:checkAmnestyStatus')
            menu.close()
        elseif data.current.value == 'register_green' then
            OpenGreenVehicleMenu()
            menu.close()
        end
    end, function(data, menu)
        menu.close()
    end)
end

-- Green vehicle registration menu
function OpenGreenVehicleMenu()
    ESX.TriggerServerCallback('altax:getOwnedVehicles', function(vehicles)
        local elements = {}
        
        for _, vehicle in ipairs(vehicles) do
            table.insert(elements, {
                label = vehicle.plate .. ' - ' .. vehicle.model .. (vehicle.is_green == 1 and ' (Ramah Lingkungan)' or ''),
                value = vehicle.plate,
                isGreen = vehicle.is_green == 1
            })
        end
        
        if #elements == 0 then
            ESX.ShowNotification('Anda tidak memiliki kendaraan')
            return
        end
        
        ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'green_vehicle_menu', {
            title    = 'Daftar Kendaraan Ramah Lingkungan',
            align    = 'top-left',
            elements = elements
        }, function(data, menu)
            local plate = data.current.value
            local isGreen = data.current.isGreen
            
            if isGreen then
                ESX.ShowNotification('Kendaraan ini sudah terdaftar sebagai ramah lingkungan')
            else
                -- Confirmation menu
                ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'green_vehicle_confirm', {
                    title    = 'Konfirmasi Pendaftaran',
                    align    = 'top-left',
                    elements = {
                        {label = 'Ya, daftarkan kendaraan ini (biaya: $5,000)', value = 'yes'},
                        {label = 'Tidak', value = 'no'}
                    }
                }, function(data2, menu2)
                    if data2.current.value == 'yes' then
                        TriggerServerEvent('altax:registerGreenVehicle', plate)
                        menu2.close()
                        menu.close()
                    else
                        menu2.close()
                    end
                end, function(data2, menu2)
                    menu2.close()
                end)
            end
        end, function(data, menu)
            menu.close()
            OpenTaxMenu()
        end)
    end)
end

-- Callbacks for the tax menu
RegisterNetEvent('altax:receivePaymentHistory')
AddEventHandler('altax:receivePaymentHistory', function(payments)
    if not payments or #payments == 0 then
        ESX.ShowNotification('Tidak ada riwayat pembayaran')
        return
    end
    
    local elements = {}
    
    for _, payment in ipairs(payments) do
        table.insert(elements, {
            label = FormatMySQLDate(payment.payment_date) .. ' - $' .. ESX.Math.GroupDigits(payment.amount),
            value = payment.id,
            payment = payment
        })
    end
    
    ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'payment_history_menu', {
        title    = 'Riwayat Pembayaran Pajak',
        align    = 'top-left',
        elements = elements
    }, function(data, menu)
        local payment = data.current.payment
        
        local message = 'Tanda Terima #' .. payment.receipt_id .. '\n' ..
                       'Tanggal: ' .. FormatMySQLDate(payment.payment_date) .. '\n' ..
                       'Jumlah: $' .. ESX.Math.GroupDigits(payment.amount) .. '\n' ..
                       'Tipe: ' .. payment.tax_type .. '\n' ..
                       'Metode: ' .. payment.payment_method
        
        ESX.ShowAdvancedNotification('Direktorat Pajak', 'Detail Pembayaran', message, 'CHAR_BANK_MAZE', 9)
    end, function(data, menu)
        menu.close()
        OpenTaxMenu()
    end)
end)

-- Functions for player registry
-- These are used to identify players for tax audits and other functions
function RegisterPlayerForTaxSystem()
    -- This would run when the player first joins the server
    -- It creates initial tax records if they don't exist
    TriggerServerEvent('altax:registerPlayer')
end

-- Run this when player spawns
AddEventHandler('esx:playerLoaded', function(playerData)
    RegisterPlayerForTaxSystem()
end)

-- Helper function to get localized text
function _(str, ...)
    if Locales[Config.Locale] then
        if Locales[Config.Locale][str] then
            return string.format(Locales[Config.Locale][str], ...)
        else
            return 'Translation [' .. Config.Locale .. '][' .. str .. '] does not exist'
        end
    else
        return 'Locale [' .. Config.Locale .. '] does not exist'
    end
end