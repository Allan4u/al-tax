## ALTAX - Automatic Tax System for ESX Framework

ALTAX is a comprehensive tax system for FiveM servers with ESX Framework. This system automatically manages income, property, and vehicle taxes.

### Features

- **Automatic Tax System**: Tax collection every 7 days according to Indonesia timezone
- **Various Tax Types**:
  - Income tax based on money in bank accounts
  - Property tax based on property value and type
  - Vehicle tax based on value, class, and number of vehicles
- **Tax Class System**: Tax categories (Poor, Middle, Rich, etc.) with different rates
- **Online & Offline Taxes**: System works even when players are offline
- **Flexible Payments**: Supports payments through bank money or cash
- **Tax Exemptions**: Settings for tax exemptions for certain jobs
- **Notifications**: Alerts about upcoming taxes and overdue taxes
- **Tax Amnesty Program**: Discounts for overdue tax payments
- **Tax Incentives**: Tax reductions for charitable donations, eco-friendly vehicles, etc.
- **Tax Audit System**: Random audits and penalties for tax evasion
- **Admin Management**: Commands for admins to manage player taxes
- **History Logging**: All tax payments are recorded for reference
- **Revenue Distribution**: Tax revenue can be distributed to various community accounts
- **Multi-language**: Supports Indonesian and English

### Installation

1. Download and extract the resource to your server's `resources` folder
2. Ensure dependencies are installed: `es_extended` and `oxmysql`
3. Add `ensure altax` to your `server.cfg`
4. Import `install.sql` to your database
5. Restart your server

### Dependencies

- es_extended
- oxmysql

### Configuration

You can configure the tax system in `config.lua`:

- Set tax intervals and times
- Configure payment methods
- Set tax categories and rates
- Configure incentives and tax amnesty
- Customize revenue distribution settings

### Commands

**Admin Commands:**
- `/tax info [playerId]` - View player's tax information
- `/tax set [playerId] [taxType] [amount]` - Set tax for a player
- `/tax exempt [playerId] [taxType]` - Exempt a player from tax
- `/tax collect [playerId]` - Collect tax from a player manually
- `/tax incentive [playerId] [incentiveType] [value]` - Add tax incentive
- `/tax stats` - Display global tax statistics
- `/processtax [playerId]` - Process taxes for all players or a specific player
- `/taxamnesty start/end/info` - Manage tax amnesty program
- `/taxaudit start/complete/status [playerId]` - Manage tax audits
- `/vehicletax info/exempt/unexempt/setclass/setprice [plate]` - Manage vehicle taxes

**Player Commands:**
- `/mytax` - View your tax information
- `/paytax` - Pay overdue taxes
- `/myaudit` - Check your tax audit status

### Integration

ALTAX integrates with various other resources:
- ESX job system
- Property system
- Vehicle system
- Notification system

### Export Functions

ALTAX provides various export functions for use by other resources:
- `CalculatePlayerTax`
- `ProcessTax`
- `AddTaxIncentive`
- `RegisterVehicleForTax`
- `RegisterPropertyForTax`
- `StartTaxAmnesty`
- `EndTaxAmnesty`
- `IsAmnestyActive`
- `StartAudit`
- `IsPlayerBeingAudited`

### Events

**Server Events:**
- `altax:registerPlayer` - Register a player to the tax system
- `altax:checkTaxStatus` - Check a player's tax status
- `altax:payOverdueTax` - Pay overdue taxes
- `altax:requestAmnesty` - Request tax amnesty
- `altax:requestAuditStatus` - Request audit status

**Client Events:**
- `altax:taxCollected` - Tax has been collected
- `altax:taxDueWarning` - Warning for upcoming taxes
- `altax:overdueNotice` - Notice of overdue taxes
- `altax:taxSummary` - Tax summary
- `altax:auditNotice` - Audit notice
- `altax:amnestyAvailable` - Tax amnesty available

### Advanced Development

ALTAX is designed to be easily expandable:
- Add new tax types in `config.lua`
- Add new tax incentives
- Integrate with other financial systems
- Add custom UI for tax interactions
- Expand audit and penalty systems

### Credits

Created by Claude to meet the needs of Indonesian RP servers.

© 2025 ALTAX Tax System





Create a job script with the trigger name aljob
1. Use the ESX framework
2. Create the config.lua file
3. The job must include: Cow milk collection, Chicken butchering, Lumberjacking, Mining, Tailoring, Farming, Oil extraction
4. All jobs must have processes, such as chicken butchering requiring live chicken collection, then butchering and packaging the chicken, and the same for all other jobs
5. Make all jobs have simple minigames
6. Create menus using ox_lib and integrate with ox_target for locations
7. Create a menu to end the job as well
8. Create blips for collection points, initial processes, and final processes for each job
9. Create coordinates for selling all final products from the jobs and sold items go into the stash that already exists in ox_inventory
10. Add your own good and interesting features
11. Make it so when selling goods, money is reduced from society_pemkot and transferred to the player
12. Create a single sales location/coordinate
13. The stash must be named according to the stash in config.lua
14. Make it so when a player disconnects or leaves the server after 1 hour, they must take the job again
15. For farming process, must include buying seeds, planting, harvesting, washing, and packaging vegetables
16. Vegetables should be differentiated into carrots, tomatoes, peppers, bananas, tea, rice, sugar cane, oranges, and add others
17. Make it so sales prices can be configured in config.lua
18. Make the mining process include getting rocks, washing rocks, smelting rocks, and after rocks are smelted, obtaining items such as ruby, diamond, iron, gold, copper and others
19. Make everything neat and well-organized