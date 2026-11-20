-- Water Bill: list or drink? For conjured water / food on WoW: Forever. Written from scratch (MIT).
--
-- Forever lets conjured items go on the auction house. This box answers, per stack in your bags: LIST it or DRINK it.
--   * A verdict is given only when the item's vendor price is 0 (all conjured items are; anything with a vendor price
--     just shows that price, because selling to a vendor is a different question).
--   * Whether the AH takes the item is asked live: C_AuctionHouse.IsSellItemValid on the real bag slot. Bound = DRINK.
--   * The price is your own PriceLog scan, through the Kenny hub (ns.Hub.GetPrice), the same way GoldPerSpot reads it.
--     No scan = "no price scan", never a guess. Prices are labelled "before AH cut".
--   * The deposit is read live from the game (CalculateCommodityDeposit / CalculateItemDeposit) only while the AH is
--     open; it is never hard-coded. No deposit from the game = DEPOSIT? and no LIST verdict.
--     Duration: the one picked in Blizzard's sell frame (CVar auctionHouseDurationDropdown, which the sell frame itself
--     reads: Blizzard_AuctionHouseSellFrame.lua) when readable, else index 1. On Forever 1/2/3 = 2/8/24 h
--     (GlobalStrings 70862 AUCTION_DURATION_ONE/TWO/THREE); every deposit is shown with its post length, e.g. 10s50c/2h.
--   * LIST needs price x count x (1 - AH cut) > deposit. The cut is an ASSUMPTION from player sources, not game data (the
--     UI only has the label AUCTION_HOUSE_CUT_COLON, no rate): 5% at a faction house, 15% at the neutral (goblin) house,
--     the same rates Kenny's NeutralFlip uses. The house comes from the uiMap (IDs confirmed in UiMap 70862), else the zone
--     name on an English client only; when it can't be told, the worse 15% is used and the box says so.
--     Displayed prices stay "before AH cut".
-- It never lists, casts, sells or moves anything. Shown at the AH, at the mailbox or with /frost water; never in combat.
local ADDON, ns = ...
local C, Core, FS = ns.Compat, ns.Core, ns.FrostSuite
local L = Core.L

local WB = {}
KennyWaterBill = WB
ns.WB = WB
local KEY = "WaterBill"
local SCHEMA = 1
WB.HOURS = { 2, 8, 24 } -- AUCTION_DURATION_ONE/TWO/THREE, GlobalStrings 70862
-- AH cut by house: assumptions from player sources (NeutralFlip, Forever guides), not game data.
WB.CUT = { faction = 0.05, neutral = 0.15, unknown = 0.15 }
-- Which house: confirmed uiMapIDs first (UiMap + UiMapAssignment, build 70862, saved in wow-research/raw/deb-db2/70862).
-- The goblin towns have no uiMap of their own: Booty Bay (area 35) is in Stranglethorn Vale (area 33 -> uiMap 1434),
-- Gadgetzan (976) in Tanaris (440 -> 1446), Everlook (2255) in Winterspring (618 -> 1452) (AreaTable 70862).
WB.NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }
-- Classic-era zone / city / battleground uiMaps in UiMap 70862 (Type 3 or 6) with no neutral auction house. The
-- Forever-only zones (2482, 2521, 2524, 2548, 2652, 2665) are left out: nothing confirms their auction houses, so they
-- fall back to the zone name (English clients) or unknown (15%).
WB.FACTION_MAPS = {}
for _, id in ipairs({ 1411, 1412, 1413, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429,
  1430, 1431, 1432, 1433, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1447, 1448, 1449, 1450, 1451,
  1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461 }) do WB.FACTION_MAPS[id] = true end
-- Name fallback (as NeutralFlip), trusted only on an English client: on any other locale a non-match proves nothing.
WB.NEUTRAL_NAMES = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true,
  ["Tanaris"] = true, ["Winterspring"] = true, ["Stranglethorn Vale"] = true, ["The Cape of Stranglethorn"] = true }
WB.ENGLISH = { enUS = true, enGB = true }

