-- Water Bill: list or drink? For conjured water / food on WoW: Forever. Written from scratch (MIT).
--
-- Forever lets conjured items go on the auction house. This box answers, per stack in your bags: LIST it or DRINK it.
--   * A verdict is given only when the item's vendor price is 0 (all conjured items are; anything with a vendor price
--     just shows that price, because selling to a vendor is a different question).
--   * Whether the AH takes the item is asked live: C_AuctionHouse.IsSellItemValid on the real bag slot. Bound = DRINK.
--   * The price is your own PriceLog scan, through the Kenny hub (ns.Hub.GetPrice), the same way GoldPerSpot reads it.
--     No scan = "no price scan", never a guess. Prices are labelled "before AH cut".
--   * The deposit is read live from the game (CalculateCommodityDeposit / CalculateItemDeposit) only while the AH is
--     open; it is never hard-coded. No deposit from the game = "deposit unknown" and no LIST verdict.
--     Duration: the one picked in Blizzard's sell frame (CVar auctionHouseDurationDropdown, which the sell frame itself
--     reads: Blizzard_AuctionHouseSellFrame.lua) when readable, else index 1. On Forever 1/2/3 = 2/8/24 h
--     (GlobalStrings 70862 AUCTION_DURATION_ONE/TWO/THREE); every deposit is labelled "for a N h post".
--   * LIST needs price x count x (1 - AH cut) > deposit. The cut is an ASSUMPTION from player sources, not game data (the
--     UI only has the label AUCTION_HOUSE_CUT_COLON, no rate): 5% at a faction house, 15% at the neutral (goblin) house,
--     the same rates Kenny's NeutralFlip uses. The house is told apart the way NeutralFlip does it (uiMap of the three
--     goblin zones, else the zone / subzone name); when it can't be told, the worse 15% is used and the box says so.
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
-- Same detection as NeutralFlip: Classic-era uiMapIDs (Stranglethorn Vale 1434, Tanaris 1446, Winterspring 1452; not
-- confirmed for Forever), then the English town / zone names.
WB.NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }
WB.NEUTRAL_NAMES = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true,
  ["Tanaris"] = true, ["Winterspring"] = true, ["Stranglethorn Vale"] = true, ["The Cape of Stranglethorn"] = true }

-- "faction" / "neutral" / "unknown", the cut for it, and how it was decided
function WB.House()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C.SafeNumber(FS.Call(C_Map.GetBestMapForUnit, "player"))
  if mapID and WB.NEUTRAL_MAPS[mapID] then return "neutral", WB.CUT.neutral, "map " .. mapID end
  local function text(fn) local v = fn and FS.Call(fn); if type(v) == "string" and not C.IsSecret(v) then return v end end
  local zone, sub = text(GetRealZoneText), text(GetSubZoneText)
  if WB.NEUTRAL_NAMES[sub or ""] or WB.NEUTRAL_NAMES[zone or ""] then return "neutral", WB.CUT.neutral, "zone " .. (zone or "") .. "/" .. (sub or "") end
  if (zone or "") == "" and (sub or "") == "" and not mapID then return "unknown", WB.CUT.unknown, "zone unreadable" end
  return "faction", WB.CUT.faction, "zone " .. (zone or "") .. "/" .. (sub or "")
end
function WB.CutLabel()
  local kind, cut = WB.House()
  local pct = math.floor(cut * 100 + 0.5)
  if kind == "unknown" then return (L["house unknown: %d%% cut assumed"]):format(pct) end
  return (kind == "neutral" and L["neutral house: %d%% cut assumed"] or L["faction house: %d%% cut assumed"]):format(pct)
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
        if not s then s = { itemID = id, count = 0, bound = false, bag = bag, slot = slot, name = info.itemName }; found[id] = s; order[#order + 1] = s end
        s.count = s.count + (C.SafeNumber(info.stackCount) or 1)
        if info.isBound == true then s.bound = true end
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
  if s.bound then s.verdict, s.why = drink, L["bound"]; return s end
  s.valid = WB.AHTakes(s)
  if s.valid == false then s.verdict, s.why = drink, L["the AH won't take it"]; return s end
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
  if net <= 0 then s.why = L["not worth the deposit"] end
  return s
end

function WB.Post(h) return (L["for a %d h post"]):format(h or 2) end

function WB.LineFor(s)
  local name = (s.name or ("item " .. s.itemID)) .. " x" .. s.count
  local v = s.verdict
  if v == "LIST" then
    return ("|cffffd100%s|r %s: ~%s %s, %s %s %s"):format(L["LIST"], name, WB.Money(s.worth), L["before AH cut"],
      L["deposit"], WB.Money(s.deposit), WB.Post(s.hours))
  elseif v == "DRINK" or v == "EAT" then
    return ("|cffd8f3ff%s|r %s: %s"):format(v == "EAT" and L["EAT"] or L["DRINK"], name, s.why or "")
  elseif v == "vendor" then return ("%s: %s %s"):format(name, L["vendor price"], WB.Money(s.vendor))
  elseif v == "noprice" then return ("%s: %s"):format(name, L["no price scan"])
  elseif v == "nodeposit" then
    return ("%s: ~%s %s, %s"):format(name, WB.Money(s.worth), L["before AH cut"], WB.ahOpen and L["deposit unknown"] or L["deposit unknown (open the AH)"])
  elseif v == "ask" then return ("%s: ~%s %s, %s"):format(name, WB.Money(s.worth), L["before AH cut"], L["the AH answers when it's open"])
  end
  return ("%s: %s"):format(name, L["item data loading"])
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
  FS.Status(KEY, WB.ahOpen and (L["at the AH"] .. " · " .. WB.CutLabel()) or "", "Mist")
  FS.State(KEY, "active")
end
WB.Height = function() return 50 + 14 * math.max(0, #WB.lines - 1) end

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
