-- FrostSuite-1.0: the shared dock, flash rule and /frost command for Kenny's Frost Mage suite. Written from scratch (MIT).
-- Canonical copy: frost-suite-lib/FrostSuite.lua. Every suite addon embeds an identical copy in
-- Libs/FrostSuite (tools/check_suite_lib.sh fails on drift). Do not edit a copy.
-- Load rule (LibStub style, without needing LibStub): all copies share one global table, FrostSuite_1_0. The copy with the
-- highest MINOR installs its functions; an older or equal copy returns early. State (rows, anchor) lives in the table, so an
-- upgrade keeps it. Each addon works alone: with one addon loaded the dock is a single row.
-- Look and numbers come from UI Bot's VISUAL_SPEC.md (v1): FS.C, FS.FONT, FS.PALETTE and FS.ADDONS are the drop-in tables.
local _, ns = ...
local MAJOR, MINOR = "FrostSuite-1.0", 6
local FS = _G.FrostSuite_1_0
if type(FS) ~= "table" then FS = {}; _G.FrostSuite_1_0 = FS end
ns.FrostSuite = FS
if (FS.minor or 0) >= MINOR then return end
FS.major, FS.minor = MAJOR, MINOR
FS.rows = FS.rows or {}       -- key -> row frame
FS.order = FS.order or {}     -- keys, in dock order
FS.lastSound = FS.lastSound or -100
local L = (ns.Core and ns.Core.L) or setmetatable({}, { __index = function(_, k) return k end })

FS.ANCHOR_NAME = "FrostSuiteAnchor"
FS.C = {
  WIDTH = 240, GAP = 2, STRIP_H = 28, EDGE = 14, INSET = 3,
  -- r4 layout: text x = 9 from each side; status right edge 9 (26 beside the padlock); title starts at 7 + 16 + 4 = 27.
  -- Headline at y -24; bar or body line 1 at y -44, body lines step FONT.LINE_H; 6 px under the last line;
  -- a bottom button (Shatter Happens' Reset: 18 tall at y +7) adds FOOTER_H. Status needs STATUS_GAP clear of the title.
  EDGE_X = 9, LOCK_X = 26, TITLE_X = 27, STATUS_GAP = 8, HEAD_Y = 24, BODY_Y = 44, BAR_H = 8, PAD_BOTTOM = 6, FOOTER_H = 24,
  BG_ALPHA = 0.92, GLOW_PEAK = 0.15, PULSE_SEC = 0.5, PULSE_MIN_GAP = 3, SOUND_MIN_GAP = 4,
  RELAYOUT_AFTER_COMBAT = 2, RELAYOUT_MIN_GAP = 1,
  SCALE_MIN = 0.8, SCALE_MAX = 1.4, SCALE_STEP = 0.1,
  DEFAULT_POINT = { "TOPLEFT", "CENTER", 220, 160 },
  LEARN_BTN_W = 128, LEARN_BTN_H = 18,   -- r5: "Hide until I learn", UIPanelButtonTemplate, BOTTOMLEFT (8, 7) like Reset
  BG = "Interface\\Tooltips\\UI-Tooltip-Background",      -- 137056
  BORDER = "Interface\\Tooltips\\UI-Tooltip-Border",      -- 137057
  BAR = "Interface\\TargetingFrame\\UI-StatusBar",        -- 137012
  LOCKED = "Interface\\Buttons\\LockButton-Locked-Up",    -- 525906
  UNLOCKED = "Interface\\Buttons\\LockButton-Unlocked-Up",-- 525908
  LOCK_TEXCOORD = { 6 / 32, 25 / 32, 7 / 32, 25 / 32 },
}
FS.FONT = { TITLE = "GameFontNormal", STATUS = "GameFontHighlight", HEAD = "GameFontNormalLarge", BODY = "GameFontHighlight", LINE_H = 14 }
FS.PALETTE = {
  FrostNight = { 0.04, 0.08, 0.16, "0a1429" }, FrostEdge = { 0.41, 0.80, 0.94, "69ccf0" },
  FrostTitle = { 0.75, 0.94, 1.00, "bfefff" }, Snow = { 1, 1, 1, "ffffff" }, LabelGold = { 1.00, 0.82, 0.00, "ffd100" },
  Mist = { 0.74, 0.83, 0.90, "bcd3e6" }, StopPink = { 1.00, 0.70, 0.70, "ffb3b3" }, StopGlow = { 1.00, 0.42, 0.42, "ff6b6b" },
  LanceCyan = { 0.50, 0.86, 1.00, "7fdbff" }, BlastOrange = { 1.00, 0.60, 0.30, "ff9a4d" },
  ScoopBlue = { 0.62, 0.91, 1.00, "9fe7ff" }, ReefTeal = { 0.25, 0.88, 0.82, "3fe0d0" }, ShardLilac = { 0.82, 0.78, 1.00, "d0c8ff" },
  DrinkBlue = { 0.42, 0.78, 1.00, "6cc8ff" }, VendorGrey = { 0.72, 0.72, 0.72, "b8b8b8" }, CoinGold = { 1.00, 0.82, 0.00, "ffd100" },
}
-- order = dock slot AND alert priority (lower wins); priority 0 = never flashes, never plays a sound.
-- Icons are the real spell icons from SpellMisc (build 1.60.1.70862) where the addon follows one spell.
-- Heights (r4) are FS.BodyHeight(lines[, footer]) = 44 + 14 * lines + 6 (+ 24): 64 = 1 line, 78 = 2 lines, 116 = 3 lines + Reset.
FS.ADDONS = {
  HoldTheWeather      = { order = 1, priority = 1, cmd = "weather", accent = "StopPink", glow = "StopGlow", style = "HOLD", h = 50, sound = 569310,
                          icon = 135848 },  -- Frost Nova (SpellMisc 10230)
  EightSecondArgument = { order = 2, priority = 2, cmd = "lance", accent = "LanceCyan", style = "TEXT", h = 78,
                          icon = 135844 },  -- Ice Lance (SpellMisc 400640)
  ConeOfPlenty        = { order = 3, priority = 3, cmd = "cone", accent = "ScoopBlue", glow = "ScoopBlue", style = "PULSE", h = 64, sound = 567407, soundDefault = false,
                          icon = 135852 },  -- Cone of Cold (SpellMisc 10161)
  BarrierReef         = { order = 4, priority = 4, cmd = "reef", accent = "ReefTeal", glow = "ReefTeal", style = "PULSE", h = 78, sound = 569286,
                          icon = 135988 },  -- Ice Barrier (SpellMisc 13033)
  ShatterHappens      = { order = 5, priority = 5, cmd = "shatter", accent = "ShardLilac", glow = "ShardLilac", style = "PULSE", h = 78, idleH = 116, footer = true,
                          icon = 236227 },  -- Fingers of Frost (SpellMisc 400669)
  WaterBill           = { order = 6, priority = 0, cmd = "water", utility = true, h = 64, maxLines = 6,
                          icon = "Interface\\Icons\\INV_Drink_18" },  -- 132805
  ScrollCall          = { order = 7, priority = 0, cmd = "scroll", utility = true, h = 64,
                          icon = 8188276 },  -- Comprehend Scroll (SpellMisc 1296017)
}

local function now() return GetTime() end
local function pcolor(name) return FS.PALETTE[name] or FS.PALETTE.Snow end
function FS.InCombat()
  if C_RestrictedActions and C_RestrictedActions.InCombatLockdown then
    local ok, v = pcall(C_RestrictedActions.InCombatLockdown)
    if ok then return v == true end
  end
  return UnitAffectingCombat ~= nil and UnitAffectingCombat("player") == true
end

-- ---------- shared detection helpers: never guess a secret value ----------
-- An aura read is trusted only when the client says it is readable right now: restrictions off, the spell flagged
-- never-secret (C_Secrets.GetSpellAuraSecrecy == 0), or C_Secrets.ShouldSpellAuraBeSecret(id) == false. Otherwise an empty
-- answer could mean "hidden" as well as "not up", so it is not used.
function FS.IsSecret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) == true end
function FS.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or FS.IsSecret(v) then return nil end
  return v
