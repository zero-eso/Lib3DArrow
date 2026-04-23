local lib = Lib3DArrow
local integration = lib.integration or {}
lib.integration = integration

local GPS = LibGPS3 or LibGPS2
local PANEL_NAME = lib.name .. "_OptionsPanel"
local INIT_EVENT = lib.name .. "_IntegrationInit"
local TRACKER_UPDATE = lib.name .. "_TrackerUpdate"

local SOURCE_SKYSHARDS = "skyshards"
local SOURCE_LOREBOOKS = "lorebooks"
local SOURCE_ACTIVE_QUEST = "activequest"

local SKYSHARDS_PINDATA_LOCX = 1
local SKYSHARDS_PINDATA_LOCY = 2
local SKYSHARDS_PINDATA_ACHIEVEMENTID = 3
local SKYSHARDS_PINDATA_ZONEGUIDEINDEX = 4

local LORE_LIBRARY_SHALIDOR = 1

local SOURCE_COLOURS = {
  [SOURCE_ACTIVE_QUEST] = { r = 0.937, g = 0.773, b = 0.278, a = 1 },
  [SOURCE_SKYSHARDS] = { r = 0.529, g = 0.808, b = 0.922, a = 1 },
  [SOURCE_LOREBOOKS] = { r = 0.788, g = 0.651, b = 0.275, a = 1 },
}

local MIGRATION_SOURCE_COLOURS = {
  [SOURCE_SKYSHARDS] = {
    { r = 0.247, g = 0.565, b = 0.573, a = 1 },
  },
  [SOURCE_LOREBOOKS] = {
    { r = 0.627, g = 0.125, b = 0.941, a = 1 },
  },
}

local defaults = {
  tracker = {
    enabled = false,
    trackActiveQuest = true,
    trackSkyShards = true,
    trackLoreBooks = true,
    useFaux3DArrow = false,
    respectSourceSettings = true,
    showDistance = true,
    showMarker = true,
    scanIntervalMs = 250,
    sourceColours = {
      [SOURCE_ACTIVE_QUEST] = {
        r = SOURCE_COLOURS[SOURCE_ACTIVE_QUEST].r,
        g = SOURCE_COLOURS[SOURCE_ACTIVE_QUEST].g,
        b = SOURCE_COLOURS[SOURCE_ACTIVE_QUEST].b,
        a = SOURCE_COLOURS[SOURCE_ACTIVE_QUEST].a,
      },
      [SOURCE_SKYSHARDS] = {
        r = SOURCE_COLOURS[SOURCE_SKYSHARDS].r,
        g = SOURCE_COLOURS[SOURCE_SKYSHARDS].g,
        b = SOURCE_COLOURS[SOURCE_SKYSHARDS].b,
        a = SOURCE_COLOURS[SOURCE_SKYSHARDS].a,
      },
      [SOURCE_LOREBOOKS] = {
        r = SOURCE_COLOURS[SOURCE_LOREBOOKS].r,
        g = SOURCE_COLOURS[SOURCE_LOREBOOKS].g,
        b = SOURCE_COLOURS[SOURCE_LOREBOOKS].b,
        a = SOURCE_COLOURS[SOURCE_LOREBOOKS].a,
      },
    },
  },
}

local function GetSettings()
  return integration.savedVars and integration.savedVars.tracker
end

local function GetQuestTrackerState()
  integration.questTrackerState = integration.questTrackerState or {
    questIndex = nil,
    currentMapId = nil,
    candidate = nil,
    dirty = true,
  }

  return integration.questTrackerState
end

local function CopyColour(target, source)
  target.r = source.r
  target.g = source.g
  target.b = source.b
  target.a = source.a
end

local function IsSameColour(left, right)
  return left
    and right
    and left.r == right.r
    and left.g == right.g
    and left.b == right.b
    and left.a == right.a
end

