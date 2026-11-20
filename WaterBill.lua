-- Water Bill: list or drink? For conjured water / food on WoW: Forever. Written from scratch (MIT).
--
-- Forever lets conjured items go on the auction house. This box answers, per stack in your bags: LIST it or DRINK it.
--   * A verdict is given only when the item's vendor price is 0 (all conjured items are; anything with a vendor price
--     just shows that price, because selling to a vendor is a different question).
--   * Whether the AH takes the item is asked live: C_AuctionHouse.IsSellItemValid on the real bag slot. Bound = DRINK.
--   * The price is your own PriceLog scan, through the Kenny hub (ns.Hub.GetPrice), the same way GoldPerSpot reads it.
--     No scan = "no price scan", never a guess. Prices are labelled "before AH cut".
--   * The deposit is read live from the game (CalculateCommodityDeposit / CalculateItemDeposit, 12 h) only while the
--     AH is open; it is never hard-coded. Away from the AH the line says "deposit at the AH".
-- It never lists, casts, sells or moves anything. Shown at the AH, at the mailbox or with /frost water; never in combat.
local ADDON, ns = ...
local C, Core, FS = ns.Compat, ns.Core, ns.FrostSuite
local L = Core.L

local WB = {}
KennyWaterBill = WB
ns.WB = WB
local KEY = "WaterBill"
local SCHEMA = 1
local DURATION = 1 -- luaIndex 1 = the shortest (12 h) listing, the cheapest deposit

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
  if s.valid == nil then s.verdict = "ask"; return s end
  local net = s.worth - (s.deposit or 0)
  s.verdict = net > 0 and "LIST" or drink
  if net <= 0 then s.why = L["not worth the deposit"] end
  return s
end

function WB.LineFor(s)
  local name = (s.name or ("item " .. s.itemID)) .. " x" .. s.count
  local v = s.verdict
  if v == "LIST" then
    return ("|cff7fd8ff%s|r %s: ~%s %s, %s"):format(L["LIST"], name, WB.Money(s.worth), L["before AH cut"],
      s.deposit and (L["deposit"] .. " " .. WB.Money(s.deposit)) or L["deposit at the AH"])
  elseif v == "DRINK" or v == "EAT" then
    return ("|cffd8f3ff%s|r %s: %s"):format(v == "EAT" and L["EAT"] or L["DRINK"], name, s.why or "")
  elseif v == "vendor" then return ("%s: %s %s"):format(name, L["vendor price"], WB.Money(s.vendor))
  elseif v == "noprice" then return ("%s: %s"):format(name, L["no price scan"])
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
  FS.Headline(KEY, listWorth > 0 and ("%s ~%s %s"):format(L["LIST"], WB.Money(listWorth), L["before AH cut"]) or L["Water Bill"], "Snow")
  FS.ClearLines(KEY)
  for i, l in ipairs(lines) do FS.Line(KEY, i, l) end
  FS.Status(KEY, WB.ahOpen and L["at the AH"] or "", "Mist")
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
  local out = { ("AH open: %s, mailbox open: %s; price source: %s"):format(tostring(WB.ahOpen), tostring(WB.mailOpen),
    (ns.Hub and ns.Hub.prices and next(ns.Hub.prices)) and "Kenny hub (PriceLog)" or "none (install PriceLog and scan)") }
  for _, s in ipairs(WB.Scan() or {}) do
    WB.Judge(s)
    out[#out + 1] = ("%d x%d: vendor %s, bound %s, AH takes it %s, price %s, deposit %s -> %s"):format(s.itemID, s.count,
      tostring(s.vendor), tostring(s.bound), tostring(s.valid), tostring(s.price), tostring(s.deposit), s.verdict)
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
    "C_AuctionHouse.GetItemCommodityStatus", "ItemLocation.CreateFromBagAndSlot" },
  db = function() return db end,
  firstRun = { L["Water Bill is ready: open the auction house or mailbox (or /frost water) to see whether your conjured water and food are worth listing."] },
  debugLines = function() return WB.DetectionLines() end })
