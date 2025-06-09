local addonName = ...
local LLT = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

_G["LigerLootTable"] = LLT
_G["LLT"] = LLT

function LLT:OnInitialize()
  LigerLootTableDB2 = LigerLootTableDB2 or {}
  LLT.DB = LigerLootTableDB2
end

LLT.AddonName = addonName

LLT.SourceTypeMask = {
  Unit = 1,
  Object = 2,
  Item = 4,
  WORLD = 64,
}

function LLT:GetSourceByGuid(guid)
  local params = { string.split("-", guid) }
  local guidType = params[1]
  if guidType == "Creature" or guidType == "Pet" or guidType == "Vehicle" then
    local npcId = tonumber(params[6])
    return "Unit", npcId
  elseif guidType == "GameObject" then
    local objectId = tonumber(params[6])
    return "Object", objectId
  elseif guidType == "Item" then
    local itemId = C_Item.GetItemIDByGUID(guid)
    return "Item", itemId
  end
end

do
  LLT.ScrappingSpellId = C_ScrappingMachineUI.GetScrapSpellID()

  LLT.SpecialSpells = {
    { spellId = 2366,                 subType = "HerbGathering", sourceTypeMask = LLT.SourceTypeMask.Unit + LLT.SourceTypeMask.Object },
    { spellId = 2575,                 subType = "Mining",        sourceTypeMask = LLT.SourceTypeMask.Unit + LLT.SourceTypeMask.Object },
    { spellId = 8613,                 subType = "Skinning",      sourceTypeMask = LLT.SourceTypeMask.Unit },
    { spellId = 49383,                subType = "Engineering",   sourceTypeMask = LLT.SourceTypeMask.Unit },
    { spellId = 13262,                subType = "Disenchanting", sourceTypeMask = LLT.SourceTypeMask.Item },
    { spellId = 51005,                subType = "Milling",       sourceTypeMask = LLT.SourceTypeMask.Item },
    { spellId = 31252,                subType = "Prospecting",   sourceTypeMask = LLT.SourceTypeMask.Item },
    { spellId = LLT.ScrappingSpellId, subType = "Scrapping",     sourceTypeMask = LLT.SourceTypeMask.Item },
    { spellId = 921,                  subType = "PickPocketing", sourceTypeMask = LLT.SourceTypeMask.Unit },
    -- { spellId = 131476,               subType = "Fishing",       sourceTypeMask = LLT.SourceTypeMask.WORLD },
  };

  for _, spellData in ipairs(LLT.SpecialSpells) do
    local spellInfo = C_Spell.GetSpellInfo(spellData.spellId)
    spellData.spellName = spellInfo.name
    spellData.title = ("|T%s:0|t %s"):format(spellInfo.iconID, spellInfo.name)
    spellData.status = nil
    spellData.lastTarget = nil
  end
end

function LLT:GetLootTable(sourceType, sourceId, subType)
  if not sourceType or not sourceId then return end
  subType = subType or "Normal"
  local key = ("%s:%s:%s"):format(sourceType, sourceId, subType)
  if not LLT.DB.LootTables then
    LLT.DB.LootTables = {}
  end
  local lootTable = LLT.DB.LootTables[key]
  if not lootTable then return end
  setmetatable(lootTable, {
    __tostring = function(t)
      return ("LootTable:%s"):format(key)
    end,
  })
  return lootTable
end

function LLT:InitLootTable(sourceType, sourceId, subType)
  if not sourceType or not sourceId then return end
  subType = subType or "Normal"
  local key = ("%s:%s:%s"):format(sourceType, sourceId, subType)
  if not LLT.DB.LootTables then
    LLT.DB.LootTables = {}
  end
  if not LLT.DB.LootTables[key] then
    LLT.DB.LootTables[key] = {
      count = 0,
      records = {},
    }
  end
  return LLT:GetLootTable(sourceType, sourceId, subType)
end

