-- Path of Building
--
-- Class: Item
-- Equippable item class
--
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_floor = math.floor

local dmgTypeList = {"Physical", "Lightning", "Cold", "Fire", "Chaos"}
local catalystList = {"Abrasive", "Fertile", "Imbued", "Intrinsic", "Prismatic", "Tempering", "Turbulent"}
local catalystTags = {
	{ "attack" },
	{ "life", "mana" },
	{ "caster" },
	{ "jewellery_attribute" },
	{ "jewellery_resistance" },
	{ "jewellery_defense" },
	{ "jewellery_elemental" },
}

local function getCatalystScalar(catalystId, tags, quality)
	if not catalystId or type(catalystId) ~= "number" or not catalystTags[catalystId] or not tags or type(tags) ~= "table" or #tags == 0 then
		return 1
	end
	if not quality then
		quality = 20
	end

	-- Create a fast lookup table for all provided tags
	local tagLookup = {}
	for _, curTag in ipairs(tags) do
		tagLookup[curTag] = true;
	end

	-- Find if any of the catalyst's tags match the provided tags
	for _, catalystTag in ipairs(catalystTags[catalystId]) do
		if tagLookup[catalystTag] then
			return (100 + quality) / 100
		end
	end
	return 1
end

local influenceInfo = itemLib.influenceInfo

local ItemClass = newClass("Item", function(self, targetVersion, raw)
	self.targetVersion = targetVersion
	if raw then
		self:ParseRaw(itemLib.sanitiseItemText(raw))
	end	
end)

-- Reset all influence keys to false
function ItemClass:ResetInfluence()
	for _, curInfluenceInfo in ipairs(influenceInfo) do
		self[curInfluenceInfo.key] = false
	end
end

