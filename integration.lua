local lib = Lib3DArrow
local integration = lib.integration or {}
lib.integration = integration

local GPS = LibGPS3 or LibGPS2
local PANEL_NAME = lib.name .. "_OptionsPanel"
local INIT_EVENT = lib.name .. "_IntegrationInit"
local TRACKER_UPDATE = lib.name .. "_TrackerUpdate"

local SOURCE_DESTINATION = "destination"
local SOURCE_SKYSHARDS = "skyshards"
local SOURCE_LOREBOOKS = "lorebooks"
local SOURCE_ACTIVE_QUEST = "activequest"
local QUEST_RETRY_WINDOW_MS = 5000
local QUEST_BOOTSTRAP_RETRY_WINDOW_MS = 12000

local SKYSHARDS_PINDATA_LOCX = 1
local SKYSHARDS_PINDATA_LOCY = 2
local SKYSHARDS_PINDATA_ACHIEVEMENTID = 3
local SKYSHARDS_PINDATA_ZONEGUIDEINDEX = 4

local LORE_LIBRARY_SHALIDOR = 1

local SOURCE_COLOURS = {
  [SOURCE_DESTINATION] = { r = 1, g = 0.494, b = 0.153, a = 1 },
  [SOURCE_ACTIVE_QUEST] = { r = 0.937, g = 0.773, b = 0.278, a = 1 },
  [SOURCE_SKYSHARDS] = { r = 0.529, g = 0.808, b = 0.922, a = 1 },
  [SOURCE_LOREBOOKS] = { r = 0.788, g = 0.651, b = 0.275, a = 1 },
}

local SOURCE_MARKER_TEXTURES = {
  [SOURCE_DESTINATION] = "esoui/art/zonestories/completiontypeicon_pointofinterest.dds",
  [SOURCE_ACTIVE_QUEST] = "esoui/art/zonestories/completiontypeicon_priorityquest.dds",
  [SOURCE_SKYSHARDS] = "esoui/art/zonestories/completiontypeicon_skyshard.dds",
  [SOURCE_LOREBOOKS] = "esoui/art/zonestories/completiontypeicon_lorebooks.dds",
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
    trackDestination = true,
    trackActiveQuest = true,
    trackSkyShards = true,
    trackLoreBooks = true,
    respectSourceSettings = true,
    showDistance = true,
    showMarker = true,
    hideArrowNearTarget = false,
    hideArrowNearTargetDistance = 10,
    hideMarkerNearTarget = false,
    hideMarkerNearTargetDistance = 10,
    scanIntervalMs = 250,
    sourceColours = {
      [SOURCE_DESTINATION] = {
        r = SOURCE_COLOURS[SOURCE_DESTINATION].r,
        g = SOURCE_COLOURS[SOURCE_DESTINATION].g,
        b = SOURCE_COLOURS[SOURCE_DESTINATION].b,
        a = SOURCE_COLOURS[SOURCE_DESTINATION].a,
      },
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
    retryUntilMS = nil,
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

local function IsDestinationAvailable()
  return type(GetMapPlayerWaypoint) == "function"
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
  })

  return integration.arrow
end

local function HideTrackerArrow()
  if integration.arrow then
    integration.arrow:SetTarget(0, 0)
  end

  integration.currentTargetKey = nil
  integration.currentSource = nil
  integration.currentDistance = nil
end

local function GetCurrentTargetDistance()
  if integration.arrow and integration.arrow.data and integration.arrow.data.metres ~= nil then
    return integration.arrow.data.metres
  end

  return integration.currentDistance
end

local function GetNearTargetFadeAlpha(isEnabled, threshold)
  if not isEnabled then
    return 1
  end

  local distance = GetCurrentTargetDistance()
  if distance == nil or threshold == nil or threshold <= 0 then
    return 1
  end

  return zo_clamp(distance / threshold, 0, 1)
end

local function GetArrowFadeAlpha()
  local settings = GetSettings()
  if not settings then
    return 1
  end

  return GetNearTargetFadeAlpha(settings.hideArrowNearTarget, settings.hideArrowNearTargetDistance)