function LLT:FindSpecialSpell(spellId)
  if not spellId then return end
  local spellInfo = C_Spell.GetSpellInfo(spellId)
  if not spellInfo then return end
  for _, spellData in ipairs(LLT.SpecialSpells) do
    if spellData.spellName == spellInfo.name then
      return spellData
    end
  end
end

function LLT:HandleSpell(event, ...)
  local unit, castGuid, spellId, status, target
  if event == "UNIT_SPELLCAST_SENT" then
    unit, target, castGuid, spellId = ...
    status = "sent"
  else
    unit, castGuid, spellId = ...
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      status = "success"
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
      status = "failure"
    end
  end

  if unit ~= "player" then return end

  local specialSpell = LLT:FindSpecialSpell(spellId)
  if not specialSpell then return end

  specialSpell.lastCast = specialSpell.lastCast or {}
  specialSpell.lastCast.status = status

  if status == "sent" then
    specialSpell.lastCast.castGuid = castGuid

    local creatureName, creatureUnit = GameTooltip:GetUnit()
    if not creatureName and target == UnitName("target") then
      creatureName = UnitName("target")
      creatureUnit = "target"
    end
    local itemName, itemLink = GameTooltip:GetItem();

    if bit.band(specialSpell.sourceTypeMask, LLT.SourceTypeMask.Unit) ~= 0 and creatureName and not itemName then
      -- creature
      local creatureGuid = UnitGUID(creatureUnit or "")
      if not creatureGuid then return end
      specialSpell.lastCast.target = creatureGuid
      specialSpell.lastCast.targetType = "Unit"
    elseif bit.band(specialSpell.sourceTypeMask, LLT.SourceTypeMask.Item) ~= 0 then
      -- item
      if itemName and itemName ~= "" and itemName == target then
        specialSpell.lastCast.target = itemLink
        specialSpell.lastCast.targetType = "Item"
      elseif target and target ~= "" then
        specialSpell.lastCast.target = C_Item.GetItemInfo(target)
        specialSpell.lastCast.targetType = "Item"
      end
    elseif bit.band(specialSpell.sourceTypeMask, LLT.SourceTypeMask.Object) ~= 0 and not creatureName and not itemName then
      specialSpell.lastCast.target = target
      specialSpell.lastCast.targetType = "Object"
    else
      return
    end
  end

  if status == "success" or status == "failure" then
    if not specialSpell.lastCast.castGuid then
      specialSpell.lastCast.castGuid = castGuid
    elseif castGuid ~= specialSpell.lastCast.castGuid then
      -- error("Cast guid mismatch")
    end
    specialSpell.lastCast.timestamp = GetTime()
  end
end

function LLT:GetLootInfoBySource()
  local lootSlotNum = GetNumLootItems()

  local lootInfoBySource = {}

  for lootSlot = 1, lootSlotNum do
    local lootType = GetLootSlotType(lootSlot)
    local lootSources = { GetLootSourceInfo(lootSlot) }
    local lootQuantity = select(3, GetLootSlotInfo(lootSlot))

    local lootQuantityBySource = {}
    local lootQuantityWithSource = 0
    for i = 1, #lootSources, 2 do
      local sourceGuid, sourceQuantity = lootSources[i], lootSources[i + 1]
      lootQuantityBySource[sourceGuid] = sourceQuantity
      lootQuantityWithSource = lootQuantityWithSource + sourceQuantity
      lootInfoBySource[sourceGuid] = lootInfoBySource[sourceGuid] or {}
    end

    if lootType ~= Enum.LootSlotType.Money and lootQuantityWithSource ~= lootQuantity then
      if #lootSources <= 2 then
        local sourceGuid = lootSources[1]
        lootQuantityBySource[sourceGuid] = lootQuantityWithSource
      else
        LLT:Print("Loot quantity mismatch, skipping")
        return {}
      end
    end

    if lootType == Enum.LootSlotType.Money then
      for sourceGuid, sourceQuantity in pairs(lootQuantityBySource) do
        lootInfoBySource[sourceGuid].money = sourceQuantity
      end
    end
    if lootType == Enum.LootSlotType.Item then
      local link = GetLootSlotLink(lootSlot)
      local id = tonumber((string.match(link, "item:(%d+)")))
      if id then
        for sourceGuid, sourceQuantity in pairs(lootQuantityBySource) do
          lootInfoBySource[sourceGuid].item = lootInfoBySource[sourceGuid].item or {}
          lootInfoBySource[sourceGuid].item[id] = sourceQuantity
        end
      end
    end
    if lootType == Enum.LootSlotType.Currency then
      local link = GetLootSlotLink(lootSlot)
      local id = tonumber(string.match(link, "currency:(%d+)"))
      if id then
        for sourceGuid, sourceQuantity in pairs(lootQuantityBySource) do
          lootInfoBySource[sourceGuid].currency = lootInfoBySource[sourceGuid].currency or {}
          lootInfoBySource[sourceGuid].currency[id] = sourceQuantity
        end
      end
    end
  end

  return lootInfoBySource
