Config = {}

-- Settings umum
Config.Debug = false -- Set ke true untuk logging debug
Config.Locale = 'id' -- en atau id
Config.NotifyType = 'esx' -- 'esx', 'mythic', 'pnotify'

-- Pengaturan waktu (untuk pajak otomatis)
Config.TaxInterval = 7 -- Jumlah hari antara pembayaran pajak (setiap 7 hari)
Config.TimeZone = 'Asia/Jakarta' -- Timezone Indonesia
Config.TaxCollectionHour = 6 -- Jam pengumpulan pajak (pagi hari)

-- Pembayaran pajak
Config.AllowCashPayment = true -- Izinkan pembayaran dari uang cash jika uang bank tidak cukup
Config.GracePeriod = 3 -- Jumlah hari untuk membayar pajak setelah waktu jatuh tempo
Config.LateFeePercentage = 10 -- Persentase denda untuk terlambat bayar pajak

-- Pembebasan pajak
Config.MinimumTaxableIncome = 5000 -- Penghasilan minimum yang kena pajak
Config.ExemptJobs = { -- Pekerjaan yang bebas dari beberapa atau semua pajak 
    ['police'] = { income = true, property = false, vehicle = false },
    ['ambulance'] = { income = true, property = false, vehicle = false },
    ['mechanic'] = { income = false, property = false, vehicle = true }
}

-- SMS notifikasi
Config.SendSMSNotification = true -- Kirim SMS pemberitahuan tentang pajak
Config.TaxServiceNumber = 'PAJAK-ID'

-- Kategori pendapatan dan tarif pajak (progressive tax)
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
Config.PropertyTaxRate = 3 -- Persentase dari nilai properti yang dibayarkan setiap periode pajak
Config.PropertyTypes = {
    ['apartment'] = { taxMultiplier = 1.0 },
    ['house'] = { taxMultiplier = 1.2 },
    ['mansion'] = { taxMultiplier = 1.5 },
    ['business'] = { taxMultiplier = 2.0 }
}

-- Pajak kendaraan
Config.VehicleTaxEnabled = true
Config.VehicleTaxBaseRate = 2 -- Persentase dari nilai kendaraan untuk pajak dasar
Config.VehicleCountTaxMultiplier = 0.5 -- Tambahan persentase pajak untuk setiap kendaraan tambahan
Config.VehicleAgeTaxDiscount = 0.1 -- Pengurangan persentase pajak untuk setiap tahun umur kendaraan
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
Config.TaxAmnestyDiscount = 50 -- Persentase diskon untuk pembayaran pajak tertunggak
Config.TaxAmnestyDuration = 3 -- Durasi program amnesti dalam hari

-- Insentif pajak
Config.TaxIncentives = {
    charityDonation = { multiplier = 0.5, maxDeduction = 10000 }, -- 50% dari donasi amal dikurangkan dari pajak
    greenVehicle = { deduction = 5 }, -- Pengurangan 5% untuk kendaraan ramah lingkungan
    policeCooperation = { deduction = 10 } -- Pengurangan 10% untuk informan polisi
}

-- Account untuk penerimaan pajak
Config.TaxRevenueAccount = 'society_government' -- Akun masyarakat yang menerima uang pajak

-- Distribusi pendapatan pajak (untuk feature tax distribution)
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