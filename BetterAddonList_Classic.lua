local ADDON_NAME, ns = ...
BetterAddonListDB = BetterAddonListDB or {}

local _G = _G

local AddonList_Update = AddonList_Update
local ADDON_BUTTON_HEIGHT = ADDON_BUTTON_HEIGHT
local MAX_ADDONS_DISPLAYED = MAX_ADDONS_DISPLAYED
local ADDON_DEPENDENCIES = ADDON_DEPENDENCIES

local L = ns.L

local sets = nil
local included = nil
local character = nil

local function IsAddonProtected(index)
	if not index then return end
	local name, _, _, _, _, security = C_AddOns.GetAddOnInfo(index)
	return name == ADDON_NAME or security == "SECURE" or BetterAddonListDB.protected[tostring(name)]
end

local function SetAddonProtected(index, value)
	if not index then return end
	local name, _, _, _, _, security = C_AddOns.GetAddOnInfo(index)
	if name ~= ADDON_NAME and security == "INSECURE" then
		BetterAddonListDB.protected[tostring(name)] = value and true or nil
	end
end

local function CheckAddonDependencies(...)
	for i = 1, select("#", ...) do
		local dep = select(i, ...)
		if C_AddOns.GetAddOnEnableState(dep, character) == 0 then
			return false
		end
	end
	return true
end

-- XXX override framexml functions to replace inconsistent usage of GetAddonCharacter
function AddonList_Enable(index, enabled)
	if enabled then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		C_AddOns.EnableAddOn(index, character)
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		C_AddOns.DisableAddOn(index, character)
	end
	_G.AddonList_Update()
end

function AddonList_EnableAll()
	C_AddOns.EnableAllAddOns(character)
	_G.AddonList_Update()
end

function AddonList_DisableAll()
	C_AddOns.DisableAllAddOns(character)
	_G.AddonList_Update()
end

local addon = CreateFrame("Frame")
addon:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_LOGOUT")

function addon:ADDON_LOADED(addon_name)
	if addon_name ~= ADDON_NAME then return end
	self:UnregisterEvent("ADDON_LOADED")

	if not BetterAddonListDB.sets then
		BetterAddonListDB.sets = {}
	end
	sets = BetterAddonListDB.sets

	if not BetterAddonListDB.nested then
		BetterAddonListDB.nested = {}
	end
	included = BetterAddonListDB.nested

	if not BetterAddonListDB.protected then
		BetterAddonListDB.protected = {}
	end

	character = UnitName("player")

	--- From BlizzBugsSuck:
	-- Fix glitchy-ness of EnableAddOn/DisableAddOn API, which affects the stability of the default
	-- UI's addon management list (both in-game and glue), as well as any addon-management addons.
	-- The problem is caused by broken defaulting logic used to merge AddOns.txt settings across
	-- characters to those missing a setting in AddOns.txt, whereby toggling an addon for a single character
	-- sometimes results in also toggling it for a different character on that realm for no obvious reason.
	-- The code below ensures each character gets an independent enable setting for each installed
	-- addon in its AddOns.txt file, thereby avoiding the broken defaulting logic.
	-- Note the fix applies to each character the first time it loads there, and a given character
	-- is not protected from the faulty logic on addon X until after the fix has run with addon X
	-- installed (regardless of enable setting) and the character has logged out normally.

	-- XXX Using this to fix startStatus (classic defaults to "All", vanilla always uses player name)
	for i = 1, C_AddOns.GetNumAddOns() do
		local enabled = C_AddOns.GetAddOnEnableState(i, character) > 0
		AddonList.startStatus[i] = enabled
		if enabled then
			C_AddOns.EnableAddOn(i, character)
		else
			C_AddOns.DisableAddOn(i, character)
		end
	end

	hooksecurefunc(C_AddOns, "DisableAllAddOns", function()
		self:EnableProtected()
	end)

	-- check protected
	local messages = {}
	for name in next, BetterAddonListDB.protected do
		local _, _, _, loadable, reason = C_AddOns.GetAddOnInfo(name)
		if C_AddOns.IsAddOnLoadOnDemand(name) then
			if not CheckAddonDependencies(C_AddOns.GetAddOnDependencies(name)) then
				loadable, reason = false, "DEP_DISABLED"
			elseif not loadable and reason == "DEMAND_LOADED" then
				loadable = true
			end
		end
		if not loadable then
			if reason == "MISSING" then
				BetterAddonListDB.protected[name] = nil
			else
				messages[name] = reason or "UNKNOWN_ERROR"
			end
		end
		C_AddOns.EnableAddOn(name)
	end
	if next(messages) then
		C_Timer.After(12, function()
			local ood, dep = nil, nil
			for name, reason in next, messages do
				self:Print(L["Problem with protected addon %q (%s)"]:format(name, _G["ADDON_"..reason]))
				if reason == "INTERFACE_VERSION" then
					ood = true
				elseif reason:find("DEP", nil, true) then
					dep = true
				end
			end
			if ood and C_AddOns.IsAddonVersionCheckEnabled() then
				self:Print(L["Out of date addons are being disabled! They will not be able to load until their interface version is updated or \"Load out of date AddOns\" is checked."])
			elseif not dep then
				self:Print(L["Reload UI to load these addons."])
			end
			messages = nil
		end)
	end