end
function FS.Restricted()
  local S = C_Secrets
  local v = S and FS.Call(S.HasSecretRestrictions)
  if v == nil and type(S) ~= "table" and issecretvalue == nil then return false end
  return v
end
function FS.AuraSecrecy(id) local S = C_Secrets; local v = S and FS.Call(S.GetSpellAuraSecrecy, id); return type(v) == "number" and v or nil end
function FS.CastSecrecy(id) local S = C_Secrets; local v = S and FS.Call(S.GetSpellCastSecrecy, id); return type(v) == "number" and v or nil end
local function canRead(unit)
  local U = C_UnitAuras
  if not U then return false end
  if unit == "player" then return type(U.GetPlayerAuraBySpellID) == "function" or type(U.GetUnitAuraBySpellID) == "function" end
  return type(U.GetUnitAuraBySpellID) == "function"
end
function FS.AuraNeverSecret(id) return FS.Restricted() == false or FS.AuraSecrecy(id) == 0 end
function FS.AuraReadableNow(id, unit)
  if not canRead(unit or "player") then return false end
  if FS.AuraNeverSecret(id) then return true end
  local S = C_Secrets
  return S ~= nil and FS.Call(S.ShouldSpellAuraBeSecret, id) == false
end
-- Returns aura (table or nil), readable (true when the answer can be trusted).
function FS.ReadAura(unit, id)
  if not FS.AuraReadableNow(id, unit) then return nil, false end
  local U = C_UnitAuras
  local fn = (unit == "player" and U.GetPlayerAuraBySpellID) or U.GetUnitAuraBySpellID
  local ok, a
  if fn == U.GetPlayerAuraBySpellID then ok, a = pcall(fn, id) else ok, a = pcall(fn, unit, id) end
  if not ok or FS.IsSecret(a) then return nil, false end
  return type(a) == "table" and a or nil, true
