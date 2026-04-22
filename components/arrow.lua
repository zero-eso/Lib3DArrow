L3DA = L3DA or {}

local ARROW_TEXTURE = "Lib3DArrow/art/arrow.dds"
local GLOW_TEXTURE = "Lib3DArrow/art/glow.dds"
local DEFAULT_FAUX_3D_LAYERS = 4
local DEFAULT_FAUX_3D_THICKNESS = 0.18

local function AngleToRadians(angle)
  return angle * math.pi / 180
end

local function GetArrowColourDef(data)
  return ZO_ColorDef:New(data.arrowColour or "3F9092")
end

local function GetFaux3DLayerCount(data)
  local layers = data.arrowFaux3DLayers or DEFAULT_FAUX_3D_LAYERS
  return zo_max(1, zo_floor(layers))
end

local function GetFaux3DThickness(data)
  return data.arrowFaux3DThickness or DEFAULT_FAUX_3D_THICKNESS
end

local function GetFaux3DLayerShade(index, count)
  local progress = count > 1 and ((index - 1) / (count - 1)) or 0
  return 0.18 + (progress * 0.14)
end

function L3DA:RefreshArrowAppearance(parent, data)
  local arrow = parent.arrow
  if not arrow then
    return
  end

  local colour = GetArrowColourDef(data)
  local useFaux3D = data.arrowUseFaux3D == true
  local layerStep = GetFaux3DThickness(data) / GetFaux3DLayerCount(data)
  local frontDepth = 0

  arrow.glow:Set3DLocalDimensions(data.arrowScale, data.arrowScale)
  arrow.chevron:Set3DLocalDimensions(data.arrowScale, data.arrowScale)
  arrow.chevron:SetColor(colour.r, colour.g, colour.b, colour.a)
  arrow.glow:SetColor(colour.r, colour.g, colour.b, colour.a)

  if arrow.fauxLayers then
    local layerCount = #arrow.fauxLayers
    for index = 1, layerCount do
      local layer = arrow.fauxLayers[index]
      layer:Set3DLocalDimensions(data.arrowScale, data.arrowScale)
      layer:SetHidden(not useFaux3D)

      if useFaux3D then
        local shade = GetFaux3DLayerShade(index, layerCount)
        layer:SetColor(colour.r * shade, colour.g * shade, colour.b * shade, colour.a)
        layer:Set3DRenderSpaceOrigin(0, 0, -((layerCount - index + 1) * layerStep))
      else
        layer:Set3DRenderSpaceOrigin(0, 0, 0)
      end
    end

    if useFaux3D then
      frontDepth = -((layerCount + 1) * layerStep)
    end
  end

  arrow.chevron:Set3DRenderSpaceOrigin(0, 0, frontDepth)
  arrow.glow:Set3DRenderSpaceOrigin(0, 0, frontDepth - (useFaux3D and (layerStep * 0.5) or 0))
end

function L3DA:UpdateArrow(parent, data, pData)
  -- 1: Arrow
  -- rotate arrow to be horizontal and angle it to point at target
  local angleRadians = math.atan2(pData.playerY-data.targetY, data.targetX-pData.playerX)
  parent.arrow:Set3DRenderSpaceOrientation(AngleToRadians(90) , angleRadians, 0)

  -- use players world position to place the arrow in a circle around the player
  -- direction of arrow + 90 degree offset to place it correctly
  local circ = angleRadians + (90 * math.pi / 180)
  parent.arrow:Set3DRenderSpaceOrigin(pData.worldX + (data.arrowMagnitude * math.sin(circ)), pData.worldY + data.arrowHeight, pData.worldZ + (data.arrowMagnitude * math.cos(circ)))

  -- glowing animation
  local time = GetFrameTimeSeconds()
  parent.arrow.glow:SetAlpha(1 - math.sin(time))
end

function L3DA:CreateArrow(parent, data)
  -- arrow settings or use defaults
  data.arrowMagnitude = data.arrowMagnitude or 5
  data.arrowScale = data.arrowScale or 2
  data.arrowHeight = data.arrowHeight or 1.5
  data.arrowColour = data.arrowColour or "3F9092"
  data.arrowUseFaux3D = data.arrowUseFaux3D == true
  data.arrowFaux3DLayers = data.arrowFaux3DLayers or DEFAULT_FAUX_3D_LAYERS
  data.arrowFaux3DThickness = data.arrowFaux3DThickness or DEFAULT_FAUX_3D_THICKNESS
  data.arrowHeight = data.arrowHeight + (parent.uniqueId * 0.005)

  -- Arrow
  parent.arrow = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
  local arrow = parent.arrow
  arrow:Create3DRenderSpace()

  arrow.glow = WINDOW_MANAGER:CreateControl(nil, arrow, CT_TEXTURE)
  local glow = arrow.glow
  glow:SetTexture(GLOW_TEXTURE)
  glow:Create3DRenderSpace()
  glow:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)

  arrow.fauxLayers = {}
  for index = 1, GetFaux3DLayerCount(data) do
    local layer = WINDOW_MANAGER:CreateControl(nil, arrow, CT_TEXTURE)
    layer:Create3DRenderSpace()
    layer:SetTexture(ARROW_TEXTURE)
    layer:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)
    arrow.fauxLayers[index] = layer
  end

  arrow.chevron = WINDOW_MANAGER:CreateControl(nil, arrow, CT_TEXTURE)
  local chevron = arrow.chevron
  chevron:Create3DRenderSpace()
  chevron:SetTexture(ARROW_TEXTURE)
  chevron:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)

  self:RefreshArrowAppearance(parent, data)
end
