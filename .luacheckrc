---@diagnostic disable: lowercase-global
std = "lua51"
max_line_length = false
codes = true

ignore = {
	"21./_",
	"212/self",
}

globals = {
	"_",
	"RaidBuffsTrackerDB",
	"SLASH_RAIDBUFFSTRACKER1",
	"SLASH_RAIDBUFFSTRACKER2",
	"SlashCmdList",
}

read_globals = {
	-- WoW API
	"C_ChallengeMode",
	"C_Spell",
	"C_Timer",
	"C_UnitAuras",
	"CreateFrame",
	"GetNumGroupMembers",
	"GetTime",
	"InCombatLockdown",
	"IsInRaid",
	"Settings",
	"SettingsPanel",
	"UIParent",
	"UnitClass",
	"UnitExists",
	"UnitGroupRolesAssigned",
	"UnitIsConnected",
	"UnitIsDeadOrGhost",

	-- WoW UI globals
	"ActionButton_HideOverlayGlow",
	"ActionButton_ShowOverlayGlow",
	"GameTooltip",
	"STANDARD_TEXT_FONT",
}
