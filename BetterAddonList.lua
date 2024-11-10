local ADDON_NAME, ns = ...
BetterAddonListDB = BetterAddonListDB or {}

local LibDialog = LibStub("LibDialog-1.0n")

local _G = _G
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local L = ns.L
L.LOAD_ADDON = GetLocale() == "ruRU" and "Загрузить" or LOAD_ADDON

local UpdateList

local sets = nil
local included = nil
local character = nil
local playerGUID = UnitGUID("player")

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
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.GetAddOnEnableState(i, character) > 0 then
			C_AddOns.EnableAddOn(i, playerGUID)
		else
			C_AddOns.DisableAddOn(i, playerGUID)
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
	AddonListForceLoad:SetPoint("TOPLEFT", AddonList, 4, 0)
	AddonListForceLoad:SetFrameLevel(AddonList.TitleContainer:GetFrameLevel() + 1)
	AddonListForceLoad:SetSize(24, 24)
	local regions = {AddonListForceLoad:GetRegions()}
	regions[1]:SetPoint("LEFT", AddonListForceLoad, "RIGHT", 2, 0)
	regions[1]:SetText(L["Load out of date"])

	-- add some option buttons
	local hideIcons = CreateFrame("Button", "BetterAddonListOptionHideIcons", AddonList)
	hideIcons:SetFrameLevel(AddonList.TitleContainer:GetFrameLevel() + 1)
	hideIcons:SetNormalTexture(134400) -- inv_misc_questionmark
	hideIcons:SetHighlightTexture(134400)
	hideIcons:SetSize(20, 20)
	hideIcons:SetPoint("LEFT", AddonListDisableAllButton, "RIGHT", 25, -1)
	hideIcons:SetScript("OnClick", function(this)
		-- cycle through
		if BetterAddonListDB.hide_icons == false then
			BetterAddonListDB.hide_icons = true -- true = hide
		elseif BetterAddonListDB.hide_icons == true then
			BetterAddonListDB.hide_icons = nil -- nil = nodefault
		elseif BetterAddonListDB.hide_icons == nil then
			BetterAddonListDB.hide_icons = false --- false = show all
		end
		UpdateList()
	end)
	hideIcons:SetScript("OnEnter", function(this)
		GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Toggle Icons"])
		GameTooltip:Show()
	end)
	hideIcons:SetScript("OnLeave", GameTooltip_Hide)

	local hideMemory = CreateFrame("Button", "BetterAddonListOptionHideIcons", AddonList)
	hideMemory:SetFrameLevel(AddonList.TitleContainer:GetFrameLevel() + 1)
	hideMemory:SetNormalTexture(4555550) -- inv_10_jewelcrafting_gem1leveling_cut_green
	hideMemory:SetHighlightTexture(4555550)
	hideMemory:SetSize(20, 20)
	hideMemory:SetPoint("LEFT", hideIcons, "RIGHT", 2, 0)
	hideMemory:SetScript("OnClick", function(this)
		BetterAddonListDB.hide_memory = not BetterAddonListDB.hide_memory or nil
		UpdateList()
	end)
	hideMemory:SetScript("OnEnter", function(this)
		GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Toggle Memory Usage"])
		GameTooltip:Show()
	end)
	hideMemory:SetScript("OnLeave", GameTooltip_Hide)

	-- let the frame overlap over ui frames
	--UIPanelWindows["AddonList"].area = nil

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
			C_AddOns.DisableAllAddOns(playerGUID)
			UpdateList()
			self:Print(L["Disabled all addons."])
		elseif command == "reset" then
			C_AddOns.ResetAddOns()
			UpdateList()
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

LibDialog:Register("BETTER_ADDONLIST_SAVESET", {
	buttons = {
		{ text = OKAY, on_click = function(self, data) addon:SaveSet(data) end, },
		{ text = CANCEL, },
	},
	on_show = function(self, data)
		self.text:SetFormattedText(L["Save the currently selected addons to %s?"], data)
		CloseDropDownMenus(1)
	end,
	no_close_button = true,
	hide_on_escape = true,
	show_while_dead = true,
})

LibDialog:Register("BETTER_ADDONLIST_DELETESET", {
	buttons = {
		{ text = OKAY, on_click = function(self, data) addon:DeleteSet(data) end, },
		{ text = CANCEL, },
	},
	on_show = function(self, data)
		self.text:SetFormattedText(L["Delete set %s?"], data)
		CloseDropDownMenus(1)
	end,
	no_close_button = true,
	hide_on_escape = true,
	show_while_dead = true,
})

