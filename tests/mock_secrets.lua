-- Secret-value rules of the WoW: Forever client for offline tests (Frost Suite copy; not Blizzard code). Mirrors Blizzard's
-- API docs for builds 1.60.1.70532 and 70862:
--   * UNIT_AURA payload is secret while combat restrictions are on (SecretWhenAurasRestricted).
--   * C_UnitAuras.GetPlayerAuraBySpellID / GetUnitAuraBySpellID return NOTHING for an aura that is secret
--     (RequiresNonSecretAura), and auras are secret in combat unless the spell is flagged never-secret
--     (SecretWhenUnitAuraRestricted). That holds for enemy auras on "target" too.
--   * C_Secrets.GetSpellAuraSecrecy / GetSpellCastSecrecy: 0 never, 1 always, 2 contextually secret (Enum.SecrecyLevel).
--   * UNIT_SPELLCAST_SUCCEEDED / _CHANNEL_START / _CHANNEL_STOP are SecretWhenUnitSpellCastRestricted. Gale Count found the
--     player's own casts plain, but tests can switch on S.castSecretInCombat (spellID arrives as a secret value in combat)
--     or S.castAlways[id] (always secret) to prove the addons fail visibly.
-- Defaults are the strict case for auras: restrictions on, nothing never-secret.
-- Canonical: frost-suite-lib/tests/mock_secrets.lua (identical in every suite addon).
local S = {}

function S.install(M)
  S.M = M
  S.restrictions = true   -- C_Secrets.HasSecretRestrictions()
  S.never = {}            -- spellID -> true: aura flagged never-secret
  S.always = {}           -- spellID -> true: aura flagged always-secret
  S.castAlways = {}       -- spellID -> true: cast events for it are always secret
  S.castSecretInCombat = false
  S.auras = {}            -- spellID -> AuraData on the player
  S.unit = { target = {} } -- unit -> spellID -> AuraData
  S.reads = 0
  S.nextInstance = 1000
  S.overlayed = {}        -- spellID -> true while the game's spell alert glows on it (not secret-flagged in the docs)
  local function secretNow(id)
    if not S.restrictions or S.never[id] then return false end
    return S.always[id] or M.combat
  end
  S.secretNow = secretNow
  C_Secrets = {
    HasSecretRestrictions = function() return S.restrictions end,
    ShouldAurasBeSecret = function() return S.restrictions and M.combat or false end,
    GetSpellAuraSecrecy = function(id)
      if not S.restrictions or S.never[id] then return 0 end
      return S.always[id] and 1 or 2
    end,
    GetSpellCastSecrecy = function(id)
      if S.castAlways[id] then return 1 end
      return S.castSecretInCombat and 2 or 0
    end,
    ShouldSpellAuraBeSecret = function(id) return secretNow(id) and true or false end,
  }
  C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
      S.reads = S.reads + 1
      if secretNow(id) then return end -- RequiresNonSecretAura: no values at all
      return S.auras[id]
    end,
    GetUnitAuraBySpellID = function(unit, id)
      S.reads = S.reads + 1
      if unit == "player" then return C_UnitAuras.GetPlayerAuraBySpellID(id) end
      if secretNow(id) then return end
      return S.unit[unit] and S.unit[unit][id]
    end,
  }
  C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return S.overlayed[id] == true end }
  return S
end

-- A secret UNIT_AURA payload (in combat) or a plain one with the given added auras.
function S.payload(added)
  local M = S.M
  if S.restrictions and M.combat then local p = {}; M.secret[p] = true; return p end
  return { addedAuras = added or {} }
end
local function newAura(id, apps, duration)
  local M = S.M
  S.nextInstance = S.nextInstance + 1
  return { spellId = id, auraInstanceID = S.nextInstance, applications = apps or 0,
    expirationTime = M.clock + (duration or 10), duration = duration or 10 }
end
-- Player aura appears (or is refreshed), then UNIT_AURA fires.
function S.gain(id, apps, duration)
  local a = newAura(id, apps, duration)
  S.auras[id] = a
  S.M.fire("UNIT_AURA", "player", S.payload({ a }))
  return a
end
function S.update(id, apps, expirationTime)
  local a = S.auras[id]
  if apps then a.applications = apps end
  if expirationTime then a.expirationTime = expirationTime end
  S.M.fire("UNIT_AURA", "player", S.payload())
end
function S.drop(id)
  S.auras[id] = nil
  S.M.fire("UNIT_AURA", "player", S.payload())
end
-- Aura on another unit (the target), then UNIT_AURA for that unit.
function S.unitGain(unit, id, apps, duration)
  local a = newAura(id, apps, duration)
  S.unit[unit] = S.unit[unit] or {}
  S.unit[unit][id] = a
  S.M.fire("UNIT_AURA", unit, S.payload({ a }))
  return a
end
function S.unitDrop(unit, id)
  if S.unit[unit] then S.unit[unit][id] = nil end
  S.M.fire("UNIT_AURA", unit, S.payload())
end

-- The spellID a cast event carries: a secret value when the client hides it.
local function castID(id)
  if S.castAlways[id] or (S.castSecretInCombat and S.M.combat) then local v = {}; S.M.secret[v] = true; return v end
  return id
end
local castN = 0
local function guid(id) castN = castN + 1; return "Cast-3-1-1-1-" .. tostring(id) .. "-" .. castN end
function S.cast(id, unit) S.M.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", guid(id), castID(id)) end
function S.channelStart(id, unit) S.M.fire("UNIT_SPELLCAST_CHANNEL_START", unit or "player", guid(id), castID(id)) end
function S.channelStop(id, unit) S.M.fire("UNIT_SPELLCAST_CHANNEL_STOP", unit or "player", guid(id), castID(id)) end
-- The game's spell alert glow on an action (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / _HIDE).
function S.glow(id, on)
  S.overlayed[id] = on and true or nil
  S.M.fire(on and "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", id)
end

return S