local function EnsureSettingsDefaults()
  local settings = GetSettings()
  if not settings then
    return
  end

  settings.sourceColours = settings.sourceColours or {}

  for source, colour in pairs(SOURCE_COLOURS) do
    settings.sourceColours[source] = settings.sourceColours[source] or {}

    local savedColour = settings.sourceColours[source]
    if savedColour.r == nil or savedColour.g == nil or savedColour.b == nil or savedColour.a == nil then
      CopyColour(savedColour, colour)
    else
      local migrationColours = MIGRATION_SOURCE_COLOURS[source]
      if migrationColours then
        for _, migrationColour in ipairs(migrationColours) do
          if IsSameColour(savedColour, migrationColour) then
            CopyColour(savedColour, colour)
            break
          end
        end
      end
    end
  end
end

local function IsSkyShardsAvailable()
  return _G["SkyShards"] ~= nil and type(_G["SkyShards_GetLocalData"]) == "function"
end

local function IsActiveQuestAvailable()
  return FOCUSED_QUEST_TRACKER ~= nil and type(ZO_WorldMap_GetPinManager) == "function"
end

local function IsLoreBooksAvailable()
  return _G["LoreBooks"] ~= nil
    and type(_G["LoreBooks_GetLocalData"]) == "function"
    and type(_G["LoreBooks_GetNewLoreBookInfo"]) == "function"
    and LibMapData ~= nil
end

local function GetSourceColour(source)
  local settings = GetSettings()
  if settings and settings.sourceColours and settings.sourceColours[source] then
    return settings.sourceColours[source]
  end

  return SOURCE_COLOURS[source]
end

local function EnsureTrackerArrow()
  if integration.arrow then
    return integration.arrow
  end

  local settings = GetSettings()
  integration.arrow = lib:CreateArrow({
    arrowColour = GetSourceColour(SOURCE_SKYSHARDS),
    markerColour = GetSourceColour(SOURCE_SKYSHARDS),
    distanceColour = GetSourceColour(SOURCE_SKYSHARDS),
    arrowUseFaux3D = settings and settings.useFaux3DArrow or false,
  })

  return integration.arrow
end

local function HideTrackerArrow()
  if integration.arrow then
    integration.arrow:SetTarget(0, 0)
  end

  integration.currentTargetKey = nil
  integration.currentSource = nil
end

local function ApplyVisualSettings()
  local settings = GetSettings()
  if not settings then
    return
  end

  if not integration.arrow and not settings.enabled then
    return
  end

  local arrow = EnsureTrackerArrow()

  arrow:SetArrowFaux3DEnabled(settings.useFaux3DArrow)
  arrow.distance:SetHidden(not settings.showDistance)
  arrow.marker:SetHidden(not settings.showMarker)
end

local function ApplySourceColour(source)
  if not integration.arrow then
    return
  end

  local colour = GetSourceColour(source)
  integration.arrow:ChangeColours(colour, colour)
end

local function GetLocalDistanceScore(x1, y1, x2, y2)
  if GPS and GPS.GetLocalDistanceInMeters then
    local metres = GPS:GetLocalDistanceInMeters(x1, y1, x2, y2)
    if metres and (metres > 0 or (x1 == x2 and y1 == y2)) then
      return metres
    end
  end

  local dx = x1 - x2
  local dy = y1 - y2
  return zo_sqrt(dx * dx + dy * dy)
end

local function FindTrackedQuestIndex()
  for questIndex = 1, MAX_JOURNAL_QUESTS do
    if IsValidQuestIndex(questIndex) then
      local _, _, _, _, _, _, tracked = GetJournalQuestInfo(questIndex)
      if tracked then
        return questIndex
      end
    end
  end
end

local function MarkQuestTargetDirty(questIndex)
  local questState = GetQuestTrackerState()
  if questIndex ~= nil then
    questState.questIndex = questIndex
  end
  questState.dirty = true
end

local function ShouldUseActiveQuest()
  local settings = GetSettings()
  return settings
    and settings.trackActiveQuest
    and IsActiveQuestAvailable()
end