LibDialog:Register("BETTER_ADDONLIST_NEWSET", {
	text = L["Enter the name for the new set"],
	buttons = {
		{
			text = OKAY,
			on_click = function(self)
				local text = self.editboxes[1]:GetText():trim()
				LibDialog:Dismiss("BETTER_ADDONLIST_NEWSET")
				if sets[text] then
					LibDialog:Spawn("BETTER_ADDONLIST_ERROR_NAME", {text, "BETTER_ADDONLIST_NEWSET"})
					return true
				end
				addon:SaveSet(text)
			end,
		},
		{ text = CANCEL, },
	},
	editboxes = {
		{
			on_enter_pressed = function(editbox)
				local text = editbox:GetText():trim()
				LibDialog:Dismiss("BETTER_ADDONLIST_NEWSET")
				if sets[text] then
					LibDialog:Spawn("BETTER_ADDONLIST_ERROR_NAME", {text, "BETTER_ADDONLIST_NEWSET"})
					return true
				end
				addon:SaveSet(text)
			end,
			on_escape_pressed = function()
				LibDialog:Dismiss("BETTER_ADDONLIST_NEWSET")
			end,
			auto_focus = true,
		},
	},
	on_show = function(self) CloseDropDownMenus(1) end,
	no_close_button = true,
	hide_on_escape = true,
	show_while_dead = true,
})

LibDialog:Register("BETTER_ADDONLIST_RENAMESET", {
	buttons = {
		{
			text = OKAY,
			on_click = function(self, data)
				local text = self.editboxes[1]:GetText():trim()
				LibDialog:Dismiss("BETTER_ADDONLIST_RENAMESET")
				if sets[text] then
					LibDialog:Spawn("BETTER_ADDONLIST_ERROR_NAME", {text, "BETTER_ADDONLIST_RENAMESET", data})
					return true
				end
				addon:RenameSet(data, text)
			end,
		},
		{ text = CANCEL, },
	},
	editboxes = {
		{
			on_enter_pressed = function(editbox, data)
				local text = editbox:GetText():trim()
				LibDialog:Dismiss("BETTER_ADDONLIST_RENAMESET")
				if sets[text] then
					LibDialog:Spawn("BETTER_ADDONLIST_ERROR_NAME", {text, "BETTER_ADDONLIST_RENAMESET", data})
					return true
				end
				addon:RenameSet(data, text)
			end,
			on_escape_pressed = function()
				LibDialog:Dismiss("BETTER_ADDONLIST_RENAMESET")
			end,
			auto_focus = true,
		},
	},
	on_show = function(self, data)
		self.text:SetFormattedText(L["Enter the new name for %s"], data)
		CloseDropDownMenus(1)
	end,
	no_close_button = true,
	hide_on_escape = true,
	show_while_dead = true,
})

LibDialog:Register("BETTER_ADDONLIST_ERROR_NAME", {
	buttons = {
		{
			text = OKAY,
			on_click = function(self, data)
				LibDialog:Dismiss("BETTER_ADDONLIST_ERROR_NAME")
				LibDialog:Spawn(data[2], data[3])
				return true
			end,
		},
		{ text = CANCEL, },
	},
	on_show = function(self, data)
		self.text:SetFormattedText(L["There is already a set named \"%s\".\nPlease choose another name."], data[1])
	end,
	icon = _G.STATICPOPUP_TEXTURE_ALERT,
	-- cancels_on_spawn = { "BETTER_ADDONLIST_NEWSET", "BETTER_ADDONLIST_RENAMESET" },
	no_close_button = true,
	hide_on_escape = true,
	show_while_dead = true,
})

