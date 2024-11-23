local _, ns = ...
local L = setmetatable({}, {
	__index = function(self, key)
		--geterrorhandler()("BetterAddonList: Missing entry for '"..tostring(key).."'")
		self[key] = key
		return key
	end,
	__newindex = function(self, key, value)
		rawset(self, key, value == true and key or value)
	end,
})
ns.L = L

L["Additionally enable addons from these sets"] = true
L["Addon List"] = true
L["Create new set"] = true
L["Delete"] = true
L["Delete set %s?"] = true
L["Deleted set %q."] = true
L["Disable addons from this set"] = true
L["Disable all addons then enable addons in this set."] = true
L["Disabled addons in set %q."] = true
L["Disabled all addons."] = true
L["Enable addons from this set"] = true
L["Enabled addons in set %q."] = true
L["Enabled only addons in set %q."] = true
L["Enabled with this set"] = true
L["Enter the name for the new set"] = true
L["Enter the new name for %s"] = true
L.FILTER_ENABLED = "Enabled"
L.FILTER_DISABLED = "Disabled"
L.FILTER_LOD = "Load On Demand"
L.FILTER_PROTECTED = "Protected"
L["Load"] = true
L["Load out of date"] = true
L["Memory: %.02f MB"] = true
L["Memory: %.0f KB"] = true
L["No set named %q."] = true
L["Out of date addons are being disabled! They will not be able to load until their interface version is updated or \"Load out of date AddOns\" is checked."] = true
L["Problem with protected addon %q (%s)"] = true
L["Reload UI to load these addons."] = true
L["Rename"] = true
L["Reset"] = true
L["Reset addons to what was enabled at login."] = true
L["Save"] = true
L["Save the currently selected addons to %s?"] = true
L["Saved enabled addons to set %q."] = true
L["Sets"] = true
L["There is already a set named \"%s\".\nPlease choose another name."] = true
L["Toggle Icons"] = true
L["Toggle Memory Usage"] = true
L["View (%d)"] = true