end

local function GetMarkerFadeAlpha()
  local settings = GetSettings()
  if not settings then
    return 1
  end

  return GetNearTargetFadeAlpha(settings.hideMarkerNearTarget, settings.hideMarkerNearTargetDistance)
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
  local arrowAlpha = GetArrowFadeAlpha()
  local markerAlpha = GetMarkerFadeAlpha()

  if arrow.SetArrowAlpha then
    arrow:SetArrowAlpha(arrowAlpha)
  end
  if arrow.SetDistanceAlpha then
    arrow:SetDistanceAlpha(arrowAlpha)
  end
  if arrow.SetMarkerAlpha then
    arrow:SetMarkerAlpha(markerAlpha)
  end

  arrow.arrow:SetHidden(arrowAlpha <= 0)
  arrow.distance:SetHidden(not settings.showDistance or arrowAlpha <= 0)
  arrow.marker:SetHidden(not settings.showMarker or markerAlpha <= 0)
end

local function ApplySourceColour(source)
  if not integration.arrow then
    return
  end

  local colour = GetSourceColour(source)
  if integration.arrow.SetMarkerIconTexture then
    integration.arrow:SetMarkerIconTexture(SOURCE_MARKER_TEXTURES[source] or SOURCE_MARKER_TEXTURES[SOURCE_DESTINATION])
  end
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

local function BuildCandidate(source, x, y, distance, key)
  return {
    source = source,
    x = x,
    y = y,
    distance = distance,
    key = key,
  }
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

local function ClearQuestRetry(questState)
  questState.retryUntilMS = nil
end

local function ScheduleQuestRetry(questState, retryWindowMS)
  if type(GetFrameTimeMilliseconds) ~= "function" then
    return
  end

  local newRetryUntilMS = GetFrameTimeMilliseconds() + (retryWindowMS or QUEST_RETRY_WINDOW_MS)
  if not questState.retryUntilMS or newRetryUntilMS > questState.retryUntilMS then
    questState.retryUntilMS = newRetryUntilMS
  end
end

local function ShouldRetryQuestRefresh(questState)
  if not questState.retryUntilMS or type(GetFrameTimeMilliseconds) ~= "function" then
    return false
  end

  if GetFrameTimeMilliseconds() <= questState.retryUntilMS then
    return true
  end

  questState.retryUntilMS = nil
  return false
end

local function MarkQuestTargetDirty(questIndex)
  local questState = GetQuestTrackerState()
  if questIndex ~= nil then
    questState.questIndex = questIndex
  end
  questState.dirty = true
  ClearQuestRetry(questState)
end

local function ShouldUseActiveQuest()
  local settings = GetSettings()
  return settings
    and settings.trackActiveQuest
    and IsActiveQuestAvailable()
end

local function ShouldUseDestination()
  local settings = GetSettings()
  return settings
    and settings.trackDestination
    and IsDestinationAvailable()
end

local function FindDestinationCandidate(playerX, playerY)
  if not ShouldUseDestination() then
    return nil
  end

  local x, y = GetMapPlayerWaypoint()
  if not x or not y or (x == 0 and y == 0) then
    return nil
  end

  return BuildCandidate(
    SOURCE_DESTINATION,
    x,
    y,
    GetLocalDistanceScore(playerX, playerY, x, y),
    string.format("%d:%.5f:%.5f", GetCurrentMapId() or 0, x, y)
  )
end

local function IsLocalPositionOnCurrentMap(x, y)
  return x ~= nil
    and y ~= nil
    and x >= 0
    and x <= 1
    and y >= 0
    and y <= 1
end

local function PushCurrentMapContext()
  if GPS and GPS.PushCurrentMap and GPS.PopCurrentMap then
    GPS:PushCurrentMap()
    return true
  end

  return false
end

local function PopCurrentMapContext(hasStoredMap)
  if hasStoredMap and GPS and GPS.PopCurrentMap then
    GPS:PopCurrentMap()
  else
    SetMapToPlayerLocation()
  end
end