local function RefreshQuestTargetCache(playerX, playerY)
  local questState = GetQuestTrackerState()
  local currentMapId = GetCurrentMapId()

  if not questState.questIndex or not IsValidQuestIndex(questState.questIndex) then
    questState.questIndex = FindTrackedQuestIndex()
  end

  questState.currentMapId = currentMapId
  questState.candidate = nil
  questState.dirty = false

  if not currentMapId or currentMapId == 0 then
    return
  end

  if not questState.questIndex or not IsValidQuestIndex(questState.questIndex) then
    return
  end

  local pinManager = ZO_WorldMap_GetPinManager()
  if not pinManager or not pinManager.AddPinsToArray then
    return
  end

  local pins = {}
  pinManager:AddPinsToArray(pins, "quest", questState.questIndex)

  local bestX = nil
  local bestY = nil
  local bestDistance = nil

  for _, pin in ipairs(pins) do
    local x, y = pin:GetNormalizedPosition()
    if x and y then
      local distance = GetLocalDistanceScore(playerX, playerY, x, y)
      if not bestDistance or distance < bestDistance then
        bestX = x
        bestY = y
        bestDistance = distance
      end
    end
  end

  if bestX and bestY then
    questState.candidate = {
      source = SOURCE_ACTIVE_QUEST,
      x = bestX,
      y = bestY,
      distance = bestDistance or 0,
      key = string.format("%d:%d:%.5f:%.5f", currentMapId, questState.questIndex, bestX, bestY),
    }
  end
end

local function FindActiveQuestCandidate(playerX, playerY)
  if not ShouldUseActiveQuest() then
    return nil
  end

  local questState = GetQuestTrackerState()
  local currentMapId = GetCurrentMapId()
  if questState.currentMapId ~= currentMapId then
    questState.dirty = true
  end

  if questState.dirty then
    RefreshQuestTargetCache(playerX, playerY)
  end

  return questState.candidate
end

local function GetSkyshardIdByCriteria(zoneId, criteriaIndex, expectedX, expectedY)
  local numSkyshards = GetNumSkyshardsInZone(zoneId)
  if not numSkyshards then
    return nil
  end

  if criteriaIndex <= numSkyshards then
    local shardId = GetZoneSkyshardId(zoneId, criteriaIndex)
    local x, y = GetNormalizedPositionForSkyshardId(shardId)
    if x and y then
      local distance = zo_sqrt((x - expectedX) ^ 2 + (y - expectedY) ^ 2)
      if distance < 0.1 then
        return shardId
      end
    end
  end

  local bestShardId = nil
  local bestDistance = math.huge

  for index = 1, numSkyshards do
    local shardId = GetZoneSkyshardId(zoneId, index)
    local x, y = GetNormalizedPositionForSkyshardId(shardId)
    if x and y then
      local distance = zo_sqrt((x - expectedX) ^ 2 + (y - expectedY) ^ 2)
      if distance < bestDistance then
        bestDistance = distance
        bestShardId = shardId
      end
    end
  end

  if bestDistance < 0.1 then
    return bestShardId
  end

  if criteriaIndex <= numSkyshards then
    return GetZoneSkyshardId(zoneId, criteriaIndex)
  end
end

local function IsAchievementComplete(achievementId)
  if not achievementId then
    return true
  end

  local _, _, _, _, completed = GetAchievementInfo(achievementId)
  return completed
end

local function ShouldDisplaySkyShards()
  local skyShards = _G["SkyShards"]
  if not skyShards or not skyShards.db or skyShards.db.immersiveMode == 1 then
    return true
  end

  local mapIndex = GetCurrentMapIndex()
  if (not mapIndex or mapIndex == 0) and IsInImperialCity() then
    mapIndex = GetImperialCityMapIndex()
  end

  if (not mapIndex or mapIndex == 0) and LibGPS3 and LibGPS3.GetCurrentMapMeasurement then
    local measurement = LibGPS3:GetCurrentMapMeasurement()
    if measurement then
      mapIndex = measurement.mapIndex
    end
  end

  if not mapIndex or mapIndex == 0 or type(_G["SkyShards_GetImmersiveModeCondition"]) ~= "function" then
    return true
  end

  local conditionData = _G["SkyShards_GetImmersiveModeCondition"](skyShards.db.immersiveMode, mapIndex)
  if not conditionData then
    return true
  end

  if skyShards.db.immersiveMode == 3 then
    if mapIndex ~= 14 then
      return conditionData
    end
    return true
  end

  if type(conditionData) == "table" then
    for _, achievementId in ipairs(conditionData) do
      if not IsAchievementComplete(achievementId) then
        return false
      end
    end
    return true
  end

  return IsAchievementComplete(conditionData)