end
function FS.AuraField(aura, key)
  if type(aura) ~= "table" then return nil end
  local ok, v = pcall(function() return aura[key] end)
  if not ok or FS.IsSecret(v) or type(v) ~= "number" then return nil end
  return v
end
-- Talent rank by the talent's spell ID, read from the active talent config. Returns rank, maxRanks, or nil when unknown.
function FS.TalentRank(spellID)
  local CT, T = C_ClassTalents, C_Traits
  if not (CT and T and CT.GetActiveConfigID and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo and T.GetEntryInfo
    and T.GetDefinitionInfo) then return nil end
  local config = FS.Call(CT.GetActiveConfigID)
  local info = config and FS.Call(T.GetConfigInfo, config)
  if type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end
  for _, tree in ipairs(info.treeIDs) do
    for _, node in ipairs(FS.Call(T.GetTreeNodes, tree) or {}) do
      local n = FS.Call(T.GetNodeInfo, config, node)
      for _, entry in ipairs(type(n) == "table" and n.entryIDs or {}) do
        local e = FS.Call(T.GetEntryInfo, config, entry)
        local d = e and e.definitionID and FS.Call(T.GetDefinitionInfo, e.definitionID)
        if d and d.spellID == spellID then return n.currentRank or n.ranksPurchased or 0, n.maxRanks end
      end
    end
  end
  return nil
end
-- Any rank of a spell set known (C_SpellBook). nil when the client can't say.
function FS.KnowsAny(set)
  local SB = C_SpellBook
  if not (SB and type(SB.IsSpellKnown) == "function") then return nil end
  for id in pairs(set) do
    local ok, v = pcall(SB.IsSpellKnown, id)
    if ok and v == true then return true end
  end
  return false
end
function FS.IsMage() local _, class = UnitClass("player"); return class == "MAGE" end