local function SetMapToQuestTarget(questIndex)
  local result = SET_MAP_RESULT_FAILED

  for stepIndex = QUEST_MAIN_STEP_INDEX, GetJournalQuestNumSteps(questIndex) do
    local requireNotCompleted = true
    local conditionsExhausted = false

    while result == SET_MAP_RESULT_FAILED and not conditionsExhausted do
      for conditionIndex = 1, GetJournalQuestNumConditions(questIndex, stepIndex) do
        local tryCondition = true
        if requireNotCompleted then
          local isComplete = select(4, GetJournalQuestConditionValues(questIndex, stepIndex, conditionIndex))
          tryCondition = not isComplete
        end

        if tryCondition then
          result = SetMapToQuestCondition(questIndex, stepIndex, conditionIndex)
          if result ~= SET_MAP_RESULT_FAILED then
            break
          end
        end
      end

      if requireNotCompleted then
        requireNotCompleted = false
      else
        conditionsExhausted = true
      end
    end

    if result ~= SET_MAP_RESULT_FAILED then
      break
    end

    if IsJournalQuestStepEnding(questIndex, stepIndex) then
      result = SetMapToQuestStepEnding(questIndex, stepIndex)
      if result ~= SET_MAP_RESULT_FAILED then
        break
      end
    end
  end

  if result == SET_MAP_RESULT_FAILED then
    result = SetMapToQuestZone(questIndex)
  end

  return result
end

local function CollectQuestPinGlobals(questIndex)
  local pinManager = ZO_WorldMap_GetPinManager()
  if not pinManager or not pinManager.AddPinsToArray or not GPS or not GPS.LocalToGlobal then
    return {}, false
  end

  local pins = {}
  pinManager:AddPinsToArray(pins, "quest", questIndex)

  local targets = {}
  for _, pin in ipairs(pins) do
    local x, y = pin:GetNormalizedPosition()
    if x and y then
      local globalX, globalY = GPS:LocalToGlobal(x, y)
      if globalX and globalY then
        targets[#targets + 1] = {
          globalX = globalX,
          globalY = globalY,
        }
      end
    end
  end

  return targets, #pins > 0
end

local function RefreshQuestTargetCache(playerX, playerY)
  local questState = GetQuestTrackerState()
  local currentMapId = GetCurrentMapId()
  local previousCandidate = questState.candidate

  if not questState.questIndex or not IsValidQuestIndex(questState.questIndex) then
    questState.questIndex = FindTrackedQuestIndex()
  end

  questState.currentMapId = currentMapId
  ClearQuestRetry(questState)

  if not currentMapId or currentMapId == 0 then
    questState.candidate = previousCandidate
    questState.dirty = false
    ScheduleQuestRetry(questState)
    return
  end

  if not questState.questIndex or not IsValidQuestIndex(questState.questIndex) then
    questState.candidate = previousCandidate
    questState.dirty = false
    ScheduleQuestRetry(questState, QUEST_BOOTSTRAP_RETRY_WINDOW_MS)
    return
  end

  if not GPS or not GPS.GlobalToLocal then
    questState.candidate = previousCandidate
    questState.dirty = false
    ScheduleQuestRetry(questState)
    return
  end

  local hasStoredMap = PushCurrentMapContext()
  local mapResult = SetMapToQuestTarget(questState.questIndex)
  local globalTargets = {}
  local hasQuestPins = false

  if mapResult ~= SET_MAP_RESULT_FAILED then
    globalTargets, hasQuestPins = CollectQuestPinGlobals(questState.questIndex)
  end

  PopCurrentMapContext(hasStoredMap)

  if mapResult == SET_MAP_RESULT_FAILED then
    questState.candidate = nil
    questState.dirty = false
    return
  end

  if not hasQuestPins or #globalTargets == 0 then
    questState.candidate = previousCandidate
    questState.dirty = false
    ScheduleQuestRetry(questState)
    return
  end

  local bestX = nil
  local bestY = nil
  local bestDistance = nil

  for _, target in ipairs(globalTargets) do
    local x, y = GPS:GlobalToLocal(target.globalX, target.globalY)
    if IsLocalPositionOnCurrentMap(x, y) then
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
  else
    questState.candidate = nil
  end

  questState.dirty = false
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

  if not questState.dirty and ShouldRetryQuestRefresh(questState) then
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

  local destinationCandidate = FindDestinationCandidate(playerX, playerY)
  if destinationCandidate then
    return destinationCandidate
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

  integration.currentDistance = candidate.distance
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
  ClearQuestRetry(questState)
  ScheduleQuestRetry(questState, QUEST_BOOTSTRAP_RETRY_WINDOW_MS)

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

