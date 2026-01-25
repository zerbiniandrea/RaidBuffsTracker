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
	"BuffRemindersDB",
	"SLASH_BUFFREMINDERS1",
	"SLASH_BUFFREMINDERS2",
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
	"IsInInstance",
	"IsInRaid",
	"Settings",
	"SettingsPanel",
	"UIParent",
	"IsPlayerSpell",
	"UnitCanAssist",
	"UnitClass",
	"UnitExists",
	"UnitGroupRolesAssigned",
	"UnitIsConnected",
	"UnitIsDeadOrGhost",
	"UnitIsUnit",

	-- WoW UI globals
	"GameTooltip",
	"STANDARD_TEXT_FONT",
	"UIDropDownMenu_AddButton",
	"UIDropDownMenu_CreateInfo",
	"UIDropDownMenu_DisableDropDown",
	"UIDropDownMenu_EnableDropDown",
	"UIDropDownMenu_Initialize",
	"UIDropDownMenu_SetSelectedValue",
	"UIDropDownMenu_SetText",
	"UIDropDownMenu_SetWidth",
}
