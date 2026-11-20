-- Frost Suite: the shared FrostSuite-1.0 dock, flash rule, saved position and /frost router (identical in every addon).
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
local toc = io.popen("ls *.toc"):read("*l")
local name = toc:gsub("%.toc$", "")
W.loadAddon(".", name)
W.fire("PLAYER_LOGIN")
local FS = _G.FrostSuite_1_0
local MINOR = tonumber(io.open("Libs/FrostSuite/VERSION"):read("*l"))
check(type(FS) == "table" and FS.minor == MINOR, "library installed as FrostSuite_1_0 at its MINOR")
check(FS.rows[name] ~= nil, "the addon registered its own row")
check(SLASH_FROSTSUITE1 == "/frost" and SlashCmdList.FROSTSUITE ~= nil, "/frost registered")

-- Same-version copy loads again (a second addon): returns early and keeps every row.
local before = FS.rows[name]
assert(loadfile("Libs/FrostSuite/FrostSuite.lua"))("Other", {})
check(_G.FrostSuite_1_0 == FS and FS.rows[name] == before, "equal MINOR copy keeps the table and rows")
-- An older copy never downgrades; a newer one replaces functions but keeps state.
FS.minor = 99
local oldLayout = FS.Layout
assert(loadfile("Libs/FrostSuite/FrostSuite.lua"))("Older", {})
check(FS.Layout == oldLayout and FS.minor == 99, "older copy does not replace a newer one")
FS.minor = 0
assert(loadfile("Libs/FrostSuite/FrostSuite.lua"))("Newer", {})
check(FS.minor == MINOR and FS.rows[name] == before, "newer copy upgrades in place and keeps rows")

-- Fake the other six rows so the dock and flash rule can be checked with the whole suite loaded.
local dbs = {}
for key in pairs(FS.ADDONS) do
  if not FS.rows[key] then dbs[key] = {}; FS.Register(key, dbs[key], { title = key }) end