end

function LLT:AddLootRecord(lootTable, lootInfo)
  if not lootTable then return end
  if not lootInfo then return end

  lootTable.count = lootTable.count + 1
  local record = { m = lootInfo.money, i = lootInfo.item, c = lootInfo.currency }
  table.insert(lootTable.records, record)
  if #lootTable.records > 200 then
    -- LLT:Print("Warning: LootTable:" .. tostring(lootTable) .. " has more than 100 records")
    -- 移除旧的记录
    while #lootTable.records > 200 do
      table.remove(lootTable.records, 1)
    end
  end
end

LLT.LootedGuid = {}

function LLT:HandleLoot(event)
  local timestamp = GetTime()
  if event == "LOOT_READY" then
    if LLT.isLooting then return end
    LLT.isLooting = true

    local lootInfoBySource = LLT:GetLootInfoBySource()
    for sourceGuid, lootInfo in pairs(lootInfoBySource) do
      local sourceType, sourceId = LLT:GetSourceByGuid(sourceGuid)
      local specialSpell
      for _, spellData in ipairs(LLT.SpecialSpells) do
        if spellData.lastCast and spellData.lastCast.status == "success" and math.abs(timestamp - spellData.lastCast.timestamp) < 0.5 then
          if spellData.lastCast.target == sourceGuid then
            specialSpell = spellData
            break
          end
          if sourceType == "Item" and C_Item.GetItemLinkByGUID(sourceGuid) == spellData.lastCast.target then
            specialSpell = spellData
            break
          end
          -- TODO: handle object loot
        end
      end
      local subType = "Normal"
      if specialSpell then
        subType = specialSpell.subType
        specialSpell.lastCast = nil
      end
      local lootGuidKey = ("%s:%s"):format(sourceGuid, subType)
      if not LLT.LootedGuid[lootGuidKey] then
        LLT.LootedGuid[lootGuidKey] = true
        C_Timer.After(300, function()
          LLT.LootedGuid[lootGuidKey] = nil
        end)

        local lootTable = LLT:InitLootTable(sourceType, sourceId, subType)
        DevTool:AddData(lootInfo, ("lootInfo:%s:%s:%s"):format(sourceType, sourceId, subType))
        DevTool:AddData(lootTable, ("lootTable:%s:%s:%s"):format(sourceType, sourceId, subType))
        LLT:AddLootRecord(lootTable, lootInfo)
      end
    end
  end

  if event == "LOOT_CLOSED" then
    LLT.isLooting = false
  end
end

LLT:RegisterEvent("UNIT_SPELLCAST_SENT", "HandleSpell")
LLT:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "HandleSpell")
LLT:RegisterEvent("UNIT_SPELLCAST_FAILED", "HandleSpell")
LLT:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", "HandleSpell")
LLT:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "HandleSpell")

LLT:RegisterEvent("LOOT_READY", "HandleLoot")
LLT:RegisterEvent("LOOT_CLOSED", "HandleLoot")

--[===============================================================================[
    Output
  ]===============================================================================]