-- ---------- r5: low-level characters (a box whose spell isn't learned yet) ----------
-- A need is { name = "Frost Nova", level = 10, spells = { [122] = 1, ... } [, talent = true] [, text = "own line"] }.
-- Levels come from the client's SpellLevels (BaseLevel) and Talent (TierID: level 10 + 5 x tier) tables.
-- FS.Missing(needs) -> the first need in the list (lowest level first) the player doesn't know yet, or nil (all known, or
-- the client can't say: then the box works as before). The box then shows one calm line and a small
-- "Hide until I learn" button (FS.NotYet), and comes back by itself when the spells are learned (FS.Learned).
function FS.PlayerLevel()
  local v = UnitLevel and FS.Call(UnitLevel, "player")
  v = type(v) == "number" and v or nil
  if FS.level and (not v or FS.level > v) then v = FS.level end   -- PLAYER_LEVEL_UP's level, before UnitLevel catches up
  return v
end
function FS.Missing(needs)
  for _, need in ipairs(needs or {}) do
    if FS.KnowsAny(need.spells or {}) == false then return need end
  end
  return nil
end
function FS.NeedText(need)
  if need.text then return need.text end
  local lvl = FS.PlayerLevel()
  local early = need.level and lvl and lvl < need.level
  if need.talent then
    return early and (L["Take %s at level %d"]):format(need.name, need.level) or (L["Take the %s talent"]):format(need.name)
  end
  return early and (L["Learn %s at level %d"]):format(need.name, need.level) or (L["Learn %s from your trainer"]):format(need.name)
end
-- "Hide until I learn" is saved per character in the addon's own SavedVariables (db.hideUntilLearned["Name-Realm"]).
-- Name or realm unreadable (secret, missing or empty): nothing is saved; the box hides for this session only.
-- r6: the character key is read secret-safe; when the name or realm can't be read, "Hide until I learn" lasts this session
-- and nothing is saved.
local function plainText(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or FS.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end
local function charKey()
  local n, r = plainText(UnitName, "player"), plainText(GetRealmName)
  if not (n and r) then return nil end
  return n .. "-" .. r
end
FS.CharKey = charKey
function FS.HiddenUntilLearned(key)
  local r = FS.rows[key]
  if not r then return false end
  if r.hideSession then return true end
  local t, k = type(r.db) == "table" and r.db.hideUntilLearned, charKey()
  return k ~= nil and type(t) == "table" and t[k] == true
end
function FS.HideUntilLearned(key)
  local r = FS.rows[key]
  if not r then return false end
  local k = charKey()
  if k and type(r.db) == "table" then
    r.db.hideUntilLearned = type(r.db.hideUntilLearned) == "table" and r.db.hideUntilLearned or {}
    r.db.hideUntilLearned[k] = true
  else
    r.hideSession = true   -- can't tell who this is: don't save, hide until reload or until learned
  end
  FS.State(key, "hidden")
  return true
end

-- ---------- shared position, lock and scale (db.suite in every addon's own SavedVariables; newest stamp wins) ----------
local function defaultSuite()
  local p = FS.C.DEFAULT_POINT
  return { point = p[1], relPoint = p[2], x = p[3], y = p[4], locked = false, scale = 1.0, stamp = 0 }
end
function FS.Suite()
  local best
  for _, key in ipairs(FS.order) do
    local s = FS.rows[key].db and FS.rows[key].db.suite
    if type(s) == "table" and (not best or (s.stamp or 0) > (best.stamp or 0)) then best = s end
  end
  return best or defaultSuite()
end
function FS.SaveSuite(changes)
  local s = {}
  for k, v in pairs(FS.Suite()) do s[k] = v end
  for k, v in pairs(changes or {}) do s[k] = v end
  s.stamp = time()
  for _, key in ipairs(FS.order) do
    local db = FS.rows[key].db
    if type(db) == "table" then local c = {}; for k, v in pairs(s) do c[k] = v end; db.suite = c end
  end
  FS.ApplySuite()
  return s
end

function FS.Anchor()
  if FS.anchor then return FS.anchor end
  local a = CreateFrame("Frame", FS.ANCHOR_NAME, UIParent)
  a:SetSize(FS.C.WIDTH, 1)
  a:SetMovable(true)
  a:SetClampedToScreen(true)
  FS.anchor = a
  return a
end
function FS.ApplySuite()
  local a, s = FS.Anchor(), FS.Suite()
  a:ClearAllPoints()
  a:SetPoint(s.point or "TOPLEFT", UIParent, s.relPoint or "CENTER", s.x or 220, s.y or 160)
  a:SetScale(s.scale or 1)
  FS.UpdateLock()
end
function FS.IsLocked() return FS.Suite().locked == true end
function FS.SetLocked(v) FS.SaveSuite({ locked = v and true or false }) end
function FS.SetScale(n)
  n = tonumber(n)
  if not n then return false end
  n = math.floor(math.max(FS.C.SCALE_MIN, math.min(FS.C.SCALE_MAX, n)) * 10 + 0.5) / 10
  FS.SaveSuite({ scale = n })
  return n
end
function FS.ResetPosition()
  local d = defaultSuite()
  FS.SaveSuite({ point = d.point, relPoint = d.relPoint, x = d.x, y = d.y })
end

-- ---------- rows ----------
local function font(parent, obj, color)
  local f = parent:CreateFontString(nil, "OVERLAY", obj)
  f:SetJustifyH("LEFT")
  local c = pcolor(color)
  f:SetTextColor(c[1], c[2], c[3])
  return f
end

-- Row content, by addon key: FS.Status / FS.Headline / FS.Line / FS.ClearLines / FS.Bar / FS.State.
-- (Plain functions, not frame methods, so the API checker never mistakes them for widget methods.)
function FS.Status(key, text, color)
  local r = FS.rows[key]
  r.statusText = text
  local c = pcolor(color or "Mist")
  r.status:SetTextColor(c[1], c[2], c[3])
  r.statusLine:SetTextColor(c[1], c[2], c[3])
  r.status:SetText(text or "")
  r.statusLine:SetText(text or "")
  FS.PlaceStatus(r)
end
function FS.Headline(key, text, color)
  local r = FS.rows[key]
  r.headText = text
  local c = pcolor(color or FS.ADDONS[key].accent or "Snow")
  r.head:SetTextColor(c[1], c[2], c[3])
  r.head:SetText(text or "")
  FS.PlaceStatus(r)
end

-- ---------- r4: body slots, heights and status vs title (VISUAL_SPEC.md section 5) ----------
-- Height that shows n body lines (and a bottom button when footer is true).
function FS.BodyHeight(n, footer)
  local C = FS.C
  return C.BODY_Y + FS.FONT.LINE_H * (n or 0) + C.PAD_BOTTOM + (footer and C.FOOTER_H or 0)
end
local function has(t) return t ~= nil and t ~= "" end
local function textWidth(f)
  local ok, w = pcall(function() return f:GetStringWidth() end)
  if ok and type(w) == "number" and not FS.IsSecret(w) then return w end
  return nil
end
-- Body line i fits when its bottom (two lines when wrapped) is inside the row.
function FS.LineFits(r, i)
  if r.full == false then return false end
  local bottom = FS.C.BODY_Y + FS.FONT.LINE_H * (i + (r.lineWrap[i] and 1 or 0))
  return (r.h or 0) >= bottom
end
-- The status sits right of the title only when title + gap + status fit. Otherwise it moves down to the first free
-- text slot: the headline slot when the headline is empty, else the first body line not used by the bar or a line.
-- r.statusNeed = row height that slot needs (FS.RowHeight grows the row to it out of combat). In combat heights are
-- frozen, so a moved status that would fall below the box is not shown (the spec's "don't show it" rule).
function FS.PlaceStatus(r, inLayout)
  local C, LH = FS.C, FS.FONT.LINE_H
  local need, y
  if has(r.statusText) then
    local tw, sw = textWidth(r.title), textWidth(r.status)
    local right = (FS.top == r) and C.LOCK_X or C.EDGE_X
    if tw and sw and C.TITLE_X + tw + C.STATUS_GAP + sw > C.WIDTH - right then
      local footer = FS.ADDONS[r.key].footer and not FS.InCombat()
      if not has(r.headText) then
        r.statusSlot, y, need = 0, C.HEAD_Y, C.HEAD_Y + LH + C.PAD_BOTTOM + (footer and C.FOOTER_H or 0)
      else
        local i = 1
        while has(r.lineText[i]) or (i == 1 and r.barValue) or (i > 1 and r.lineWrap[i - 1] and has(r.lineText[i - 1])) do i = i + 1 end
        r.statusSlot, y, need = i, C.BODY_Y + (i - 1) * LH, FS.BodyHeight(i, footer)
      end
    end
  end
  local l = r.statusLine
  if need then
    r.status:Hide()
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", r, "TOPLEFT", C.EDGE_X, -y)
    l:SetPoint("RIGHT", r, "RIGHT", -C.EDGE_X, 0)
    l:SetShown(r.full ~= false and (r.h or 0) >= need)
  else
    r.statusSlot = nil
    r.status:SetShown(has(r.statusText))
    l:Hide()
  end
  local changed = r.statusNeed ~= need
  r.statusNeed = need
  -- out of combat a change of the needed height (or of an addon's own height) relayouts once (rate-limited)
  if not inLayout and r.h and not FS.InCombat() and FS.Visible(r) and (changed or FS.RowHeight(r) ~= r.h) then FS.QueueLayout() end
end
-- Body line i at y = -(44 + 14 * (i - 1)). One line, cut with "..." when too long (never wrapped into the next line),
-- unless wrap is true: then it may take two lines, so leave line i + 1 empty.
function FS.Line(key, i, text, wrap)
  local r = FS.rows[key]
  if not r.lines[i] then
    local l = font(r, FS.FONT.BODY, "Snow")
    l:SetPoint("TOPLEFT", r, "TOPLEFT", FS.C.EDGE_X, -FS.C.BODY_Y - (i - 1) * FS.FONT.LINE_H)
    l:SetPoint("RIGHT", r, "RIGHT", -FS.C.EDGE_X, 0)
    r.lines[i] = l
  end
  local l = r.lines[i]
  r.lineText[i], r.lineWrap[i] = text, wrap and true or nil
  l:SetWordWrap(wrap and true or false)
  l:SetMaxLines(wrap and 2 or 1)
  l:SetText(text or "")
  l:SetShown(FS.LineFits(r, i))
  FS.PlaceStatus(r)
end
function FS.ClearLines(key, from)
  local r = FS.rows[key]
  for i = from or 1, #r.lines do r.lineText[i], r.lineWrap[i] = nil, nil; r.lines[i]:SetText("") end
  FS.PlaceStatus(r)
end
function FS.Bar(key, frac, color)
  local r = FS.rows[key]
  r.barValue = frac
  FS.PlaceStatus(r)
  if not frac then r.bar:Hide(); return end
  if r.full == false or (r.h and r.h < FS.C.BODY_Y + FS.C.BAR_H) then return end
  local c = pcolor(color or FS.ADDONS[key].accent or "Snow")
  r.bar:SetStatusBarColor(c[1], c[2], c[3])
  r.bar:SetValue(math.max(0, math.min(1, frac)))
  r.bar:Show()
end
-- "idle" (thin strip), "active" (full height), "learn" (r5: the spell isn't learned yet: one calm line and the
-- "Hide until I learn" button; hidden in combat), or "hidden" (takes no slot: addon off, or a utility row with nothing to show).
local function learnParts(r)
  if r.learnText then return end
  r.learnText = font(r, FS.FONT.BODY, "Mist")
  r.learnText:SetPoint("TOPLEFT", r, "TOPLEFT", FS.C.EDGE_X, -FS.C.HEAD_Y)
  r.learnText:SetPoint("RIGHT", r, "RIGHT", -FS.C.EDGE_X, 0)
  r.learnText:SetWordWrap(false)
  r.learnText:SetMaxLines(1)
  r.learnText:Hide()
  local key = r.key
  local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  b:SetSize(FS.C.LEARN_BTN_W, FS.C.LEARN_BTN_H)
  b:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 8, 7)
  b:SetText(L["Hide until I learn"])
  b:SetScript("OnClick", function() _G.FrostSuite_1_0.HideUntilLearned(key) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Hide until I learn"])
    GameTooltip:AddLine(L["Hides this box on this character. It comes back by itself when you learn it."], 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  r.learnBtn = b
end
local function showLearn(r)
  if not r.learnText then return end
  local on = r.state == "learn"
  r.learnText:SetShown(on)
  r.learnBtn:SetShown(on and not FS.InCombat())   -- like Shatter Happens' Reset: never shown in combat
end
function FS.State(key, state)
  local r = FS.rows[key]
  if r.state == state then return end
  r.state = state
  showLearn(r)
  FS.RequestLayout()
end
-- The box can't work yet: show the need's line and the button (or nothing, if this character chose "Hide until I learn").
function FS.NotYet(key, need)
  local r = FS.rows[key]
  if not r then return end
  r.learnLine = FS.NeedText(need)
  if FS.HiddenUntilLearned(key) then FS.State(key, "hidden"); return end
  learnParts(r)
  r.learnText:SetText(r.learnLine)
  FS.Headline(key, ""); FS.Bar(key, nil); FS.ClearLines(key); FS.Status(key, "")
  FS.State(key, "learn")
  showLearn(r)
end
-- Everything the box needs is known (or the client can't say): forget "Hide until I learn" for this character.
function FS.Learned(key)
  local r = FS.rows[key]
  if not r then return end
  r.learnLine, r.hideSession = nil, nil
  local t, k = type(r.db) == "table" and r.db.hideUntilLearned, charKey()
  if k and type(t) == "table" then t[k] = nil end
end

function FS.Register(key, db, opts)
  local spec = FS.ADDONS[key]
  assert(spec, "FrostSuite: unknown row " .. tostring(key))
  if FS.rows[key] then FS.rows[key].db = db; FS.rows[key].opts = opts or {}; return FS.rows[key] end
  local a = FS.Anchor()
  local r = CreateFrame("Frame", nil, a, "BackdropTemplate")
  r.key, r.db, r.opts, r.lines, r.lineText, r.lineWrap, r.state = key, db, opts or {}, {}, {}, {}, "idle"
  r:SetSize(FS.C.WIDTH, FS.C.STRIP_H)
  r:SetBackdrop({ bgFile = FS.C.BG, edgeFile = FS.C.BORDER, edgeSize = FS.C.EDGE,
    insets = { left = FS.C.INSET, right = FS.C.INSET, top = FS.C.INSET, bottom = FS.C.INSET } })
  local bg, edge = pcolor("FrostNight"), pcolor("FrostEdge")
  r:SetBackdropColor(bg[1], bg[2], bg[3], FS.C.BG_ALPHA)
  r:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
  r.glow = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.glow:SetPoint("TOPLEFT", FS.C.INSET, -FS.C.INSET)
  r.glow:SetPoint("BOTTOMRIGHT", -FS.C.INSET, FS.C.INSET)
  local g = pcolor(spec.glow or spec.accent or "FrostEdge")
  r.glow:SetColorTexture(g[1], g[2], g[3], 1)
  r.glow:SetBlendMode("ADD")
  r.glow:SetAlpha(0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("TOPLEFT", 7, -6)
  r.icon:SetTexture(spec.icon)
  r.title = font(r, FS.FONT.TITLE, "FrostTitle")
  r.title:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.title:SetText((opts and opts.title) or key)
  r.status = font(r, FS.FONT.STATUS, "Mist")
  r.status:SetJustifyH("RIGHT")
  r.status:SetPoint("TOPRIGHT", -9, -7)
  r.status:SetWordWrap(false)
  r.statusLine = font(r, FS.FONT.BODY, "Mist")   -- the status, moved below the title when it doesn't fit beside it
  r.statusLine:SetWordWrap(false)
  r.statusLine:SetMaxLines(1)
  r.statusLine:Hide()
  r.head = font(r, FS.FONT.HEAD, spec.accent or "Snow")
  r.head:SetPoint("TOPLEFT", 9, -24)
  r.head:SetPoint("RIGHT", r, "RIGHT", -9, 0)
  r.head:SetWordWrap(false)
  r.bar = CreateFrame("StatusBar", nil, r)
  r.bar:SetStatusBarTexture(FS.C.BAR)
  r.bar:SetMinMaxValues(0, 1)
  r.bar:SetPoint("TOPLEFT", FS.C.EDGE_X, -FS.C.BODY_Y)
  r.bar:SetPoint("RIGHT", r, "RIGHT", -9, 0)
  r.bar:SetHeight(FS.C.BAR_H)
  r.bar:Hide()
  r:EnableMouse(true)
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function() if not FS.IsLocked() then FS.Anchor():StartMoving() end end)
  r:SetScript("OnDragStop", function()
    local an = FS.Anchor()
    an:StopMovingOrSizing()
    local p, _, rp, x, y = an:GetPoint(1)
    if p then FS.SaveSuite({ point = p, relPoint = rp, x = x, y = y }) end
  end)
  if type(db) == "table" then
    if type(db.suite) ~= "table" then db.suite = defaultSuite() end
    if db.sound == nil then db.sound = spec.soundDefault ~= false end
  end
  FS.rows[key] = r
  FS.order[#FS.order + 1] = key
  table.sort(FS.order, function(x, y) return FS.ADDONS[x].order < FS.ADDONS[y].order end)
  FS.ApplySuite()
  FS.Layout()
  return r
end

-- ---------- dock layout ----------
-- Row height: the addon's own height function (opts.height active / opts.idleHeight idle) or FS.ADDONS h / idleH,
-- grown to fit a status that moved below the title.
function FS.RowHeight(r)
  local spec, h = FS.ADDONS[r.key]
  if r.state == "learn" then return FS.BodyHeight(1) end   -- line at y -24, button at the bottom: 64
  if r.state == "active" or (FS.InCombat() and not spec.utility) then
    h = (r.opts.height and r.opts.height(r)) or spec.h
  else
    h = (r.opts.idleHeight and r.opts.idleHeight(r)) or spec.idleH or FS.C.STRIP_H
  end
  return math.max(h, r.statusNeed or 0)
end
function FS.Visible(r)
  if r.state == "hidden" then return false end
  if (FS.ADDONS[r.key].utility or r.state == "learn") and FS.InCombat() then return false end
  return true
end
function FS.Layout()
  FS.layoutPending, FS.lastLayout = nil, now()
  local prev
  FS.top = nil
  for _, key in ipairs(FS.order) do
    local r = FS.rows[key]
    if FS.Visible(r) then
      FS.top = FS.top or r
      FS.PlaceStatus(r, true)   -- measure first: a moved status can make the row taller
      r.h = FS.RowHeight(r)
      r:SetHeight(r.h)
      -- a title strip shows only icon, title and status; headline, bar and lines need the taller row,
      -- and nothing is drawn below the row's bottom edge
      local full = r.h > FS.C.STRIP_H and r.state ~= "learn"   -- the learn line replaces headline, bar and lines
      r.full = full
      r.head:SetShown(full)
      if not full or r.h < FS.C.BODY_Y + FS.C.BAR_H then r.bar:Hide() elseif r.barValue then r.bar:Show() end
      for i, l in ipairs(r.lines) do l:SetShown(FS.LineFits(r, i)) end
      FS.PlaceStatus(r, true)
      r:ClearAllPoints()
      if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -FS.C.GAP) else r:SetPoint("TOPLEFT", FS.Anchor(), "TOPLEFT", 0, 0) end
      r.after = prev and prev.key or "anchor"
      showLearn(r)
      r:Show()
      prev = r
    else
      r.after = nil
      r:Hide()
    end
  end
  FS.UpdateLock()
end
-- Out of combat: at most one relayout per second. In combat heights are frozen (set once at the start of the fight).
function FS.RequestLayout()
  if FS.InCombat() or FS.layoutPending then return end
  local wait = (FS.lastLayout or -100) + FS.C.RELAYOUT_MIN_GAP - now()
  if wait <= 0 then FS.Layout(); return end
  FS.layoutPending = true
  C_Timer.After(wait, function() _G.FrostSuite_1_0.Layout() end)
end
-- Same limit, but never right away: content changes (lines, status) made in one paint settle into one relayout next frame.
function FS.QueueLayout()
  if FS.InCombat() or FS.layoutPending then return end
  FS.layoutPending = true
  C_Timer.After(math.max(0, (FS.lastLayout or -100) + FS.C.RELAYOUT_MIN_GAP - now()), function() _G.FrostSuite_1_0.Layout() end)
end

-- One padlock, on the top shown row.
function FS.UpdateLock()
  local top = FS.top
  if not top then if FS.lock then FS.lock:Hide() end return end
  if not FS.lock then
    local b = CreateFrame("Button", nil, top)
    b:SetSize(16, 16)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(unpack(FS.C.LOCK_TEXCOORD))
    b:SetScript("OnClick", function() local S = _G.FrostSuite_1_0; S.SetLocked(not S.IsLocked()) end)
    b:SetScript("OnEnter", function(self)
      local S = _G.FrostSuite_1_0
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if S.IsLocked() then GameTooltip:SetText(L["Box locked"]); GameTooltip:AddLine(L["Click to unlock it."], 1, 1, 1)
      else GameTooltip:SetText(L["Drag the boxes to move them."]); GameTooltip:AddLine(L["Click to lock them."], 1, 1, 1) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    FS.lock = b
  end
  local b = FS.lock
  b:SetParent(top)
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", top, "TOPRIGHT", -7, -6)
  b.icon:SetTexture(FS.IsLocked() and FS.C.LOCKED or FS.C.UNLOCKED)
  b:Show()
  b.owner = top.key
  for _, key in ipairs(FS.order) do
    local r = FS.rows[key]
    r.status:ClearAllPoints()
    r.status:SetPoint("TOPRIGHT", r == top and -FS.C.LOCK_X or -FS.C.EDGE_X, -7)
    FS.PlaceStatus(r, true)
  end
end

-- ---------- one glow at a time ----------
-- RequestFlash(key, style) -> won. A higher-priority glow replaces a lower one at once; a lower one is denied (no queue).
-- PULSE: one 0.5 s fade, once per state entry and never twice within 3 s. HOLD: steady until EndFlash. TEXT: never glows.
local function glowTick(r)
  local left = (r.pulseUntil or 0) - now()
  if left <= 0 then
    r.glow:SetAlpha(0); r:SetScript("OnUpdate", nil)
    if FS.flashKey == r.key then FS.flashKey = nil end
    return
  end
  r.glow:SetAlpha(FS.C.GLOW_PEAK * left / FS.C.PULSE_SEC)
end
local function stopGlow(key)
  local r = key and FS.rows[key]
  if r then r.glow:SetAlpha(0); r:SetScript("OnUpdate", nil); r.pulseUntil = nil end
end
function FS.RequestFlash(key, style)
  local spec, r = FS.ADDONS[key], FS.rows[key]
  if not (spec and r) or spec.priority == 0 then return false end
  style = style or spec.style
  if style == "TEXT" then return false end
  local cur = FS.flashKey
  if cur and cur ~= key and FS.ADDONS[cur].priority <= spec.priority then FS.denied = (FS.denied or 0) + 1; return false end
  if style == "PULSE" and r.lastPulse and now() - r.lastPulse < FS.C.PULSE_MIN_GAP then return false end
  if cur and cur ~= key then stopGlow(cur) end
  FS.flashKey = key
  if style == "HOLD" then
    r.glow:SetAlpha(FS.C.GLOW_PEAK)
  else
    r.lastPulse = now()
    r.pulseUntil = now() + FS.C.PULSE_SEC
    r.glow:SetAlpha(FS.C.GLOW_PEAK)
    r:SetScript("OnUpdate", glowTick)
  end
  return true
end
function FS.EndFlash(key)
  if FS.flashKey == key then stopGlow(key); FS.flashKey = nil end
end
function FS.Glowing() return FS.flashKey end
-- Only the row holding the glow may play its sound; one suite sound per 4 s; each addon has its own db.sound switch.
function FS.PlaySound(key)
  local spec, r = FS.ADDONS[key], FS.rows[key]
  if not (spec and r and spec.sound) or FS.flashKey ~= key then return false end
  if r.db and r.db.sound == false then return false end
  if now() - FS.lastSound < FS.C.SOUND_MIN_GAP then return false end
  local ok, willPlay = pcall(PlaySoundFile, spec.sound, "Master")
  if ok and willPlay ~= false then FS.lastSound = now(); return true end
  return false
end

-- ---------- /frost ----------
local function say(msg) print("|cff69ccf0Frost Suite|r: " .. tostring(msg)) end
FS.Print = say
function FS.Slash(msg)
  msg = (msg or ""):lower()
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "lock" or cmd == "unlock" then
    FS.SetLocked(cmd == "lock"); say(cmd == "lock" and L["boxes locked"] or L["boxes unlocked: drag any box to move them all"])
  elseif cmd == "scale" then
    local n = FS.SetScale(rest)
    say(n and (L["scale"] .. " " .. n) or ("/frost scale 0.8-1.4"))
  elseif cmd == "reset" then
    FS.ResetPosition(); say(L["boxes moved back to the default spot"])
  elseif cmd == "debug" then
    say(("FrostSuite-1.0 r%d, rows: %s, glowing: %s, locked: %s"):format(FS.minor, table.concat(FS.order, ", "),
      tostring(FS.flashKey), tostring(FS.IsLocked())))
    for _, key in ipairs(FS.order) do
      local o = FS.rows[key].opts
      if o.debug then local ok, err = pcall(o.debug); if not ok then say(key .. " debug error: " .. tostring(err)) end end
    end
  else
    for _, key in ipairs(FS.order) do
      local o = FS.rows[key].opts
      if cmd == FS.ADDONS[key].cmd and o.slash then return o.slash(rest) end
    end
    say("/frost lock | unlock | scale 0.8-1.4 | reset | debug")
    for _, key in ipairs(FS.order) do
      local o = FS.rows[key].opts
      say("  /frost " .. FS.ADDONS[key].cmd .. (o.help and (" " .. o.help) or ""))
    end
  end
end
SLASH_FROSTSUITE1, SLASH_FROSTSUITE2 = "/frost", "/frostsuite"
SlashCmdList.FROSTSUITE = function(msg) _G.FrostSuite_1_0.Slash(msg) end

-- ---------- combat: freeze heights at the start, relayout 2 s after the end ----------
-- r5: a level-up or a newly learned spell re-checks every box (opts.refresh), so a box appears by itself.
function FS.Relearn()
  for _, key in ipairs(FS.order) do
    local o = FS.rows[key].opts
    if o.refresh then pcall(o.refresh) end
  end
end
function FS.OnEvent(event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    FS.Layout()
  elseif event == "PLAYER_REGEN_ENABLED" then
    C_Timer.After(FS.C.RELAYOUT_AFTER_COMBAT, function() _G.FrostSuite_1_0.Layout() end)
  elseif event == "PLAYER_LEVEL_UP" then
    local lvl = ...
    if type(lvl) == "number" and not FS.IsSecret(lvl) then FS.level = lvl end
    FS.Relearn()
  elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
    FS.Relearn()
  end
end
FS.events = FS.events or CreateFrame("Frame")
FS.events:RegisterEvent("PLAYER_REGEN_DISABLED")
FS.events:RegisterEvent("PLAYER_REGEN_ENABLED")
FS.events:RegisterEvent("PLAYER_LEVEL_UP")
FS.events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
FS.events:SetScript("OnEvent", function(_, event, ...) _G.FrostSuite_1_0.OnEvent(event, ...) end)
