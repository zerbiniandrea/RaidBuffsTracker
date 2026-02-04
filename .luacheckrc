---@diagnostic disable: lowercase-global
std = "lua51"
max_line_length = false
codes = true

ignore = {
	"21./_",
	"212/self",
	"212/profileKey",
}

globals = {
	"_",
	"BuffReminders",
	"BuffRemindersDB",
	"SLASH_BUFFREMINDERS1",
	"SLASH_BUFFREMINDERS2",
	"SlashCmdList",
	"StaticPopupDialogs",
}

read_globals = {
	-- WoW API
	"C_AddOns",
	"C_ChallengeMode",
	"C_EncodingUtil",
	"C_Item",
	"C_Spell",
	"C_Timer",
	"C_UnitAuras",
	"CreateFrame",
	"GetNumGroupMembers",
	"GetSpecialization",
	"GetSpecializationRole",
	"GetTime",
	"GetWeaponEnchantInfo",
	"InCombatLockdown",
	"IsInInstance",
	"IsInRaid",
	"ReloadUI",
	"Settings",
	"SettingsPanel",
	"StaticPopup_Show",
	"time",
	"UIParent",
	"IsPlayerSpell",
	"UnitCanAssist",
	"UnitClass",
	"UnitExists",
	"UnitGroupRolesAssigned",
	"UnitIsConnected",
	"UnitIsDeadOrGhost",
	"UnitIsUnit",
	"UnitIsVisible",

	"tinsert",

	-- WoW UI globals
	"GameTooltip",
	"HideUIPanel",
	"STANDARD_TEXT_FONT",
	"UISpecialFrames",
	"UIDropDownMenu_AddButton",
	"UIDropDownMenu_CreateInfo",
	"UIDropDownMenu_DisableDropDown",
	"UIDropDownMenu_EnableDropDown",
	"UIDropDownMenu_Initialize",
	"UIDropDownMenu_SetSelectedValue",
	"UIDropDownMenu_SetText",
	"UIDropDownMenu_SetWidth",
}