function LLT:IsItemJunk(quality, classId, subClassId)
  if quality ~= Enum.ItemQuality.Poor then
    return false
  end
  if classId == Enum.ItemClass.Miscellaneous and subClassId == Enum.ItemMiscellaneousSubclass.Junk then
    return true
  end
  if classId == Enum.ItemClass.Consumable and subClassId == Enum.ItemConsumableSubclass.Other then
    return true
  end
  return false
end

function LLT:FormatNumber(num)
  local n = string.format("%.2f", num)
  return string.format("%s", n:gsub("%.?0+$", ""))
end

function LLT:ParseLootTable(lootTable, title)
  if not lootTable or lootTable.count == 0 then return {} end

  local lines = {}

  table.insert(lines, {
    type = "title",
    title = title or LLT.AddonName,
  })

  local itemQuantities, currencyQuantities, totalMoney = {}, {}, 0


  for _, record in ipairs(lootTable.records) do
    for itemId, quantity in pairs(record.i or {}) do
      itemQuantities[itemId] = (itemQuantities[itemId] or 0) + quantity
    end
    for currencyId, quantity in pairs(record.c or {}) do
      currencyQuantities[currencyId] = (currencyQuantities[currencyId] or 0) + quantity
    end
    totalMoney = totalMoney + (record.m or 0)
  end

  -- icon, color, name, quantity, typeString, classId, subClassId, quality
  local items = {}
  -- icon, price
  local junks = {}
  -- icon, name, quantity
  local currencies = {}

  for itemId, quantity in pairs(itemQuantities) do
    local name, link, quality, _, _, itemType, itemSubType, _, _, icon,
    sellPrice, classId, subClassId, _, _, _, isReagent = C_Item.GetItemInfo(itemId)
    if name then
      if LLT:IsItemJunk(quality, classId, subClassId) then
        table.insert(junks, { icon, (sellPrice or 0) * quantity })
      else
        items[itemId] = (items[itemId] or 0) + quantity
        local color = select(4, C_Item.GetItemQualityColor(quality))
        local typeString = ("%s-%s"):format(itemType, itemSubType)
        table.insert(items, { icon, color, name, quantity, typeString, classId, subClassId, quality })
      end
    end
  end
  for currencyId, quantity in pairs(currencyQuantities) do
    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyId)
    local name, icon = currencyInfo.name, currencyInfo.iconFileID
    if name then
      table.insert(currencies, { icon, name, quantity })
    end
  end

  table.sort(items, function(a, b)
    if a[4] ~= b[4] then
      return a[4] > b[4]
    end
    if a[8] ~= b[8] then
      return a[8] < b[8]
    end
    if a[6] ~= b[6] then
      return a[6] < b[6]
    end
    if a[7] ~= b[7] then
      return a[7] < b[7]
    end
    return false
  end)
  table.sort(currencies, function(a, b) return a[3] > b[3] end)
  table.sort(junks, function(a, b) return a[2] > b[2] end)

  for _, item in ipairs(items) do
    local icon, color, name, quantity, typeString = unpack(item)
    table.insert(lines, {
      type = "item",
      icon = icon,
      name = ("|c%s%s|r"):format(color, name),
      total = quantity,
      average = quantity / #lootTable.records,
      typeString = typeString,
    })
  end
  for _, currency in ipairs(currencies) do
    local icon, name, quantity = unpack(currency)
    table.insert(lines, {
      type = "currency",
      icon = icon,
      name = name,
      total = quantity,
      average = quantity / #lootTable.records,
      typeString = CURRENCY,
    })
  end
  if #junks > 0 then
    local junkLabels, junkTotalPrice = {}, 0
    for _, junk in ipairs(junks) do
      local icon, price = unpack(junk)
      table.insert(junkLabels, ("|T%s:0|t"):format(icon))
      junkTotalPrice = junkTotalPrice + price
    end
    table.insert(lines, {
      type = "junk",
      icon = 133785,
      name = table.concat(junkLabels, " "),
      -- label = table.concat(junkLabels, " "),
      total = junkTotalPrice,
      average = junkTotalPrice / #lootTable.records,
    })
  end
  if totalMoney > 0 then
    table.insert(lines, {
      type = "money",
      icon = 133785,
      name = "金钱",
      -- label = "|T133785:0|t",
      total = totalMoney,
      average = totalMoney / #lootTable.records,
    })
  end

  for _, line in ipairs(lines) do
    setmetatable(line, {
      __tostring = function(t)
        if t.type == "title" then
          return RAID_CLASS_COLORS.EVOKER:WrapTextInColorCode(("---- %s ----"):format(t.title)) or ""
        end
        if t.type == "item" then
          return ("|T%s:0|t %s x%s"):format(t.icon, t.name, LLT:FormatNumber(t.average))
        end
        if t.type == "currency" then
          return ("|T%s:0|t %s x%s"):format(t.icon, t.name, LLT:FormatNumber(t.average))
        end
        if t.type == "junk" then
          return ("%s %s"):format(t.name, GetMoneyString(t.average))
        end
        if t.type == "money" then
          return ("|T%s:0|t %s"):format(t.icon, GetMoneyString(t.average))
        end
        return ""
      end,
    })
  end

  return lines