local function OnMapPing(_, pingEventType, pingType)
  if pingType ~= MAP_PIN_TYPE_PLAYER_WAYPOINT then
    return
  end

  if pingEventType == PING_EVENT_ADDED or pingEventType == PING_EVENT_REMOVED then
    integration:RefreshTarget()
  end
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
      text = "Optional auto-tracking for the marked destination, assisted quest, or nearby SkyShards and LoreBooks targets on the current map.",
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
      name = "Track Marked Destination",
      tooltip = "Tracks the player waypoint set with Set Destination on the current map. This source takes top priority when present.",
      getFunc = function()
        return settings.trackDestination
      end,
      setFunc = function(value)
        settings.trackDestination = value
        integration:RefreshTarget()
      end,
      default = defaults.tracker.trackDestination,
      disabled = function()
        return not IsDestinationAvailable()
      end,
      width = "half",
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
      tooltip = "Shows the managed arrow's world marker.",
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
      name = "Hide Arrow Near Target",
      tooltip = "Fades the large arrow and distance label while you are within the configured distance of the current target, reaching full transparency at the target.",
      getFunc = function()
        return settings.hideArrowNearTarget
      end,
      setFunc = function(value)
        settings.hideArrowNearTarget = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.hideArrowNearTarget,
      width = "full",
    },
    {
      type = "slider",
      name = "Hide Arrow Within Distance",
      tooltip = "Within this distance in meters, the arrow and distance label fade progressively until they reach full transparency at the target.",
      min = 1,
      max = 100,
      step = 1,
      getFunc = function()
        return settings.hideArrowNearTargetDistance
      end,
      setFunc = function(value)
        settings.hideArrowNearTargetDistance = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.hideArrowNearTargetDistance,
      disabled = function()
        return not settings.hideArrowNearTarget
      end,
      width = "full",
    },
    {
      type = "checkbox",
      name = "Hide Marker Near Target",
      tooltip = "Fades the world marker while you are within the configured distance of the current target, reaching full transparency at the target.",
      getFunc = function()
        return settings.hideMarkerNearTarget
      end,
      setFunc = function(value)
        settings.hideMarkerNearTarget = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.hideMarkerNearTarget,
      width = "full",
    },
    {
      type = "slider",
      name = "Hide Marker Within Distance",
      tooltip = "Within this distance in meters, the marker fades progressively until it reaches full transparency at the target.",
      min = 1,
      max = 100,
      step = 1,
      getFunc = function()
        return settings.hideMarkerNearTargetDistance
      end,
      setFunc = function(value)
        settings.hideMarkerNearTargetDistance = value
        ApplyVisualSettings()
      end,
      default = defaults.tracker.hideMarkerNearTargetDistance,
      disabled = function()
        return not settings.hideMarkerNearTarget
      end,
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
      name = "Marked Destination Colour",
      tooltip = "Used for the managed arrow, marker, glow, and distance text when tracking the player-set destination.",
      getFunc = function()
        local colour = settings.sourceColours[SOURCE_DESTINATION]
        return colour.r, colour.g, colour.b, colour.a
      end,
      setFunc = function(r, g, b, a)
        local colour = settings.sourceColours[SOURCE_DESTINATION]
        colour.r, colour.g, colour.b, colour.a = r, g, b, a
        if integration.currentSource == SOURCE_DESTINATION then
          ApplySourceColour(SOURCE_DESTINATION)
        end
      end,
      width = "half",
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
  EVENT_MANAGER:RegisterForEvent(INIT_EVENT, EVENT_MAP_PING, OnMapPing)
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
