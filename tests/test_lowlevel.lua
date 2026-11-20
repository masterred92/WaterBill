-- Water Bill: works at any level and for any class (it reads items, not spells); never a learn line or button.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
W.level, W.known = 1, { [133] = true, [168] = true }   -- level 1: no Conjure Water (level 4) yet
local ns = W.loadAddon(".", "WaterBill")
W.fire("PLAYER_LOGIN"); W.advance(2)
local FS = _G.FrostSuite_1_0
local row = FS.rows.WaterBill
W.fire("MAIL_SHOW"); W.advance(1)
check(row.state == "active" and row.lineText[1] == "No conjured water or food in your bags.", "level 1 at the mailbox: no conjured items yet")
check(not row.learnText and not row.learnBtn, "no learn line or button: Water Bill needs no spell")
W.fire("MAIL_CLOSED")
W.fire("PLAYER_LEVEL_UP", 4); W.fire("LEARNED_SPELL_IN_SKILL_LINE", 5504); W.advance(2)
check(row.state == "hidden", "level-up events change nothing away from the mailbox")
W.class = "WARRIOR"
W.items = { [5350] = { name = "Conjured Water", sellPrice = 0 } }
W.bags = { [0] = { { 5350, 10 } } }
W.fire("MAIL_SHOW"); W.advance(1)
check(row.state == "active" and row.lineText[1] ~= nil and row.lineText[1]:find("Water x10", 1, true) ~= nil, "a non-Mage with conjured water gets a verdict too")
check(#ns.Core.errors == 0, "no Lua errors")
W.done("WaterBill low level")
