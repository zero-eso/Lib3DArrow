L3DA = L3DA or {}

local DEFAULT_STEM_TEXTURE = "Lib3DArrow/art/marker_stem.dds"
local GPS = LibGPS3 or LibGPS2

local function CreateMarkerPart(parent)
  local control = WINDOW_MANAGER:CreateControl(nil, parent, CT_TEXTURE)
  control:Create3DRenderSpace()
  control:Set3DRenderSpaceUsesDepthBuffer(true)
  control:Set3DRenderSpaceOrigin(0, 0, 0)
  return control
end

local function GetMarkerColour(data)
  return ZO_ColorDef:New(data.markerColour or "3F9092")
end

local function GetScaledValue(data, value)
  return value * (data.markerScale or 1)
end

function L3DA:RefreshMarkerAppearance(parent, data)
  if not parent.marker then
    return
  end

  data.markerColour = data.markerColour or "3F9092"
  data.markerScale = data.markerScale or 1
  data.markerStemTexture = data.markerStemTexture or DEFAULT_STEM_TEXTURE
  data.markerIconTexture = data.markerIconTexture or data.markerStemTexture
  data.markerStemWidth = data.markerStemWidth or 2.45
  data.markerStemHeight = data.markerStemHeight or 4.5
  data.markerStemOffsetY = data.markerStemOffsetY or 2.0
  data.markerIconWidth = data.markerIconWidth or 2.2
  data.markerIconHeight = data.markerIconHeight or 2.2
  data.markerIconOffsetY = data.markerIconOffsetY or 5.6
  data.markerStemAlphaScale = data.markerStemAlphaScale == nil and 0.6 or data.markerStemAlphaScale
  data.markerIconAlphaScale = data.markerIconAlphaScale == nil and 1 or data.markerIconAlphaScale
  data.markerAlpha = data.markerAlpha or 1

  local colour = GetMarkerColour(data)
  local alpha = colour.a or 1

  local stem = parent.marker.stem
  local stemHidden = data.markerStemHidden == true
    or data.markerStemWidth <= 0
    or data.markerStemHeight <= 0
    or data.markerAlpha <= 0
  stem:SetTexture(data.markerStemTexture)
  stem:SetColor(colour.r, colour.g, colour.b, alpha)
  stem:SetAlpha(data.markerStemAlphaScale * data.markerAlpha)
  stem:Set3DLocalDimensions(GetScaledValue(data, data.markerStemWidth), GetScaledValue(data, data.markerStemHeight))
  stem:Set3DRenderSpaceOrigin(0, GetScaledValue(data, data.markerStemOffsetY), 0)
  stem:SetHidden(stemHidden)

  local icon = parent.marker.icon
  local iconHidden = data.markerIconHidden == true
    or data.markerIconWidth <= 0
    or data.markerIconHeight <= 0
    or data.markerAlpha <= 0
  icon:SetTexture(data.markerIconTexture)
  icon:SetColor(colour.r, colour.g, colour.b, alpha)
  icon:SetAlpha(data.markerIconAlphaScale * data.markerAlpha)
  icon:Set3DLocalDimensions(GetScaledValue(data, data.markerIconWidth), GetScaledValue(data, data.markerIconHeight))
  icon:Set3DRenderSpaceOrigin(0, GetScaledValue(data, data.markerIconOffsetY), 0)
  icon:SetHidden(iconHidden)
end

function L3DA:UpdateMarker(parent, data, pData)
  local heading = GetPlayerCameraHeading and GetPlayerCameraHeading() or 0
  parent.marker:Set3DRenderSpaceOrientation(0, heading, 0)

  if GPS and GPS.GlobalToWorld then
    local worldX, worldY, worldZ = GPS:GlobalToWorld(data.targetX, data.targetY)
    if worldX and worldY and worldZ then
      local renderX, renderY, renderZ = WorldPositionToGuiRender3DPosition(worldX, worldY, worldZ)
      if renderX and renderY and renderZ then
        parent.marker:Set3DRenderSpaceOrigin(renderX, renderY, renderZ)
        return
      end
    end
  end

  local circ = math.atan2(pData.playerY - data.targetY, data.targetX - pData.playerX) + (90 * math.pi / 180)
  parent.marker:Set3DRenderSpaceOrigin(
    pData.worldX + (data.metres * math.sin(circ)),
    pData.worldY,
    pData.worldZ + (data.metres * math.cos(circ))
  )
end

function L3DA:CreateMarker(parent, data)
  data.markerColour = data.markerColour or "3F9092"
  data.markerScale = data.markerScale or 1

  parent.marker = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
  local marker = parent.marker
  marker:Create3DRenderSpace()
  marker:Set3DRenderSpaceOrigin(0, 0, 0)

  marker.stem = CreateMarkerPart(marker)
  marker.icon = CreateMarkerPart(marker)

  self:RefreshMarkerAppearance(parent, data)
end