end

local function ShouldDisplayLoreBooks()
  local loreBooks = _G["LoreBooks"]
  local internal = _G["LoreBooks_Internal"]
  local mapData = LibMapData

  if not loreBooks or not loreBooks.db or not internal or loreBooks.db.immersiveMode == internal.LBOOKS_IMMERSIVE_DISABLED then
    return true
  end

  local mapIndex = mapData and mapData.mapIndex
  if not mapIndex or mapIndex == 0 or type(_G["LoreBooks_GetImmersiveModeCondition"]) ~= "function" then
    return true
  end

  local conditionData = _G["LoreBooks_GetImmersiveModeCondition"](loreBooks.db.immersiveMode, mapIndex)
  if not conditionData then
    return true
  end

  if loreBooks.db.immersiveMode == internal.LBOOKS_IMMERSIVE_WAYSHRINES then
    if mapIndex ~= GetCyrodiilMapIndex() then
      return conditionData
    end
    return true
  end

  if type(conditionData) == "table" then
    for _, achievementId in ipairs(conditionData) do
      if not IsAchievementComplete(achievementId) then
        return false
      end
    end
    return true
  end

  return IsAchievementComplete(conditionData)
end

local function ShouldUseSkyShards()
  local settings = GetSettings()
  local skyShards = _G["SkyShards"]

  if not settings.trackSkyShards or not IsSkyShardsAvailable() then
    return false
  end

  if not settings.respectSourceSettings then
    return true
  end

  if not skyShards.db or not skyShards.db.filters then
    return false
  end

  return skyShards.db.filters[skyShards.PINS_UNKNOWN] and ShouldDisplaySkyShards()
end

local function ShouldUseLoreBooks()
  local settings = GetSettings()
  local loreBooks = _G["LoreBooks"]
  local internal = _G["LoreBooks_Internal"]

  if not settings.trackLoreBooks or not IsLoreBooksAvailable() then
    return false
  end

  if not settings.respectSourceSettings then
    return true
  end

  if not loreBooks.db or not loreBooks.db.filters or not internal then
    return false
  end

  return loreBooks.db.filters[internal.PINS_UNKNOWN] and ShouldDisplayLoreBooks()
end

local function BuildCandidate(source, x, y, distance, key)
  return {
    source = source,
    x = x,
    y = y,
    distance = distance,
    key = key,
  }
end

local function FindSkyShardCandidate(playerX, playerY)
  if not ShouldUseSkyShards() then
    return nil
  end

  local mapPins = LibMapPins
  if not mapPins or not mapPins.GetZoneAndSubzone then
    return nil
  end

  local zone, subzone = mapPins:GetZoneAndSubzone(false, true)
  local data = _G["SkyShards_GetLocalData"](zone, subzone)
  if not data then
    return nil
  end

  local bestCandidate = nil

  for _, pinData in ipairs(data) do
    local zoneId = GetSkyshardAchievementZoneId(pinData[SKYSHARDS_PINDATA_ACHIEVEMENTID])
    local shardId = GetSkyshardIdByCriteria(zoneId, pinData[SKYSHARDS_PINDATA_ZONEGUIDEINDEX], pinData[SKYSHARDS_PINDATA_LOCX], pinData[SKYSHARDS_PINDATA_LOCY])

    if shardId then
      local shardStatus = GetSkyshardDiscoveryStatus(shardId)
      local isUnknown = shardStatus == SKYSHARD_DISCOVERY_STATUS_DISCOVERED or shardStatus == SKYSHARD_DISCOVERY_STATUS_UNDISCOVERED

      if isUnknown then
        local distance = GetLocalDistanceScore(playerX, playerY, pinData[SKYSHARDS_PINDATA_LOCX], pinData[SKYSHARDS_PINDATA_LOCY])
        if not bestCandidate or distance < bestCandidate.distance then
          bestCandidate = BuildCandidate(
            SOURCE_SKYSHARDS,
            pinData[SKYSHARDS_PINDATA_LOCX],
            pinData[SKYSHARDS_PINDATA_LOCY],
            distance,
            tostring(zoneId) .. ":" .. tostring(pinData[SKYSHARDS_PINDATA_ZONEGUIDEINDEX])
          )
        end
      end
    end
  end

  return bestCandidate