-- "faction" / "neutral" / "unknown", the cut for it, and how it was decided. "faction" only from a confirmed map or an
-- English zone name; anything else is "unknown" (the worse 15%).
function WB.House()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C.SafeNumber(FS.Call(C_Map.GetBestMapForUnit, "player"))
  if mapID and WB.NEUTRAL_MAPS[mapID] then return "neutral", WB.CUT.neutral, "map " .. mapID end
  if mapID and WB.FACTION_MAPS[mapID] then return "faction", WB.CUT.faction, "map " .. mapID end
  local function text(fn) local v = fn and FS.Call(fn); if type(v) == "string" and not C.IsSecret(v) then return v end end
  local zone, sub = text(GetRealZoneText) or "", text(GetSubZoneText) or ""
  local locale = text(GetLocale)
  if WB.ENGLISH[locale or ""] then
    if WB.NEUTRAL_NAMES[sub] or WB.NEUTRAL_NAMES[zone] then return "neutral", WB.CUT.neutral, "zone " .. zone .. "/" .. sub end
    if zone ~= "" or sub ~= "" then return "faction", WB.CUT.faction, "zone " .. zone .. "/" .. sub end
  end
  return "unknown", WB.CUT.unknown, ("map %s not confirmed, zone name not usable (%s client)"):format(tostring(mapID), tostring(locale))
end
-- Short form for the box status: "faction 5% assumed", "neutral 15% assumed", "house unknown, 15% assumed".
function WB.CutShort()
  local kind, cut = WB.House()
  local pct = math.floor(cut * 100 + 0.5)
  if kind == "unknown" then return (L["house unknown, %d%% assumed"]):format(pct) end
  return (kind == "neutral" and L["neutral %d%% assumed"] or L["faction %d%% assumed"]):format(pct)
end

-- duration index (1-3) and whether it came from the player's pick in the sell frame
function WB.Duration()
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  local v = get and tonumber(FS.Call(get, "auctionHouseDurationDropdown"))
  if v and WB.HOURS[v] then return v, true end
  return 1, false
end

-- Item IDs from the game's Item table (build 70862); all have SellPrice 0 there.
WB.ITEMS = {
  [5350] = "water", [2288] = "water", [2136] = "water", [3772] = "water", [8077] = "water", [8078] = "water", [8079] = "water", [231778] = "water",
  [5349] = "food", [1113] = "food", [1114] = "food", [1487] = "food", [8075] = "food", [8076] = "food", [22895] = "food",
  [274964] = "mote", -- Mote of Unstable Magic: SellPrice 200 in ItemSparse, so it only shows its vendor price
}
WB.MAX_LINES = 6

local db, row
local migrations = {}
WB.ahOpen, WB.mailOpen, WB.asked = false, false, false
WB.stacks, WB.lines = {}, {}

