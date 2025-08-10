std = "lua51"
max_line_length = false
codes = true
exclude_files = {
	"**/libs",
}
ignore = {
	"11./SLASH_.*", -- Setting an undefined (Slash handler) global variable
	"212", -- Unused argument
	"213", -- Unused loop variable
}
globals = {
	"BetterAddonListDB",

	"AddonCharacterDropDown",
	"AddonCharacterDropDownButton",
	"AddonList",
	"AddonList_Enable",
	"AddonList_SetSecurityIcon",
	"AddonList_SetStatus",
	"AddonListForceLoad",
	"AddonTooltip_Update",
	"C_AddOns",
	"C_Timer",
	"CloseDropDownMenus",
	"CopyTable",
	"CreateAtlasMarkup",
	"CreateFrame",
	"CreateSimpleTextureMarkup",
	"GameTooltip",
	"GetAddOnMemoryUsage",
	"GetLocale",
	"hooksecurefunc",
	"IsAddonVersionCheckEnabled",
	"IsShiftKeyDown",
	"MenuResponse",
	"MenuUtil",
	"PlaySound",
	"ResetAddOns",
	"SecureCmdOptionParse",
	"ShowUIPanel",
	"SlashCmdList",
	"SOUNDKIT",
	"ToggleDropDownMenu",
	"UIDropDownMenu_AddButton",
	"UIDropDownMenu_CreateInfo",
	"UIDropDownMenu_Initialize",
	"UIDROPDOWNMENU_MENU_VALUE",
	"UIDropDownMenu_SetSelectedValue",
	"UnitGUID",
	"UnitName",
	"UpdateAddOnMemoryUsage",

	"tContains",
	"CountTable",
	"GetKeysArray",
	"sort",
	"wipe",
	"tostringall",

	"ADDON_BANNED_TOOLTIP",
	"CANCEL",
	"FILTER",
	"LOAD_ADDON",
	"NONE",
	"OKAY",
	"YES",
	"NORMAL_FONT_COLOR",
}
files["BetterAddonList.lua"].globals = {
	"LibStub",
	"AddonList_IsAddOnLoadOnDemand",
	"AddonList_HasAnyChanged",
	"AddonList_Update",
	"AddonListDisableAllButton",
	"AddonListOkayButton",
	"CreateDataProvider",
	"CreateIndexRangeDataProvider",
	"GameTooltip_Hide",
	"SearchBoxTemplate_OnTextChanged",
}
files["BetterAddonList_Classic.lua"].globals = {
	"AddonList_EnableAll",
	"AddonList_DisableAll",
	"AddonList_Update",
	"AddonListScrollFrame",
	"AddonTooltip_BuildDeps",
	"FauxScrollFrame_Update",
	"SearchBoxTemplate_OnTextChanged",
	"StaticPopup_Show",
	"StaticPopupDialogs",
	"ADDON_DEPENDENCIES",
	"ADDON_BUTTON_HEIGHT",
	"MAX_ADDONS_DISPLAYED",
}