end

local function FindLoreBookCandidate(playerX, playerY)
  if not ShouldUseLoreBooks() then
    return nil
  end

  local mapData = LibMapData
  if not mapData or not mapData.mapId or mapData.mapId == 0 or mapData.isMacroMap then
    return nil
  end

  local data = _G["LoreBooks_GetLocalData"](mapData.mapId)
  if not data then
    return nil
  end

  local bestCandidate = nil

  for _, pinData in ipairs(data) do
    local _, _, known = _G["LoreBooks_GetNewLoreBookInfo"](LORE_LIBRARY_SHALIDOR, pinData[3], pinData[4])
    if not known then
      local distance = GetLocalDistanceScore(playerX, playerY, pinData[1], pinData[2])
      if not bestCandidate or distance < bestCandidate.distance then
        bestCandidate = BuildCandidate(
          SOURCE_LOREBOOKS,
          pinData[1],
          pinData[2],
          distance,
          tostring(mapData.mapId) .. ":" .. tostring(pinData[3]) .. ":" .. tostring(pinData[4])
        )
      end
    end
  end

  return bestCandidate
end

local function FindBestCandidate()
  if not DoesUnitExist("player") then
    return nil
  end

  local playerX, playerY = GetMapPlayerPosition("player")
  if not playerX or not playerY then
    return nil
  end

  local activeQuestCandidate = FindActiveQuestCandidate(playerX, playerY)
  if activeQuestCandidate then
    return activeQuestCandidate
  end

  local bestCandidate = FindSkyShardCandidate(playerX, playerY)
  local loreBooksCandidate = FindLoreBookCandidate(playerX, playerY)

  if loreBooksCandidate and (not bestCandidate or loreBooksCandidate.distance < bestCandidate.distance) then
    bestCandidate = loreBooksCandidate
  end

  return bestCandidate
end

function integration:RefreshTarget()
  local settings = GetSettings()
  if not settings or not settings.enabled then
    HideTrackerArrow()
    return
  end

  local candidate = FindBestCandidate()
  if not candidate then
    HideTrackerArrow()
    return
  end

  local arrow = EnsureTrackerArrow()
  if integration.currentSource ~= candidate.source then
    ApplySourceColour(candidate.source)
    integration.currentSource = candidate.source
  end

  integration.currentTargetKey = candidate.key
  arrow:SetTarget(candidate.x, candidate.y)
  ApplyVisualSettings()
end

local function StopTracker()
  EVENT_MANAGER:UnregisterForUpdate(TRACKER_UPDATE)
  HideTrackerArrow()
end

local function RefreshQuestTrackingState()
  local questState = GetQuestTrackerState()
  questState.questIndex = FindTrackedQuestIndex()
  questState.dirty = true

  if integration.savedVars then
    integration:RefreshTarget()
  end
end

local function OnQuestAssistStateChanged(_, assistedData)
  local questIndex = assistedData and assistedData.arg1 or FindTrackedQuestIndex()
  MarkQuestTargetDirty(questIndex)
  integration:RefreshTarget()
end

local function OnQuestTargetChanged()
  RefreshQuestTrackingState()
end

local function RefreshTrackerState()
  local settings = GetSettings()
  if not settings or not settings.enabled then
    StopTracker()
    return
  end

  EnsureTrackerArrow()
  ApplyVisualSettings()
  EVENT_MANAGER:UnregisterForUpdate(TRACKER_UPDATE)
  EVENT_MANAGER:RegisterForUpdate(TRACKER_UPDATE, settings.scanIntervalMs, function()
    integration:RefreshTarget()
  end)
  integration:RefreshTarget()
