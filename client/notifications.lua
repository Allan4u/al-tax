
function ShowNotification(message)
    if Config.NotifyType == 'esx' then
        ESX.ShowNotification(message)
    elseif Config.NotifyType == 'mythic' then
        exports['mythic_notify']:DoHudText('inform', message)
    elseif Config.NotifyType == 'pnotify' then
        exports.pNotify:SendNotification({
            text = message,
            type = "info",
            timeout = 5000,
            layout = "bottomCenter",
            queue = "tax"
        })
    elseif Config.NotifyType == 'okokNotify' then
        exports['okokNotify']:Alert('Kantor Pajak', message, 5000, 'info')
    else
        -- Default notification method
        SetNotificationTextEntry('STRING')
        AddTextComponentString(message)
        DrawNotification(false, false)
    end
end

function ShowAdvancedNotification(title, subject, message, icon, iconType)
    if Config.NotifyType == 'esx' then
        ESX.ShowAdvancedNotification(title, subject, message, icon, iconType)
    elseif Config.NotifyType == 'mythic' then
        exports['mythic_notify']:DoHudText('inform', message)
    elseif Config.NotifyType == 'pnotify' then
        exports.pNotify:SendNotification({
            text = '<b>' .. title .. '</b><br>' .. subject .. '<br>' .. message,
            type = "info",
            timeout = 7500,
            layout = "bottomCenter",
            queue = "tax"
        })
    elseif Config.NotifyType == 'okokNotify' then
        exports['okokNotify']:Alert(title, message, 7500, 'info')
    else
        SetNotificationTextEntry('STRING')
        AddTextComponentString(message)
        SetNotificationMessage(icon, icon, true, iconType, title, subject)
        DrawNotification(false, true)
    end
end

function ShowTaxHUDNotification(taxInfo)
    
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
    
    message = message .. '-------------------\n'
    message = message .. 'Total: $' .. ESX.Math.GroupDigits(taxInfo.total)
    
    ShowAdvancedNotification('Tax Receipt', _U('tax_receipt', math.random(10000, 99999)), message, 'CHAR_BANK_MAZE', 9)
end

function FormatCash(amount)
    return ESX.Math.GroupDigits(amount)
end

function ShowTaxDueWarning(amount, days)
    PlaySoundFrontend(-1, "ATM_WINDOW", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
    
    local title = "Peringatan Pajak"
    local subject = "Pajak Jatuh Tempo"
    local message = _U('tax_due_soon', ESX.Math.GroupDigits(amount), days)
    
    ShowAdvancedNotification(title, subject, message, 'CHAR_BANK_MAZE', 1)
end

function ShowTaxOverdueNotice(amount)
    PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
    
    local title = "Pajak Tertunggak"
    local subject = "Peringatan Resmi"
    local message = _U('tax_overdue', ESX.Math.GroupDigits(amount), Config.LateFeePercentage)
    
    ShowAdvancedNotification(title, subject, message, 'CHAR_BANK_MAZE', 1)
end

function ShowAuditNotification(isStarting)
    if isStarting then
        PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
        
        local title = "Pemberitahuan Audit"
        local subject = "Direktorat Pajak"
        local message = _U('audit_notice')
        
        ShowAdvancedNotification(title, subject, message, 'CHAR_BANK_MAZE', 1)
    else
        PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", 1)
    end
end

function ShowAmnestyNotification(discountPercentage)
    PlaySoundFrontend(-1, "CHALLENGE_UNLOCKED", "HUD_AWARDS", 1)
    
    local title = "Program Amnesti Pajak"
    local subject = "Kesempatan Terbatas"
    local message = _U('amnesty_available', discountPercentage)
    
    ShowAdvancedNotification(title, subject, message, 'CHAR_BANK_MAZE', 2)
end

function ShowTaxScaleform(title, message, duration)
    local scaleform = RequestScaleformMovie("mp_big_message_freemode")
    while not HasScaleformMovieLoaded(scaleform) do
        Citizen.Wait(0)
    end
    
    BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
    PushScaleformMovieMethodParameterString(title)
    PushScaleformMovieMethodParameterString(message)
    EndScaleformMovieMethod()
    
    local time = GetGameTimer() + (duration or 5000)
    while GetGameTimer() < time do
        Citizen.Wait(0)
        DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)
    end
    
    SetScaleformMovieAsNoLongerNeeded(scaleform)
end

RegisterNUICallback('closeTaxUI', function(data, cb)
    isShowingTaxUI = false
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('payOverdueTax', function(data, cb)
    TriggerServerEvent('altax:payOverdueTax')
    cb({})
end)

RegisterNUICallback('requestAmnesty', function(data, cb)
    TriggerServerEvent('altax:requestAmnesty')
    cb({})
end)

exports('ShowTaxNotification', ShowNotification)
exports('ShowAdvancedTaxNotification', ShowAdvancedNotification)
exports('ShowTaxHUD', ShowTaxHUDNotification)
exports('ShowTaxDueWarning', ShowTaxDueWarning)
exports('ShowTaxOverdueNotice', ShowTaxOverdueNotice)
exports('ShowTaxScaleform', ShowTaxScaleform)