end

function addon:PLAYER_LOGIN()
	-- make the panel movable
	local mover = CreateFrame("Frame", "BetterAddonListMover", AddonList)
	mover:EnableMouse(true)
	mover:SetPoint("TOP", AddonList, "TOP", 0, 0)
	mover:SetWidth(500)
	mover:SetHeight(25)
	mover:SetScript("OnMouseDown", function() AddonList:StartMoving() end)
	mover:SetScript("OnMouseUp", function() AddonList:StopMovingOrSizing() end)
	AddonList:SetMovable(true)
	AddonList:ClearAllPoints()
	AddonList:SetPoint("CENTER")

	-- move and resize the "Load out of date addons" check box
	AddonListForceLoad:ClearAllPoints()
	AddonListForceLoad:SetPoint("TOPLEFT", AddonList, 2, 1)
	AddonListForceLoad:SetSize(24, 24)
	local regions = {AddonListForceLoad:GetRegions()}
	regions[1]:SetPoint("LEFT", AddonListForceLoad, "RIGHT", 2, 0)
	regions[1]:SetText(L["Load out of date"])

	-- let the frame overlap over ui frames
	--UIPanelWindows["AddonList"].area = nil

	-- default to showing the player profile
	AddonList:HookScript("OnShow", function()
		local dropdown = AddonList.Dropdown
		local _, nextSelection = dropdown:CollectSelectionData()
		dropdown:Pick(nextSelection, 1) -- MenuInputContext.None
		dropdown:Disable()
		_G.AddonList_Update()
	end)

	-- fix the "Load AddOn" text overflowing for some locales
	local loadAddonText = GetLocale() == "ruRU" and "Загрузить" or LOAD_ADDON
	local loadAddonSize = #loadAddonText > 12 and 120 or 100
	for i=1, MAX_ADDONS_DISPLAYED do
		local button = _G["AddonListEntry"..i].LoadAddonButton
		button:SetText(loadAddonText)
		button:SetWidth(loadAddonSize)
	end

	SLASH_BETTERADDONLIST1 = "/addons"
	SLASH_BETTERADDONLIST2 = "/acp" -- muscle memory ;[
	SLASH_BETTERADDONLIST3 = "/bal" -- why not
	SlashCmdList["BETTERADDONLIST"] = function(input)
		if not input or input:trim() == "" then
			ShowUIPanel(AddonList)
			return
		end

		input = SecureCmdOptionParse(input)
		if not input then return end

		local command, rest = input:match("^(%S*)%s*(.-)$")
		command = command and command:lower()
		rest = (rest and rest ~= "") and rest:trim() or nil

		if command == "load" then
			if sets[rest] then
				self:LoadSet(rest)
				self:Print(L["Enabled only addons in set %q."]:format(rest))
			else
				self:Print(L["No set named %q."]:format(rest))
			end
		elseif command == "unload" or command == "disable" then
			if sets[rest] then
				self:DisableSet(rest)
				self:Print(L["Disabled addons in set %q."]:format(rest))
			else
				self:Print(L["No set named %q."]:format(rest))
			end
		elseif command == "enable" then
			if sets[rest] then
				self:EnableSet(rest)
				self:Print(L["Enabled addons in set %q."]:format(rest))
			else
				self:Print(L["No set named %q."]:format(rest))
			end
		elseif command == "save" then
			self:SaveSet(rest)
			self:Print(L["Saved enabled addons to set %q."]:format(rest))
		elseif command == "delete" then
			if sets[rest] then
				self:DeleteSet(rest)
				self:Print(L["Deleted set %q."]:format(rest))
			else
				self:Print(L["No set named %q."]:format(rest))
			end
		elseif command == "disableall" then
			C_AddOns.DisableAllAddOns(character)
			_G.AddonList_Update()
			self:Print(L["Disabled all addons."])
		elseif command == "reset" then
			C_AddOns.ResetAddOns()
			_G.AddonList_Update()
			self:Print(L["Reset addons to what was enabled at login."])
		end
	end
end

function addon:PLAYER_LOGOUT()
	-- clean up
	for k, v in next, included do
		if not next(v) then
			included[k] = nil
		end
	end
end

function addon:Print(...)
	print("|cff33ff99BetterAddonList|r:", tostringall(...))
end

StaticPopupDialogs["BETTER_ADDONLIST_SAVESET"] = {
	text = L["Save the currently selected addons to %s?"],
	button1 = YES,
	button2 = CANCEL,
	OnAccept = function(self) addon:SaveSet(self.data) end,
	OnShow = function(self) CloseDropDownMenus(1) end,
	OnHide = function(self) self.data = nil end,
	timeout = 0,
	hideOnEscape = 1,
	whileDead = 1,
	exclusive = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_DELETESET"] = {
	text = L["Delete set %s?"],
	button1 = YES,
	button2 = CANCEL,
	OnAccept = function(self) addon:DeleteSet(self.data) end,
	OnShow = function(self) CloseDropDownMenus(1) end,
	OnHide = function(self) self.data = nil end,
	timeout = 0,
	hideOnEscape = 1,
	whileDead = 1,
	exclusive = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_NEWSET"] = {
	text = L["Enter the name for the new set"],
	button1 = OKAY,
	button2 = CANCEL,
	OnAccept = function(self)
		local name = self.editBox:GetText()
		if sets[name] then
			StaticPopup_Show("BETTER_ADDONLIST_ERROR_NAME", name, nil, {"BETTER_ADDONLIST_NEWSET"})
			return
		end
		addon:SaveSet(name)
	end,
	EditBoxOnEnterPressed = function(self)
		local name = self:GetParent().editBox:GetText():trim()
		self:GetParent():Hide()
		if sets[name] then
			StaticPopup_Show("BETTER_ADDONLIST_ERROR_NAME", name, nil, {"BETTER_ADDONLIST_NEWSET"})
			return
		end
		addon:SaveSet(name)
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	OnShow = function(self)
		CloseDropDownMenus(1)
		self.editBox:SetFocus()
	end,
	OnHide = function(self)
		self.editBox:SetText("")
	end,
	timeout = 0,
	hideOnEscape = 1,
	exclusive = 1,
	whileDead = 1,
	hasEditBox = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_RENAMESET"] = {
	text = L["Enter the new name for %s"],
	button1 = OKAY,
	button2 = CANCEL,
	OnAccept = function(self)
		local text = self.editBox:GetText()
		addon:RenameSet(self.data, text)
	end,
	EditBoxOnEnterPressed = function(self)
		local dialog = self:GetParent()
		local text = dialog.editBox:GetText()
		addon:RenameSet(dialog.data, text)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	OnShow = function(self)
		CloseDropDownMenus(1)
		self.editBox:SetFocus()
	end,
	OnHide = function(self)
		self.editBox:SetText("")
		self.data = nil
	end,
	timeout = 0,
	hideOnEscape = 1,
	exclusive = 1,
	whileDead = 1,
	hasEditBox = 1,
	preferredIndex = 3,
}

StaticPopupDialogs["BETTER_ADDONLIST_ERROR_NAME"] = {
	text = L["There is already a set named \"%s\".\nPlease choose another name."],
	button1 = OKAY,
	button2 = CANCEL,
	OnAccept = function(self)
		local name, text = unpack(self.data)
		StaticPopup_Show(name, text)
	end,
	OnHide = function(self)
		self.data = nil
	end,
	timeout = 0,
	hideOnEscape = 1,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	preferredIndex = 3,
}

-- sets menu
local natsort
do
	-- pseudo natural sorting
	local function pad(s)
		local n = tonumber(s)
		if n < 1000 then
			return ("%04d"):format(n)
		end
		return s
	end
	function natsort(a, b)
		return a:gsub("(%d+)", pad):lower() < b:gsub("(%d+)", pad):lower()
	end
	-- local function icmp(a, b) -- ignore color
	-- 	return a:gsub("(%|c%x%x%x%x%x%x%x%x|%|r)", "") < b:gsub("(%|c%x%x%x%x%x%x%x%x|%|r)", "") -- =~ s/(\|c[a-fA-F0-9]{8}|\|r)//g
	-- end

	local function IsSetIncluded(data)
		local setA, setB = data[1], data[2]
		return included[setA] and included[setA][setB] and true
	end

	local function SetSetIncluded(data)
		local value = not IsSetIncluded(data)
		local setA, setB = data[1], data[2]
		if not included[setA] then
			included[setA] = {}
		end
		included[setA][setB] = value or nil
	end

	local function GenerateSetsMenu(owner, root)
		if next(sets) then
			local list = {}
			for name in next, sets do
				list[#list + 1] = name
			end
			sort(list, natsort)

			for _, currentSet in ipairs(list) do
				local set = root:CreateButton(currentSet)
				set:CreateTitle(currentSet)

				local diff = {}
				local count = #sets[currentSet]
				local view = set:CreateButton(L["View (%d)"]:format(count))
				view:SetEnabled(count > 0)
				if count > 0 then
					view:SetScrollMode(50 * 8)
					view:CreateTitle(L["Addon List"])
					sort(sets[currentSet])
					for _, addonName in ipairs(sets[currentSet]) do
						local _, _, _, loadable, reason = C_AddOns.GetAddOnInfo(addonName)
						view:CreateButton(addonName):SetEnabled(loadable or reason ~= "MISSING")
						if C_AddOns.GetAddOnEnableState(addonName, character) == 0 and (loadable or reason ~= "MISSING") then
							diff[addonName] = "+"
						end
					end
					for addonIndex = 1, C_AddOns.GetNumAddOns() do
						local addonName, _, _, loadable, reason = C_AddOns.GetAddOnInfo(addonIndex)
						if not IsAddonProtected(addonIndex) and not tContains(sets[currentSet], addonName) and C_AddOns.GetAddOnEnableState(addonName, character) > 0 and (loadable or reason ~= "MISSING") then
							diff[addonName] = "-"
						end
					end
				end

				local numChanges = CountTable(diff)
				local changes = set:CreateButton(L["Changes (%d)"]:format(numChanges))
				changes:SetEnabled(numChanges > 0)
				if numChanges > 0 then
					changes:SetScrollMode(50 * 8)
					changes:CreateTitle(L["Addon Changes"])
					local kdiff = GetKeysArray(diff)
					sort(kdiff)
					for _, addonName in ipairs(kdiff) do
						-- maybe dim lod addons (DIM_GREEN_FONT_COLOR / DIM_RED_FONT_COLOR)?
						if diff[addonName] == "+" then
							changes:CreateButton(("|cff19ff19+%s|r"):format(addonName))
						else
							changes:CreateButton(("|cffff2020-%s|r"):format(addonName))
						end
					end
				end

				set:CreateDivider()

				set:CreateButton(L["Load"], function(data) addon:LoadSet(data) end, currentSet):SetTooltip(function(tooltip)
					tooltip:SetText(L["Load"], 1.0, 1.0, 1.0, 1.0, true)
					tooltip:AddLine(L["Disable all addons then enable addons in this set."], 1.0, 0.82, 0.0, true)
				end)
				set:CreateButton(L["Save"], function(data) StaticPopup_Show("BETTER_ADDONLIST_SAVESET", data, nil, data) end, currentSet)
				set:CreateButton(L["Rename"], function(data) StaticPopup_Show("BETTER_ADDONLIST_RENAMESET", data, nil, data) end, currentSet)
				set:CreateButton(L["Delete"], function(data) StaticPopup_Show("BETTER_ADDONLIST_DELETESET", data, nil, data) end, currentSet)

				set:CreateDivider()

				local includeSets = set:CreateButton(L["Enabled with this set"])
				includeSets:SetEnabled(#list > 1) -- have more than the current set
				-- includeSets:CreateTitle(L["Additionally load these sets"])
				for _, name in ipairs(list) do
					if name ~= currentSet then
						includeSets:CreateCheckbox(name, IsSetIncluded, SetSetIncluded, { currentSet, name })
					end
				end

				set:CreateDivider()

				set:CreateButton(L["Enable addons from this set"], function(data) addon:EnableSet(data) end, currentSet)
				set:CreateButton(L["Disable addons from this set"], function(data) addon:DisableSet(data) end, currentSet)
			end

			root:CreateDivider()
		end

		root:CreateButton(L["Create new set"], function() StaticPopup_Show("BETTER_ADDONLIST_NEWSET") end)
		root:CreateButton(L["Reset"], function()
			C_AddOns.ResetAddOns()
			_G.AddonList_Update()
		end)
	end

	local button = CreateFrame("Button", "BetterAddonListSetsButton", AddonList, "UIPanelButtonTemplate")
	button:SetPoint("LEFT", AddonList.Dropdown, "RIGHT", 3, 0)
	button:SetSize(80, 22)
	button:SetText(L["Sets"])
	-- button:SetScript("OnClick", function(self)
	-- 	MenuUtil.CreateContextMenu(self, GenerateSetsMenu)
	-- end)

	-- because I want the old ToggleDropDownMenu behaviour with a context menu x.x
	_G.Mixin(button, _G.DropdownButtonMixin)
	button.menuRelativePoint = "BOTTOMLEFT"
	button.menuPointX = 6
	button.menuPointY = 2
	button.menuGenerator = GenerateSetsMenu
	button:OnLoad_Intrinsic()
	button:SetScript("OnMouseDown", button.OnMouseDown_Intrinsic)
	-- button:EnableRegenerateOnResponse() -- rebuild the menu to pick up included set changes
end

-- lock icon toggle / memory usage
do
	local function OnClick(lock, button, down)
		if IsShiftKeyDown() and button == "LeftButton" then
			local index = lock:GetParent():GetID()
			SetAddonProtected(index, not IsAddonProtected(index))
			AddonList_Enable(index, true)
		end
	end

	local lockIcons = {}
	local memIcons = {}
	for i=1, MAX_ADDONS_DISPLAYED do
		local checkbox = _G["AddonListEntry"..i.."Enabled"]

		local lock = CreateFrame("Button", nil, _G["AddonListEntry"..i], nil, i)
		lock:SetSize(16, 16)
		lock:SetPoint("CENTER", checkbox, "CENTER")
		lock:SetNormalTexture([[Interface\Glues\CharacterSelect\Glues-AddOn-Icons]])
		lock:GetNormalTexture():SetTexCoord(0, 16/64, 0, 1) -- AddonList_SetSecurityIcon
		lock:SetScript("OnClick", OnClick)
		lock:Hide()
		lockIcons[i] = lock

		checkbox:HookScript("OnClick", function(self, ...) OnClick(lock, ...) end)

		local mem = CreateFrame("Button", nil, _G["AddonListEntry"..i], nil, i)
		mem:SetSize(6, 32)
		mem:SetPoint("RIGHT", checkbox, "LEFT", 1, 0)
		mem:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem0]])
		memIcons[i] = mem
	end

	local updater = CreateFrame("Frame", nil, AddonList)
	updater:SetScript("OnShow", function(self)
		UpdateAddOnMemoryUsage()
	end)

	hooksecurefunc("AddonList_LoadAddOn", function(self)
		UpdateAddOnMemoryUsage()
		AddonList_Update()
	end)

	local function buildDeps(...)
		local deps = ""
		for i = 1, select("#", ...) do
			local dep = select(i, ...)
			if C_AddOns.GetAddOnEnableState(dep, character) == 0 then
				dep = ("|cffff2020%s|r"):format(dep)
			end
			if i == 1 then
				deps = ADDON_DEPENDENCIES .. dep
			else
				deps = deps .. ", " .. dep
			end
		end
		return deps
	end

	AddonTooltip_Update = function(owner)
		local index = owner:GetID()
		if not index or index < 1 or index > C_AddOns.GetNumAddOns() then return end

		local name, title, notes, _, _, security = C_AddOns.GetAddOnInfo(index)
		GameTooltip:ClearLines()
		if security == "BANNED" then
			GameTooltip:SetText(ADDON_BANNED_TOOLTIP)
		else
			local version = C_AddOns.GetAddOnMetadata(index, "Version")
			if version and version ~= "@project-version@" then
				GameTooltip:AddDoubleLine(title or name, version)
			else
				GameTooltip:AddLine(title or name)
			end
			GameTooltip:AddLine(notes, 1.0, 1.0, 1.0)
			GameTooltip:AddLine(buildDeps(C_AddOns.GetAddOnDependencies(index)))

			local memory = owner.memory
			if memory then
				local text
				if memory > 1000 then
					memory = memory / 1000
					text = L["Memory: %.02f MB"]:format(memory)
				else
					text = L["Memory: %.0f KB"]:format(memory)
				end
				GameTooltip:AddLine(text)
			end
		end
		GameTooltip:Show()
	end

	-- Update the panel my way
	AddonList_Update = function()
		if AddonList.searchList then
			local numEntrys = #AddonList.searchList
			for i=1, MAX_ADDONS_DISPLAYED do
				local offset = AddonList.offset + i
				local addonIndex = AddonList.searchList[offset]
				local entry = _G["AddonListEntry"..i]
				if offset > numEntrys then
					entry:Hide()
				else
					-- aaaaand copy from AddonList_Update
					local name, title, _, loadable, reason, security = C_AddOns.GetAddOnInfo(addonIndex)
					local enabled = C_AddOns.GetAddOnEnableState(addonIndex, character) > 0

					local checkbox = _G["AddonListEntry"..i.."Enabled"]
					checkbox:SetChecked(enabled)

					local titleString = _G["AddonListEntry"..i.."Title"]
					if loadable or ( enabled and (reason == "DEP_DEMAND_LOADED" or reason == "DEMAND_LOADED") ) then
						titleString:SetTextColor(1.0, 0.78, 0.0)
					elseif enabled and reason ~= "DEP_DISABLED" then
						titleString:SetTextColor(1.0, 0.1, 0.1)
					else
						titleString:SetTextColor(0.5, 0.5, 0.5)
					end
					titleString:SetText(title or name)

					local securityIcon = _G["AddonListEntry"..i.."SecurityIcon"]
					if security == "SECURE" then
						AddonList_SetSecurityIcon(securityIcon, 1)
					elseif security == "INSECURE" then
						AddonList_SetSecurityIcon(securityIcon, 2)
					elseif security == "BANNED" then
						AddonList_SetSecurityIcon(securityIcon, 3)
					end
					_G["AddonListEntry"..i.."Security"].tooltip = _G["ADDON_"..security]

					local statusString = _G["AddonListEntry"..i.."Status"]
					statusString:SetText((not enabled and reason) and _G["ADDON_"..reason] or "")

					if enabled ~= AddonList.startStatus[addonIndex] and reason ~= "DEP_DISABLED" then
						if enabled then
							local lod = C_AddOns.IsAddOnLoadOnDemand(addonIndex) and not C_AddOns.IsAddOnLoaded(addonIndex)
							AddonList_SetStatus(entry, lod, false, not lod)
						else
							AddonList_SetStatus(entry, false, false, true)
						end
					else
						AddonList_SetStatus(entry, false, true, false)
					end

					entry:SetID(addonIndex)
					entry:Show()
				end
			end

			FauxScrollFrame_Update(AddonListScrollFrame, numEntrys, MAX_ADDONS_DISPLAYED, ADDON_BUTTON_HEIGHT)
		end

		local numAddons = C_AddOns.GetNumAddOns()
		for i=1, MAX_ADDONS_DISPLAYED do
			local entry = _G["AddonListEntry"..i]
			local checkbox = _G["AddonListEntry"..i.."Enabled"]
			local title = _G["AddonListEntry"..i.."Title"]
			local status = _G["AddonListEntry"..i.."Status"]

			local lockIcon = lockIcons[i]
			local memIcon = memIcons[i]

			local addonIndex = entry:GetID()
			if addonIndex > numAddons then
				entry.memory = nil
				memIcon:Hide()
				lockIcon:Hide()
				checkbox:Show()
			else
				local enabled = C_AddOns.GetAddOnEnableState(addonIndex, character) > 0
				if enabled then
					local depsEnabled = CheckAddonDependencies(C_AddOns.GetAddOnDependencies(addonIndex))
					if not depsEnabled then
						title:SetTextColor(1.0, 0.1, 0.1)
						status:SetText(_G["ADDON_DEP_DISABLED"])
					end
					if C_AddOns.IsAddOnLoadOnDemand(addonIndex) and not C_AddOns.IsAddOnLoaded(addonIndex) and depsEnabled then
						AddonList_SetStatus(entry, true, false, false)
					end

					local memory = GetAddOnMemoryUsage(addonIndex)
					entry.memory = memory
					local usage = memory / 8192 -- just needed some baseline!
					if usage > 0.8 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem5]])
					elseif usage > 0.6 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem4]])
					elseif usage > 0.4 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem3]])
					elseif usage > 0.2 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem2]])
					elseif usage > 0.1 then
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem1]])
					else
						memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem0]])
					end
					memIcon:Show()

					-- XXX undo TriStateCheckbox_SetState
					if checkbox.state ~= 2 then
						checkbox:SetChecked(true)
						checkbox:SetVertexColor(1, 1, 1)
						checkbox:SetDesaturated(false)
						checkbox.AddonTooltip = nil
						checkbox.state = 2
					end
				else
					entry.memory = nil
					memIcon:Hide()
				end

				local protected = IsAddonProtected(addonIndex)
				lockIcon:SetShown(protected)
				checkbox:SetShown(not protected)
			end
		end
	end
	hooksecurefunc("AddonList_Update", AddonList_Update)