end

local function InitializeSettingsPanel()
  local LAM = LibAddonMenu2
  if not LAM then
    return
  end

  local settings = GetSettings()
  local panelData = {
    type = "panel",
    name = lib.name,
    displayName = "|cFFFFB0" .. lib.name .. "|r",
    author = "kadeer",
    version = "1.1",
    registerForRefresh = true,
    registerForDefaults = true,
  }

  local optionsTable = {
    {
      type = "description",
      text = "Optional auto-tracking for the assisted quest or for nearby SkyShards and LoreBooks targets on the current map.",
      width = "full",
    },
    {
      type = "checkbox",
      name = "Enable Auto Tracking",
      tooltip = "Creates one managed Lib3DArrow instance and points it at the nearest enabled target source.",
      getFunc = function()
        return settings.enabled
      end,
      setFunc = function(value)
        settings.enabled = value
        RefreshTrackerState()
      end,
      default = defaults.tracker.enabled,
      width = "full",
    },
    {
      type = "checkbox",
      name = "Track Active Quest",
      tooltip = "Tracks the currently assisted quest when it has a target pin on the current map. This source takes priority over collectible sources.",
      getFunc = function()
        return settings.trackActiveQuest
      end,
      setFunc = function(value)
        settings.trackActiveQuest = value
        integration:RefreshTarget()
      end,
      default = defaults.tracker.trackActiveQuest,
      disabled = function()
        return not IsActiveQuestAvailable()
      end,
      width = "half",
    },
    {
      type = "checkbox",
      name = "Track SkyShards",
      tooltip = "Uses the installed SkyShards addon as a target source.",
      getFunc = function()
        return settings.trackSkyShards
      end,
      setFunc = function(value)
        settings.trackSkyShards = value
        integration:RefreshTarget()
      end,
      default = defaults.tracker.trackSkyShards,
      disabled = function()
        return not IsSkyShardsAvailable()
      end,
      width = "half",
    },
    {
      type = "checkbox",
      name = "Track LoreBooks (Shalidor)",
      tooltip = "Uses the installed LoreBooks addon as a target source.",
      getFunc = function()
        return settings.trackLoreBooks
      end,
      setFunc = function(value)
        settings.trackLoreBooks = value
        integration:RefreshTarget()
      end,
      default = defaults.tracker.trackLoreBooks,
      disabled = function()
        return not IsLoreBooksAvailable()
      end,
      width = "half",
    },
    {
      type = "checkbox",
      name = "Respect Source Addon Settings",
      tooltip = "When enabled, only tracks targets that the source addon would currently show based on its own filters and immersive settings.",
      getFunc = function()
        return settings.respectSourceSettings
      end,
      setFunc = function(value)
        settings.respectSourceSettings = value
        integration:RefreshTarget()
      end,
      default = defaults.tracker.respectSourceSettings,
      width = "full",
    },
    {
      type = "checkbox",
      name = "Show Distance",
      tooltip = "Shows the managed arrow's distance label.",
      getFunc = function()
        return settings.showDistance
      end,
      setFunc = function(value)
        settings.showDistance = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.showDistance,
      width = "half",
    },
    {
      type = "checkbox",
      name = "Show Marker",
      tooltip = "Shows the managed arrow's world marker pillar.",
      getFunc = function()
        return settings.showMarker
      end,
      setFunc = function(value)
        settings.showMarker = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.showMarker,
      width = "half",
    },
    {
      type = "checkbox",
      name = "Use Faux 3D Arrow",
      tooltip = "Builds a chunkier 2.5D arrow from the same arrow art while keeping the default flat mode available.",
      getFunc = function()
        return settings.useFaux3DArrow
      end,
      setFunc = function(value)
        settings.useFaux3DArrow = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.useFaux3DArrow,
      width = "full",
    },
    {
      type = "slider",
      name = "Refresh Interval",
      tooltip = "How often Lib3DArrow rescans for the nearest target.",
      min = 100,
      max = 2000,
      step = 50,
      getFunc = function()
        return settings.scanIntervalMs
      end,
      setFunc = function(value)
        settings.scanIntervalMs = value
        RefreshTrackerState()
      end,
      default = defaults.tracker.scanIntervalMs,
      width = "full",
    },
    {
      type = "header",
      name = "Source Colours",
      width = "full",
    },
    {
      type = "colorpicker",
      name = "Active Quest Colour",
      tooltip = "Used for the managed arrow, marker, glow, and distance text when tracking the assisted quest.",
      getFunc = function()
        local colour = settings.sourceColours[SOURCE_ACTIVE_QUEST]
        return colour.r, colour.g, colour.b, colour.a
      end,
      setFunc = function(r, g, b, a)
        local colour = settings.sourceColours[SOURCE_ACTIVE_QUEST]
        colour.r, colour.g, colour.b, colour.a = r, g, b, a
        if integration.currentSource == SOURCE_ACTIVE_QUEST then
          ApplySourceColour(SOURCE_ACTIVE_QUEST)
        end
      end,
      width = "half",
    },
    {
      type = "colorpicker",
      name = "SkyShards Colour",
      tooltip = "Used for the managed arrow, marker, glow, and distance text when tracking SkyShards.",
      getFunc = function()
        local colour = settings.sourceColours[SOURCE_SKYSHARDS]
        return colour.r, colour.g, colour.b, colour.a
      end,
      setFunc = function(r, g, b, a)
        local colour = settings.sourceColours[SOURCE_SKYSHARDS]
        colour.r, colour.g, colour.b, colour.a = r, g, b, a
        if integration.currentSource == SOURCE_SKYSHARDS then
          ApplySourceColour(SOURCE_SKYSHARDS)
        end
      end,
      width = "half",
    },
    {
      type = "colorpicker",
      name = "LoreBooks Colour",
      tooltip = "Used for the managed arrow, marker, glow, and distance text when tracking LoreBooks.",
      getFunc = function()
        local colour = settings.sourceColours[SOURCE_LOREBOOKS]
        return colour.r, colour.g, colour.b, colour.a
      end,
      setFunc = function(r, g, b, a)
        local colour = settings.sourceColours[SOURCE_LOREBOOKS]
        colour.r, colour.g, colour.b, colour.a = r, g, b, a
        if integration.currentSource == SOURCE_LOREBOOKS then
          ApplySourceColour(SOURCE_LOREBOOKS)
        end
      end,
      width = "half",
    },
  }

  LAM:RegisterAddonPanel(PANEL_NAME, panelData)
  LAM:RegisterOptionControls(PANEL_NAME, optionsTable)
