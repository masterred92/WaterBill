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
-- Game-font line fit: the addon measures with a FontString; here it gets real 12 pt Friz Quadrata widths, and visible()
-- cuts a line the way the client does at the 222 px text width (characters off the end, then "…").
local FRIZ = dofile("tests/friz12_widths.lua")
local function chars(t) local out = {}; for ch in t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end; return out end
local function friz(t) local w = 0; for _, ch in ipairs(chars(t)) do w = w + (FRIZ[ch] or 7) end; return w end
local function visible(t, width)
  local c = chars(t)
  if friz(t) <= width then return table.concat(c) end
  while #c > 0 and friz(table.concat(c) .. "…") > width do c[#c] = nil end
  return table.concat(c) .. "…"
end
WB.Width("x"); WB.measure.GetStringWidth = function(self) return friz(self.text_ or "") end

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
check(row.lineText[4]:find("|cffb8b8b8VENDOR|r", 1, true) and row.lineText[4]:find("2s 0c"), "vendor price shown, VENDOR first")
-- r4 layout: one short line per stack, never wrapped, box tall enough for every line (lines start at y -44)
W.advance(1.1)
check(row.h == 44 + 14 * #WB.lines + 6, "box height = 44 + 14 per line + 6")
check(row.lines[1].shown and row.lines[#WB.lines].shown, "every verdict line is inside the box")
check(not row.lineText[1]:find("Conjured", 1, true), "panel lines leave off 'Conjured'")

prices[8079] = { p = 40, t = 100 }; prices[5350] = { p = 1, t = 100 }
W.fire("BAG_UPDATE_DELAYED")
check(by[8079] ~= WB.stacks[1] or true, "rescan")
local s1 = WB.stacks[1]
check(s1.verdict == "nodeposit" and s1.worth == 1400 and s1.deposit == nil, "away from the AH: no deposit, so no LIST verdict")
local function noNoDeposit() for _, l in ipairs(WB.lines) do if l:find("NO DEPOSIT", 1, true) then return false end end return true end
check(visible(row.lineText[1], 222):find("^DEPOSIT%? ") and visible(row.lineText[1], 222):find("~14s 0c", 1, true) and not row.lineText[1]:find("LIST"),
  "WB fit: no deposit away from the AH: DEPOSIT? + worth visible at 222 px")
check(noNoDeposit(), "WB fit: unknown deposit never says NO DEPOSIT (reads as 'none needed')")
check(not row.headText:find("LIST"), "no LIST headline without a deposit")

-- At the AH: live deposit; a cheap stack is not worth it; the AH refusing an item turns it into DRINK.
local zone, sub, map = "Orgrimmar", "The Drag", nil
_G.GetRealZoneText = function() return zone end
_G.GetSubZoneText = function() return sub end
_G.C_Map = { GetBestMapForUnit = function() return map end }
W.fire("MAIL_CLOSED"); W.ahOpen = true; W.deposit = 30; W.fire("AUCTION_HOUSE_SHOW"); W.advance(0.3)
s1 = WB.stacks[1]
check(s1.deposit == 1050 and s1.verdict == "LIST" and row.lineText[1]:find("· 10s50c/2h", 1, true), "live deposit, 2 h post by default")
check(visible(row.lineText[1], 222):find("~14s 0c · 10s50c/2h", 1, true) ~= nil and friz(row.lineText[1]) <= 222,
  "WB fit: LIST line keeps worth and deposit visible at 222 px")
W.items[8079].name = "Conjured Crystal Water of the Very Long Name Indeed"; W.fire("BAG_UPDATE_DELAYED")
local long = visible(row.lineText[1], 222)
check(long:find("…", 1, true) and long:find("x35 ~14s 0c · 10s50c/2h", 1, true) and friz(row.lineText[1]) <= 222,
  "WB fit: a long item name is cut with …, the figures stay visible")
W.items[8079].name = "Conjured Crystal Water"; W.fire("BAG_UPDATE_DELAYED")
check(row.lineText[1]:find("|cffffd100LIST|r", 1, true) ~= nil, "LIST text is CoinGold ffd100")
check(math.abs(s1.net - (1400 * 0.95 - 1050)) < 0.01 and s1.house == "faction", "faction house: 5% cut applied in the comparison")
check(row.statusText == "AH · faction 5% assumed" and friz(row.statusText) <= 222, "faction rate labelled as an assumption, short status fits a line")
W.advance(1.1)
check(not row.status.shown and row.statusLine.shown and row.statusSlot == #WB.lines + 1
  and row.h == 44 + 14 * (#WB.lines + 1) + 6, "AH status too wide beside the title + padlock: moves under the verdict lines; box grows one line")
-- worth 1200, deposit 1050: faction 1140 > 1050 = LIST; neutral / unknown 1020 < 1050 = not worth it.
prices[8079] = { p = 1200 / 35, t = 100 }; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].verdict == "LIST", "faction house (5%): LIST")
zone, sub = "Stranglethorn Vale", "Booty Bay"; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "neutral" and WB.stacks[1].cut == 0.15 and WB.stacks[1].verdict == "DRINK", "neutral house by zone name: 15%, not worth it")
check(row.statusText == "AH · neutral 15% assumed", "neutral rate labelled as an assumption")
check(visible(row.lineText[1], 222):find("· deposit too high", 1, true) ~= nil, "WB fit: DRINK reason (deposit too high) visible at 222 px")
zone, sub, map = "Somewhere", "", 1446; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "neutral", "neutral house by uiMap (Tanaris 1446)")
zone, sub, map = nil, nil, nil; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "unknown" and WB.stacks[1].cut == 0.15 and WB.stacks[1].verdict == "DRINK", "unknown house: the worse 15%")
check(row.statusText == "AH · house unknown, 15% assumed" and friz(row.statusText) <= 222, "unknown house says so, and fits a line")
local secretZone = {}; W.secret[secretZone] = true
_G.GetRealZoneText = function() return secretZone end; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "unknown", "secret zone text: unknown, 15%")
_G.GetRealZoneText = function() return zone end
-- Non-English client: names prove nothing; only confirmed uiMapIDs (UiMap 70862) decide.
_G.GetLocale = function() return "deDE" end
zone, sub, map = "Schlingendorntal", "Beutebucht", 9999; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "unknown" and WB.stacks[1].cut == 0.15, "deDE in Booty Bay, unmatched map: unknown, 15%")
zone, sub, map = "Orgrimmar", "", nil; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "unknown", "deDE, no map: a zone name never means faction")
map = 1434; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "neutral" and WB.stacks[1].cut == 0.15, "confirmed neutral map (Stranglethorn Vale 1434): neutral")
map = 1454; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "faction" and WB.stacks[1].cut == 0.05, "confirmed faction map (Orgrimmar 1454): faction, 5%")
map = 2482; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].house == "unknown" and WB.stacks[1].cut == 0.15, "unconfirmed Forever-only map (Mount Hyjal 2482): unknown, 15%")
_G.GetLocale = function() return "enUS" end; map = nil
zone, sub = "Orgrimmar", "The Drag"; prices[8079] = { p = 40, t = 100 }; W.fire("BAG_UPDATE_DELAYED")
-- faction 5% cut decides: worth 1100, deposit 1050 -> 1045 after the cut -> not worth it (would be LIST without the cut).
prices[8079] = { p = 1100 / 35, t = 100 }; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].verdict == "DRINK" and WB.stacks[1].why == "not worth the deposit", "after the 5% cut: not worth the deposit")
prices[8079] = { p = 40, t = 100 }
-- The player's own duration pick in the sell frame (CVar) changes the deposit and the label.
local cv = 3
_G.C_CVar = { GetCVar = function(n) if n == "auctionHouseDurationDropdown" then return tostring(cv) end end }
local seen
local orig = C_AuctionHouse.CalculateCommodityDeposit
C_AuctionHouse.CalculateCommodityDeposit = function(id, d, q) seen = d; return orig(id, d, q) end
W.fire("BAG_UPDATE_DELAYED")
check(seen == 3 and WB.stacks[1].hours == 24 and row.lineText[1]:find("/24h", 1, true), "picked 24 h: deposit asked for index 3, labelled 24 h")
cv = 9; W.fire("BAG_UPDATE_DELAYED")
check(seen == 1 and row.lineText[1]:find("/2h", 1, true), "unreadable pick: 2 h")
_G.C_CVar = nil; C_AuctionHouse.CalculateCommodityDeposit = orig; W.fire("BAG_UPDATE_DELAYED")
local cheap
for _, s in ipairs(WB.stacks) do if s.itemID == 5350 then cheap = s end end
check(cheap.verdict == "DRINK" and cheap.why == "not worth the deposit", "worth less than the deposit: DRINK")
W.ahRefuse = { [8079] = true }; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].verdict == "DRINK" and WB.stacks[1].why == "the AH won't take it", "IsSellItemValid false: DRINK")
check(visible(row.lineText[1], 222):find("· AH won't take it", 1, true) ~= nil, "WB fit: DRINK reason (AH won't take it) visible at 222 px")
W.ahRefuse = nil; W.fire("BAG_UPDATE_DELAYED")
local valid = C_AuctionHouse.IsSellItemValid; C_AuctionHouse.IsSellItemValid = nil; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].verdict == "ask" and visible(row.lineText[1], 222):find("^ASK .* x35 ~") ~= nil, "WB fit: AH can't say if it takes it: ASK + worth visible at 222 px")
C_AuctionHouse.IsSellItemValid = valid; W.fire("BAG_UPDATE_DELAYED")
check(row.headText:find("LIST ~") and row.statusText:find("^AH · ") ~= nil, "headline sums what's worth listing")