end

-- search / filter
do
	AddonList.filterList = {}
	local filterList = AddonList.filterList

	local filters = { -- for menu order
		"ENABLED",
		"DISABLED",
		"LOD",
		"PROTECTED",
	}
	for _, key in next, filters do
		filterList[key] = false
	end

	local filterFunc = {
		ENABLED = function(index) return C_AddOns.GetAddOnEnableState(index, character) > 0 end,
		DISABLED = function(index) return C_AddOns.GetAddOnEnableState(index, character) == 0 end,
		LOD = function(index) return C_AddOns.IsAddOnLoadOnDemand(index) end,
		PROTECTED = function(index) return IsAddonProtected(index) end,
	}
	local function checkFilters(index)
		for filter, value in next, filterList do
			if value and not filterFunc[filter](index) then
				return false
			end
		end
		return true
	end

	local strfind = string.find
	local searchList = {}
	local searchString = ""
	local function OnTextChanged(self)
		SearchBoxTemplate_OnTextChanged(self)
		local oldText = searchString
		searchString = self:GetText():lower():trim()

		if searchString == "" and not next(filterList) then
			AddonList.searchList = nil
			_G.AddonList_Update()
		elseif oldText ~= searchString or next(filterList) then
			wipe(searchList)
			for i=1, C_AddOns.GetNumAddOns() do
				local name, title = C_AddOns.GetAddOnInfo(i)
				if (searchString == "" or (strfind(name:lower(), searchString, nil, true) or (title and strfind(title:lower(), searchString, nil, true)))) and checkFilters(i) then
					searchList[#searchList+1] = i
				end
			end
			AddonList.searchList = searchList
			AddonList_Update()
		end
	end

	local editBox = CreateFrame("EditBox", "BetterAddonListSearchBox", AddonList, "SearchBoxTemplate")
	editBox:SetPoint("TOPRIGHT", -107, -33) -- -107 w/filter, -11 w/o
	editBox:SetSize(115, 20)
	editBox:SetMaxLetters(40)
	editBox:SetScript("OnTextChanged", OnTextChanged)

	local filterButton = CreateFrame("DropdownButton", "BetterAddonListFilterButton", AddonList, "WowStyle1FilterDropdownTemplate")
	filterButton:SetPoint("LEFT", editBox, "RIGHT", 3, 0)
	filterButton:SetSize(93, 22)

	local function isFilterSelected(key)
		return filterList[key]
	end
	local function setFilterSelected(key)
		filterList[key] = not filterList[key]
		OnTextChanged(editBox)
	end
	filterButton:SetupMenu(function(_, root)
		for _, key in ipairs(filters) do
			root:CreateCheckbox(L[("FILTER_%s"):format(key)], isFilterSelected, setFilterSelected, key)
		end
	end)

	filterButton:SetDefaultCallback(function()
		wipe(filterList)
		OnTextChanged(editBox)
	end)
	filterButton:SetIsDefaultCallback(function()
		for _, value in next, filterList do
			if value then
				return false
			end
		end
		return true
	end)
end

function addon:EnableProtected()
	C_AddOns.EnableAddOn(ADDON_NAME)
	for name in next, BetterAddonListDB.protected do
		C_AddOns.EnableAddOn(name)
	end
end

function addon:LoadSet(name)
	C_AddOns.DisableAllAddOns(character)
	self:EnableSet(name)
end

function addon:EnableSet(name, done)
	local set = sets[name]
	if set and #set > 0 then
		for i=1, C_AddOns.GetNumAddOns() do
			local addon_name = C_AddOns.GetAddOnInfo(i)
			if tContains(set, addon_name) then
				C_AddOns.EnableAddOn(i, character)
			end
		end
	end
	if included[name] then
		done = done or { [name] = true }
		for included_set in next, included[name] do
			if not done[included_set] then
				done[included_set] = true
				self:EnableSet(included_set, done)
			end
		end
	end
	_G.AddonList_Update()
end

function addon:DisableSet(name)
	local set = sets[name]
	if set and #set > 0 then
		for i=1, C_AddOns.GetNumAddOns() do
			local addon_name = C_AddOns.GetAddOnInfo(i)
			if not IsAddonProtected(i) and tContains(set, addon_name) then
				C_AddOns.DisableAddOn(i, character)
			end
		end
	end
	_G.AddonList_Update()
end

function addon:SaveSet(name)
	if not name or name == "" then return end

	local set = sets[name]
	if not set then
		sets[name] = {}
		set = sets[name]
	end
	wipe(set)

	for i=1, C_AddOns.GetNumAddOns() do
		local enabled = C_AddOns.GetAddOnEnableState(i, character) > 0
		if enabled and not IsAddonProtected(i) then
			set[#set+1] = C_AddOns.GetAddOnInfo(i)
		end
	end
end

function addon:RenameSet(name, newName)
	if not sets[name] then return end
	if sets[newName] then
		StaticPopup_Show("BETTER_ADDONLIST_ERROR_NAME", newName, nil, {"BETTER_ADDONLIST_RENAMESET", name, nil, name})
		return
	end

	sets[newName] = CopyTable(sets[name])
	sets[name] = nil
end

function addon:DeleteSet(name)
	if not sets[name] then return end

	sets[name] = nil
end

-- indexed set list (can also be used as AceConfig select `sorting`)
function addon:GetSets()
	local list = {}
	for name in next, sets do
		list[#list + 1] = name
	end
	sort(list, natsort)
	return list
end

-- keyed set list (for use as AceConfig select `values` or such)
function addon:GetSetsAsValues()
	local list = {}
	for name in next, sets do
		list[name] = name
	end
	return list
end

------------------------------------
-- API

local public = {}
local api = {
	"LoadSet",
	"EnableSet",
	"DisableSet",
	"SaveSet",
	"RenameSet",
	"DeleteSet",
	"GetSets",
	"GetSetsAsValues",
}
for _, name in next, api do
	public[name] = addon[name]
end

_G.BetterAddonList = public