end
for _, key in ipairs(FS.order) do FS.rows[key].state = "idle" end
FS.Layout()
check(#FS.order == 7, "seven rows docked")
check(FS.order[1] == "HoldTheWeather" and FS.order[7] == "ScrollCall", "dock order follows FS.ADDONS order")
check(FS.rows.HoldTheWeather.after == "anchor" and FS.rows.EightSecondArgument.after == "HoldTheWeather", "rows chain top to bottom")
check(FS.rows.HoldTheWeather.h == 28 and FS.rows.ShatterHappens.h == (name == "ShatterHappens" and 102 or 116),
  "idle heights: strip 28, Shatter 116 (3 lines + Reset; the real addon: 102 before any fight)")
check(FS.lock.owner == "HoldTheWeather", "padlock on the top row")
check(FS.rows.HoldTheWeather.head.shown == false and FS.rows.ShatterHappens.head.shown == true, "strip hides the headline; taller idle rows keep it")
-- A hidden row takes no slot; the next one moves up and takes the padlock.
FS.rows.HoldTheWeather.state = "hidden"; FS.Layout()
check(FS.rows.EightSecondArgument.after == "anchor" and FS.lock.owner == "EightSecondArgument", "hidden row leaves no gap")
FS.rows.HoldTheWeather.state = "idle"; FS.Layout()

-- Combat: five combat rows go to active height, utility rows hide; heights frozen until 2 s after combat.
W.combat = true
W.fire("PLAYER_REGEN_DISABLED")
check(FS.rows.HoldTheWeather.h == 50 and FS.rows.BarrierReef.h == 78 and FS.rows.ShatterHappens.h == 78
  and FS.rows.EightSecondArgument.h == 78 and FS.rows.ConeOfPlenty.h == 64, "combat heights fit line 2 (r4)")
check(FS.rows.WaterBill.after == nil and FS.rows.ScrollCall.after == nil, "utility rows hidden in combat")
FS.State("BarrierReef", "active")
check(FS.layoutPending == nil, "no relayout in combat")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
check(FS.rows.WaterBill.after == nil, "utility rows still hidden right after combat")
W.advance(2.1)
-- (in the WaterBill / ScrollCall repos that row is the real addon and stays hidden away from the AH: check the other one)
local util = FS.rows.WaterBill.state ~= "hidden" and "WaterBill" or "ScrollCall"
check(FS.rows[util].after ~= nil and FS.rows.HoldTheWeather.h == 28, "relayout 2 s after combat")

-- Flash rule: one glow, highest priority wins, lower is denied (no queue), utility rows never flash.
W.advance(10)
check(FS.RequestFlash("ShatterHappens", "PULSE") == true, "Shatter pulse wins when nothing glows")
check(FS.RequestFlash("BarrierReef", "PULSE") == true and FS.Glowing() == "BarrierReef", "Reef outranks Shatter")
check(FS.rows.ShatterHappens.glow.alpha == 0, "outranked glow drops to 0 at once")
check(FS.RequestFlash("ShatterHappens", "PULSE") == false, "lower priority denied")
check(FS.RequestFlash("HoldTheWeather", "HOLD") == true and FS.rows.BarrierReef.glow.alpha == 0, "Hold the Weather outranks all")
check(FS.RequestFlash("ConeOfPlenty", "PULSE") == false, "Cone denied while Hold glows")
check(FS.RequestFlash("WaterBill") == false and FS.RequestFlash("ScrollCall") == false, "utility rows never flash")
check(FS.RequestFlash("EightSecondArgument", "TEXT") == false, "TEXT style never glows")
FS.EndFlash("HoldTheWeather")
check(FS.Glowing() == nil and FS.rows.HoldTheWeather.glow.alpha == 0, "EndFlash clears the HOLD glow")
check(FS.RequestFlash("BarrierReef", "PULSE") == false, "same row may not pulse twice within 3 s")
W.advance(3.1)
check(FS.RequestFlash("BarrierReef", "PULSE") == true, "pulse allowed again after 3 s")
local r = FS.rows.BarrierReef
W.clock = W.clock + 0.6; r.scripts.OnUpdate(r)
check(FS.Glowing() == nil and r.glow.alpha == 0, "pulse fades out after 0.5 s and frees the glow")
-- Sounds: only the winner, one per 4 s, own switch.
W.sounds = {}
FS.RequestFlash("HoldTheWeather", "HOLD")
check(FS.PlaySound("HoldTheWeather") == true and W.sounds[1][1] == 569310, "winner plays its in-game sound")
check(FS.PlaySound("BarrierReef") == false, "a row without the glow is silent")
FS.EndFlash("HoldTheWeather"); W.advance(1)
FS.RequestFlash("HoldTheWeather", "HOLD")
check(FS.PlaySound("HoldTheWeather") == false, "one suite sound per 4 s")
FS.EndFlash("HoldTheWeather")
W.advance(5)
FS.rows.HoldTheWeather.db.sound = false
FS.RequestFlash("HoldTheWeather", "HOLD")
check(FS.PlaySound("HoldTheWeather") == false, "per-addon sound switch honoured")
FS.rows.HoldTheWeather.db.sound = true
FS.EndFlash("HoldTheWeather")
check(FS.rows.ConeOfPlenty.db.sound == false, "Cone sound off by default")

-- Saved position, lock and scale: written to every addon's db.suite, newest stamp wins.
W.now = W.now + 100
FS.SetLocked(true)
local all = true
for _, key in ipairs(FS.order) do local s = FS.rows[key].db.suite; all = all and s.locked == true end
check(all and FS.IsLocked(), "lock written to every row's db.suite")
check(FS.SetScale(2) == 1.4 and FS.SetScale(0.5) == 0.8 and FS.SetScale("1.13") == 1.1, "scale clamped 0.8-1.4, step 0.1")
dbs[name == "ScrollCall" and "WaterBill" or "ScrollCall"].suite = { point = "TOP", relPoint = "TOP", x = 1, y = 2, locked = false, scale = 1.2, stamp = W.now + 50 }
check(FS.Suite().scale == 1.2 and FS.IsLocked() == false, "newest db.suite wins")
FS.ResetPosition()
local s = FS.Suite()
check(s.point == "TOPLEFT" and s.relPoint == "CENTER" and s.x == 220 and s.y == 160, "reset to the default spot")

-- r4 layout: heights fit their lines, a status that would touch the title moves to a free text slot.
check(FS.BodyHeight(1) == 64 and FS.BodyHeight(2) == 78 and FS.BodyHeight(3, true) == 116, "BodyHeight: 44 + 14 n + 6 (+ 24 Reset)")
for _, key in ipairs(FS.order) do FS.rows[key].state = "idle"; FS.Status(key, ""); FS.Headline(key, ""); FS.ClearLines(key); FS.Bar(key, nil) end
FS.Layout()
local lr = FS.rows.LayoutTest or FS.rows.ScrollCall
lr.state = "active"
FS.Headline("ScrollCall", "3 unread scrolls", "Snow"); FS.Line("ScrollCall", 1, "Last: Spell Notes")
FS.Status("ScrollCall", "short", "Mist"); FS.Layout()
check(FS.rows.ScrollCall.status.shown and not FS.rows.ScrollCall.statusLine.shown and FS.rows.ScrollCall.statusSlot == nil, "short status stays beside the title")
FS.Status("ScrollCall", "read 2 · ~5g 0s before AH cut", "Mist"); FS.Layout()
local sc = FS.rows.ScrollCall
check(not sc.status.shown and sc.statusLine.shown and sc.statusSlot == 2 and sc.h == 78, "long status moves to body line 2 and the row grows to 78")
check(sc.statusLine.text_ == "read 2 · ~5g 0s before AH cut", "moved status keeps its text")
FS.Status("ScrollCall", "", "Mist"); FS.Layout()
check(not sc.status.shown and not sc.statusLine.shown and sc.h == 64, "empty status: nothing shown, row back to 64")
-- headline empty: a long status takes the headline slot of a 44 px row (out of combat, idle)
local hw = FS.rows.HoldTheWeather
FS.Status("HoldTheWeather", "can't see your casts here", "Mist"); FS.Layout()
check(hw.statusSlot == 0 and hw.h == 44 and hw.statusLine.shown, "idle strip + long status: status under the title, row 44")
FS.Status("HoldTheWeather", "clear", "Mist"); FS.Layout()
check(hw.statusSlot == nil and hw.h == 28 and hw.status.shown, "short status: back to a 28 px strip")
-- bar takes body slot 1
local bk = name == "BarrierReef" and "ConeOfPlenty" or "BarrierReef"   -- a fake row: the real addon repaints itself in combat
local br = FS.rows[bk]
br.state = "active"; FS.Headline(bk, "BUFF +15%"); FS.Bar(bk, 0.5); FS.Status(bk, "shield state unknown and more"); FS.Layout()
check(br.statusSlot == 2 and br.h == 78 and br.statusLine.shown, "bar row: moved status on line 2, inside 78")
-- lines never drawn below the row, and the move happens on the next frame without an explicit Layout
local wb = FS.rows.WaterBill
wb.state = "active"; FS.Headline("WaterBill", "Water Bill"); W.advance(2); FS.Layout()
for i = 1, 4 do FS.Line("WaterBill", i, "DRINK Conjured Water x" .. i) end
W.advance(1.1)
check(wb.lines[4].shown == (wb.h >= 44 + 14 * 4), "a line is shown only when it fits inside the row")
-- in combat heights are frozen: a moved status that would fall below the row is not shown
W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
FS.Headline(bk, "REEF +20%"); FS.Line(bk, 2, "REFRESH"); FS.Status(bk, "shield state unknown and more")
check(br.statusSlot == 3 and br.h == 78 and not br.statusLine.shown and not br.status.shown, "combat: no room below, status hidden, not overlapping")
check(FS.layoutPending == nil, "combat: no relayout from content changes")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(2.1)
for _, key in ipairs(FS.order) do FS.Status(key, ""); FS.Headline(key, ""); FS.ClearLines(key); FS.Bar(key, nil) end
-- wrapped line takes two slots
FS.Headline("ShatterHappens", "No fights yet."); FS.Line("ShatterHappens", 1, "Use Frost spells and your Fingers of Frost show up here.", true)
FS.Status("ShatterHappens", "a very long status that will not fit beside it")
check(FS.rows.ShatterHappens.statusSlot == 3, "wrapped line 1 also takes slot 2")
FS.Status("ShatterHappens", ""); FS.ClearLines("ShatterHappens")
W.advance(2)

-- /frost router.
W.prints = {}
SlashCmdList.FROSTSUITE("lock")
check(FS.IsLocked() and W.printed("locked"), "/frost lock")
SlashCmdList.FROSTSUITE("unlock")
check(not FS.IsLocked(), "/frost unlock")
W.prints = {}
SlashCmdList.FROSTSUITE("")
check(W.printed("/frost " .. FS.ADDONS[name].cmd), "/frost lists the addon's subcommand")
W.prints = {}
SlashCmdList.FROSTSUITE("debug")
check(W.printed("FrostSuite-1.0 r" .. MINOR), "/frost debug prints the dock state")

-- Detection helpers: an aura answer is trusted only when the client says it is readable.
local S = W.S
S.install(W)
W.combat = false
S.gain(400669, 2, 15)
local a, ok = FS.ReadAura("player", 400669)
check(ok and FS.AuraField(a, "applications") == 2, "out of combat: aura readable")
W.combat = true
a, ok = FS.ReadAura("player", 400669)
check(a == nil and ok == false, "in combat: secret aura is 'not readable', not 'not up'")
S.never[400669] = true
a, ok = FS.ReadAura("player", 400669)
check(ok and a ~= nil and FS.AuraNeverSecret(400669), "never-secret aura readable in combat")
S.unitGain("target", 12579, 3, 15)
a, ok = FS.ReadAura("target", 12579)
check(not ok, "enemy aura secret in combat")
S.restrictions = false
a, ok = FS.ReadAura("target", 12579)
check(ok and FS.AuraField(a, "applications") == 3, "no restrictions: enemy aura readable")
W.combat = false
check(FS.TalentRank(11180) == nil, "talent rank unknown without a talent config")
W.talents = { [11180] = { 3, 5 } }
local rk, mx = FS.TalentRank(11180)
check(rk == 3 and mx == 5, "talent rank read from the active config")
W.talents = nil
W.known = { [10] = true }
check(FS.KnowsAny({ [10] = true, [6141] = true }) == true and FS.KnowsAny({ [120] = true }) == false, "KnowsAny")
W.known = nil
check(FS.IsMage(), "IsMage")

-- r5 low level: one calm line and "Hide until I learn" while a needed spell isn't learned; back by itself once it is.
W.known, W.level = { [133] = true, [168] = true }, 1   -- a new Mage: Fireball and Frost Armor
local needs = { { name = "Frost Nova", level = 10, spells = { [122] = 1, [865] = 2 } }, { name = "Blizzard", level = 20, spells = { [10] = 1 } } }
check(FS.PlayerLevel() == 1 and FS.Missing(needs) == needs[1], "level 1: Frost Nova is the first need")
check(FS.NeedText(needs[1]) == "Learn Frost Nova at level 10", "need line names the level")
check(FS.NeedText({ name = "Ice Barrier", level = 40, talent = true }) == "Take Ice Barrier at level 40", "talent need line")
W.level = 45
check(FS.NeedText({ name = "Ice Barrier", level = 40, talent = true }) == "Take the Ice Barrier talent", "talent need after its level")
check(FS.NeedText(needs[1]) == "Learn Frost Nova from your trainer", "spell need after its level")
check(FS.NeedText({ name = "X", text = "own line" }) == "own line", "a need may bring its own line")
W.level = 1
W.known[865] = true
check(FS.Missing(needs) == needs[2], "any rank counts as known")
W.known[10] = true
check(FS.Missing(needs) == nil, "all known: nothing missing")
local saveSB = C_SpellBook; C_SpellBook = nil
check(FS.Missing(needs) == nil, "client can't say: treated as known (the box works as before)")
C_SpellBook = saveSB
local lk = name == "ConeOfPlenty" and "BarrierReef" or "ConeOfPlenty"   -- a fake row
local lrow, refreshed = FS.rows[lk], 0
lrow.opts.refresh = function() refreshed = refreshed + 1 end
FS.Status(lk, "0/5"); FS.Headline(lk, "SCOOP 1/5"); FS.Bar(lk, 0.2)
FS.NotYet(lk, needs[1]); FS.Layout()
check(lrow.state == "learn" and lrow.h == 64 and lrow.learnText.shown and lrow.learnText.text_ == "Learn Frost Nova at level 10",
  "learn state: one line, row 64")
check(lrow.learnBtn.shown and lrow.learnBtn.text_ == "Hide until I learn", "the button shows out of combat")
check(not lrow.head.shown and not lrow.bar.shown and lrow.statusText == "", "no headline, bar or status beside the learn line")
W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
check(not lrow.shown and lrow.after == nil, "learn rows hide in combat")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(2.1)
check(lrow.shown and lrow.learnBtn.shown, "and come back after combat")
lrow.learnBtn.scripts.OnClick(lrow.learnBtn)
check(lrow.state == "hidden" and lrow.db.hideUntilLearned["Kenny-TestRealm"] == true, "Hide until I learn: hidden, saved per character")
FS.Layout()
check(not lrow.shown and lrow.after == nil, "a hidden-until-learned row takes no slot")
FS.NotYet(lk, needs[1])
check(lrow.state == "hidden", "stays hidden while the spell is still missing")
lrow.db.hideUntilLearned = { ["Alt-TestRealm"] = true }
FS.NotYet(lk, needs[1])
check(lrow.state == "learn", "another character's choice doesn't hide this one")
lrow.learnBtn.scripts.OnClick(lrow.learnBtn)
FS.Learned(lk)
check(lrow.db.hideUntilLearned["Kenny-TestRealm"] == nil and lrow.db.hideUntilLearned["Alt-TestRealm"] == true, "learning it clears only this character's choice")
FS.State(lk, "idle")
check(not lrow.learnText.shown and not lrow.learnBtn.shown, "leaving the learn state hides the line and button")
W.fire("PLAYER_LEVEL_UP", 12)
check(refreshed == 1 and FS.PlayerLevel() == 12, "PLAYER_LEVEL_UP re-checks every box and its level is used at once")
W.fire("LEARNED_SPELL_IN_SKILL_LINE", 122)
check(refreshed == 2, "LEARNED_SPELL_IN_SKILL_LINE re-checks every box")
-- name or realm unreadable (secret value, or empty): the click hides for this session only and saves nothing
local saveName, saveRealm = UnitName, GetRealmName
UnitName = function() return "SecretName" end; W.secret["SecretName"] = true
lrow.db.hideUntilLearned = nil; lrow.hideSession = nil; FS.NotYet(lk, needs[1])
check(FS.CharKey() == nil and lrow.state == "learn", "secret name: no character key, the line still shows")
lrow.learnBtn.scripts.OnClick(lrow.learnBtn)
check(lrow.state == "hidden" and lrow.hideSession == true and lrow.db.hideUntilLearned == nil, "secret name: hidden this session, nothing saved")
FS.NotYet(lk, needs[1])
check(lrow.state == "hidden", "secret name: stays hidden this session")
FS.Learned(lk)
check(lrow.hideSession == nil, "learning it ends the session hide")
W.secret["SecretName"] = nil; UnitName = saveName
GetRealmName = function() return "" end
FS.NotYet(lk, needs[1]); lrow.learnBtn.scripts.OnClick(lrow.learnBtn)
check(FS.CharKey() == nil and lrow.hideSession == true and lrow.db.hideUntilLearned == nil, "empty realm: nothing saved")
GetRealmName = saveRealm; FS.Learned(lk)
check(FS.CharKey() == "Kenny-TestRealm", "readable name and realm: Name-Realm")
lrow.opts.refresh = nil
FS.level, W.level, W.known = nil, nil, nil
W.prints = {}
W.done(name .. " frostsuite")