function WB.Money(c)
  if not c then return "-" end
  c = math.floor(c + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return ("%ds %dc"):format(s, cp) end
  return ("%dc"):format(cp)
end

-- ---------- bag scan ----------
function WB.Scan()
  local found, order = {}, {}
  local CC = C_Container
  if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return nil end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = FS.Call(CC.GetContainerNumSlots, bag) or 0
    for slot = 1, n do
      local info = FS.Call(CC.GetContainerItemInfo, bag, slot)
      local id = type(info) == "table" and C.SafeNumber(info.itemID)
      if id and WB.ITEMS[id] then
        local s = found[id]
        -- name and bound flag are used only when plain (a secret value is never read or compared)
        local nm = info.itemName
        if C.IsSecret(nm) or type(nm) ~= "string" or nm == "" then nm = nil end
        if not s then s = { itemID = id, count = 0, bound = false, bag = bag, slot = slot, name = nm }; found[id] = s; order[#order + 1] = s end
        s.name = s.name or nm
        s.count = s.count + (C.SafeNumber(info.stackCount) or 1)
        if not C.IsSecret(info.isBound) and info.isBound == true then s.bound = true end
      end
    end
  end
  WB.stacks = order
  return order
end

local function location(s)
  if ItemLocation and ItemLocation.CreateFromBagAndSlot then return FS.Call(ItemLocation.CreateFromBagAndSlot, ItemLocation, s.bag, s.slot) end
end
-- true / false / nil (can't ask)
function WB.AHTakes(s)
  local loc = location(s)
  if not (loc and C_AuctionHouse and C_AuctionHouse.IsSellItemValid) then return nil end
  local v = FS.Call(C_AuctionHouse.IsSellItemValid, loc, false)
  if type(v) == "boolean" then return v end
  return nil
end
function WB.Deposit(s)
  if not (WB.ahOpen and C_AuctionHouse) then return nil end
  local AH = C_AuctionHouse
  local commodity
  if AH.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
    local loc = location(s)
    local st = loc and FS.Call(AH.GetItemCommodityStatus, loc)
    if st == Enum.ItemCommodityStatus.Item then commodity = false elseif st ~= nil and st ~= Enum.ItemCommodityStatus.Unknown then commodity = true end
  end
  local d
  local DURATION = WB.Duration()
  if commodity ~= false and AH.CalculateCommodityDeposit then d = C.SafeNumber(FS.Call(AH.CalculateCommodityDeposit, s.itemID, DURATION, s.count)) end
  if d == nil and commodity ~= true and AH.CalculateItemDeposit then
    local loc = location(s)
    if loc then d = C.SafeNumber(FS.Call(AH.CalculateItemDeposit, loc, DURATION, s.count)) end
  end
  return d
end
function WB.Vendor(id)
  if not (C_Item and C_Item.GetItemInfo) then return nil end
  local r = { pcall(C_Item.GetItemInfo, id) }
  if not r[1] or r[2] == nil then return nil end
  return C.SafeNumber(r[12]), r[2]
end
function WB.Price(id)
  local hub = ns.Hub
  if not (hub and hub.GetPrice) then return nil end
  local rec = hub.GetPrice(id)
  if type(rec) == "table" and C.SafeNumber(rec.p) then return rec.p, rec end
  return nil
end

-- verdict: "LIST", "DRINK" (or "EAT"), "vendor", "noprice", "ask" (go to the AH), "loading"
function WB.Judge(s)
  local vendor, name = WB.Vendor(s.itemID)
  s.name = s.name or name
  s.vendor = vendor
  if vendor == nil then s.verdict = "loading"; return s end
  if vendor > 0 then s.verdict = "vendor"; return s end
  local drink = WB.ITEMS[s.itemID] == "food" and "EAT" or "DRINK"
  if s.bound then s.verdict, s.why, s.short = drink, L["bound"], L["bound"]; return s end
  s.valid = WB.AHTakes(s)
  if s.valid == false then s.verdict, s.why, s.short = drink, L["the AH won't take it"], L["AH won't take it"]; return s end
  s.price = WB.Price(s.itemID)
  if not s.price then s.verdict = "noprice"; return s end
  s.worth = s.price * s.count
  s.deposit = WB.Deposit(s)
  s.hours = WB.HOURS[(WB.Duration())]
  if s.deposit == nil then s.verdict = "nodeposit"; return s end
  if s.valid == nil then s.verdict = "ask"; return s end
  s.house, s.cut = WB.House()
  s.net = s.worth * (1 - s.cut) - s.deposit
  local net = s.net
  s.verdict = net > 0 and "LIST" or drink
  if net <= 0 then s.why, s.short = L["not worth the deposit"], L["deposit too high"] end
  return s
end


-- One short line per stack (VISUAL_SPEC section 9): VERDICT, item, xN, then the figures. The verdict word comes first and
-- the figures last; when the line is too wide for the box, the ITEM NAME is shortened with "…" first, so the price, the
-- deposit (or DEPOSIT? when it's unknown) and the reason stay visible. Only when the figures alone are too wide (huge gold or
-- xN) are they cut too, from the right with "…" (see WB.Fit). "Conjured " is left off (every item here is conjured);
-- tooltips keep the full name.
--   LIST Crystal Water x40 ~32s 0c · 10s50c/2h      (worth before the AH cut · deposit / post length)
--   DRINK Sparkling Water x20 · deposit too high     EAT Cinnamon Roll x20 · AH won't take it   DRINK … · bound
--   VENDOR Mote of Unstable Magic x5 2s 0c            DEPOSIT? Crystal Water x40 ~32s 0c        ASK Crystal Water x40 ~32s 0c
--   Crystal Water x40 · no price scan                 Crystal Water x40 · item data loading
WB.TEXT_W = 218   -- body line width: FrostSuite row 240 - 2 x 9, less 4 px so the client never adds its own "..."
local measure
function WB.Width(text)
  if not measure and row then measure = row:CreateFontString(nil, "OVERLAY", FS.FONT.BODY); measure:Hide(); WB.measure = measure end
  if measure then
    measure:SetText(text)
    local ok, w = pcall(function() return measure:GetStringWidth() end)
    if ok and type(w) == "number" and not C.IsSecret(w) then return w end
  end
  return #(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6
end
-- head .. name .. tail, with name cut (whole characters, then "…") until it fits WB.TEXT_W.
-- Last resort, when even "head … tail" is too wide (huge gold, a huge xN): drop the name, then cut the tail from the
-- right with "…"; if the head alone is too wide, cut it as plain text. The line is always within WB.TEXT_W, so the
-- client never wraps or cuts it on its own.
local function trim(s) return (s:sub(1, -2):gsub("[\128-\255]+$", ""):gsub("%s+$", "")) end
function WB.Fit(head, name, tail)
  local line = head .. name .. tail
  if WB.Width(line) <= WB.TEXT_W then return line end
  local cut = name
  while cut ~= "" do
    cut = trim(cut)
    line = head .. cut .. "…" .. tail
    if WB.Width(line) <= WB.TEXT_W then return line end
  end
  if WB.Width(head .. "…" .. tail) <= WB.TEXT_W then return head .. "…" .. tail end
  local t = tail
  while t ~= "" do
    t = trim(t)
    line = head .. t .. "…"
    if WB.Width(line) <= WB.TEXT_W then return line end
  end
  if WB.Width(head .. "…") <= WB.TEXT_W then return head .. "…" end
  local h = head:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")   -- plain text, so a cut never splits a colour code
  while h ~= "" do
    h = trim(h)
    if WB.Width(h .. "…") <= WB.TEXT_W then return h .. "…" end
  end
  return "…"
end
function WB.ShortName(s)
  return ((s.name or ("item " .. s.itemID)):gsub("^" .. L["Conjured"] .. " ", ""))
end
-- deposit as one token: 10s50c/2h
function WB.DepositToken(s) return (WB.Money(s.deposit):gsub(" ", "")) .. "/" .. (s.hours or 2) .. "h" end
local function word(hex, text) return ("|cff%s%s|r "):format(hex, text) end
function WB.LineFor(s)
  local name, v, n = WB.ShortName(s), s.verdict, " x" .. s.count
  if v == "LIST" then
    return WB.Fit(word("ffd100", L["LIST"]), name, ("%s ~%s · %s"):format(n, WB.Money(s.worth), WB.DepositToken(s)))
  elseif v == "DRINK" or v == "EAT" then
    return WB.Fit(word("d8f3ff", v == "EAT" and L["EAT"] or L["DRINK"]), name, n .. (s.short and (" · " .. s.short) or ""))
  elseif v == "vendor" then return WB.Fit(word("b8b8b8", L["VENDOR"]), name, ("%s %s"):format(n, WB.Money(s.vendor)))
  elseif v == "nodeposit" then return WB.Fit(word("bcd3e6", L["DEPOSIT?"]), name, ("%s ~%s"):format(n, WB.Money(s.worth)))
  elseif v == "ask" then return WB.Fit(word("bcd3e6", L["ASK"]), name, ("%s ~%s"):format(n, WB.Money(s.worth)))
  elseif v == "noprice" then return WB.Fit("", name, n .. " · " .. L["no price scan"])
  end
  return WB.Fit("", name, n .. " · " .. L["item data loading"])
end

function WB.Showing() return (WB.ahOpen or WB.mailOpen or WB.asked) and not C.InCombat() end

function WB.Update()
  if not row then return end
  if not WB.Showing() then FS.State(KEY, "hidden"); return end
  local stacks = WB.Scan()
  local lines, listWorth, n = {}, 0, 0
  if stacks == nil then lines[1] = L["can't read your bags here"]
  else
    for _, s in ipairs(stacks) do
      WB.Judge(s)
      if s.verdict == "LIST" then listWorth = listWorth + s.worth end
      n = n + 1
      if #lines < WB.MAX_LINES then lines[#lines + 1] = WB.LineFor(s) end
    end
    if n > WB.MAX_LINES then lines[#lines + 1] = ("+%d %s"):format(n - WB.MAX_LINES, L["more"]) end
    if n == 0 then lines[1] = L["No conjured water or food in your bags."] end
  end
  WB.lines = lines
  FS.Headline(KEY, listWorth > 0 and ("%s ~%s %s"):format(L["LIST"], WB.Money(listWorth), L["before AH cut"]) or L["Water Bill"], listWorth > 0 and "CoinGold" or "Snow")
  FS.ClearLines(KEY)
  for i, l in ipairs(lines) do FS.Line(KEY, i, l) end
  FS.Status(KEY, WB.ahOpen and (L["AH"] .. " · " .. WB.CutShort()) or "", "Mist")   -- e.g. "AH · faction 5% assumed"
  FS.State(KEY, "active")
end
-- Lines start at y -44 and step 14 (FrostSuite r4 BodyHeight): 44 + 14 per line + 6 under the last one. A long AH status
-- that can't sit beside the title gets one more line from the library.
WB.Height = function() return FS.BodyHeight(math.max(1, #WB.lines)) end

-- Item tooltip line through the Kenny hub (shared with the other Kenny addons).
function WB.Tooltip(tooltip, itemID)
  if not (WB.ITEMS[itemID] and tooltip and tooltip.AddLine) then return end
  local vendor = WB.Vendor(itemID)
  if vendor ~= 0 then return end
  local p = WB.Price(itemID)
  tooltip:AddLine("Water Bill: " .. (p and ("~%s %s %s"):format(WB.Money(p), L["each"], L["before AH cut"]) or L["no price scan"]), 0.85, 0.95, 1)
end

function WB.Slash(msg)
  local cmd = (msg or ""):lower():match("^(%S*)")
  if cmd == "debug" then for _, l in ipairs(WB.DetectionLines()) do Core.Print(l) end
  elseif C.InCombat() then Core.Print(L["Water Bill waits until combat ends."])
  else WB.asked = not WB.asked; WB.Update() end
end

function WB.DetectionLines()
  local d, picked = WB.Duration()
  local kind, cut, how = WB.House()
  local out = { ("AH cut: %d%% for a %s house (%s); an assumption from player sources, not game data"):format(math.floor(cut * 100 + 0.5), kind, how),
    ("duration: %d h (%s)"):format(WB.HOURS[d], picked and "your pick in the sell frame" or "default; your pick isn't readable"),
    ("AH open: %s, mailbox open: %s; price source: %s"):format(tostring(WB.ahOpen), tostring(WB.mailOpen),
    (ns.Hub and ns.Hub.prices and next(ns.Hub.prices)) and "Kenny hub (PriceLog)" or "none (install PriceLog and scan)") }
  for _, s in ipairs(WB.Scan() or {}) do
    WB.Judge(s)
    out[#out + 1] = ("%d x%d: vendor %s, bound %s, AH takes it %s, price %s, deposit %s (%d h), after cut and deposit %s -> %s"):format(
      s.itemID, s.count, tostring(s.vendor), tostring(s.bound), tostring(s.valid), tostring(s.price), tostring(s.deposit),
      s.hours or 2, tostring(s.net), s.verdict)
  end
  return out
end

-- ---------- wiring ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "BAG_UPDATE_DELAYED",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
local function later() C_Timer.After(0.2, function() Core.SafeCall("update", WB.Update) end) end
local handlers = {
  PLAYER_LOGIN = WB.Update,
  AUCTION_HOUSE_SHOW = function() WB.ahOpen = true; later() end,
  AUCTION_HOUSE_CLOSED = function() WB.ahOpen = false; WB.asked = false; WB.Update() end,
  MAIL_SHOW = function() WB.mailOpen = true; WB.Update() end,
  MAIL_CLOSED = function() WB.mailOpen = false; WB.asked = false; WB.Update() end,
  BAG_UPDATE_DELAYED = function() if WB.Showing() then WB.Update() end end,
  PLAYER_REGEN_DISABLED = function() FS.State(KEY, "hidden") end,
  PLAYER_REGEN_ENABLED = WB.Update,
}
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyWaterBillDB, migrations, SCHEMA)
    KennyWaterBillDB = db
    row = FS.Register(KEY, db, { title = L["Water Bill"], slash = WB.Slash, help = "(toggle) | debug", debug = Core.PrintDebug, height = WB.Height })
    if ns.Hub and ns.Hub.AddTooltip then ns.Hub.AddTooltip(ADDON, 60, WB.Tooltip) end
    Core.SafeCall("update", WB.Update)
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = "/frost water",
  required = { "C_Container.GetContainerItemInfo", "C_Item.GetItemInfo", "C_Timer.After" },
  optional = { "C_AuctionHouse.IsSellItemValid", "C_AuctionHouse.CalculateCommodityDeposit", "C_AuctionHouse.CalculateItemDeposit",
    "C_AuctionHouse.GetItemCommodityStatus", "ItemLocation.CreateFromBagAndSlot", "C_CVar.GetCVar" },
  db = function() return db end,
  firstRun = { L["Water Bill is ready: open the auction house or mailbox (or /frost water) to see whether your conjured water and food are worth listing."] },
  debugLines = function() return WB.DetectionLines() end })