end

local function OnPlayerActivated()
  RefreshQuestTrackingState()
  integration:RefreshTarget()
end

local function InitializeIntegration()
  integration.savedVars = ZO_SavedVars:NewAccountWide("Lib3DArrow_SavedVariables", 1, nil, defaults)
  EnsureSettingsDefaults()
  RefreshQuestTrackingState()
  RefreshTrackerState()
  InitializeSettingsPanel()

  if FOCUSED_QUEST_TRACKER and FOCUSED_QUEST_TRACKER.RegisterCallback then
    FOCUSED_QUEST_TRACKER:RegisterCallback("QuestTrackerAssistStateChanged", OnQuestAssistStateChanged)
  end

  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_QUEST_ADDED, OnQuestTargetChanged)
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_QUEST_REMOVED, OnQuestTargetChanged)
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_QUEST_ADVANCED, OnQuestTargetChanged)
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_QUEST_CONDITION_COUNTER_CHANGED, OnQuestTargetChanged)
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_QUEST_CONDITION_OVERRIDE_TEXT_CHANGED, OnQuestTargetChanged)
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_QUEST_LIST_UPDATED, OnQuestTargetChanged)
end

local function OnAddonLoaded(eventCode, addonName)
  if addonName ~= lib.name then
    return
  end

  EVENT_MANAGER:UnregisterForEvent(INIT_EVENT, EVENT_ADD_ON_LOADED)
  InitializeIntegration()
end

EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_ADD_ON_LOADED, OnAddonLoaded)
