Config = {}

Config.Debug = false 
Config.Locale = 'id' 
Config.NotifyType = 'esx' 

Config.TaxInterval = 7 
Config.TimeZone = 'Asia/Jakarta' 
Config.TaxCollectionHour = 6 

-- Pembayaran pajak
Config.AllowCashPayment = true -
Config.GracePeriod = 3 
Config.LateFeePercentage = 10 

-- Pembebasan pajak
Config.MinimumTaxableIncome = 5000 
Config.ExemptJobs = { 
    ['police'] = { income = true, property = false, vehicle = false },
    ['ambulance'] = { income = true, property = false, vehicle = false },
    ['mechanic'] = { income = false, property = false, vehicle = true }
}

Config.SendSMSNotification = true 
Config.TaxServiceNumber = 'PAJAK-ID'

Config.IncomeTaxBrackets = {
    { name = 'Sangat Miskin', minMoney = 0, maxMoney = 50000, taxRate = 2 },
    { name = 'Miskin', minMoney = 50001, maxMoney = 150000, taxRate = 5 },
    { name = 'Menengah Bawah', minMoney = 150001, maxMoney = 500000, taxRate = 10 },
    { name = 'Menengah', minMoney = 500001, maxMoney = 1000000, taxRate = 15 },
    { name = 'Menengah Atas', minMoney = 1000001, maxMoney = 5000000, taxRate = 20 },
    { name = 'Kaya', minMoney = 5000001, maxMoney = 10000000, taxRate = 25 },
    { name = 'Sangat Kaya', minMoney = 10000001, maxMoney = 999999999, taxRate = 30 }
}

-- Pajak properti
Config.PropertyTaxEnabled = true
Config.PropertyTaxRate = 3
Config.PropertyTypes = {
    ['apartment'] = { taxMultiplier = 1.0 },
    ['house'] = { taxMultiplier = 1.2 },
    ['mansion'] = { taxMultiplier = 1.5 },
    ['business'] = { taxMultiplier = 2.0 }
}

-- Pajak kendaraan
Config.VehicleTaxEnabled = true
Config.VehicleTaxBaseRate = 2
Config.VehicleCountTaxMultiplier = 0.5 
Config.VehicleAgeTaxDiscount = 0.1 
Config.VehicleClasses = {
    [0] = { name = 'Compacts', taxMultiplier = 0.8 },
    [1] = { name = 'Sedans', taxMultiplier = 1.0 },
    [2] = { name = 'SUVs', taxMultiplier = 1.2 },
    [3] = { name = 'Coupes', taxMultiplier = 1.1 },
    [4] = { name = 'Muscle', taxMultiplier = 1.3 },
    [5] = { name = 'Sports Classics', taxMultiplier = 1.4 },
    [6] = { name = 'Sports', taxMultiplier = 1.5 },
    [7] = { name = 'Super', taxMultiplier = 2.0 },
    [8] = { name = 'Motorcycles', taxMultiplier = 0.7 },
    [9] = { name = 'Off-road', taxMultiplier = 1.2 },
    [10] = { name = 'Industrial', taxMultiplier = 1.3 },
    [11] = { name = 'Utility', taxMultiplier = 1.1 },
    [12] = { name = 'Vans', taxMultiplier = 1.0 },
    [13] = { name = 'Cycles', taxMultiplier = 0.1 },
    [14] = { name = 'Boats', taxMultiplier = 1.5 },
    [15] = { name = 'Helicopters', taxMultiplier = 2.5 },
    [16] = { name = 'Planes', taxMultiplier = 3.0 },
    [17] = { name = 'Service', taxMultiplier = 0.5 },
    [18] = { name = 'Emergency', taxMultiplier = 0.0 },
    [19] = { name = 'Military', taxMultiplier = 0.0 },
    [20] = { name = 'Commercial', taxMultiplier = 1.4 },
    [21] = { name = 'Trains', taxMultiplier = 0.0 }
}

-- Program Amnesti Pajak
Config.TaxAmnestyEnabled = true
Config.TaxAmnestyDiscount = 50 
Config.TaxAmnestyDuration = 3

-- Insentif pajak
Config.TaxIncentives = {
    charityDonation = { multiplier = 0.5, maxDeduction = 10000 }, 
    greenVehicle = { deduction = 5 }, 
    policeCooperation = { deduction = 10 } 
}

Config.TaxRevenueAccount = 'society_government' 


Config.TaxDistribution = {
    government = 50, -- 50% masuk ke pemerintah pusat
    police = 20, -- 20% untuk pendanaan kepolisian
    ambulance = 15, -- 15% untuk layanan kesehatan
    maintenance = 10, -- 10% untuk pemeliharaan kota
    welfare = 5 -- 5% untuk program kesejahteraan
}

-- Pengaturan audit pajak (fitur tambahan)
Config.TaxAuditEnabled = true
Config.AuditChance = 5 -- Kemungkinan diaudit (dalam persen)
Config.AuditPenaltyMultiplier = 2.0 -- Denda jika ketahuan menghindari pajak
