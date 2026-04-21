L3DA = L3DA or {}

local BASE_DIGIT_WIDTH = 20
local BASE_LABEL_HEIGHT = 32
local LABEL_SIDE_PADDING = 12
local BASE_FONT_SIZE = 26

local function ClampMetres(metres, data)
  local maxMetres = math.pow(10, data.distanceDigits) - 1
  metres = metres < maxMetres and metres or maxMetres
  return metres > 0 and metres or 0
end

local function GetPixelScale(data)
  return data.distanceScale / 25
end

local function GetDistancePixelDimensions(data)
  local pixelScale = GetPixelScale(data)
  local width = zo_floor((((BASE_DIGIT_WIDTH * data.distanceDigits) + LABEL_SIDE_PADDING) * pixelScale) + 0.5)
  local height = zo_floor((BASE_LABEL_HEIGHT * pixelScale) + 0.5)
  return zo_max(1, width), zo_max(1, height)
end

local function GetDistanceWorldDimensions(data)
  local worldScale = data.distanceScale / 100
  local width = (((BASE_DIGIT_WIDTH * data.distanceDigits) + LABEL_SIDE_PADDING) / BASE_LABEL_HEIGHT) * worldScale
  local height = worldScale
  return width, height
end

local function GetDistanceFontString(data)
  local fontSize = data.distanceFontSize or zo_max(12, zo_floor((BASE_FONT_SIZE * GetPixelScale(data)) + 0.5))
  return string.format("%s|%d|%s", data.distanceFontFace, fontSize, data.distanceFontEffect)
end

local function ApplyDistanceStyle(distance, data)
  local pixelWidth, pixelHeight = GetDistancePixelDimensions(data)

  distance:SetDimensions(pixelWidth, pixelHeight)
  if distance.Set3DLocalDimensions then
    local worldWidth, worldHeight = GetDistanceWorldDimensions(data)
    distance:Set3DLocalDimensions(worldWidth, worldHeight)
  end
  if distance.Set3DRenderSpaceUsesDepthBuffer then
    distance:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)
  end

  if distance.label then
    local c = ZO_ColorDef:New(data.distanceColour)
    distance.label:ClearAnchors()
    distance.label:SetAnchorFill(distance)
    distance.label:SetDimensions(pixelWidth, pixelHeight)
    distance.label:SetFont(GetDistanceFontString(data))
    distance.label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    distance.label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    distance.label:SetColor(c.r, c.g, c.b, c.a)
    distance.label:SetPixelRoundingEnabled(false)
  end
end

local function SetMetres(metres, distance, data)
  metres = ClampMetres(metres, data)

  data.prevMetres = data.prevMetres or -1
  if data.prevMetres == metres then
    return
  end

  data.prevMetres = metres
  distance.label:SetText(tostring(zo_floor(metres)))
end

function L3DA:UpdateDistance(parent, data, pData)
  -- align the distance control with the camera so the label stays billboarded
  local circ = math.atan2(pData.playerY - data.targetY, data.targetX - pData.playerX) + (90 * math.pi / 180)

  parent.distance:Set3DRenderSpaceForward(pData.forwardX, pData.forwardY, pData.forwardZ)
  parent.distance:Set3DRenderSpaceRight(pData.rightX, pData.rightY, pData.rightZ)
  parent.distance:Set3DRenderSpaceUp(pData.upX, pData.upY, pData.upZ)
  parent.distance:Set3DRenderSpaceOrigin(
    pData.worldX + (data.distanceMagnitude * math.sin(circ)),
    pData.worldY + data.distanceHeight + 0.5,
    pData.worldZ + (data.distanceMagnitude * math.cos(circ))
  )

  SetMetres(data.metres, parent.distance, data)
end

function L3DA:CreateDistance(parent, data)
  data.distanceDigits = data.distanceDigits or 4
  data.distanceScale = data.distanceScale or 25
  data.distanceColour = data.distanceColour or "FFFFFF"
  data.distanceMagnitude = data.distanceMagnitude or 5
  data.distanceHeight = data.distanceHeight or 1.5
  data.distanceFontFace = data.distanceFontFace or "$(BOLD_FONT)"
  data.distanceFontEffect = data.distanceFontEffect or "thick-outline"

  parent.distance = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
  local distance = parent.distance
  distance:Create3DRenderSpace()
  distance:SetMouseEnabled(false)

  distance.label = WINDOW_MANAGER:CreateControl(nil, distance, CT_LABEL)
  local label = distance.label
  label:SetMouseEnabled(false)
  label:SetText("")

  ApplyDistanceStyle(distance, data)
end