end

function LLT:AttachTooltipWithLootTable(tooltip, lootTable, title)
  if not lootTable or lootTable.count == 0 then return end
  local lines = LLT:ParseLootTable(lootTable, title)

  for _, line in ipairs(lines) do
    if line.type == "title" then
      tooltip:AddDoubleLine(("---- %s ----"):format(line.title), lootTable.count, RAID_CLASS_COLORS.EVOKER:GetRGB())
    elseif line.type == "item" or line.type == "currency" then
      tooltip:AddDoubleLine(
        ("|T%s:0|t %s x%s"):format(line.icon, line.name, LLT:FormatNumber(line.average)),
        line.typeString,
        nil, nil, nil,
        0.5, 0.5, 0.5
      )
    elseif line.type == "junk" then
      tooltip:AddLine(("%s %s"):format(line.name, GetMoneyString(line.average)))
    elseif line.type == "money" then
      tooltip:AddLine(("|T%s:0|t %s"):format(line.icon, GetMoneyString(line.average)))
    end
  end
end

function LLT:AttachUnitTooltip(tooltip, data)
  if not data then return end
  local sourceType, sourceId = LLT:GetSourceByGuid(data.guid)
  do
    local lootTable = LLT:GetLootTable(sourceType, sourceId)
    LLT:AttachTooltipWithLootTable(tooltip, lootTable, data.lines[1].leftText)
  end
  for _, spell in ipairs(LLT.SpecialSpells) do
    if bit.band(spell.sourceTypeMask, LLT.SourceTypeMask.Unit) ~= 0 then
      local lootTable = LLT:GetLootTable(sourceType, sourceId, spell.subType)
      LLT:AttachTooltipWithLootTable(tooltip, lootTable, spell.spellName)
    end
  end
end

TooltipDataProcessor.AddTooltipPostCall(
  Enum.TooltipDataType.Unit,
  function(tooltip, data)
    return LLT:AttachUnitTooltip(tooltip, data)
  end
)


function LLT:AttachItemTooltip(tooltip, data)
  if not data then return end
  local sourceType, sourceId = "Item", data.id
  do
    local lootTable = LLT:GetLootTable(sourceType, sourceId)
    LLT:AttachTooltipWithLootTable(tooltip, lootTable, data.lines[1].leftText)
  end
  for _, spell in ipairs(LLT.SpecialSpells) do
    if bit.band(spell.sourceTypeMask, LLT.SourceTypeMask.Unit) ~= 0 then
      local lootTable = LLT:GetLootTable(sourceType, sourceId, spell.subType)
      LLT:AttachTooltipWithLootTable(tooltip, lootTable, spell.spellName)
    end
  end
end

TooltipDataProcessor.AddTooltipPostCall(
  Enum.TooltipDataType.Item,
  function(tooltip, data)
    return LLT:AttachItemTooltip(tooltip, data)
  end
)