-- Parse raw item data and extract item name, base type, quality, and modifiers
function ItemClass:ParseRaw(raw)
	self.raw = raw
	local verData = data[self.targetVersion]
	self.name = "?"
	self.rarity = "UNIQUE"
	self.quality = nil
	self.rawLines = { }
	for line in string.gmatch(self.raw .. "\r\n", "([^\r\n]*)\r?\n") do
		line = line:gsub("^%s+",""):gsub("%s+$","")
		if #line > 0 then
			t_insert(self.rawLines, line)
		end
	end
	local mode = "WIKI"
	local l = 1
	if self.rawLines[l] then
		local rarity = self.rawLines[l]:match("^Rarity: (%a+)")
		if rarity then
			mode = "GAME"
			if colorCodes[rarity:upper()] then
				self.rarity = rarity:upper()
			end
			if self.rarity == "NORMAL" then
				-- Hack for relics
				for _, line in ipairs(self.rawLines) do
					if line == "Relic Unique" then
						self.rarity = "RELIC"
						break
					end
				end
			end
			l = l + 1
		end
	end
	if self.rawLines[l] then
		self.name = self.rawLines[l]
		l = l + 1
	end
	self.namePrefix = ""
	self.nameSuffix = ""
	if self.rarity == "NORMAL" or self.rarity == "MAGIC" then
		for baseName, baseData in pairs(verData.itemBases) do
			local s, e = self.name:find(baseName, 1, true)
			if s then
				self.baseName = baseName
				self.namePrefix = self.name:sub(1, s - 1)
				self.nameSuffix = self.name:sub(e + 1)
				self.type = baseData.type
				break
			end
		end
		if not self.baseName then
			local s, e = self.name:find("Two-Toned Boots", 1, true)
			if s then
				-- Hack for Two-Toned Boots
				self.baseName = "Two-Toned Boots (Armour/Energy Shield)"
				self.namePrefix = self.name:sub(1, s - 1)
				self.nameSuffix = self.name:sub(e + 1)
				self.type = "Boots"
			end
		end
		self.name = self.name:gsub(" %(.+%)","")
	elseif self.rawLines[l] and not self.rawLines[l]:match("^%-") then
		if self.rawLines[l] == "Two-Toned Boots" then
			self.rawLines[l] = "Two-Toned Boots (Armour/Energy Shield)"
		end
		local baseName = self.rawLines[l]:gsub("Synthesised ","")
		if verData.itemBases[baseName] then
			self.baseName = baseName
			self.title = self.name
			self.name = self.title .. ", " .. baseName:gsub(" %(.+%)","")
			self.type = verData.itemBases[baseName].type
			l = l + 1
		end
	end
	self.base = verData.itemBases[self.baseName]
	self.sockets = { }
	self.buffModLines = { }
	self.enchantModLines = { }
	self.implicitModLines = { }
	self.explicitModLines = { }
	local implicitLines = 0
	if self.base then
		self.affixes = (self.base.subType and verData.itemMods[self.base.type..self.base.subType])
			or verData.itemMods[self.base.type] 
			or verData.itemMods.Item
		self.enchantments = verData.enchantments[self.base.type]
		self.corruptable = self.base.type ~= "Flask" and self.base.subType ~= "Cluster"
		self.influenceTags = data.specialBaseTags[self.type]
		self.canBeInfluenced = self.influenceTags
		self.clusterJewel = verData.clusterJewels and verData.clusterJewels.jewels[self.baseName]
	end
	self.variantList = nil
	self.prefixes = { }
	self.suffixes = { }
	self.requirements = { }
	if self.base then
		self.requirements.str = self.base.req.str or 0
		self.requirements.dex = self.base.req.dex or 0
		self.requirements.int = self.base.req.int or 0
		local maxReq = m_max(self.requirements.str, self.requirements.dex, self.requirements.int)
		self.defaultSocketColor = (maxReq == self.requirements.dex and "G") or (maxReq == self.requirements.int and "B") or "R"
	end
	local importedLevelReq
	local flaskBuffLines = { }
	if self.base and self.base.flask and self.base.flask.buff then
		for _, line in ipairs(self.base.flask.buff) do
			flaskBuffLines[line] = true
			local modList, extra = modLib.parseMod[self.targetVersion](line)
			t_insert(self.buffModLines, { line = line, extra = extra, modList = modList or { } })
		end
	end
	local deferJewelRadiusIndexAssignment
	local gameModeStage = "FINDIMPLICIT"
	local foundExplicit, foundImplicit

	local function processInfluenceLine(line)
		for i, curInfluenceInfo in ipairs(influenceInfo) do
			if line == curInfluenceInfo.display.." Item" then
				self[curInfluenceInfo.key] = true
				return true
			end
		end
		return false
	end

	while self.rawLines[l] do	
		local line = self.rawLines[l]
		if flaskBuffLines[line] then
			flaskBuffLines[line] = nil
		elseif line == "--------" then
			if gameModeStage == "IMPLICIT" then
				if foundImplicit then
					-- There were definitely implicits, so any following modifiers must be explicits
					gameModeStage = "EXPLICIT"
					foundExplicit = true
				else
					gameModeStage = "FINDEXPLICIT"
				end
			elseif gameModeStage == "EXPLICIT" then
				gameModeStage = "DONE"
			end
		elseif line == "Corrupted" then
			self.corrupted = true
		elseif line == "Fractured Item" then
			self.fractured = true
		elseif line == "Synthesised Item" then
			self.synthesised = true
		elseif processInfluenceLine(line) then
			-- self already updated within the helper function
		else
			local specName, specVal = line:match("^([%a ]+): (%x+)$")
			if not specName then
				specName, specVal = line:match("^([%a ]+): %+?([%d+%-%.,]+)")
				if not tonumber(specVal) then
					specName = nil
				end
			end
			if not specName then
				specName, specVal = line:match("^([%a ]+): (.+)$")
			end
			if not specName then
				specName, specVal = line:match("^(Requires) (.+)$")
			end
			if specName then
				if specName == "Unique ID" then
					self.uniqueID = specVal
				elseif specName == "Item Level" then
					self.itemLevel = tonumber(specVal)
				elseif specName == "Quality" then
					self.quality = tonumber(specVal)
				elseif specName == "Sockets" then
					local group = 0
					for c in specVal:gmatch(".") do
						if c:match("[RGBWA]") then
							t_insert(self.sockets, { color = c, group = group })
						elseif c == " " then
							group = group + 1
						end
					end
				elseif specName == "Radius" and self.type == "Jewel" then
					self.jewelRadiusLabel = specVal:match("^%a+")
					if specVal:match("^%a+") == "Variable" then
                        -- Jewel radius is variable and must be read from it's mods instead after they are parsed
                        deferJewelRadiusIndexAssignment = true
                    else
                        for index, data in pairs(verData.jewelRadius) do
                            if specVal:match("^%a+") == data.label then
                                self.jewelRadiusIndex = index
                                break
                            end
						end
					end
				elseif specName == "Limited to" and self.type == "Jewel" then
					self.limit = tonumber(specVal)
				elseif specName == "Variant" then
					if not self.variantList then
						self.variantList = { }
					end
					local ver, name = specVal:match("{([%w_]+)}(.+)")
					if ver then
						t_insert(self.variantList, name)
						if ver == self.targetVersion then
							self.defaultVariant = #self.variantList
						end
					else
						t_insert(self.variantList, specVal)
					end
				elseif specName == "Talisman Tier" then
					self.talismanTier = tonumber(specVal)
				elseif specName == "Requires Level" then
					self.requirements.level = tonumber(specVal)
				elseif specName == "Requires" then
					self.requirements.level = tonumber(specVal:match("Level (%d+)"))
				elseif specName == "Level" then
					-- Requirements from imported items can't always be trusted
					importedLevelReq = tonumber(specVal)
				elseif specName == "LevelReq" then
					self.requirements.level = tonumber(specVal)
				elseif specName == "Has Alt Variant" then
					self.hasAltVariant = true
				elseif specName == "Has Alt Variant Two" then
					self.hasAltVariant2 = true
				elseif specName == "Selected Variant" then
					self.variant = tonumber(specVal)
				elseif specName == "Selected Alt Variant" then
					self.variantAlt = tonumber(specVal)
				elseif specName == "Selected Alt Variant Two" then
					self.variantAlt2 = tonumber(specVal)
				elseif specName == "Has Variants" or specName == "Selected Variants" then
					-- Need to skip this line for backwards compatibility
					-- with builds that used an old Watcher's Eye implementation
					l = l + 1
				elseif specName == "League" then
					self.league = specVal
				elseif specName == "Crafted" then
					self.crafted = true
				elseif specName == "Implicit" then
					self.implicit = true
				elseif specName == "Prefix" then
					local range, affix = specVal:match("{range:([%d.]+)}(.+)")
					t_insert(self.prefixes, {
						modId = affix or specVal,
						range = tonumber(range),
					})
				elseif specName == "Suffix" then
					local range, affix = specVal:match("{range:([%d.]+)}(.+)")
					t_insert(self.suffixes, {
						modId = affix or specVal,
						range = tonumber(range),
					})
				elseif specName == "Implicits" then
					implicitLines = tonumber(specVal) or 0
					gameModeStage = "EXPLICIT"
				elseif specName == "Unreleased" then
					self.unreleased = (specVal == "true")
				elseif specName == "Upgrade" then
					self.upgradePaths = self.upgradePaths or { }
					t_insert(self.upgradePaths, specVal)
				elseif specName == "Source" then
					self.source = specVal
				elseif specName == "Evasion Rating" then
					if self.baseName == "Two-Toned Boots (Armour/Energy Shield)" then
						-- Another hack for Two-Toned Boots
						self.baseName = "Two-Toned Boots (Armour/Evasion)"
						self.base = verData.itemBases[self.baseName]
					end
				elseif specName == "Energy Shield" then
					if self.baseName == "Two-Toned Boots (Armour/Evasion)" then
						-- Yet another hack for Two-Toned Boots
						self.baseName = "Two-Toned Boots (Evasion/Energy Shield)"
						self.base = verData.itemBases[self.baseName]
					end
				elseif specName == "Cluster Jewel Skill" then
					if self.clusterJewel and self.clusterJewel.skills[specVal] then
						self.clusterJewelSkill = specVal
					end
				elseif specName == "Cluster Jewel Node Count" then
					if self.clusterJewel then
						local num = tonumber(specVal) or self.clusterJewel.maxNodes
						self.clusterJewelNodeCount = m_min(m_max(num, self.clusterJewel.minNodes), self.clusterJewel.maxNodes)
					end
				elseif specName == "Catalyst" then
					for i=1, #catalystList do
						if specVal == catalystList[i] then
							self.catalyst = i
						end
					end
				elseif specName == "CatalystQuality" then
					self.catalystQuality = tonumber(specVal)
				else
					foundExplicit = true
					gameModeStage = "EXPLICIT"
				end
			end
			if line == "Prefixes:" then
				foundExplicit = true
				gameModeStage = "EXPLICIT"
			end
			if not specName or foundExplicit or foundImplicit then
				local varSpec = line:match("{variant:([%d,]+)}")
				local variantList
				if varSpec then
					variantList = { }
					for varId in varSpec:gmatch("%d+") do
						variantList[tonumber(varId)] = true
					end
				end
				local fractured = line:match("{fractured}") or line:match(" %(fractured%)")
				local rangeSpec = line:match("{range:([%d.]+)}")
				local enchant = line:match(" %(enchant%)")
				local crafted = line:match("{crafted}") or line:match(" %(crafted%)") or enchant
				local custom = line:match("{custom}")
				local modTagsText = line:match("{tags:([^}]*)}") or ''
				local modTags = {}
				for curMod in modTagsText:gmatch("[^,]+") do
					curMod = curMod:match('^%s*(.*%S)') or '' -- Trim whitespace
					table.insert(modTags, curMod)
				end
				local implicit = line:match(" %(implicit%)") or enchant
				if implicit then
					foundImplicit = true
					gameModeStage = "IMPLICIT"
				end
				line = line:gsub("%b{}", ""):gsub(" %(fractured%)",""):gsub(" %(crafted%)",""):gsub(" %(implicit%)",""):gsub(" %(enchant%)","")
				local catalystScalar = getCatalystScalar(self.catalyst, modTags, self.catalystQuality)
				local rangedLine
				if line:match("%(%d+%-%d+ to %d+%-%d+%)") or line:match("%(%-?[%d%.]+ to %-?[%d%.]+%)") or line:match("%(%-?[%d%.]+%-[%d%.]+%)") then
					rangedLine = itemLib.applyRange(line, 1, catalystScalar)
				elseif catalystScalar ~= 1 then
					rangedLine = itemLib.applyValueScalar(line, catalystScalar)
				end
				local modList, extra = modLib.parseMod[self.targetVersion](rangedLine or line)
				if (not modList or extra) and self.rawLines[l+1] then
					-- Try to combine it with the next line
					local combLine = line.." "..self.rawLines[l+1]:gsub("%b{}", ""):gsub(" %(fractured%)",""):gsub(" %(crafted%)",""):gsub(" %(implicit%)",""):gsub(" %(enchant%)","")
					if combLine:match("%(%d+%-%d+ to %d+%-%d+%)") or combLine:match("%(%-?[%d%.]+ to %-?[%d%.]+%)") or combLine:match("%(%-?[%d%.]+%-[%d%.]+%)") then
						rangedLine = itemLib.applyRange(combLine, 1, catalystScalar)
					elseif catalystScalar ~= 1 then
						rangedLine = itemLib.applyValueScalar(combLine, catalystScalar)
					end
					modList, extra = modLib.parseMod[self.targetVersion](rangedLine or combLine, true)
					if modList and not extra then
						line = line.."\n"..self.rawLines[l+1]
						l = l + 1
					else
						modList, extra = modLib.parseMod[self.targetVersion](rangedLine or line)
					end
				end

				local lineLower = line:lower()
				if lineLower == "this item can be anointed by cassia" then
					self.canBeAnointed = true
				elseif lineLower == "can have a second enchantment modifier" then
					self.canHaveTwoEnchants = true
				end

				local modLines
				if enchant or (crafted and #self.enchantModLines + #self.implicitModLines < implicitLines) then
					modLines = self.enchantModLines
				elseif implicit or (not crafted and #self.enchantModLines + #self.implicitModLines < implicitLines) then
					modLines = self.implicitModLines
				else
					modLines = self.explicitModLines
				end
				if modList then
					t_insert(modLines, { line = line, extra = extra, modList = modList, modTags = modTags, variantList = variantList, crafted = crafted, custom = custom, fractured = fractured, implicit = implicit, range = rangedLine and (tonumber(rangeSpec) or 0.5), valueScalar = catalystScalar })
					if mode == "GAME" then
						if gameModeStage == "FINDIMPLICIT" then
							gameModeStage = "IMPLICIT"
						elseif gameModeStage == "FINDEXPLICIT" then
							foundExplicit = true
							gameModeStage = "EXPLICIT"
						elseif gameModeStage == "EXPLICIT" then
							foundExplicit = true
						end
					else
						foundExplicit = true
					end
				elseif mode == "GAME" then
					if gameModeStage == "IMPLICIT" or gameModeStage == "EXPLICIT" then
						t_insert(modLines, { line = line, extra = line, modList = { }, modTags = { }, variantList = variantList, crafted = crafted, custom = custom, fractured = fractured, implicit = implicit })
					elseif gameModeStage == "FINDEXPLICIT" then
						gameModeStage = "DONE"
					end
				elseif foundExplicit then
					t_insert(modLines, { line = line, extra = line, modList = { }, modTags = { }, variantList = variantList, crafted = crafted, custom = custom, fractured = fractured, implicit = implicit })
				end
					
			end
		end
		l = l + 1
	end
	if self.base and not self.requirements.level then
		if importedLevelReq and #self.sockets == 0 then
			-- Requirements on imported items can only be trusted for items with no sockets
			self.requirements.level = importedLevelReq
		else
			self.requirements.level = self.base.req.level
		end
	end
	self.affixLimit = 0
	if self.crafted then
		if not self.affixes then 
			self.crafted = false
		elseif self.rarity == "MAGIC" then
			self.affixLimit = 2
		elseif self.rarity == "RARE" then
			self.affixLimit = (self.type == "Jewel" and 4 or 6)
		else
			self.crafted = false
		end
		if self.crafted then
			for _, list in ipairs({self.prefixes,self.suffixes}) do
				for i = 1, self.affixLimit/2 do
					if not list[i] then
						list[i] = { modId = "None" }
					elseif list[i].modId ~= "None" and not self.affixes[list[i].modId] then
						for modId, mod in pairs(self.affixes) do
							if list[i].modId == mod.affix then
								list[i].modId = modId
								break
							end
						end
						if not self.affixes[list[i].modId] then
							list[i].modId = "None"
						end
					end
				end
			end
		end
	end
	if self.base and self.base.socketLimit then
		if #self.sockets == 0 then
			for i = 1, self.base.socketLimit do
				t_insert(self.sockets, {
					color = self.defaultSocketColor,
					group = 0,
				})
			end
		end
	end
	self.abyssalSocketCount = 0
	if self.variantList then
		self.variant = m_min(#self.variantList, self.variant or self.defaultVariant or #self.variantList)
		if self.hasAltVariant then
			self.variantAlt = m_min(#self.variantList, self.variantAlt or self.defaultVariant or #self.variantList)
		end
		if self.hasAltVariant2 then
			self.variantAlt2 = m_min(#self.variantList, self.variantAlt2 or self.defaultVariant or #self.variantList)
		end
	end
	if not self.quality then
		self:NormaliseQuality()
	end
	self:BuildModList()
	if deferJewelRadiusIndexAssignment then
		self.jewelRadiusIndex = self.jewelData.radiusIndex
	end
end

function ItemClass:NormaliseQuality()
	if self.base and (self.base.armour or self.base.weapon or self.base.flask) then
		if not self.quality then
			self.quality = self.corrupted and 0 or 20 
		elseif not self.uniqueID and not self.corrupted and self.quality < 20 then
			self.quality = 20
		end
	end	
end

function ItemClass:GetModSpawnWeight(mod, extraTags)
	local weight = 0
	if self.base then
		local function HasInfluenceTag(key)
			if self.influenceTags then
				for _, curInfluenceInfo in ipairs(influenceInfo) do
					if self[curInfluenceInfo.key] and self.influenceTags[curInfluenceInfo.key] == key then
						return true
					end
				end
			end
			return false
		end

		for i, key in ipairs(mod.weightKey) do
			if self.base.tags[key] or (extraTags and extraTags[key]) or HasInfluenceTag(key) then
				weight = mod.weightVal[i]
				break
			end
		end
		for i, key in ipairs(mod.weightMultiplierKey) do
			if self.base.tags[key] or (extraTags and extraTags[key]) or HasInfluenceTag(key) then
				weight = weight * mod.weightMultiplierVal[i] / 100
				break
			end
		end
	end
	return weight
end

function ItemClass:BuildRaw()
	local rawLines = { }
	t_insert(rawLines, "Rarity: "..self.rarity)
	if self.title then
		t_insert(rawLines, self.title)
		t_insert(rawLines, self.baseName)
	else
		t_insert(rawLines, (self.namePrefix or "")..self.baseName..(self.nameSuffix or ""))
	end
	if self.uniqueID then
		t_insert(rawLines, "Unique ID: "..self.uniqueID)
	end
	if self.league then
		t_insert(rawLines, "League: "..self.league)
	end
	if self.unreleased then
		t_insert(rawLines, "Unreleased: true")
	end
	for i, curInfluenceInfo in ipairs(influenceInfo) do
		if self[curInfluenceInfo.key] then
			t_insert(rawLines, curInfluenceInfo.display.." Item")
		end
	end
	if self.crafted then
		t_insert(rawLines, "Crafted: true")
		for i, affix in ipairs(self.prefixes or { }) do
			t_insert(rawLines, "Prefix: "..(affix.range and ("{range:"..round(affix.range,3).."}") or "")..affix.modId)
		end
		for i, affix in ipairs(self.suffixes or { }) do
			t_insert(rawLines, "Suffix: "..(affix.range and ("{range:"..round(affix.range,3).."}") or "")..affix.modId)
		end
	end
	if self.catalyst and self.catalyst > 0 then
		t_insert(rawLines, "Catalyst: "..catalystList[self.catalyst])
	end
	if self.catalystQuality then
		t_insert(rawLines, "CatalystQuality: "..self.catalystQuality)
	end
	if self.clusterJewel then
		if self.clusterJewelSkill then
			t_insert(rawLines, "Cluster Jewel Skill: "..self.clusterJewelSkill)
		end
		if self.clusterJewelNodeCount then
			t_insert(rawLines, "Cluster Jewel Node Count: "..self.clusterJewelNodeCount)
		end
	end
	if self.talismanTier then
		t_insert(rawLines, "Talisman Tier: "..self.talismanTier)
	end
	if self.itemLevel then
		t_insert(rawLines, "Item Level: "..self.itemLevel)
	end
	if self.variantList then
		for _, variantName in ipairs(self.variantList) do
			t_insert(rawLines, "Variant: "..variantName)
		end
		t_insert(rawLines, "Selected Variant: "..self.variant)

		if self.hasAltVariant then
			t_insert(rawLines, "Has Alt Variant: true")
			t_insert(rawLines, "Selected Alt Variant: "..self.variantAlt)
		end
		if self.hasAltVariant2 then
			t_insert(rawLines, "Has Alt Variant Two: true")
			t_insert(rawLines, "Selected Alt Variant Two: "..self.variantAlt2)
		end
	end
	if self.quality then
		t_insert(rawLines, "Quality: "..self.quality)
	end
	if self.sockets and #self.sockets > 0 then
		local line = "Sockets: "
		for i, socket in pairs(self.sockets) do
			line = line .. socket.color
			if self.sockets[i+1] then
				line = line .. (socket.group == self.sockets[i+1].group and "-" or " ")
			end
		end
		t_insert(rawLines, line)
	end
	if self.requirements and self.requirements.level then
		t_insert(rawLines, "LevelReq: "..self.requirements.level)
	end
	if self.jewelRadiusLabel then
		t_insert(rawLines, "Radius: "..self.jewelRadiusLabel)
	end
	if self.limit then
		t_insert(rawLines, "Limited to: "..self.limit)
	end
	t_insert(rawLines, "Implicits: "..(#self.enchantModLines + #self.implicitModLines))
	local function writeModLine(modLine)
		local line = modLine.line
		if modLine.range then
			line = "{range:"..round(modLine.range,3).."}" .. line
		end
		if modLine.crafted then
			line = "{crafted}" .. line
		end
		if modLine.custom then
			line = "{custom}" .. line
		end
		if modLine.fractured then
			line = "{fractured}" .. line
		end
		if modLine.variantList then
			local varSpec
			for varId in pairs(modLine.variantList) do
				varSpec = (varSpec and varSpec.."," or "") .. varId
			end
			line = "{variant:"..varSpec.."}"..line
		end
		if modLine.modTags and #modLine.modTags > 0 then
			line = "{tags:"..table.concat(modLine.modTags, ",").."}"..line
		end
		t_insert(rawLines, line)
	end
	for _, modLine in ipairs(self.enchantModLines) do
		writeModLine(modLine)
	end
	for _, modLine in ipairs(self.implicitModLines) do
		writeModLine(modLine)
	end
	for _, modLine in ipairs(self.explicitModLines) do
		writeModLine(modLine)
	end
	if self.corrupted then
		t_insert(rawLines, "Corrupted")
	end
	return table.concat(rawLines, "\n")
end

function ItemClass:BuildAndParseRaw()
	local raw = self:BuildRaw()
	self:ParseRaw(raw)
end

-- Rebuild explicit modifiers using the item's affixes
function ItemClass:Craft()
	-- Save off any crafted or custom mods so they can be re-added at the end
	local savedMods = {}
	for _, mod in ipairs(self.explicitModLines) do
		if mod.crafted or mod.custom then
			t_insert(savedMods, mod)
		end
	end

	wipeTable(self.explicitModLines)
	self.namePrefix = ""
	self.nameSuffix = ""
	self.requirements.level = self.base.req.level
	local statOrder = { }
	for _, list in ipairs({self.prefixes,self.suffixes}) do
		for i = 1, self.affixLimit/2 do
			local affix = list[i]
			if not affix then
				list[i] = { modId = "None" }
			end
			local mod = self.affixes[affix.modId]
			if mod then
				if mod.type == "Prefix" then
					self.namePrefix = mod.affix .. " "
				elseif mod.type == "Suffix" then
					self.nameSuffix = " " .. mod.affix
				end
				self.requirements.level = m_max(self.requirements.level or 0, m_floor(mod.level * 0.8))
				local rangeScalar = getCatalystScalar(self.catalyst, mod.modTags, self.catalystQuality)
				for i, line in ipairs(mod) do
					line = itemLib.applyRange(line, affix.range or 0.5, rangeScalar)
					local order = mod.statOrder[i]
					if statOrder[order] then
						-- Combine stats
						local start = 1
						statOrder[order].line = statOrder[order].line:gsub("%d+", function(num)
							local s, e, other = line:find("(%d+)", start)
							start = e + 1
							return tonumber(num) + tonumber(other)
						end)
					else
						local modLine = { line = line, order = order }
						for l = 1, #self.explicitModLines + 1 do
							if not self.explicitModLines[l] or self.explicitModLines[l].order > order then
								t_insert(self.explicitModLines, l, modLine)
								break
							end
						end
						statOrder[order] = modLine
					end	
				end
			end
		end
	end

	-- Restore the crafted and custom mods
	for _, mod in ipairs(savedMods) do
		t_insert(self.explicitModLines, mod)
	end

	self:BuildAndParseRaw()
end

function ItemClass:CheckModLineVariant(modLine)
	return not modLine.variantList 
		or modLine.variantList[self.variant]
		or (self.hasAltVariant and modLine.variantList[self.variantAlt])
		or (self.hasAltVariant2 and modLine.variantList[self.variantAlt2])
end

-- Return the name of the slot this item is equipped in
function ItemClass:GetPrimarySlot()
	if self.base.weapon then
		return "Weapon 1"
	elseif self.type == "Quiver" or self.type == "Shield" then
		return "Weapon 2"
	elseif self.type == "Ring" then
		return "Ring 1"
	elseif self.type == "Flask" then
		return "Flask 1"
	else
		return self.type
	end
end

-- Add up local modifiers, and removes them from the modifier list
-- To be considered local, a modifier must be an exact flag match, and cannot have any tags (e.g. conditions, multipliers)
-- Only the InSlot tag is allowed (for Adds x to x X Damage in X Hand modifiers)
local function sumLocal(modList, name, type, flags)
	local result
	if type == "FLAG" then
		result = false
	else
		result = 0
	end
	local i = 1
	while modList[i] do
		local mod = modList[i]
		if mod.name == name and mod.type == type and mod.flags == flags and mod.keywordFlags == 0 and (not mod[1] or mod[1].type == "InSlot") then
			if type == "FLAG" then
				result = result or mod.value
			else	
				result = result + mod.value
			end
			t_remove(modList, i)
		else
			i = i + 1
		end
	end
	return result
end

-- Build list of modifiers in a given slot number (1 or 2) while applying local modifiers and adding quality
function ItemClass:BuildModListForSlotNum(baseList, slotNum)
	local slotName = self:GetPrimarySlot()
	if slotNum == 2 then
		slotName = slotName:gsub("1", "2")
	end
	local modList = new("ModList")
	for _, baseMod in ipairs(baseList) do
		local mod = copyTable(baseMod)
		local add = true
		for _, tag in ipairs(mod) do
			if tag.type == "SlotNumber" or tag.type == "InSlot" then
				if tag.num ~= slotNum then
					add = false
					break
				end
			end
			for k, v in pairs(tag) do
				if type(v) == "string" then
					tag[k] = v:gsub("{SlotName}", slotName)
							  :gsub("{Hand}", (slotNum == 1) and "MainHand" or "OffHand")
							  :gsub("{OtherSlotNum}", slotNum == 1 and "2" or "1")
				end
			end
		end
		if add then
			mod.sourceSlot = slotName
			modList:AddMod(mod)
		end
	end
	if #self.sockets > 0 then
		local multiName = {
			R = "Multiplier:RedSocketIn"..slotName,
			G = "Multiplier:GreenSocketIn"..slotName,
			B = "Multiplier:BlueSocketIn"..slotName,
			W = "Multiplier:WhiteSocketIn"..slotName,
		}
		for _, socket in ipairs(self.sockets) do
			if multiName[socket.color] then
				modList:NewMod(multiName[socket.color], "BASE", 1, "Item Sockets")
			end
		end
	end
	if self.base.weapon then
		local weaponData = { }
		self.weaponData[slotNum] = weaponData
		weaponData.type = self.base.type
		weaponData.name = self.name
		weaponData.AttackSpeedInc = sumLocal(modList, "Speed", "INC", ModFlag.Attack)
		weaponData.AttackRate = round(self.base.weapon.AttackRateBase * (1 + weaponData.AttackSpeedInc / 100), 2)
		weaponData.range = self.base.weapon.Range + sumLocal(modList, "WeaponRange", "BASE", 0)
		for _, dmgType in pairs(dmgTypeList) do
			local min = (self.base.weapon[dmgType.."Min"] or 0) + sumLocal(modList, dmgType.."Min", "BASE", 0)
			local max = (self.base.weapon[dmgType.."Max"] or 0) + sumLocal(modList, dmgType.."Max", "BASE", 0)
			if dmgType == "Physical" then
				local physInc = sumLocal(modList, "PhysicalDamage", "INC", 0)
				min = round(min * (1 + (physInc + self.quality) / 100))
				max = round(max * (1 + (physInc + self.quality) / 100))
			end
			if min > 0 and max > 0 then
				weaponData[dmgType.."Min"] = min
				weaponData[dmgType.."Max"] = max
				local dps = (min + max) / 2 * weaponData.AttackRate
				weaponData[dmgType.."DPS"] = dps
				if dmgType ~= "Physical" and dmgType ~= "Chaos" then
					weaponData.ElementalDPS = (weaponData.ElementalDPS or 0) + dps
				end
			end
		end
		weaponData.CritChance = round(self.base.weapon.CritChanceBase * (1 + sumLocal(modList, "CritChance", "INC", 0) / 100), 2)
		for _, value in ipairs(modList:List(nil, "WeaponData")) do
			weaponData[value.key] = value.value
		end
		if self.targetVersion == "2_6" then
			local accuracyInc = sumLocal(modList, "Accuracy", "INC", 0)
			if accuracyInc > 0 then
				modList:NewMod("Accuracy", "MORE", accuracyInc, self.modSource, { type = "Condition", var = (slotNum == 1) and "MainHandAttack" or "OffHandAttack" })
			end
		end
		for _, mod in ipairs(modList) do
			-- Convert accuracy, L/MGoH and PAD Leech modifiers to local
			if (
				(mod.name == "Accuracy" and mod.flags == 0) or
                (mod.name == "ImpaleChance" ) or
				((mod.name == "LifeOnHit" or mod.name == "ManaOnHit") and mod.flags == ModFlag.Attack) or
				((mod.name == "PhysicalDamageLifeLeech" or mod.name == "PhysicalDamageManaLeech") and mod.flags == ModFlag.Attack)
			   ) and (mod.keywordFlags == 0 or mod.keywordFlags == KeywordFlag.Attack) and not mod[1] then
				mod[1] = { type = "Condition", var = (slotNum == 1) and "MainHandAttack" or "OffHandAttack" }
			elseif self.targetVersion ~= "2_6" and (mod.name == "PoisonChance" or mod.name == "BleedChance") and (not mod[1] or (mod[1].type == "Condition" and mod[1].var == "CriticalStrike" and not mod[2])) then
				t_insert(mod, { type = "Condition", var = (slotNum == 1) and "MainHandAttack" or "OffHandAttack" })
			end
		end
		weaponData.TotalDPS = 0
		for _, dmgType in pairs(dmgTypeList) do
			weaponData.TotalDPS = weaponData.TotalDPS + (weaponData[dmgType.."DPS"] or 0)
		end
	elseif self.base.armour then
		local armourData = self.armourData
		local armourBase = sumLocal(modList, "Armour", "BASE", 0) + (self.base.armour.ArmourBase or 0)
		local armourEvasionBase = sumLocal(modList, "ArmourAndEvasion", "BASE", 0)
		local evasionBase = sumLocal(modList, "Evasion", "BASE", 0) + (self.base.armour.EvasionBase or 0)
		local evasionEnergyShieldBase = sumLocal(modList, "EvasionAndEnergyShield", "BASE", 0)
		local energyShieldBase = sumLocal(modList, "EnergyShield", "BASE", 0) + (self.base.armour.EnergyShieldBase or 0)
		local armourEnergyShieldBase = sumLocal(modList, "ArmourAndEnergyShield", "BASE", 0)
		local armourInc = sumLocal(modList, "Armour", "INC", 0)
		local armourEvasionInc = sumLocal(modList, "ArmourAndEvasion", "INC", 0)
		local evasionInc = sumLocal(modList, "Evasion", "INC", 0)
		local evasionEnergyShieldInc = sumLocal(modList, "EvasionAndEnergyShield", "INC", 0)
		local energyShieldInc = sumLocal(modList, "EnergyShield", "INC", 0)
		local armourEnergyShieldInc = sumLocal(modList, "ArmourAndEnergyShield", "INC", 0)
		local defencesInc = sumLocal(modList, "Defences", "INC", 0)
		armourData.Armour = round((armourBase + armourEvasionBase + armourEnergyShieldBase) * (1 + (armourInc + armourEvasionInc + armourEnergyShieldInc + defencesInc + self.quality) / 100))
		armourData.Evasion = round((evasionBase + armourEvasionBase + evasionEnergyShieldBase) * (1 + (evasionInc + armourEvasionInc + evasionEnergyShieldInc + defencesInc + self.quality) / 100))
		armourData.EnergyShield = round((energyShieldBase + evasionEnergyShieldBase + armourEnergyShieldBase) * (1 + (energyShieldInc + armourEnergyShieldInc + evasionEnergyShieldInc + defencesInc + self.quality) / 100))
		if self.base.armour.BlockChance then
			armourData.BlockChance = self.base.armour.BlockChance + sumLocal(modList, "BlockChance", "BASE", 0)
		end
		if self.base.armour.MovementPenalty then
			modList:NewMod("MovementSpeed", "INC", -self.base.armour.MovementPenalty, self.modSource, { type = "Condition", var = "IgnoreMovementPenalties", neg = true })
		end
		for _, value in ipairs(modList:List(nil, "ArmourData")) do
			armourData[value.key] = value.value
		end
	elseif self.base.flask then
		local flaskData = self.flaskData
		local durationInc = sumLocal(modList, "Duration", "INC", 0)
		if self.base.flask.life or self.base.flask.mana then
			-- Recovery flask
			flaskData.instantPerc = sumLocal(modList, "FlaskInstantRecovery", "BASE", 0)
			local recoveryMod = 1 + sumLocal(modList, "FlaskRecovery", "INC", 0) / 100
			local rateMod = 1 + sumLocal(modList, "FlaskRecoveryRate", "INC", 0) / 100
			flaskData.duration = self.base.flask.duration * (1 + durationInc / 100) / rateMod
			if self.base.flask.life then
				flaskData.lifeBase = self.base.flask.life * (1 + self.quality / 100) * recoveryMod
				flaskData.lifeInstant = flaskData.lifeBase * flaskData.instantPerc / 100
				flaskData.lifeGradual = flaskData.lifeBase * (1 - flaskData.instantPerc / 100) * (1 + durationInc / 100)
				flaskData.lifeTotal = flaskData.lifeInstant + flaskData.lifeGradual
			end
			if self.base.flask.mana then
				flaskData.manaBase = self.base.flask.mana * (1 + self.quality / 100) * recoveryMod
				flaskData.manaInstant = flaskData.manaBase * flaskData.instantPerc / 100
				flaskData.manaGradual = flaskData.manaBase * (1 - flaskData.instantPerc / 100) * (1 + durationInc / 100)
				flaskData.manaTotal = flaskData.manaInstant + flaskData.manaGradual
			end
		else
			-- Utility flask
			flaskData.duration = self.base.flask.duration * (1 + (durationInc + self.quality) / 100)
		end
		flaskData.chargesMax = self.base.flask.chargesMax + sumLocal(modList, "FlaskCharges", "BASE", 0)
		flaskData.chargesUsed = m_floor(self.base.flask.chargesUsed * (1 + sumLocal(modList, "FlaskChargesUsed", "INC", 0) / 100))
		flaskData.gainMod = 1 + sumLocal(modList, "FlaskChargeRecovery", "INC", 0) / 100
		flaskData.effectInc = sumLocal(modList, "FlaskEffect", "INC", 0)
		for _, value in ipairs(modList:List(nil, "FlaskData")) do
			flaskData[value.key] = value.value
		end
	elseif self.type == "Jewel" then
		local jewelData = self.jewelData
		for _, func in ipairs(modList:List(nil, "JewelFunc")) do
			jewelData.funcList = jewelData.funcList or { }
			t_insert(jewelData.funcList, func)
		end
		for _, value in ipairs(modList:List(nil, "JewelData")) do
			jewelData[value.key] = value.value
		end
		if self.clusterJewel then
			jewelData.clusterJewelNotables = { }
			for _, name in ipairs(modList:List(nil, "ClusterJewelNotable")) do
				t_insert(jewelData.clusterJewelNotables, name)
			end
			jewelData.clusterJewelAddedMods = { }
			for _, line in ipairs(modList:List(nil, "AddToClusterJewelNode")) do
				t_insert(jewelData.clusterJewelAddedMods, line)
			end

			-- Validation
			if jewelData.clusterJewelNodeCount then
				jewelData.clusterJewelNodeCount = m_min(m_max(jewelData.clusterJewelNodeCount, self.clusterJewel.minNodes), self.clusterJewel.maxNodes)
			end
			if jewelData.clusterJewelSkill and not self.clusterJewel.skills[jewelData.clusterJewelSkill] then
				jewelData.clusterJewelSkill = nil
			end
			jewelData.clusterJewelValid = jewelData.clusterJewelKeystone 
				or ((jewelData.clusterJewelSkill or jewelData.clusterJewelSmallsAreNothingness) and jewelData.clusterJewelNodeCount) 
				or (jewelData.clusterJewelSocketCountOverride and jewelData.clusterJewelNothingnessCount)
		end
	end	
	return { unpack(modList) }
end

-- Build lists of modifiers for each slot the item can occupy
function ItemClass:BuildModList()
	if not self.base then
		return
	end
	local baseList = new("ModList")
	if self.base.weapon then
		self.weaponData = { }
	elseif self.base.armour then
		self.armourData = { }
	elseif self.base.flask then
		self.flaskData = { }
		self.buffModList = { }
	elseif self.type == "Jewel" then
		self.jewelData = { }
	end
	self.baseModList = baseList
	self.rangeLineList = { }
	self.modSource = "Item:"..(self.id or -1)..":"..self.name
	for _, modLine in ipairs(self.buffModLines) do
		if not modLine.extra and self:CheckModLineVariant(modLine) then
			for _, mod in ipairs(modLine.modList) do
				mod.source = self.modSource
				t_insert(self.buffModList, mod)
			end
		end
	end
	local function processModLine(modLine)
		if not modLine.extra and self:CheckModLineVariant(modLine) then
			if modLine.range then
				local catalystScalar = getCatalystScalar(self.catalyst, modLine.modTags, self.catalystQuality)
				local line = itemLib.applyRange(modLine.line:gsub("\n"," "), modLine.range, catalystScalar)
				local list, extra = modLib.parseMod[self.targetVersion](line)
				if list and not extra then
					modLine.modList = list
					t_insert(self.rangeLineList, modLine)
				end
			end
			for _, mod in ipairs(modLine.modList) do
				mod.source = self.modSource
				if type(mod.value) == "table" and mod.value.mod then
					mod.value.mod.source = mod.source
				end
				baseList:AddMod(mod)
			end
			if modLine.modTags and #modLine.modTags > 0 then
				self.hasModTags = true
			end
		end
	end
	for _, modLine in ipairs(self.enchantModLines) do
		processModLine(modLine)
	end
	for _, modLine in ipairs(self.implicitModLines) do
		processModLine(modLine)
	end
	for _, modLine in ipairs(self.explicitModLines) do
		processModLine(modLine)
	end
	if sumLocal(baseList, "NoAttributeRequirements", "FLAG", 0) then
		self.requirements.strMod = 0
		self.requirements.dexMod = 0
		self.requirements.intMod = 0
	else
		self.requirements.strMod = m_floor((self.requirements.str + sumLocal(baseList, "StrRequirement", "BASE", 0)) * (1 + sumLocal(baseList, "StrRequirement", "INC", 0) / 100))
		self.requirements.dexMod = m_floor((self.requirements.dex + sumLocal(baseList, "DexRequirement", "BASE", 0)) * (1 + sumLocal(baseList, "DexRequirement", "INC", 0) / 100))
		self.requirements.intMod = m_floor((self.requirements.int + sumLocal(baseList, "IntRequirement", "BASE", 0)) * (1 + sumLocal(baseList, "IntRequirement", "INC", 0) / 100))
	end
	self.grantedSkills = { }
	for _, skill in ipairs(baseList:List(nil, "ExtraSkill")) do
		if skill.name ~= "Unknown" then
			t_insert(self.grantedSkills, {
				skillId = skill.skillId,
				level = skill.level,
				noSupports = skill.noSupports,
				source = self.modSource,
			})
		end
	end
	local socketCount = sumLocal(baseList, "SocketCount", "BASE", 0)
	self.abyssalSocketCount = sumLocal(baseList, "AbyssalSocketCount", "BASE", 0)
	self.selectableSocketCount = m_max(self.base.socketLimit or 0, #self.sockets) - self.abyssalSocketCount
	if sumLocal(baseList, "NoSockets", "FLAG", 0) then
		-- Remove all sockets
		wipeTable(self.sockets)
		self.selectableSocketCount = 0
	elseif socketCount > 0 then
		-- Force the socket count to be equal to the stated number
		self.selectableSocketCount = socketCount
		local group = 0
		for i = 1, m_max(socketCount, #self.sockets) do 
			if i > socketCount then
				self.sockets[i] = nil
			elseif not self.sockets[i] then
				self.sockets[i] = {
					color = self.defaultSocketColor,
					group = group
				}
			else
				group = self.sockets[i].group
			end
		end
	elseif self.abyssalSocketCount > 0 then
		-- Ensure that there are the correct number of abyssal sockets present
		local newSockets = { }
		local group = 0
		if self.sockets then
			for i, socket in ipairs(self.sockets) do
				if socket.color ~= "A" then
					t_insert(newSockets, socket)
					group = socket.group
					if #newSockets >= self.selectableSocketCount then
						break
					end
				end
			end
		end
		for i = 1, self.abyssalSocketCount do
			group = group + 1
			t_insert(newSockets, {
				color = "A",
				group = group
			})
		end
		self.sockets = newSockets
	end
	self.socketedJewelEffectModifier = 1 + sumLocal(baseList, "SocketedJewelEffect", "INC", 0) / 100
	if self.name == "Tabula Rasa, Simple Robe" or self.name == "Skin of the Loyal, Simple Robe" or self.name == "Skin of the Lords, Simple Robe" then
		-- Hack to remove the energy shield
		baseList:NewMod("ArmourData", "LIST", { key = "EnergyShield", value = 0 })
	end
	if self.base.weapon or self.type == "Ring" then
		self.slotModList = { }
		for i = 1, 2 do
			self.slotModList[i] = self:BuildModListForSlotNum(baseList, i)
		end
	else
		self.modList = self:BuildModListForSlotNum(baseList)
	end
end
