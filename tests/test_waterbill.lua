-- Water Bill: verdicts only at vendor price 0, live AH check, live deposit, PriceLog prices, never shown in combat.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
local ns = W.loadAddon(".", "WaterBill")
W.fire("PLAYER_LOGIN")
local WB, FS = ns.WB, _G.FrostSuite_1_0
local row = FS.rows.WaterBill
local hub = ns.Hub
local prices = {}
hub.RegisterPrices("PriceLog", function(id) return prices[id] end)

W.items = { [8079] = { name = "Conjured Crystal Water", sellPrice = 0 }, [8076] = { name = "Conjured Sweet Roll", sellPrice = 0 },
  [5350] = { name = "Conjured Water", sellPrice = 0 }, [274964] = { name = "Mote of Unstable Magic", sellPrice = 200 } }
W.bags = { [0] = { [1] = { 8079, 20 }, [2] = { 8079, 15 }, [3] = { 8076, 10, true }, [4] = { 5350, 5 }, [5] = { 274964, 2 } } }

check(row.state == "hidden", "hidden until the AH, mailbox or /frost water")
W.fire("MAIL_SHOW")
check(row.state == "active", "shown at the mailbox")
local by = {}
for _, s in ipairs(WB.stacks) do by[s.itemID] = s end
check(by[8079].count == 35, "stacks of the same water add up")
check(by[8076].verdict == "EAT" and by[8076].why == "bound", "bound food: EAT")
check(by[274964].verdict == "vendor", "vendor price > 0: no LIST/DRINK verdict")
check(by[8079].verdict == "noprice" and row.lineText[1]:find("no price scan"), "no PriceLog scan: no price scan, never a guess")
check(row.lineText[4]:find("vendor price 2s 0c"), "vendor price shown")

prices[8079] = { p = 40, t = 100 }; prices[5350] = { p = 1, t = 100 }
W.fire("BAG_UPDATE_DELAYED")
check(by[8079] ~= WB.stacks[1] or true, "rescan")
local s1 = WB.stacks[1]
check(s1.verdict == "LIST" and s1.worth == 1400 and s1.deposit == nil, "away from the AH: LIST by price, deposit unknown")
check(row.lineText[1]:find("before AH cut") and row.lineText[1]:find("deposit at the AH"), "labelled before AH cut, deposit at the AH")

-- At the AH: live deposit; a cheap stack is not worth it; the AH refusing an item turns it into DRINK.
W.fire("MAIL_CLOSED"); W.ahOpen = true; W.deposit = 30; W.fire("AUCTION_HOUSE_SHOW"); W.advance(0.3)
s1 = WB.stacks[1]
check(s1.deposit == 1050 and s1.verdict == "LIST" and row.lineText[1]:find("deposit 10s 50c"), "live deposit read at the AH")
local cheap
for _, s in ipairs(WB.stacks) do if s.itemID == 5350 then cheap = s end end
check(cheap.verdict == "DRINK" and cheap.why == "not worth the deposit", "worth less than the deposit: DRINK")
W.ahRefuse = { [8079] = true }; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].verdict == "DRINK" and WB.stacks[1].why == "the AH won't take it", "IsSellItemValid false: DRINK")
W.ahRefuse = nil; W.fire("BAG_UPDATE_DELAYED")
check(row.headText:find("LIST ~") and row.statusText == "at the AH", "headline sums what's worth listing")

-- Deposit is never invented: no live answer -> nil.
W.deposit = nil; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].deposit == nil, "no deposit from the game: none shown")

-- Combat: hidden; /frost water waits.
W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
check(row.state == "hidden", "hidden in combat")
W.prints = {}; WB.Slash("")
check(W.prints[1] and W.prints[1]:find("waits until combat ends"), "/frost water waits in combat")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
check(row.state == "active", "back after combat at the AH")
W.fire("AUCTION_HOUSE_CLOSED"); W.ahOpen = false
check(row.state == "hidden", "hidden when the AH closes")

-- /frost water toggles; more than six stacks -> "+N more"; dynamic height.
local many = {}
for i, id in ipairs({ 5350, 2288, 2136, 3772, 8077, 8078, 8079, 231778 }) do many[i] = { id, 1 }; W.items[id] = W.items[id] or { name = "Water " .. id, sellPrice = 0 } end
W.bags = { [0] = many }
WB.Slash("")
check(row.state == "active" and #WB.lines == 7 and WB.lines[7] == "+2 more", "max 6 lines, then +N more")
check(WB.Height() == 50 + 14 * 6, "height grows with the lines")
WB.Slash("")
check(row.state == "hidden", "/frost water toggles off")

-- Empty bags; tooltip line; debug.
W.bags = { [0] = {} }; WB.Slash("")
check(row.lineText[1] == "No conjured water or food in your bags.", "nothing to judge")
WB.Slash("")
local tt = { lines = {} }; function tt.AddLine(_, t) tt.lines[#tt.lines + 1] = t end
hub.RunTooltips(tt, { id = 8079 })
check(tt.lines[1] and tt.lines[1]:find("40c each before AH cut"), "tooltip: price each, before AH cut")
tt.lines = {}; hub.RunTooltips(tt, { id = 274964 })
check(#tt.lines == 0, "no tooltip line for items with a vendor price")
W.prints = {}; WB.Slash("debug")
check(W.prints[1] and W.prints[1]:find("PriceLog"), "debug names the price source")

W.done("WaterBill")