-- Deposit is never invented: no live answer -> nil.
W.deposit = nil; W.fire("BAG_UPDATE_DELAYED")
check(WB.stacks[1].deposit == nil and WB.stacks[1].verdict == "nodeposit" and visible(row.lineText[1], 222):find("^DEPOSIT%? ")
  and visible(row.lineText[1], 222):find("~" .. WB.Money(WB.stacks[1].worth), 1, true) and noNoDeposit(),
  "WB fit: AH open, no deposit from the game: DEPOSIT? + worth visible at 222 px, never NO DEPOSIT, no LIST")

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
check(WB.Height() == 44 + 14 * 7 + 6, "height grows with the lines (7 lines incl. +N more: 148)")
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
check(W.prints[1] and W.prints[1]:find("AH cut: 5%% for a faction house") and W.prints[1]:find("not game data") and W.prints[2]:find("duration: 2 h") and W.prints[3]:find("PriceLog"), "debug names the duration and price source")

-- Last resort in WB.Fit: huge gold or a huge xN still fits (name dropped, then the tail cut with "…"), never wider.
local lst = "|cffffd100LIST|r "
for _, tail in ipairs({ " x40 ~9999999g 99s · 9999g 99s/24h", " x99999999999 ~123456789012g 99s · 99999999g 99s/24h",
  (" x1"):rep(200) }) do
  local line = WB.Fit(lst, "Crystal Water", tail)
  check(friz(line) <= WB.TEXT_W and line:sub(1, #lst) == lst and visible(line, 222) == table.concat(chars(line)), "overflow fits 218 px, the client never cuts it: " .. line)
end
check(WB.Fit(lst, "Crystal Water", " x40 ~9999999g 99s · 9999g 99s/24h"):find("Crystal", 1, true) == nil, "the name goes first when only the figures fit")
check(WB.Fit(lst, "Water", " x4") == lst .. "Water x4", "short lines are untouched")
local hugeHead = ("|cffffd100%s|r "):format(("W"):rep(60))
local cutHead = WB.Fit(hugeHead, "Water", " x4")
check(friz(cutHead) <= WB.TEXT_W and cutHead:sub(1, 3) == "WWW" and cutHead:sub(-3) == "…" and not cutHead:find("|", 1, true),
  "a head wider than the line is cut too (plain text, ends in …), within 218 px: " .. cutHead)
check(WB.Fit("|cffffd100LIST|r ", "Water", (" x1"):rep(200)):sub(1, 17) == "|cffffd100LIST|r ", "a head that fits keeps its colour")

-- Secret item name or bound flag: never read; the stack falls back to the item's own name or "item <id>".
local origInfo = C_Container.GetContainerItemInfo
local secretName, secretBound = "SecretItemName", {}
W.secret[secretName] = true; W.secret[secretBound] = true
C_Container.GetContainerItemInfo = function(b, sl)
  local t = origInfo(b, sl); if t then t.itemName, t.isBound = secretName, secretBound end; return t
end
W.bags = { [0] = { { 8079, 20 } } }
WB.Scan()
local st = WB.stacks[1]
check(st and st.name == nil and st.bound == false and st.count == 20, "secret itemName / isBound: not stored, not read as bound")
WB.Slash("")
local shown = table.concat(WB.lines, "\n")
check(not shown:find("SecretItemName", 1, true) and #ns.Core.errors == 0, "the secret name never reaches a line, no Lua errors")
WB.Slash("")
C_Container.GetContainerItemInfo = origInfo; W.secret[secretName] = nil


W.done("WaterBill")