-- sets menu
do
	local CURRENT_SET = nil
	local CURRENT_SET_CHUNK = 1
	local CHUNK_SIZE = 40
	local list = {}

	local separator = {
		isTitle = true,
		notCheckable = 1,
		icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
		iconInfo = {
			tCoordLeft = 0,
			tCoordRight = 1,
			tCoordTop = 0,
			tCoordBottom = 1,
			tSizeX = 0,
			tFitDropDownSizeX = true,
			tSizeY = 8,
		},
		iconOnly = true,
	}

	-- pseudo natural sorting
	local function pad(s)
		local n = tonumber(s)
		if n < 1000 then
			return ("%04d"):format(n)
		end
		return s
	end
	local function natsort(a, b)
		return a:gsub("(%d+)", pad):lower() < b:gsub("(%d+)", pad):lower()
	end
	local function icmp(a, b) -- ignore color
		return a:gsub("(%|c%x%x%x%x%x%x%x%x|%|r)", "") < b:gsub("(%|c%x%x%x%x%x%x%x%x|%|r)", "") -- =~ s/(\|c[a-fA-F0-9]{8}|\|r)//g
	end

	local function menu(self, level)
		if not level then return end

		local info = UIDropDownMenu_CreateInfo()
		info.notCheckable = 1

		if level == 1 then
			if next(sets) then
				wipe(list)
				for name in next, sets do
					list[#list+1] = name
				end
				sort(list, natsort)

				info.hasArrow = 1
				for _, name in ipairs(list) do
					info.text = name
					info.value = name
					UIDropDownMenu_AddButton(info, level)
				end

				UIDropDownMenu_AddButton(separator, level)
			end

			info = UIDropDownMenu_CreateInfo()
			info.notCheckable = 1

			info.text = L["Create new set"]
			info.func = function() LibDialog:Spawn("BETTER_ADDONLIST_NEWSET") end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Reset"]
			info.func = function()
				C_AddOns.ResetAddOns()
				UpdateList()
			end
			info.tooltipTitle = info.text
			info.tooltipText = L["Reset addons to what was enabled at login."]
			info.tooltipOnButton = 1
			UIDropDownMenu_AddButton(info, level)

		elseif level == 2 then
			CURRENT_SET = UIDROPDOWNMENU_MENU_VALUE

			info.text = CURRENT_SET
			info.isTitle = 1
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = L["View (%d)"]:format(#sets[CURRENT_SET])
			info.value = "view_set"
			info.func = nil
			info.hasArrow = 1
			info.notCheckable = 1
			info.disabled = #sets[CURRENT_SET] == 0 and 1 or nil
			UIDropDownMenu_AddButton(info, level)

			UIDropDownMenu_AddButton(separator, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = L["Load"]
			info.func = function()
				addon:LoadSet(CURRENT_SET)
				CloseDropDownMenus(1)
			end
			info.tooltipTitle = info.text
			info.tooltipText = L["Disable all addons then enable addons in this set."]
			info.tooltipOnButton = 1
			info.notCheckable = 1
			UIDropDownMenu_AddButton(info, level)
			info.tooltipTitle = nil
			info.tooltipText = nil

			info.text = L["Save"]
			info.func = function() LibDialog:Spawn("BETTER_ADDONLIST_SAVESET", CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Rename"]
			info.func = function() LibDialog:Spawn("BETTER_ADDONLIST_RENAMESET", CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Delete"]
			info.func = function() LibDialog:Spawn("BETTER_ADDONLIST_DELETESET", CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			UIDropDownMenu_AddButton(separator, level)

			info.text = L["Include with another set"]
			info.value = "include_set"
			info.func = nil
			info.hasArrow = 1
			info.disabled = (#list < 3) and 1 or nil -- have more than the current set and default
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Remove an included set"]
			info.value = "remove_set"
			info.func = nil
			info.hasArrow = 1
			info.disabled = not included[CURRENT_SET] or not next(included[CURRENT_SET])
			UIDropDownMenu_AddButton(info, level)

			UIDropDownMenu_AddButton(separator, level)

			info = UIDropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.disabled = #sets[CURRENT_SET] == 0 and 1 or nil

			info.text = L["Enable addons from this set"]
			info.func = function() addon:EnableSet(CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)

			info.text = L["Disable addons from this set"]
			info.func = function() addon:DisableSet(CURRENT_SET) end
			UIDropDownMenu_AddButton(info, level)
		elseif level == 3 then
			if UIDROPDOWNMENU_MENU_VALUE == "view_set" then
				info = UIDropDownMenu_CreateInfo()
				info.text = L["Addon List"]
				info.isTitle = 1
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil

				sort(sets[CURRENT_SET], icmp)
				local count = #sets[CURRENT_SET]
				if count <= CHUNK_SIZE then
					info.disabled = 1
					info.hasArrow = nil
					for i, name in ipairs(sets[CURRENT_SET]) do
						info.text = name
						UIDropDownMenu_AddButton(info, level)
					end
				else
					info.disabled = nil
					info.hasArrow = 1
					for i = 1, count, CHUNK_SIZE do
						info.text = ("%d - %d"):format(i, math.min(count, i + CHUNK_SIZE))
						info.value = i
						UIDropDownMenu_AddButton(info, level)
					end
				end
			elseif UIDROPDOWNMENU_MENU_VALUE == "include_set" then
				info.text = L["Include with another set"]
				info.isTitle = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil
				info.disabled = nil
				info.notCheckable = nil
				info.isNotRadio = 1
				info.keepShownOnClick = 1

				for i, name in ipairs(list) do
					if name ~= CURRENT_SET then
						info.text = name
						info.checked = included[name] and included[name][CURRENT_SET] and 1 or nil
						info.func = function(_, _, _, checked)
							if not included[name] then
								included[name] = {}
							end
							included[name][CURRENT_SET] = checked or nil
						end
						UIDropDownMenu_AddButton(info, level)
					end
				end
			elseif UIDROPDOWNMENU_MENU_VALUE == "remove_set" then
				info.text = L["Remove an included set"]
				info.isTitle = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil
				info.disabled = nil
				info.notCheckable = 1
				info.isNotRadio = 1

				if included[CURRENT_SET] and next(included[CURRENT_SET]) then
					for name in next, included[CURRENT_SET] do
						info.text = name
						info.func = function() included[CURRENT_SET][name] = nil end
						UIDropDownMenu_AddButton(info, level)
					end
				else
					info.text = NONE
					info.disabled = 1
					UIDropDownMenu_AddButton(info, level)
				end
			end
		elseif level == 4 then
			CURRENT_SET_CHUNK = tonumber(UIDROPDOWNMENU_MENU_VALUE)
			if CURRENT_SET_CHUNK then
				info = UIDropDownMenu_CreateInfo()
				info.text = L["Addon List"]
				info.isTitle = 1
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
				info.isTitle = nil

				sort(sets[CURRENT_SET], icmp)
				for i = CURRENT_SET_CHUNK, CURRENT_SET_CHUNK + CHUNK_SIZE do
					local name = sets[CURRENT_SET][i]
					if not name then break end
					info.text = name
					UIDropDownMenu_AddButton(info, level)
				end
			end
		end
	end
	local dropdown = CreateFrame("Frame", "BetterAddonListSetsDropDown", AddonList, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(dropdown, menu, "MENU")

	local button = CreateFrame("Button", "BetterAddonListSetsButton", AddonList, "UIPanelButtonTemplate")
	button:SetPoint("LEFT", AddonList.Dropdown, "RIGHT", 3, 0)
	button:SetSize(80, 22)
	button:SetText(L["Sets"])
	button:SetScript("OnClick", function(self)
		ToggleDropDownMenu(1, nil, dropdown, self:GetName(), 0, 0)
	end)
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

	local updater = CreateFrame("Frame", nil, AddonList)
	updater:SetScript("OnShow", function(self)
		UpdateAddOnMemoryUsage()
	end)

	local function buildDeps(...)
		local deps = ""
		for i = 1, select("#", ...) do
			local dep = select(i, ...)
			if C_AddOns.GetAddOnEnableState(dep, character) == 0 then
				dep = ("|cffff2020%s|r"):format(dep)
			end
			if i == 1 then
				deps = _G.ADDON_DEPENDENCIES .. dep
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
			local version = GetAddOnMetadata(index, "Version")
			if version and version ~= "@project-version@" then
				GameTooltip:AddDoubleLine(title or name, version)
			else
				GameTooltip:AddLine(title or name)
			end
			GameTooltip:AddLine(notes, 1.0, 1.0, 1.0)
			GameTooltip:AddLine(buildDeps(C_AddOns.GetAddOnDependencies(index)))

			local memory = owner.memoryUsage
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

	local InitButton = function(entry, addonIndex)
		local checkbox = entry.Enabled
		local title = entry.Title
		local status = entry.Status

		if BetterAddonListDB.hide_icons ~= false then -- false = show all
			local titleIcon
			local iconTexture = GetAddOnMetadata(addonIndex, "IconTexture")
			local iconAtlas = GetAddOnMetadata(addonIndex, "IconAtlas")
			if not iconTexture and not iconAtlas and BetterAddonListDB.hide_icons == nil then -- nil = nodefault
				titleIcon = CreateSimpleTextureMarkup("Interface\\ICONS\\INV_Misc_QuestionMark", 20, 20)
			elseif BetterAddonListDB.hide_icons then -- true = hide
				if iconTexture then
					titleIcon = CreateSimpleTextureMarkup(iconTexture, 20, 20)
				elseif iconAtlas then
					titleIcon = CreateAtlasMarkup(iconAtlas, 20, 20)
				else
					titleIcon = CreateSimpleTextureMarkup("Interface\\ICONS\\INV_Misc_QuestionMark", 20, 20)
				end
			end
			if titleIcon then
				local name = title:GetText()
				local _, start = name:find(titleIcon, nil, true)
				if start then
					title:SetText(name:sub(start + 2))
				end
			end
		end

		local lockIcon = entry.Protected
		if not lockIcon then
			lockIcon = CreateFrame("Button", nil, entry, nil, addonIndex)
			lockIcon:SetSize(16, 16)
			lockIcon:SetPoint("CENTER", checkbox, "CENTER")
			lockIcon:SetNormalTexture([[Interface\Glues\CharacterSelect\Glues-AddOn-Icons]])
			lockIcon:GetNormalTexture():SetTexCoord(0, 16/64, 0, 1) -- AddonList_SetSecurityIcon
			lockIcon:SetScript("OnClick", OnClick)
			lockIcon:Hide()
			entry.Protected = lockIcon

			checkbox:HookScript("OnClick", function(self, ...) OnClick(lockIcon, ...) end)
		end

		local memIcon = entry.Memory
		if not memIcon then
			memIcon = CreateFrame("Button", nil, entry, nil, addonIndex)
			memIcon:SetSize(6, 32)
			memIcon:SetPoint("RIGHT", checkbox, "LEFT", 1, 0)
			memIcon:SetNormalTexture([[Interface\AddOns\BetterAddonList\textures\mem0]])
			entry.Memory = memIcon
		end

		-- fix the "Load AddOn" text overflowing for some locales
		local load = entry.LoadAddonButton
		load:SetText(L.LOAD_ADDON)
		load:SetWidth(#L.LOAD_ADDON > 12 and 120 or 100)

		local enabled = C_AddOns.GetAddOnEnableState(addonIndex, character) > 0
		if enabled then
			local depsEnabled = CheckAddonDependencies(C_AddOns.GetAddOnDependencies(addonIndex))
			if not depsEnabled then
				title:SetTextColor(1.0, 0.1, 0.1)
				status:SetText(_G.ADDON_DEP_DISABLED)
			end
			if C_AddOns.IsAddOnLoadOnDemand(addonIndex) and not C_AddOns.IsAddOnLoaded(addonIndex) and depsEnabled then
				AddonList_SetStatus(entry, true, false, false)
			end

			if not BetterAddonListDB.hide_memory then
				local memory = GetAddOnMemoryUsage(addonIndex)
				entry.memoryUsage = memory
				local usage = memory / 8000 -- just needed some baseline
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
			else
				entry.memoryUsage = nil
				memIcon:Hide()
			end
		else
			entry.memoryUsage = nil
			memIcon:Hide()
		end

		local protected = IsAddonProtected(addonIndex)
		lockIcon:SetShown(protected)
		checkbox:SetShown(not protected)
	end
	hooksecurefunc("AddonList_InitButton", InitButton)

	hooksecurefunc("AddonList_LoadAddOn", function(index)
		UpdateAddOnMemoryUsage()
		for _, frame in AddonList.ScrollBox:EnumerateFrames() do
			if frame:GetID() == index then
				InitButton(frame, index)
				return
			end
		end
	end)
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

	local fullList = CreateIndexRangeDataProvider(C_AddOns.GetNumAddOns())
	local searchList = CreateDataProvider()
	AddonList.searchList = searchList

	local strfind = string.find
	local searchString = ""
	local function OnTextChanged(self)
		SearchBoxTemplate_OnTextChanged(self)
		local oldText = searchString
		searchString = self:GetText():lower():trim()

		searchList:Flush()
		if (searchString ~= "" and oldText ~= searchString) or next(filterList) then
			local list = {}
			for i=1, C_AddOns.GetNumAddOns() do
				local name, title = C_AddOns.GetAddOnInfo(i)
				if (searchString == "" or (strfind(name:lower(), searchString, nil, true) or (title and strfind(title:lower(), searchString, nil, true)))) and checkFilters(i) then
					list[#list + 1] = i
				end
			end
			if #list > 0 then
				searchList:InsertTable(list)
			end
		end
		UpdateList()
	end

	function UpdateList()
		if not AddonList.searchList:IsEmpty() then
			AddonList.ScrollBox:SetDataProvider(AddonList.searchList, true)
		else
			AddonList.ScrollBox:SetDataProvider(fullList, true)
		end

		if AddonList_HasAnyChanged() then
			AddonListOkayButton:SetText(_G.RELOADUI)
			AddonList.shouldReload = true
		else
			AddonListOkayButton:SetText(_G.OKAY)
			AddonList.shouldReload = false
		end
	end

	hooksecurefunc("AddonList_Update", function()
		if not AddonList.searchList:IsEmpty() then
			AddonList.ScrollBox:SetDataProvider(AddonList.searchList, true)
		end
	end)

	AddonList:HookScript("OnHide", function(self)
		-- reset search box
		wipe(self.filterList)
		self.SearchBox:SetText("")
		OnTextChanged(self.SearchBox)
	end)

	local editBox = CreateFrame("EditBox", "BetterAddonListSearchBox", AddonList, "SearchBoxTemplate")
	editBox:SetPoint("TOPRIGHT", -107, -33) -- -107 w/filter, -11 w/o
	editBox:SetSize(115, 20)
	editBox:SetMaxLetters(40)
	editBox:SetScript("OnTextChanged", OnTextChanged)
	AddonList.SearchBox = editBox

	local filterButton = CreateFrame("Button", "BetterAddonListFilterButton", AddonList, "UIMenuButtonStretchTemplate")
	filterButton:SetPoint("LEFT", editBox, "RIGHT", 3, 0)
	filterButton:SetSize(93, 22)
	filterButton:SetText(FILTER)

	local arrow = filterButton:CreateTexture(nil, "ARTWORK")
	arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetSize(10, 12)
	arrow:SetTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
	arrow:Show()
	filterButton.Icon = arrow

	local function menu(self, level)
		local info = UIDropDownMenu_CreateInfo()
		info.keepShownOnClick = true

		if level == 1 then
			info.isNotRadio = true
			for _, key in ipairs(filters) do
				info.text = L[("FILTER_%s"):format(key)]
				info.func = function(_, _, _, checked)
					filterList[key] = checked or nil
					OnTextChanged(editBox)
				end
				info.checked = filterList[key]
				UIDropDownMenu_AddButton(info, level)
			end
		end
		--[[
			-- - Addon meta flags
			info.checked = 	nil
			info.isNotRadio = nil
			info.func =  nil

			info.text = "Categories"
			info.value = 1
			info.hasArrow = true
			info.notCheckable = true
			UIDropDownMenu_AddButton(info, level)
		else
			if UIDROPDOWNMENU_MENU_VALUE == 1 then
				info.hasArrow = false
				info.isNotRadio = true
				info.notCheckable = true

				info.text = CHECK_ALL
				UIDropDownMenu_AddButton(info, level)

				info.text = UNCHECK_ALL
				UIDropDownMenu_AddButton(info, level)
			end
		end
		--]]
	end

	local dropdown = CreateFrame("Frame", "BetterAddonListFilterDropDown", AddonList, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(dropdown, menu, "MENU")

	filterButton:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ToggleDropDownMenu(1, nil, dropdown, self:GetName(), 74, 15)
	end)

end

function addon:EnableProtected()
	C_AddOns.EnableAddOn(ADDON_NAME)
	for name in next, BetterAddonListDB.protected do
		C_AddOns.EnableAddOn(name)
	end
end

function addon:LoadSet(name)
	C_AddOns.DisableAllAddOns(playerGUID)
	self:EnableSet(name)
end

function addon:EnableSet(name, done)
	local set = sets[name]
	if set and #set > 0 then
		for i=1, C_AddOns.GetNumAddOns() do
			local addon_name = C_AddOns.GetAddOnInfo(i)
			if tContains(set, addon_name) then
				C_AddOns.EnableAddOn(i, playerGUID)
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
	UpdateList()
end

function addon:DisableSet(name)
	local set = sets[name]
	if set and #set > 0 then
		for i=1, C_AddOns.GetNumAddOns() do
			local addon_name = C_AddOns.GetAddOnInfo(i)
			if not IsAddonProtected(i) and tContains(set, addon_name) then
				C_AddOns.DisableAddOn(i, playerGUID)
			end
		end
	end
	UpdateList()
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
	if sets[newName] then return end

	sets[newName] = CopyTable(sets[name])
	sets[name] = nil
end

function addon:DeleteSet(name)
	if not sets[name] then return end

	sets[name] = nil
end
