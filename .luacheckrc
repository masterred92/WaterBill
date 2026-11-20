std = "lua51"
max_line_length = false
exclude_files = { "tests/**", "tools/**", ".release/**", ".lua/**", ".luarocks/**", "wow-ui/**", "index/**", "hosts/**" }
-- Our own globals (plus the suite library's shared table and the shared /frost command).
globals = { "KennyWaterBill", "KennyWaterBillDB", "FrostSuite_1_0", "SLASH_FROSTSUITE1", "SLASH_FROSTSUITE2", "SlashCmdList" }
-- WoW API (checked against Blizzard's UI source by tools/verify_api.py).
read_globals = { "C_AuctionHouse", "C_CVar", "GetCVar", "C_Map", "GetRealZoneText", "GetSubZoneText", "GetLocale", "C_Container", "C_Item", "ItemLocation", "NUM_BAG_SLOTS", "GameTooltip",
  -- used by Libs/FrostSuite
  "C_ClassTalents", "C_Secrets", "C_SpellBook", "C_Timer", "C_Traits", "C_UnitAuras", "GameTooltip", "PlaySoundFile", "UnitAffectingCombat", "UnitClass",
  -- used by the shared KennyShared library (Libs/KennyShared)
  "C_AddOns", "C_AuctionHouse", "C_CVar", "GetCVar", "C_Map", "GetRealZoneText", "GetSubZoneText", "GetLocale", "C_Container", "C_Item", "C_RestrictedActions", "CreateFrame", "Enum", "GetBuildInfo", "GetLocale", "GetMoney", "GetMoneyString", "GetRealZoneText", "GetRealmName", "GetSubZoneText", "GetTime", "ItemRefTooltip", "LibStub", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "TooltipDataProcessor", "UIParent", "UnitFactionGroup", "date", "issecretvalue", "time" }
