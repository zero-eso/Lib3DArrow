L3DA = L3DA or {}

local TEX_WIDTH = 256
local TEX_HEIGHT = 32
local CELL_WIDTH = 20
local CELL_HEIGHT = 32

local function SetMetres(metres, distance, data)
  data.prevMetres = data.prevMetres or 0
  if data.prevMetres == metres then
    return
  end
  data.prevMetres = metres

  metres = metres < math.pow(10, data.distanceDigits) and metres or math.pow(10, data.distanceDigits) - 1
  metres = metres > 0 and metres or 0

  local str = tostring(math.floor(metres))
  local numDigits = #str

  local nSize = data.distanceScale / 100
  local nCellWidth = (1 / TEX_WIDTH) * CELL_WIDTH
  local nCellWidth2 = (1 / TEX_HEIGHT) * CELL_WIDTH
  local nCellHeight = (1 / TEX_HEIGHT) * CELL_HEIGHT
  local number, left, right, pos

  for i = 1, data.distanceDigits do
    number = tonumber(string.sub(str, i, i)) or 123

    left = nCellWidth * number
    right = nCellWidth * (number + 1)
    distance.metres[i]:SetTextureCoords(left, right, 0, 1)
    distance.metres[i]:Set3DLocalDimensions(nCellWidth2 * nSize, nCellHeight * nSize)

    pos = (i * nCellWidth2) - ((nCellWidth2 * (numDigits + 1)) * 0.5)
    distance.metres[i]:Set3DRenderSpaceOrigin(pos * nSize, 0, 0)
  end
end

function L3DA:UpdateDistance(parent, data, pData)
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
  data.distanceAlpha = data.distanceAlpha or 1

  parent.distance = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
  local distance = parent.distance
  distance:Create3DRenderSpace()

  distance.metres = {}

  for i = 1, data.distanceDigits do
    distance.metres[i] = WINDOW_MANAGER:CreateControl(nil, distance, CT_TEXTURE)
    local metres = distance.metres[i]
    metres:Create3DRenderSpace()
    local c = ZO_ColorDef:New(data.distanceColour)
    metres:SetColor(c.r, c.g, c.b, c.a)
    metres:SetAlpha(data.distanceAlpha)
    metres:SetTexture("Lib3DArrow/art/font.dds")
    metres:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)
  end
end
