L3DA = L3DA or {}

local TEX_WIDTH = 256
local TEX_HEIGHT = 32
local CELL_WIDTH = 20
local CELL_HEIGHT = 32
local OUTLINE_OFFSETS = {
  { -1,  0 },
  {  1,  0 },
  {  0, -1 },
  {  0,  1 },
  { -1, -1 },
  { -1,  1 },
  {  1, -1 },
  {  1,  1 },
}

local function SetDigitTexture(control, left, right, width, height, x, y)
  control:SetTextureCoords(left, right, 0, 1)
  control:Set3DLocalDimensions(width, height)
  control:Set3DRenderSpaceOrigin(x, y, 0)
end

-- dont look at this
local function SetMetres(metres, distance, data)
  -- skip if its the same
  data.prevMetres = data.prevMetres or 0
  if data.prevMetres == metres then return end
  data.prevMetres = metres

  -- set numbers (texturecoord and texture dimension)
  metres = metres < math.pow(10, data.distanceDigits) and metres or math.pow(10, data.distanceDigits)-1
  metres = metres > 0 and metres or 0

  local str = tostring(math.floor(metres))
  local numDigits = #str

  local nSize = data.distanceScale / 100
  local nCellWidth = (1/TEX_WIDTH) * CELL_WIDTH
  local nCellWidth2 = (1/TEX_HEIGHT) * CELL_WIDTH
  local nCellHeight = (1/TEX_HEIGHT) * CELL_HEIGHT
  local outlineOffset = nSize * data.distanceOutlineThickness
  local width = nCellWidth2 * nSize
  local height = nCellHeight * nSize
  local number, left, right, pos

  for i = 1, data.distanceDigits do
    number = tonumber(string.sub(str, i, i)) or 123 -- grab a non existant cell (so it will show as empty)

    -- Only width is needed currently for getting a cell rect
    left = nCellWidth * number
    right = nCellWidth * (number + 1)

    pos = (i*nCellWidth2) - ((nCellWidth2*(numDigits+1)) * 0.5)

    if distance.metresOutline and distance.metresOutline[i] then
      for outlineIndex = 1, #OUTLINE_OFFSETS do
        local offset = OUTLINE_OFFSETS[outlineIndex]
        SetDigitTexture(
          distance.metresOutline[i][outlineIndex],
          left,
          right,
          width,
          height,
          (pos * nSize) + (offset[1] * outlineOffset),
          offset[2] * outlineOffset
        )
      end
    end

    SetDigitTexture(distance.metres[i], left, right, width, height, pos * nSize, 0)
  end
end

function L3DA:UpdateDistance(parent, data, pData)
  -- 2: Distance Label
  -- align our distance 3d control with the camera's render space so the its always facing the camera
  -- use same position as arrow but 0.5 higher
  local circ = math.atan2(pData.playerY-data.targetY, data.targetX-pData.playerX) + (90 * math.pi / 180)

  parent.distance:Set3DRenderSpaceForward(pData.forwardX, pData.forwardY, pData.forwardZ)
  parent.distance:Set3DRenderSpaceRight(pData.rightX, pData.rightY, pData.rightZ)
  parent.distance:Set3DRenderSpaceUp(pData.upX, pData.upY, pData.upZ)
  parent.distance:Set3DRenderSpaceOrigin(pData.worldX + (data.distanceMagnitude * math.sin(circ)), pData.worldY + data.distanceHeight + 0.5, pData.worldZ + (data.distanceMagnitude * math.cos(circ)))

  SetMetres(data.metres, parent.distance, data)
end

function L3DA:CreateDistance(parent, data)
  -- distance label settings/defaults
  data.distanceDigits = data.distanceDigits or 4
  data.distanceScale = data.distanceScale or 25
  data.distanceColour = data.distanceColour or "FFFFFF"
  data.distanceOutlineColour = data.distanceOutlineColour or "000000"
  data.distanceOutlineThickness = data.distanceOutlineThickness or 0.06
  data.distanceMagnitude = data.distanceMagnitude or 5
  data.distanceHeight = data.distanceHeight or 1.5

  -- Distance label
  parent.distance = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
  local distance = parent.distance
  distance:Create3DRenderSpace()

  -- create max digits texture controls
  distance.metres = {}
  distance.metresOutline = {}

  for i = 1, data.distanceDigits do
    distance.metresOutline[i] = {}

    for outlineIndex = 1, #OUTLINE_OFFSETS do
      local outline = WINDOW_MANAGER:CreateControl(nil, distance, CT_TEXTURE)
      distance.metresOutline[i][outlineIndex] = outline
      outline:Create3DRenderSpace()
      local outlineColour = ZO_ColorDef:New(data.distanceOutlineColour)
      outline:SetColor(outlineColour.r, outlineColour.g, outlineColour.b, outlineColour.a)
      outline:SetTexture("Lib3DArrow/art/font.dds")
      outline:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)
    end

    distance.metres[i] = WINDOW_MANAGER:CreateControl(nil, distance, CT_TEXTURE)
    local metres = distance.metres[i]
    metres:Create3DRenderSpace()
    local c = ZO_ColorDef:New(data.distanceColour)
    metres:SetColor(c.r, c.g, c.b, c.a)
    metres:SetTexture("Lib3DArrow/art/font.dds")
    metres:Set3DRenderSpaceUsesDepthBuffer(data.depthBuffer)
  end
end
