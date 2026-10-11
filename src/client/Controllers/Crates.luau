-- Kisten-Shop + die befriedigende 3D-Oeffnungs-Sequenz in einer Schatz-Grotte:
-- Die Truhe faellt auf einen alten Steinsockel, man tippt 3x drauf, sie bekommt leuchtende
-- Risse und steigt in der Seltenheit auf. Ab MYTHISCH verwandelt sie sich dramatisch, dann
-- springt der Deckel auf, eine Lichtsaeule schiesst hoch und die Faehigkeit steigt heraus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local VFXController = require(Controllers:WaitForChild("VFXController"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))
local VFX = Client:WaitForChild("VFX")
local Effects = require(VFX:WaitForChild("Effects"))
local CrateModel = require(VFX:WaitForChild("CrateModel"))

local CratesController = {}

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local TEX = Effects.Textures
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CAM_BIND = "NovaCrateCam"
local FACE_CAMERA = CFrame.Angles(0, math.pi, 0) -- Truhen-Vorderseite (-Z) zur Kamera (+Z) drehen

local rng = Random.new()

local window: UI.Window
local cardsHolder: Frame
local walletLabel: TextLabel? = nil
local viewportCrates: { any } = {}
local cardsKey = ""
local viewportConn: RBXScriptConnection? = nil
local busy = false

-- =============================================================================
-- Kleine UI-Helfer
-- =============================================================================

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	return UI.Stroke(parent, color or C.Ink, thickness, 0)
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(4000, 400))
	end)
	if ok and typeof(v) == "Vector2" then
		return v.X
	end
	return #text * size * 0.6
end

-- Gezeichnete Muenze (gleicher Stil wie im HUD): Rand + goldene Flaeche + Innenring + Glanz
local function drawCoin(parent: Instance, size: number, position: UDim2, z: number): Frame
	local edge = math.max(2, math.floor(size * 0.09))
	local holder = Make("Frame", {
		Name = "Coin",
		BackgroundTransparency = 1,
		Position = position,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
		Parent = parent,
	})
	local rim = Make("Frame", {
		Name = "Rim",
		BackgroundColor3 = C.GoldDark,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, edge),
		Size = UDim2.new(1, 0, 1, -edge),
		ZIndex = z,
		Parent = holder,
	})
	UI.Round(rim)
	stroke(rim, math.max(1.5, size * 0.055))
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = C.Coin,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -edge),
		ZIndex = z + 1,
		Parent = holder,
	})
	UI.Round(face)
	stroke(face, math.max(1.5, size * 0.055))
	local inner = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(240, 172, 34),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.58),
		ZIndex = z + 2,
		Parent = face,
	})
	UI.Round(inner)
	UI.Stroke(inner, C.GoldDark, math.max(1, size * 0.045), 0)
	local glint = Make("Frame", {
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.2, 0.17),
		Size = UDim2.fromScale(0.2, 0.13),
		Rotation = -35,
		ZIndex = z + 3,
		Parent = face,
	})
	UI.Round(glint)
	return holder
end

-- 3D-Schild mit Lippe (Seltenheits-Band, NEW!, Karten-Etiketten)
type TagProps = {
	Text: string,
	Fill: Color3,
	Lip: Color3?,
	Font: Enum.Font?,
	TextSize: number?,
	Height: number?,
	PadX: number?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Rotation: number?,
	ZIndex: number?,
	Parent: Instance?,
}

local function makeTag(props: TagProps): Frame
	local textSize = props.TextSize or 16
	local font = props.Font or F.Heading
	local h = props.Height or 30
	local lipH = math.max(3, math.floor(h * 0.12))
	local w = math.ceil(textWidth(props.Text, textSize, font)) + (props.PadX or 24)
	local lipColor = props.Lip or Theme.Darken(props.Fill, 0.4)
	local z = props.ZIndex or 1
	local radius = math.floor(h * 0.3)
	local holder = Make("Frame", {
		Name = "Tag",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h + lipH),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Rotation = props.Rotation or 0,
		ZIndex = z,
	})
	local lip = Make("Frame", {
		Name = "Lip",
		BackgroundColor3 = lipColor,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, lipH),
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
		Parent = holder,
	})
	UI.Corner(lip, radius)
	stroke(lip, 2.5)
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = props.Fill,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		ZIndex = z + 1,
		Parent = holder,
	})
	UI.Corner(face, radius)
	stroke(face, 2.5)
	UI.Shade(face)
	UI.Text({
		Name = "Label",
		Text = props.Text,
		Font = font,
		TextSize = textSize,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 2,
		Stroke = 2,
		StrokeColor = Theme.Darken(lipColor, 0.45),
		Parent = face,
	})
	holder.Parent = props.Parent
	return holder
end

-- Preis-Knopf: Muenze + Zahl mittig
local function setPriceLabel(button: GuiObject, text: string, textSize: number, coinSize: number)
	local face = button:FindFirstChild("Face")
	local label = face and face:FindFirstChild("Label")
	if not face or not label then
		return
	end
	local lbl = label :: TextLabel
	lbl.Text = text
	local gap = 6
	local total = coinSize + gap + textWidth(text, textSize, F.Heading)
	lbl.Position = UDim2.fromOffset(math.floor((coinSize + gap) / 2), 0)
	drawCoin(face, coinSize, UDim2.new(0.5, -math.floor(total / 2), 0.5, -math.floor(coinSize / 2)), (face :: GuiObject).ZIndex + 1)
end

-- Knopf mit Text links und Preis (Muenze + Zahl) rechts, z.B. "AGAIN   (o) 400"
local function addPriceRight(button: GuiObject, price: number, textSize: number)
	local face = button:FindFirstChild("Face")
	local label = face and face:FindFirstChild("Label")
	if not face or not label then
		return
	end
	local f = face :: GuiObject
	local lbl = label :: TextLabel
	local priceText = UI.Format(price)
	local pw = math.ceil(textWidth(priceText, textSize, F.Heading))
	local coin = math.floor(textSize * 1.05)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Position = UDim2.fromOffset(18, 0)
	lbl.Size = UDim2.new(1, -18, 1, 0)
	drawCoin(f, coin, UDim2.new(1, -(16 + pw + 6 + coin), 0.5, -math.floor(coin / 2)), f.ZIndex + 1)
	UI.Text({
		Name = "Price",
		Text = priceText,
		Font = F.Heading,
		TextSize = textSize,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.new(0, pw + 4, 1, 0),
		ZIndex = f.ZIndex + 1,
		Stroke = 2,
		StrokeColor = Theme.Darken(C.GoldDark, 0.45),
		Parent = f,
	})
end

-- Niedrigste / hoechste Seltenheitsstufe in einer Kiste
local function crateTiers(def: any): (number, number)
	local lo, hi = math.huge, 0
	for rid in def.Weights do
		local t = Rarities.Get(rid).Tier
		lo = math.min(lo, t)
		hi = math.max(hi, t)
	end
	if lo == math.huge then
		lo = 1
	end
	return lo, hi
end

local function fmtPct(p: number): string
	if p >= 10 or math.abs(p - math.floor(p + 0.5)) < 0.05 then
		return string.format("%d%%", math.floor(p + 0.5))
	end
	return string.format("%.1f%%", p)
end

local function profileCoins(): number
	local p = State.Profile
	return if p then tonumber(p.Coins) or 0 else 0
end

-- =============================================================================
-- Kisten-Fenster
-- =============================================================================

local CARD_W, CARD_H = 232, 520
local VP_DIST, VP_HEIGHT = 9.4, 4.3
local VP_LOOK = Vector3.new(0, 1.65, 0)

local function updateWallet()
	local label = walletLabel
	if label then
		label.Text = UI.Format(profileCoins())
	end
end

local function buildCard(def: any, order: number)
	local theme = CrateModel.ThemeFor(def)
	local accent: Color3 = theme.Gem
	local slot = Make("Frame", {
		Name = def.Id,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CARD_W, CARD_H + 8),
		LayoutOrder = order,
		Parent = cardsHolder,
	})
	local shadow = Make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Parent = slot,
	})
	UI.Corner(shadow, 16)
	local card = UI.Card({
		Name = "Card",
		Radius = 16,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Parent = slot,
	})

	-- Schaukasten mit drehender 3D-Truhe
	local show = UI.Inset({
		Name = "Showcase",
		Color = Theme.Darken(accent, 0.72),
		Radius = 12,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 176),
		Parent = card,
	})
	UI.Gradient(show, ColorSequence.new(WHITE, Color3.fromRGB(150, 150, 150)), 90)
	local spot = Make("Frame", {
		Name = "Spot",
		BackgroundColor3 = Theme.Darken(accent, 0.45),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(150, 150),
		Parent = show,
	})
	UI.Round(spot)
	local vp, cam = UI.Viewport({ Size = UDim2.fromScale(1, 1), Parent = show, FieldOfView = 34 })
	vp.ZIndex = 2
	vp.Ambient = Color3.fromRGB(150, 146, 142)
	vp.LightColor = Color3.fromRGB(255, 244, 226)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.9)
	local crate = CrateModel.Build(def, vp, 1)
	crate:SetCFrame(FACE_CAMERA)
	-- kleiner Steinsockel mit Moos
	Make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 6.2, 6.2),
		CFrame = CFrame.new(0, -0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(132, 124, 112),
		Anchored = true,
		Parent = vp,
	})
	Make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 6.9, 6.9),
		CFrame = CFrame.new(0, -0.62, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(88, 138, 62),
		Anchored = true,
		Parent = vp,
	})
	local entry = { Crate = crate, Camera = cam, Phase = order * 1.9, SpinStart = nil :: number? }
	cam.CFrame = CFrame.lookAt(Vector3.new(0, VP_HEIGHT, VP_DIST), VP_LOOK)
	table.insert(viewportCrates, entry)

	-- Etikett oben links
	local lo = crateTiers(def)
	if def.Free then
		makeTag({ Text = "FREE GIFT", Fill = C.Green, TextSize = 14, Height = 26, PadX = 20, Position = UDim2.fromOffset(8, 8), ZIndex = 3, Parent = show })
	elseif lo >= 2 then
		local r = Rarities.ByTier(lo)
		makeTag({ Text = r.Name .. "+", Fill = r.Color, TextSize = 14, Height = 26, PadX = 20, Position = UDim2.fromOffset(8, 8), ZIndex = 3, Parent = show })
	end

	-- Name + Beschreibung
	local title = UI.Text({
		Name = "Title",
		Text = string.upper(def.Name),
		Font = F.Heading,
		TextScaled = true,
		TextWrapped = false,
		Position = UDim2.fromOffset(10, 196),
		Size = UDim2.new(1, -20, 0, 28),
		Stroke = 2,
		Parent = card,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 14, Parent = title })
	UI.Text({
		Name = "Description",
		Text = def.Description,
		Font = F.Body,
		TextSize = 13,
		TextColor3 = C.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(14, 228),
		Size = UDim2.new(1, -28, 0, 40),
		Parent = card,
	})

	-- Chancen: Verteilungsbalken + Zeilen
	local odds = Crates.GetOdds(def)
	local oddsBox = UI.Inset({
		Name = "Odds",
		Radius = 10,
		Position = UDim2.fromOffset(12, 274),
		Size = UDim2.new(1, -24, 0, 166),
		Parent = card,
	})
	UI.Text({
		Text = "DROP RATES",
		Font = F.Heading,
		TextSize = 12,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(10, 5),
		Size = UDim2.new(1, -20, 0, 16),
		Parent = oddsBox,
	})
	local bar = Make("Frame", {
		Name = "Bar",
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(10, 24),
		Size = UDim2.new(1, -20, 0, 10),
		Parent = oddsBox,
	})
	UI.Corner(bar, 3)
	stroke(bar, 2)
	UI.List(bar, true, 0)
	local rows = Make("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -46),
		Parent = oddsBox,
	})
	UI.List(rows, false, 2)
	for _, r in Rarities.List do
		local pct = odds[r.Id]
		if pct and r.Id ~= "Exclusive" then
			Make("Frame", {
				BackgroundColor3 = r.Color,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(pct / 100, 1),
				LayoutOrder = r.Tier,
				Parent = bar,
			})
			local row = Make("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 15),
				LayoutOrder = r.Tier,
				Parent = rows,
			})
			local chip = Make("Frame", {
				BackgroundColor3 = r.Color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 1, 0.5, 0),
				Size = UDim2.fromOffset(10, 10),
				Parent = row,
			})
			UI.Corner(chip, 3)
			stroke(chip, 1.5)
			UI.Text({
				Text = r.Name,
				Font = F.Heading,
				TextSize = 13,
				TextColor3 = Theme.Lighten(r.Color, 0.15),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = false,
				Position = UDim2.fromOffset(18, 0),
				Size = UDim2.new(0.7, -18, 1, 0),
				Parent = row,
			})
			UI.Text({
				Text = fmtPct(pct),
				Font = F.Heading,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextWrapped = false,
				Position = UDim2.fromScale(0.6, 0),
				Size = UDim2.fromScale(0.4, 1),
				Parent = row,
			})
		end
	end

	-- Kaufen
	local button = UI.Button({
		Name = "Buy",
		Text = if def.Free then "FREE" else UI.Format(def.Price),
		Style = "Gold",
		Size = UDim2.new(1, -24, 0, 56),
		Position = UDim2.new(0, 12, 1, -68),
		TextSize = 26,
		Shine = def.Free == true,
		Parent = card,
	})
	if not def.Free then
		setPriceLabel(button, UI.Format(def.Price), 26, 28)
	end
	button.Activated:Connect(function()
		CratesController.Purchase(def.Id, button)
	end)

	-- Hover: Karte hebt sich, Truhe dreht sich einmal
	card.MouseEnter:Connect(function()
		UI.Tween(card, 0.15, { Position = UDim2.fromOffset(0, -6) }, Enum.EasingStyle.Quad)
		if not entry.SpinStart then
			entry.SpinStart = os.clock()
		end
	end)
	card.MouseLeave:Connect(function()
		UI.Tween(card, 0.2, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quad)
	end)
end

local function visibleCrates(): { any }
	local profile = State.Profile
	local list = {}
	for _, def in Crates.List do
		if def.Free then
			if profile and profile.FreeCrate then
				table.insert(list, def)
			end
		elseif not def.Hidden then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

local function rebuildCards(force: boolean?)
	local list = visibleCrates()
	local ids = {}
	for _, d in list do
		table.insert(ids, d.Id)
	end
	local key = table.concat(ids, ",")
	if key == cardsKey and not force then
		return
	end
	cardsKey = key
	table.clear(viewportCrates)
	for _, child in cardsHolder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, def in list do
		buildCard(def, i)
	end
end

-- Vorschau-Truhen: Kamera schwenkt sanft hin und her, beim Hover dreht sich die Truhe
local function animateViewports()
	local t = os.clock()
	for _, v in viewportCrates do
		local th = math.sin(t * 0.5 + v.Phase) * 0.6
		local pos = Vector3.new(math.sin(th) * VP_DIST, VP_HEIGHT + math.sin(t * 0.9 + v.Phase) * 0.12, math.cos(th) * VP_DIST)
		v.Camera.CFrame = CFrame.lookAt(pos, VP_LOOK)
		local spinStart = v.SpinStart
		if spinStart then
			local a = (t - spinStart) / 0.75
			if a >= 1 then
				v.SpinStart = nil
				v.Crate:SetCFrame(FACE_CAMERA)
			else
				local e = 1 - (1 - a) ^ 3
				local hop = math.sin(math.clamp(a * 1.4, 0, 1) * math.pi) * 0.7
				v.Crate:SetCFrame(CFrame.new(0, hop, 0) * FACE_CAMERA * CFrame.Angles(0, e * math.pi * 2, 0))
			end
		end
	end
end

local function setViewportsAnimating(on: boolean)
	local conn = viewportConn
	if conn then
		conn:Disconnect()
		viewportConn = nil
	end
	if on then
		viewportConn = RunService.RenderStepped:Connect(animateViewports)
	end
end

function CratesController.OpenWindow()
	if busy or State.InCrateOpening then
		return
	end
	rebuildCards()
	updateWallet()
	window:Open()
end

-- =============================================================================
-- Die Buehne: eine warme Schatz-Grotte mit Steinsockel, Ruinenbogen und Fackeln
-- =============================================================================

local stage: any = nil

local ROCK_COLORS = {
	Color3.fromRGB(112, 102, 92),
	Color3.fromRGB(98, 90, 82),
	Color3.fromRGB(124, 112, 98),
	Color3.fromRGB(88, 82, 78),
}

local function buildStage()
	if stage then
		-- geparkte Grotte wieder in die Welt holen (falls sie zerstoert wurde: neu bauen)
		local folder = stage.Folder
		local ok = pcall(function()
			folder.Parent = Effects.Folder
		end)
		if ok and folder.Parent then
			return stage
		end
		stage = nil
	end
	local O: Vector3 = Config.World.CrateStage
	local P = O + Vector3.new(0, 1.6, 0) -- Oberkante Sockel
	local folder = Make("Folder", { Name = "CrateGrotto", Parent = Effects.Folder })
	local srng = Random.new(1337)
	local fires = {}
	local emitters: { ParticleEmitter } = {}

	local function part(props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.Rock
		if props.Shape then
			p.Shape = props.Shape
		end
		for k, v in props do
			if k ~= "Shape" then
				(p :: any)[k] = v
			end
		end
		p.Parent = folder
		return p
	end
	-- stehender Zylinder (Achse = Y)
	local function cyl(center: Vector3, height: number, diameter: number, props: { [string]: any }): Part
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(height, diameter, diameter)
		props.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		return part(props)
	end
	local function rockColor(): Color3
		return ROCK_COLORS[srng:NextInteger(1, #ROCK_COLORS)]
	end
	local function ring(radius: number, angle: number, y: number): Vector3
		return O + Vector3.new(math.sin(angle) * radius, y, math.cos(angle) * radius)
	end

	-- Feuer: heller Kern -> orange Flammen -> dunkler Rauch + Glut, flackerndes Licht
	local function addFire(pos: Vector3, size: number, range: number, brightness: number)
		local anchor = part({ Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos), Transparency = 1 })
		local att = Make("Attachment", { Parent = anchor })
		table.insert(
			emitters,
			Effects.Emitter(att, {
				Texture = TEX.Fire,
				Enabled = false,
				Rate = 22,
				Color = Effects.Seq(Color3.fromRGB(255, 246, 204), Color3.fromRGB(255, 186, 76), Color3.fromRGB(255, 118, 40)),
				LightEmission = 1,
				Size = Effects.NSeq(0.9 * size, 0.45 * size, 0),
				Transparency = Effects.NSeq(0.15, 0.35, 1),
				Lifetime = NumberRange.new(0.35, 0.6),
				Speed = NumberRange.new(1.5, 3),
				SpreadAngle = Vector2.new(8, 8),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 4, 0),
				RotSpeed = NumberRange.new(-60, 60),
			})
		)
		table.insert(
			emitters,
			Effects.Emitter(att, {
				Texture = TEX.Fire,
				Enabled = false,
				Rate = 16,
				Color = Effects.Seq(Color3.fromRGB(255, 168, 60), Color3.fromRGB(230, 88, 30), Color3.fromRGB(140, 36, 18)),
				LightEmission = 0.85,
				Size = Effects.NSeq(1.3 * size, 0.7 * size, 0),
				Transparency = Effects.NSeq(0.35, 0.55, 1),
				Lifetime = NumberRange.new(0.5, 0.85),
				Speed = NumberRange.new(2, 3.5),
				SpreadAngle = Vector2.new(14, 14),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 3, 0),
				RotSpeed = NumberRange.new(-50, 50),
			})
		)
		table.insert(
			emitters,
			Effects.Emitter(att, {
				Texture = TEX.Smoke,
				Enabled = false,
				Rate = 5,
				Color = ColorSequence.new(Color3.fromRGB(46, 40, 36)),
				LightEmission = 0,
				LightInfluence = 0.8,
				Size = Effects.NSeq(0.8 * size, 2.6 * size),
				Transparency = Effects.NSeq(0.65, 1),
				Lifetime = NumberRange.new(1.4, 2.2),
				Speed = NumberRange.new(2, 3.5),
				SpreadAngle = Vector2.new(10, 10),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 1.5, 0),
			})
		)
		table.insert(
			emitters,
			Effects.Emitter(att, {
				Texture = TEX.Sparks,
				Enabled = false,
				Rate = 4,
				Color = Effects.Seq(Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 120, 40)),
				LightEmission = 1,
				Size = Effects.NSeq(0.13 * size, 0),
				Transparency = Effects.NSeq(0, 1),
				Lifetime = NumberRange.new(0.8, 1.4),
				Speed = NumberRange.new(2.5, 5),
				SpreadAngle = Vector2.new(25, 25),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 2, 0),
				Drag = 1,
			})
		)
		local light = Make("PointLight", {
			Color = Color3.fromRGB(255, 150, 72),
			Range = range,
			Brightness = brightness,
			Shadows = false,
			Parent = anchor,
		})
		table.insert(fires, { Light = light, Base = brightness, Seed = srng:NextNumber(0, 100) })
	end

	-- Boden ---------------------------------------------------------------------
	part({
		Size = Vector3.new(80, 4, 80),
		CFrame = CFrame.new(O - Vector3.new(0, 2, 0)),
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(96, 80, 62),
		CanCollide = true,
	})
	cyl(O + Vector3.new(0, 0.1, 0), 0.24, 19, { Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(126, 118, 106), CanCollide = true })
	for _ = 1, 9 do
		local a = srng:NextNumber(0, math.pi * 2)
		cyl(ring(srng:NextNumber(11, 18), a, 0.05), 0.14, srng:NextNumber(4, 8), {
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(82, 124, 56):Lerp(Color3.fromRGB(110, 146, 62), srng:NextNumber()),
		})
	end
	for _ = 1, 16 do
		local sz = srng:NextNumber(0.5, 1.6)
		part({
			Size = Vector3.new(sz * srng:NextNumber(0.8, 1.4), sz * 0.6, sz),
			CFrame = CFrame.new(ring(srng:NextNumber(10, 19), srng:NextNumber(0, math.pi * 2), sz * 0.2))
				* CFrame.Angles(srng:NextNumber(-0.3, 0.3), srng:NextNumber(0, 6.3), srng:NextNumber(-0.3, 0.3)),
			Material = Enum.Material.Slate,
			Color = rockColor(),
		})
	end

	-- Steinsockel (zwei Stufen) mit Moos --------------------------------------------
	cyl(O + Vector3.new(0, 0.5, 0), 0.8, 9.2, { Material = Enum.Material.Slate, Color = Color3.fromRGB(116, 110, 102), CanCollide = true, CastShadow = true })
	cyl(O + Vector3.new(0, 1.22, 0), 0.66, 7.2, { Material = Enum.Material.Slate, Color = Color3.fromRGB(140, 132, 120), CanCollide = true, CastShadow = true })
	cyl(O + Vector3.new(0, 1.575, 0), 0.05, 6.6, { Material = Enum.Material.Slate, Color = Color3.fromRGB(158, 150, 136), CanCollide = true })
	for _ = 1, 9 do
		local pos = ring(4.5, srng:NextNumber(0, math.pi * 2), 0.86)
		part({
			Size = Vector3.new(srng:NextNumber(0.9, 1.8), 0.2, 0.7),
			CFrame = CFrame.lookAt(pos, Vector3.new(O.X, pos.Y, O.Z)) * CFrame.Angles(math.rad(12), 0, 0),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(84, 130, 58),
		})
	end

	-- Ruinenbogen hinter dem Sockel ---------------------------------------------
	local archZ = -11
	for _, x in { -8.5, 8.5 } do
		local base = O + Vector3.new(x, 0, archZ)
		part({ Size = Vector3.new(3.6, 1.2, 3.6), CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)), Material = Enum.Material.Slate, Color = Color3.fromRGB(120, 112, 100), CastShadow = true })
		part({
			Size = Vector3.new(2.6, 9, 2.6),
			CFrame = CFrame.new(base + Vector3.new(0, 5.7, 0)) * CFrame.Angles(0, 0, math.rad(if x > 0 then -1 else 0.8)),
			Material = Enum.Material.Cobblestone,
			Color = Color3.fromRGB(146, 138, 124),
			CastShadow = true,
		})
		part({ Size = Vector3.new(3.4, 1, 3.4), CFrame = CFrame.new(base + Vector3.new(0, 10.6, 0)), Material = Enum.Material.Slate, Color = Color3.fromRGB(120, 112, 100), CastShadow = true })
		-- Fackel vorne am Pfeiler
		local wz = archZ + 1.3
		local fp = O + Vector3.new(x, 6.6, wz + 0.7)
		part({ Size = Vector3.new(0.45, 0.25, 0.8), CFrame = CFrame.new(O + Vector3.new(x, 5.5, wz + 0.35)), Material = Enum.Material.Metal, Color = Color3.fromRGB(52, 50, 52) })
		part({
			Size = Vector3.new(0.3, 1.5, 0.3),
			CFrame = CFrame.new(O + Vector3.new(x, 5.95, wz + 0.5)) * CFrame.Angles(math.rad(14), 0, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(92, 62, 40),
		})
		part({ Size = Vector3.new(0.42, 0.38, 0.42), CFrame = CFrame.new(fp - Vector3.new(0, 0.12, 0)), Material = Enum.Material.Fabric, Color = Color3.fromRGB(64, 44, 32) })
		addFire(fp + Vector3.new(0, 0.12, 0), 0.65, 16, 1.4)
	end
	part({
		Size = Vector3.new(21.5, 2.2, 3.2),
		CFrame = CFrame.new(O + Vector3.new(0, 12.2, archZ)) * CFrame.Angles(0, 0, math.rad(1.2)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(134, 126, 112),
		CastShadow = true,
	})
	part({
		Size = Vector3.new(19.5, 0.35, 3.4),
		CFrame = CFrame.new(O + Vector3.new(0, 13.45, archZ)) * CFrame.Angles(0, 0, math.rad(1.2)),
		Material = Enum.Material.LeafyGrass,
		Color = Color3.fromRGB(78, 122, 54),
	})
	for i = 1, 7 do
		local x = -9 + (i - 1) * 3 + srng:NextNumber(-0.8, 0.8)
		local len = srng:NextNumber(2, 4.5)
		part({
			Size = Vector3.new(0.22, len, 0.22),
			CFrame = CFrame.new(O + Vector3.new(x, 11.1 - len / 2, archZ + 1.55)),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromRGB(70, 116, 50),
		})
	end

	-- Feuerschalen links und rechts vom Sockel -----------------------------------
	for _, x in { -6.6, 6.6 } do
		local b = O + Vector3.new(x, 0, -1.2)
		cyl(b + Vector3.new(0, 1.5, 0), 3.0, 1.3, { Material = Enum.Material.Slate, Color = Color3.fromRGB(110, 104, 96), CastShadow = true })
		cyl(b + Vector3.new(0, 3.2, 0), 0.5, 2.3, { Material = Enum.Material.Metal, Color = Color3.fromRGB(58, 56, 58) })
		cyl(b + Vector3.new(0, 3.48, 0), 0.08, 1.9, { Material = Enum.Material.CrackedLava, Color = Color3.fromRGB(210, 96, 40) })
		addFire(b + Vector3.new(0, 3.62, 0), 1.25, 20, 1.8)
	end

	-- Schaetze, Faesser, Holzkiste -------------------------------------------------
	local gold = Color3.fromRGB(246, 190, 66)
	for _, spot in { Vector3.new(-4.3, 0, 3.4), Vector3.new(4.7, 0, 2.3), Vector3.new(-3.2, 0, -4.8) } do
		local base = O + spot
		cyl(base + Vector3.new(0, 0.34, 0), 0.26, 1.8, { Material = Enum.Material.Metal, Color = Theme.Darken(gold, 0.12) })
		for _ = 1, 5 do
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.09, 0.6, 0.6),
				CFrame = CFrame.new(base + Vector3.new(srng:NextNumber(-0.9, 0.9), 0.52 + srng:NextNumber(0, 0.18), srng:NextNumber(-0.9, 0.9)))
					* CFrame.Angles(srng:NextNumber(-0.5, 0.5), srng:NextNumber(0, 6), math.rad(90) + srng:NextNumber(-0.5, 0.5)),
				Material = Enum.Material.Metal,
				Color = gold,
			})
		end
	end
	for _, b in { Vector3.new(-13.5, 0, -6), Vector3.new(-11.3, 0, -7.8) } do
		local base = O + b
		cyl(base + Vector3.new(0, 1.5, 0), 3, 2.4, { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(128, 86, 54), CastShadow = true })
		for _, y in { 0.5, 2.5 } do
			cyl(base + Vector3.new(0, y, 0), 0.18, 2.5, { Material = Enum.Material.Metal, Color = Color3.fromRGB(64, 62, 64) })
		end
	end
	part({
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(O + Vector3.new(12.6, 1.5, -6.8)) * CFrame.Angles(0, math.rad(22), 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 104, 62),
		CastShadow = true,
	})
	part({
		Size = Vector3.new(1.9, 1.9, 1.9),
		CFrame = CFrame.new(O + Vector3.new(12.3, 3.95, -6.6)) * CFrame.Angles(0, math.rad(-8), 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(138, 94, 56),
		CastShadow = true,
	})

	-- Hoehlenwaende, Felsbrocken, Decke ---------------------------------------------
	local SLABS = 18
	for i = 0, SLABS - 1 do
		local a = (i / SLABS) * math.pi * 2 + srng:NextNumber(-0.05, 0.05)
		local pos = ring(25 + srng:NextNumber(-1.5, 1.5), a, 13)
		part({
			Size = Vector3.new(srng:NextNumber(12, 16), srng:NextNumber(30, 36), srng:NextNumber(7, 10)),
			CFrame = CFrame.lookAt(pos, Vector3.new(O.X, pos.Y, O.Z)) * CFrame.Angles(math.rad(-srng:NextNumber(4, 12)), 0, math.rad(srng:NextNumber(-6, 6))),
			Material = Enum.Material.Rock,
			Color = rockColor(),
			CastShadow = true,
		})
	end
	for i = 0, 15 do
		local sz = srng:NextNumber(4, 8)
		part({
			Size = Vector3.new(sz * srng:NextNumber(0.9, 1.4), sz * srng:NextNumber(0.6, 1), sz),
			CFrame = CFrame.new(ring(20 + srng:NextNumber(-1.5, 1.5), (i / 16) * math.pi * 2 + srng:NextNumber(-0.15, 0.15), sz * 0.25))
				* CFrame.Angles(srng:NextNumber(-0.4, 0.4), srng:NextNumber(0, 6.3), srng:NextNumber(-0.4, 0.4)),
			Material = Enum.Material.Rock,
			Color = rockColor(),
			CastShadow = true,
		})
	end
	part({ Size = Vector3.new(76, 6, 76), CFrame = CFrame.new(O + Vector3.new(0, 30, 0)), Material = Enum.Material.Rock, Color = Color3.fromRGB(76, 70, 66), CastShadow = true })
	for _ = 1, 12 do
		local top = ring(srng:NextNumber(9, 21), srng:NextNumber(0, math.pi * 2), 27.5)
		local len = srng:NextNumber(4, 9)
		local w = srng:NextNumber(1.6, 3.2)
		local tilt = CFrame.Angles(srng:NextNumber(-0.15, 0.15), srng:NextNumber(0, 6), srng:NextNumber(-0.15, 0.15))
		part({ Size = Vector3.new(w, len, w), CFrame = CFrame.new(top - Vector3.new(0, len / 2, 0)) * tilt, Material = Enum.Material.Rock, Color = rockColor() })
		part({ Size = Vector3.new(w * 0.55, len * 0.6, w * 0.55), CFrame = CFrame.new(top - Vector3.new(0, len * 1.2, 0)) * tilt, Material = Enum.Material.Rock, Color = rockColor() })
	end
	-- dichte Aussenhuelle, damit kein Tageslicht hereinfaellt
	for _, d in { Vector3.new(0, 0, -36), Vector3.new(0, 0, 36), Vector3.new(-36, 0, 0), Vector3.new(36, 0, 0) } do
		part({
			Size = if d.X ~= 0 then Vector3.new(2, 48, 74) else Vector3.new(74, 48, 2),
			CFrame = CFrame.new(O + d + Vector3.new(0, 18, 0)),
			Material = Enum.Material.Rock,
			Color = Color3.fromRGB(40, 36, 34),
		})
	end

	-- Farne am Fuss der Waende ------------------------------------------------------
	local function fern(pos: Vector3, size: number)
		local leaves = srng:NextInteger(5, 7)
		for k = 1, leaves do
			local yaw = (k / leaves) * math.pi * 2 + srng:NextNumber(-0.3, 0.3)
			local pitch = math.rad(srng:NextNumber(28, 55))
			local len = size * srng:NextNumber(0.8, 1.2)
			part({
				Size = Vector3.new(0.5 * size, 0.06, len),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, -len / 2),
				Material = Enum.Material.LeafyGrass,
				Color = Color3.fromRGB(70, 128, 52):Lerp(Color3.fromRGB(112, 150, 62), srng:NextNumber()),
			})
		end
	end
	for _ = 1, 12 do
		fern(ring(srng:NextNumber(14, 18), srng:NextNumber(0, math.pi * 2), 0.1), srng:NextNumber(1.6, 2.6))
	end
	for _, spot in { Vector3.new(-10.6, 0.1, -9), Vector3.new(10.4, 0.1, -9.4), Vector3.new(-9.6, 0.1, -5.5), Vector3.new(9.8, 0.1, -3.5) } do
		fern(O + spot, srng:NextNumber(1.4, 2.2))
	end

	-- Lichtschacht von oben + Staub im Licht ---------------------------------------------
	local shaftAnchor = part({ Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(O), Transparency = 1 })
	local shafts: { Beam } = {}
	local shaftDefs = {
		{ Top = Vector3.new(4.2, 27, -3.2), W0 = 5, W1 = 8, T = 0.87 },
		{ Top = Vector3.new(2.8, 27, -1.8), W0 = 2.4, W1 = 4.4, T = 0.8 },
	}
	for _, sd in shaftDefs do
		local a0 = Make("Attachment", { Position = sd.Top, Parent = shaftAnchor })
		local a1 = Make("Attachment", { Position = Vector3.new(sd.Top.X * 0.1, 1.6, sd.Top.Z * 0.1), Parent = shaftAnchor })
		table.insert(
			shafts,
			Make("Beam", {
				Attachment0 = a0,
				Attachment1 = a1,
				Color = ColorSequence.new(Color3.fromRGB(255, 238, 206)),
				Width0 = sd.W0,
				Width1 = sd.W1,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.97),
					NumberSequenceKeypoint.new(0.3, sd.T),
					NumberSequenceKeypoint.new(0.85, sd.T + 0.05),
					NumberSequenceKeypoint.new(1, 1),
				}),
				LightEmission = 0.6,
				LightInfluence = 0,
				FaceCamera = true,
				Segments = 1,
				Brightness = 1,
				Parent = shaftAnchor,
			})
		)
	end
	local dustBox = part({ Size = Vector3.new(8, 22, 8), CFrame = CFrame.new(O + Vector3.new(2, 12, -1.5)), Transparency = 1 })
	table.insert(
		emitters,
		Effects.Emitter(dustBox, {
			Texture = TEX.Sparkle,
			Enabled = false,
			Rate = 9,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(0.1, 0.4),
			SpreadAngle = Vector2.new(180, 180),
			Size = Effects.NSeq(0.13),
			Transparency = Effects.NSeq(1, 0.35, 1),
			Color = ColorSequence.new(Color3.fromRGB(255, 236, 200)),
			LightEmission = 0.7,
			RotSpeed = NumberRange.new(-20, 20),
		})
	)

	-- Licht: warmes Hauptlicht, Kantenlicht in Seltenheitsfarbe, kuehles Fuelllicht -----
	local keyPart = part({ Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1, CFrame = CFrame.lookAt(O + Vector3.new(5, 24, 7), P) })
	local key = Make("SpotLight", {
		Face = Enum.NormalId.Front,
		Angle = 36,
		Range = 42,
		Brightness = 3,
		Color = Color3.fromRGB(255, 228, 188),
		Shadows = true,
		Parent = keyPart,
	})
	local rimPart = part({ Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1, CFrame = CFrame.new(P + Vector3.new(0, 3.5, -5)) })
	local rim = Make("PointLight", { Range = 20, Brightness = 2.4, Color = C.Blue, Shadows = false, Parent = rimPart })
	local fillPart = part({ Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1, CFrame = CFrame.new(P + Vector3.new(0, 5, 10)) })
	Make("PointLight", { Range = 22, Brightness = 0.6, Color = Color3.fromRGB(160, 178, 220), Shadows = false, Parent = fillPart })

	stage = {
		Folder = folder,
		Origin = O,
		Top = P,
		Fires = fires,
		Emitters = emitters,
		Shafts = shafts,
		Key = key,
		Rim = rim,
		Mood = 1,
		MoodConn = nil :: RBXScriptConnection?,
		FlickerConn = nil :: RBXScriptConnection?,
	}
	return stage
end

-- Partikel + Flackern nur waehrend einer Oeffnung laufen lassen.
-- Ausserhalb wird die ganze Grotte aus der Welt genommen (kostet nichts, ist nirgends zu sehen).
local function setStageActive(on: boolean)
	local s = stage
	if not s then
		return
	end
	for _, e in s.Emitters do
		e.Enabled = on
	end
	pcall(function()
		s.Folder.Parent = if on then Effects.Folder else nil
	end)
	if s.FlickerConn then
		s.FlickerConn:Disconnect()
		s.FlickerConn = nil
	end
	if on then
		s.FlickerConn = RunService.Heartbeat:Connect(function()
			local t = os.clock()
			for _, f in s.Fires do
				local n = math.noise(t * 6, f.Seed, 0) * 0.5 + math.noise(t * 13, f.Seed, 3) * 0.25
				f.Light.Brightness = f.Base * s.Mood * (0.92 + n * 0.4)
			end
		end)
	end
end

-- dark = 0 (normal) .. 1 (Fackeln fast aus, fuer die Mythisch-Verwandlung)
local function setMood(dark: number, time: number)
	local s = stage
	if not s then
		return
	end
	local goal = 1 - 0.78 * dark
	if s.MoodConn then
		s.MoodConn:Disconnect()
		s.MoodConn = nil
	end
	if time <= 0 then
		s.Mood = goal
		s.Key.Brightness = 3 * goal
		for _, b in s.Shafts do
			b.Brightness = goal
		end
		return
	end
	local from = s.Mood
	s.MoodConn = Effects.Animate(time, function(a)
		s.Mood = from + (goal - from) * a
	end)
	UI.Tween(s.Key, time, { Brightness = 3 * goal })
	for _, b in s.Shafts do
		UI.Tween(b, time, { Brightness = goal })
	end
end

local function setRim(color: Color3, time: number)
	local s = stage
	if not s then
		return
	end
	if time > 0 then
		UI.Tween(s.Rim, time, { Color = color })
	else
		s.Rim.Color = color
	end
end

-- =============================================================================
-- GUI der Oeffnung
-- =============================================================================

local openGui: ScreenGui
local fade: Frame
local darkOverlay: Frame
local tierPop: Frame
local tierLabel: TextLabel
local tierShadow: TextLabel
local promptPulse: UIScale
local promptLabel: TextLabel
local pipsHolder: Frame
local tapPips: { Frame } = {}
local tapCatcher: TextButton
local rippleLayer: Frame
local revealHolder: Frame
local tapSignal = Signal.new()
local waitingForTap = false

local function buildOpenGui()
	openGui = UI.Screen("NovaCrateOpen", 30)
	openGui.Enabled = false
	tapCatcher = Make("TextButton", {
		Name = "TapCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = openGui,
	})
	tapCatcher.Activated:Connect(function()
		if waitingForTap then
			tapSignal:Fire()
		end
	end)
	darkOverlay = Make("Frame", {
		Name = "Dark",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = openGui,
	})
	rippleLayer = Make("Frame", { Name = "Ripples", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = openGui })

	-- Grosse Seltenheits-Ansage oben
	local tierRoot = Make("Frame", {
		Name = "Tier",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.13),
		Size = UDim2.fromOffset(900, 110),
		ZIndex = 5,
		Parent = openGui,
	})
	UI.Scaled(tierRoot)
	tierPop = Make("Frame", { Name = "Pop", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = tierRoot })
	tierShadow = UI.Text({
		Name = "Shadow",
		Text = "",
		Font = F.Display,
		TextSize = 84,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Stroke = 6,
		Parent = tierPop,
	})
	tierLabel = UI.Text({
		Name = "Label",
		Text = "",
		Font = F.Display,
		TextSize = 84,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Stroke = 6,
		Parent = tierPop,
	})

	-- Aufforderung + drei Tipp-Punkte unten
	local promptRoot = Make("Frame", {
		Name = "Prompt",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(700, 96),
		ZIndex = 5,
		Parent = openGui,
	})
	UI.Scaled(promptRoot)
	local pulseFrame = Make("Frame", { Name = "Pulse", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), ZIndex = 5, Parent = promptRoot })
	promptPulse = Make("UIScale", { Name = "PulseScale", Parent = pulseFrame })
	promptLabel = UI.Text({
		Name = "Label",
		Text = "",
		Font = F.Heading,
		TextSize = 34,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Stroke = 3,
		Parent = pulseFrame,
	})
	pipsHolder = Make("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(140, 28),
		ZIndex = 5,
		Parent = promptRoot,
	})
	UI.List(pipsHolder, true, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, 3 do
		local pip = Make("Frame", {
			Name = "Pip" .. i,
			BackgroundColor3 = C.PanelDark,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(22, 22),
			LayoutOrder = i,
			ZIndex = 5,
			Parent = pipsHolder,
		})
		UI.Round(pip)
		stroke(pip, 3)
		table.insert(tapPips, pip)
	end

	revealHolder = Make("Frame", { Name = "Reveal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = openGui })
	fade = Make("Frame", {
		Name = "Fade",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = openGui,
	})

	-- Leertaste / Enter / Gamepad-A tippt auch
	UserInputService.InputBegan:Connect(function(input)
		if not waitingForTap or not openGui.Enabled then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA then
			tapSignal:Fire()
		end
	end)
end

local function resetOpenGui()
	for _, c in revealHolder:GetChildren() do
		c:Destroy()
	end
	for _, c in rippleLayer:GetChildren() do
		c:Destroy()
	end
	tierLabel.Text = ""
	tierShadow.Text = ""
	tierPop.Visible = true
	tierLabel.TextTransparency = 0
	tierShadow.TextTransparency = 0
	promptLabel.Text = ""
	pipsHolder.Visible = false
	darkOverlay.BackgroundTransparency = 1
	for _, pip in tapPips do
		pip.BackgroundColor3 = C.PanelDark
	end
end

local function fadeTo(transparency: number, time: number)
	UI.Tween(fade, time, { BackgroundTransparency = transparency }, Enum.EasingStyle.Quad)
	task.wait(time)
end

local tierHideToken = 0

local function showTier(rarity: any, big: boolean)
	tierHideToken += 1
	local text = rarity.Name .. (if big then "!" else "")
	tierLabel.Text = text
	tierShadow.Text = text
	tierLabel.TextColor3 = rarity.Color
	tierShadow.TextColor3 = Theme.Darken(rarity.Color, 0.6)
	tierLabel.TextTransparency = 0
	tierShadow.TextTransparency = 0
	tierPop.Visible = true
	UI.Pop(tierPop, if big then 1.9 else 1.35, if big then 0.45 else 0.3)
	tierPop.Rotation = if big then (if rng:NextNumber() < 0.5 then -7 else 7) else 0
	UI.Tween(tierPop, 0.45, { Rotation = 0 }, Enum.EasingStyle.Back)
end

local function hideTier(time: number)
	tierHideToken += 1
	local token = tierHideToken
	UI.Tween(tierLabel, time, { TextTransparency = 1 })
	UI.Tween(tierShadow, time, { TextTransparency = 1 })
	-- Kontur verschwindet nicht immer mit dem Text -> danach ganz ausblenden
	task.delay(time, function()
		if token == tierHideToken then
			tierPop.Visible = false
		end
	end)
end

local function setPrompt(text: string)
	promptLabel.Text = text
	if text ~= "" then
		UI.Pop(promptLabel, 0.8, 0.25)
	end
end

local function waitTap(timeout: number): boolean
	waitingForTap = true
	local done = false
	local conn = tapSignal:Once(function()
		done = true
	end)
	local start = os.clock()
	while not done and os.clock() - start < timeout do
		promptPulse.Scale = 1 + math.sin((os.clock() - start) * 7) * 0.045
		task.wait()
	end
	conn:Disconnect()
	waitingForTap = false
	promptPulse.Scale = 1
	return done
end

-- Comic-Einschlaglinien an der Truhe als Tipp-Rueckmeldung (kurze dicke Striche mit Kontur)
local function impactLines(screenPos: Vector2, color: Color3, count: number)
	local base = rng:NextNumber(0, 360)
	for i = 1, count do
		local ang = base + (i / count) * 360 + rng:NextNumber(-12, 12)
		local rad = math.rad(ang)
		local dir = Vector2.new(math.cos(rad), math.sin(rad))
		local len = rng:NextInteger(18, 30)
		local from = screenPos + dir * 34
		local to = screenPos + dir * rng:NextNumber(70, 100)
		local line = Make("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(from.X, from.Y),
			Size = UDim2.fromOffset(len, 6),
			Rotation = ang,
			ZIndex = 3,
			Parent = rippleLayer,
		})
		UI.Corner(line, 3)
		stroke(line, 2)
		UI.Tween(line, 0.22, { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(4, 3) }, Enum.EasingStyle.Quad)
		task.delay(0.24, function()
			line:Destroy()
		end)
	end
end

-- =============================================================================
-- Effekt-Helfer fuer die Buehne
-- =============================================================================

-- Kleine Splitter (Holz/Stein), die ballistisch fliegen und auf dem Boden abprallen
local function debris(origin: Vector3, count: number, color: Color3, material: Enum.Material, speed: number, floorAt: (Vector3) -> number)
	local n = math.max(1, math.floor(count * Effects.Quality))
	local parts: { BasePart } = {}
	local vel: { Vector3 } = {}
	local spin: { CFrame } = {}
	for i = 1, n do
		local sz = rng:NextNumber(0.12, 0.3)
		local p = Make("Part", {
			Size = Vector3.new(sz, sz * 0.55, sz * rng:NextNumber(1.2, 2.2)),
			Color = color:Lerp(BLACK, rng:NextNumber(0, 0.25)),
			Material = material,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			CFrame = CFrame.new(origin) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Parent = Effects.Folder,
		})
		Effects.Clean(p, 2)
		local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		if dir.Magnitude < 0.05 then
			dir = Vector3.xAxis
		end
		parts[i] = p
		vel[i] = dir.Unit * speed * rng:NextNumber(0.35, 1) + Vector3.new(0, speed * rng:NextNumber(0.6, 1.2), 0)
		spin[i] = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.4, 0.4))
	end
	Effects.Animate(1.3, function(a, dt)
		for i, p in parts do
			local v = vel[i] - Vector3.new(0, 70 * dt, 0)
			local pos = p.Position + v * dt
			local floorY = floorAt(pos) + p.Size.Y * 0.5
			local resting = false
			if pos.Y < floorY then
				pos = Vector3.new(pos.X, floorY, pos.Z)
				v = Vector3.new(v.X * 0.55, math.abs(v.Y) * 0.3, v.Z * 0.55)
				resting = math.abs(v.Y) < 2
			end
			vel[i] = v
			p.CFrame = CFrame.new(pos) * p.CFrame.Rotation * (if resting then CFrame.identity else spin[i])
			if a > 0.7 then
				p.Transparency = (a - 0.7) / 0.3
			end
		end
	end, function()
		for _, p in parts do
			p:Destroy()
		end
	end)
end

-- Weiches Aufleuchten als Partikel-Sprite (statt grosser Neon-Kugel)
local function glowPop(at: Vector3, color: Color3, size: number, life: number)
	Effects.Burst(at, 1, {
		Texture = TEX.Glow,
		Color = ColorSequence.new(color),
		Size = Effects.NSeq(size * 0.6, size),
		Transparency = Effects.NSeq(0.2, 1),
		Lifetime = NumberRange.new(life),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		RotSpeed = NumberRange.new(0),
		ZOffset = 1,
	})
end

-- Bodenstaub, der als Ring vom Punkt wegrollt
local function dustRing(at: Vector3, count: number, speed: number, color: Color3)
	Effects.Burst(at, count, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(color),
		LightEmission = 0,
		LightInfluence = 1,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(84, 84),
		Speed = NumberRange.new(speed * 0.6, speed),
		Drag = 4,
		Acceleration = Vector3.new(0, 1.2, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = Effects.NSeq(1.2, 3.6),
		Transparency = Effects.NSeq(0.35, 1),
	})
end

-- Lichtstrahlen (Beams) von einem Punkt aus; liefert Anker + Strahlen zum Animieren
type Ray = { Beam: Beam, A1: Attachment, Dir: Vector3, Len: number, W: number }

local function makeRays(parent: Instance, at: Vector3, count: number, color: Color3, minUp: number, lenMin: number, lenMax: number): (Part, { Ray })
	local anchor = Make("Part", {
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(at),
		Parent = parent,
	})
	local rays: { Ray } = {}
	for k = 1, count do
		local ang = (k / count) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local up = rng:NextNumber(minUp, 1)
		local flat = math.sqrt(math.max(0, 1 - up * up))
		local dir = Vector3.new(math.cos(ang) * flat, up, math.sin(ang) * flat)
		local a0 = Make("Attachment", { Parent = anchor })
		local a1 = Make("Attachment", { Position = dir * 0.2, Parent = anchor })
		local beam = Make("Beam", {
			Attachment0 = a0,
			Attachment1 = a1,
			Color = ColorSequence.new(WHITE, color),
			Width0 = 0.2,
			Width1 = 0.2,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 1,
			LightInfluence = 0,
			FaceCamera = true,
			Segments = 1,
			Brightness = 2,
			Parent = anchor,
		})
		table.insert(rays, { Beam = beam, A1 = a1, Dir = dir, Len = rng:NextNumber(lenMin, lenMax), W = rng:NextNumber(1.2, 2.4) })
	end
	return anchor, rays
end

local function setRays(rays: { Ray }, grow: number)
	for _, r in rays do
		r.A1.Position = r.Dir * math.max(0.2, r.Len * grow)
		r.Beam.Width1 = r.W * grow
		r.Beam.Width0 = 0.25 * grow
	end
end

local function recolorRays(rays: { Ray }, color: Color3)
	for _, r in rays do
		r.Beam.Color = ColorSequence.new(WHITE, color)
	end
end

-- =============================================================================
-- Ergebnis-Karte
-- =============================================================================

local function statPill(parent: Instance, text: string, order: number, fill: Color3?): Frame
	local pill = Make("Frame", {
		Name = "Pill",
		BackgroundColor3 = fill or C.PanelDark,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Corner(pill, 10)
	stroke(pill, 2)
	Make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = pill })
	UI.Text({
		Text = text,
		Font = F.Heading,
		TextSize = 16,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Stroke = if fill then 1.5 else nil,
		Parent = pill,
	})
	return pill
end

local function showReveal(result: any, crateDef: any, coinsAfter: number, onAction: (string) -> ())
	for _, c in revealHolder:GetChildren() do
		c:Destroy()
	end
	local def = Abilities.Get(result.AbilityId) :: any
	local rarity = Rarities.Get(def.Rarity)
	local root = Make("Frame", {
		Name = "Card",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 420),
		Size = UDim2.fromOffset(760, 316),
		ZIndex = 10,
		Parent = revealHolder,
	})
	UI.Scaled(root)
	UI.Tween(root, 0.55, { Position = UDim2.new(0.5, 0, 1, -20) }, Enum.EasingStyle.Back)

	local shadow = Make("Frame", {
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 224),
		Parent = root,
	})
	UI.Corner(shadow, 18)
	local card = UI.Panel({ Name = "Panel", Radius = 18, Size = UDim2.new(1, 0, 0, 224), Parent = root })

	-- Faehigkeits-Kachel auf einem Feld in Seltenheitsfarbe
	local slot = UI.Inset({
		Name = "Slot",
		Color = Theme.Darken(rarity.Color, 0.62),
		Radius = 16,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(192, 192),
		Parent = card,
	})
	local tile = UI.AbilityTile({ AbilityId = def.Id, Size = 164, Parent = slot })
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	UI.Pop(tile, 0.3, 0.55)

	-- Seltenheits-Band ragt oben aus der Karte
	local ribbon = makeTag({
		Text = rarity.Name,
		Fill = rarity.Color,
		Font = F.Display,
		TextSize = 26,
		Height = 40,
		PadX = 36,
		Position = UDim2.fromOffset(224, -22),
		Rotation = -2,
		ZIndex = 6,
		Parent = card,
	})
	UI.Pop(ribbon, 1.6, 0.4)

	-- Name (Tipp-Effekt), Beschreibung, Werte
	local full = string.upper(def.Name)
	local nameSize = 40
	while nameSize > 24 and textWidth(full, nameSize, F.Heading) > 500 do
		nameSize -= 2
	end
	local name = UI.Text({
		Name = "Name",
		Text = "",
		Font = F.Heading,
		TextSize = nameSize,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(226, 28),
		Size = UDim2.fromOffset(510, 48),
		Stroke = 3,
		Parent = card,
	})
	task.spawn(function()
		for i = 1, #full do
			if not name.Parent then
				return
			end
			name.Text = string.sub(full, 1, i)
			task.wait(0.025)
		end
	end)
	UI.Text({
		Name = "Description",
		Text = def.Description,
		Font = F.Body,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(228, 80),
		Size = UDim2.fromOffset(508, 44),
		Parent = card,
	})
	local pills = Make("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(226, 140),
		Size = UDim2.fromOffset(510, 36),
		Parent = card,
	})
	UI.List(pills, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local muted = "#868EA3"
	local function num(v: any): string
		local n = tonumber(v) or 0
		return if n == math.floor(n) then tostring(math.floor(n)) else string.format("%.1f", n)
	end
	statPill(pills, string.format("<font color='%s'>DMG</font> %s", muted, num(def.Damage)), 1)
	statPill(pills, string.format("<font color='%s'>COOLDOWN</font> %ss", muted, num(def.Cooldown)), 2)
	statPill(pills, string.format("<font color='%s'>RANGE</font> %s", muted, num(def.Range)), 3)
	if def.Cutscene then
		statPill(pills, "CUTSCENE", 4, C.Gold)
	end

	-- NEU! oder Duplikat (+ Muenzen)
	if result.IsNew then
		local badge = makeTag({
			Text = "NEW!",
			Fill = C.Gold,
			Font = F.Display,
			TextSize = 26,
			Height = 40,
			PadX = 30,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -18, 0, 0),
			Rotation = 6,
			ZIndex = 6,
			Parent = card,
		})
		badge.Visible = false
		task.delay(0.45, function()
			if badge.Parent then
				badge.Visible = true
				UI.Pop(badge, 2.2, 0.45)
				UI.Sound("Coins", 1.2)
			end
		end)
	else
		makeTag({
			Text = "DUPLICATE",
			Fill = C.Grey,
			TextSize = 18,
			Height = 32,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -18, 0, 0),
			Rotation = 4,
			ZIndex = 6,
			Parent = card,
		})
		local refund = tonumber(result.Refund) or 0
		if refund > 0 then
			local pill = statPill(pills, "+0", 5, C.GoldDark)
			local label = pill:FindFirstChildOfClass("TextLabel")
			drawCoin(pill, 20, UDim2.new(0, -6, 0.5, -10), 3)
			Make("UIPadding", { PaddingLeft = UDim.new(0, 16), Parent = label })
			if label then
				task.delay(0.4, function()
					if label.Parent then
						UI.CountTo(label, 0, refund, 0.8, function(n)
							return "+" .. UI.Format(n)
						end)
						UI.Sound("Coins", 1)
					end
				end)
			end
		end
	end

	-- Knoepfe erst kurz danach, damit wildes Tippen nichts ausloest
	local row = Make("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 244),
		Size = UDim2.new(1, 0, 0, 64),
		Parent = root,
	})
	UI.List(row, true, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local chosen = false
	local function choose(a: string)
		if chosen then
			return
		end
		chosen = true
		onAction(a)
	end
	task.delay(0.75, function()
		if not row.Parent then
			return
		end
		local buttons: { GuiObject } = {}
		if not crateDef.Free and coinsAfter >= crateDef.Price then
			local again = UI.Button({
				Name = "Again",
				Text = "AGAIN",
				Style = "Gold",
				Size = UDim2.fromOffset(236, 60),
				TextSize = 26,
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					choose("Again")
				end,
			})
			addPriceRight(again, crateDef.Price, 24)
			table.insert(buttons, again)
		end
		table.insert(
			buttons,
			UI.Button({
				Name = "Preview",
				Text = "PREVIEW",
				Style = "Blue",
				Size = UDim2.fromOffset(196, 60),
				TextSize = 26,
				LayoutOrder = 2,
				Parent = row,
				OnClick = function()
					choose("Preview")
				end,
			})
		)
		table.insert(
			buttons,
			UI.Button({
				Name = "Continue",
				Text = "CONTINUE",
				Style = "Green",
				Size = UDim2.fromOffset(220, 60),
				TextSize = 26,
				LayoutOrder = 3,
				Shine = true,
				Parent = row,
				OnClick = function()
					choose("Close")
				end,
			})
		)
		for i, b in buttons do
			UI.Pop(b, 0.4, 0.3 + i * 0.05)
		end
	end)

	-- Konfetti in Seltenheitsfarben
	local colors = { rarity.Color, rarity.Glow, WHITE, C.Gold }
	if rarity.Tier >= 7 then
		for _, kp in rarity.Gradient.Keypoints do
			table.insert(colors, kp.Value)
		end
	end
	UI.Burst(revealHolder, UDim2.fromScale(0.5, 0.36), colors, 36 + rarity.Tier * 10, 520)
end

-- =============================================================================
-- Hauptablauf
-- =============================================================================

type Jolt = { Start: number, RX: number, RZ: number, Power: number }

local function runOpening(result: any, crateDef: any, coinsAfter: number, trash: { () -> () }): string
	local s = buildStage()
	setStageActive(true)
	table.insert(trash, function()
		setStageActive(false)
		setMood(0, 0)
	end)
	local O: Vector3 = s.Origin
	local P: Vector3 = s.Top
	local finalRarity = Rarities.Get(result.Rarity)
	local finalTier = finalRarity.Tier
	local def = Abilities.Get(result.AbilityId) :: any
	assert(def, "unknown ability " .. tostring(result.AbilityId))

	-- Start-Stufe = niedrigste Stufe, die in dieser Kiste vorkommt
	local startTier = finalTier
	for rid in crateDef.Weights do
		startTier = math.min(startTier, Rarities.Get(rid).Tier)
	end
	-- Aufstiege auf die drei Taps verteilen (bei MYTHISCH+ kommt der letzte beim Oeffnen)
	local increments = { 0, 0, 0, 0 }
	local ups = finalTier - startTier
	for i = 1, ups do
		local slot = if finalTier >= 6 and i == ups then 4 else math.random(1, 3)
		increments[slot] += 1
	end
	local displayTier = startTier

	-- Bodenhoehe fuer Splitter (Sockel-Stufen)
	local function floorAt(pos: Vector3): number
		local d = Vector2.new(pos.X - O.X, pos.Z - O.Z).Magnitude
		if d < 3.6 then
			return P.Y
		elseif d < 4.6 then
			return O.Y + 0.9
		elseif d < 9.5 then
			return O.Y + 0.22
		end
		return O.Y
	end

	-- 0) Schwarz abblenden, Kamera umschalten
	openGui.Enabled = true
	resetOpenGui()
	fadeTo(0, 0.25)

	local cam = workspace.CurrentCamera :: Camera
	cam.CameraType = Enum.CameraType.Scriptable
	local camGoal = {
		Pos = P + Vector3.new(0, 3.4, 12.5),
		Look = P + Vector3.new(0, 1.9, 0),
		Fov = 50,
		Rate = 5,
		Kick = 0,
	}
	local curPos = camGoal.Pos + Vector3.new(0, 1.2, 3)
	local curLook = camGoal.Look + Vector3.new(0, 0.8, 0)
	local curFov = 50
	local camStart = os.clock()
	RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local k = 1 - math.exp(-camGoal.Rate * dt)
		curPos = curPos:Lerp(camGoal.Pos, k)
		curLook = curLook:Lerp(camGoal.Look, k)
		curFov += (camGoal.Fov - curFov) * k
		camGoal.Kick *= math.exp(-dt * 9)
		local t = os.clock() - camStart
		local sway = Vector3.new(math.sin(t * 0.5) * 0.3, math.sin(t * 0.7) * 0.15, 0)
		cam.CFrame = CFrame.lookAt(curPos + sway, curLook)
		cam.FieldOfView = curFov - camGoal.Kick
	end)
	table.insert(trash, function()
		RunService:UnbindFromRenderStep(CAM_BIND)
	end)

	-- Truhe
	local crate = CrateModel.Build(crateDef, s.Folder, 1)
	table.insert(trash, function()
		crate:Destroy()
	end)
	local startRarity = Rarities.ByTier(startTier)
	crate:SetTrim(startRarity.Color)
	local glow = 0.08
	crate:SetGlow(glow)
	setRim(startRarity.Color, 0)
	setMood(0, 0)
	local woodColor: Color3 = crate.Theme.Wood
	local hinge: CFrame = crate.LidHinge

	-- Kurzes Aufleuchten der ganzen Truhe (Treffer-Frame)
	local flash = Make("Highlight", {
		Adornee = crate.Model,
		FillColor = WHITE,
		FillTransparency = 1,
		OutlineColor = WHITE,
		OutlineTransparency = 1,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = crate.Model,
	})
	local function flashChest(color: Color3, strength: number, time: number)
		flash.FillColor = color
		flash.OutlineColor = color
		flash.FillTransparency = 1 - strength
		flash.OutlineTransparency = 1 - strength * 0.7
		UI.Tween(flash, time, { FillTransparency = 1, OutlineTransparency = 1 }, Enum.EasingStyle.Quad)
	end

	-- Aura: aufsteigende Funkeln, je seltener desto mehr
	local aura = Effects.Emitter(crate.Core, {
		Texture = TEX.Sparkle,
		Rate = 0,
		Color = Effects.Seq(WHITE, startRarity.Color),
		Size = Effects.NSeq(0.35, 0),
		Speed = NumberRange.new(1.5, 3.5),
		Lifetime = NumberRange.new(0.8, 1.4),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 2, 0),
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LightEmission = 1,
	})
	local embers = Effects.Emitter(crate.Core, {
		Texture = TEX.Sparks,
		Rate = 0,
		Color = Effects.Seq(WHITE, startRarity.Color),
		Size = Effects.NSeq(0.18, 0),
		Speed = NumberRange.new(3, 6),
		Lifetime = NumberRange.new(0.6, 1.1),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 1,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LightEmission = 1,
	})
	local function setAura(tier: number, color: Color3)
		aura.Color = Effects.Seq(WHITE, color)
		embers.Color = Effects.Seq(WHITE, color)
		aura.Rate = ({ 0, 4, 8, 14, 22, 30, 40 })[math.clamp(tier, 1, 7)] * Effects.Quality
		embers.Rate = (if tier >= 5 then (tier - 4) * 6 else 0) * Effects.Quality
	end
	setAura(startTier, startRarity.Color)

	-- Animation der Truhe (jeden Frame)
	local anim = { Hover = 16, Bob = 0, Shake = 0, LidMode = "", LidStart = 0, LidSpin = 0 }
	local jolt: Jolt? = nil
	local animConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cf = CFrame.new(P + Vector3.new(0, anim.Hover + math.sin(t * 2.4) * anim.Bob, 0)) * FACE_CAMERA * CFrame.Angles(0, math.sin(t * 0.8) * 0.05, 0)
		local j = jolt
		if j then
			local a = math.clamp((t - j.Start) / 0.34, 0, 1)
			local hop = math.sin(a * math.pi) * (1 - a * 0.4) * 0.5 * j.Power
			local wob = math.sin(a * math.pi * 2.5) * (1 - a)
			cf = cf * CFrame.new(0, hop, 0) * CFrame.Angles(j.RX * wob, 0, j.RZ * wob)
			if a >= 1 then
				jolt = nil
			end
		end
		local sh = anim.Shake
		if sh > 0 then
			cf = cf
				* CFrame.new(rng:NextNumber(-1, 1) * sh * 0.06, rng:NextNumber(-1, 1) * sh * 0.04, rng:NextNumber(-1, 1) * sh * 0.06)
				* CFrame.Angles(rng:NextNumber(-1, 1) * sh * 0.022, rng:NextNumber(-1, 1) * sh * 0.022, rng:NextNumber(-1, 1) * sh * 0.022)
		end
		-- Deckel: aufklappen (mit Ueberschwingen) oder wegsprengen
		if anim.LidMode == "Swing" then
			local a = math.clamp((t - anim.LidStart) / 0.42, 0, 1)
			crate.LidTransform = hinge * CFrame.Angles(math.rad(108) * Effects.Ease(a, "OutBack"), 0, 0) * hinge:Inverse()
		elseif anim.LidMode == "Blast" then
			local a = math.clamp((t - anim.LidStart) / 0.9, 0, 1)
			local e = 1 - (1 - a) ^ 2
			crate.LidTransform = CFrame.new(0, e * 11, e * 7) * hinge * CFrame.Angles(math.rad(200) * e, anim.LidSpin * e, anim.LidSpin * 0.5 * e) * hinge:Inverse()
		end
		crate:SetCFrame(cf)
	end)
	table.insert(trash, function()
		animConn:Disconnect()
	end)

	fadeTo(1, 0.35)

	-- 1) Truhe faellt auf den Sockel -------------------------------------------------
	Effects.Sound("Whoosh", nil, { Pitch = 0.6 })
	local dropT = 0.42
	local t0 = os.clock()
	while os.clock() - t0 < dropT do
		local a = (os.clock() - t0) / dropT
		anim.Hover = 16 * (1 - a * a)
		task.wait()
	end
	anim.Hover = 0
	Effects.Sound("CrateLand")
	Effects.Sound("Impact", nil, { Volume = 0.6, Pitch = 0.8 })
	Effects.Shake(1.6, 0.35)
	camGoal.Kick = 4
	jolt = { Start = os.clock(), RX = 0.04, RZ = -0.03, Power = 0.5 }
	dustRing(P + Vector3.new(0, 0.2, 0), 26, 14, Color3.fromRGB(176, 160, 140))
	debris(P + Vector3.new(0, 0.3, 0), 7, Color3.fromRGB(150, 142, 128), Enum.Material.Slate, 14, floorAt)
	showTier(startRarity, false)
	task.wait(0.5)
	anim.Bob = 0.05

	-- 2) Drei Mal tippen ------------------------------------------------------------
	local function upgradeTo(tier: number, huge: boolean)
		local r = Rarities.ByTier(tier)
		local center = crate:Center()
		crate:SetTrim(r.Color, 0.12)
		glow = math.min(1, glow + (if huge then 0.22 else 0.14))
		crate:SetGlow(glow, 0.2)
		setRim(r.Color, 0.3)
		setAura(tier, r.Color)
		flashChest(r.Color, if huge then 0.85 else 0.65, 0.35)
		glowPop(center, r.Color:Lerp(WHITE, 0.3), if huge then 16 else 11, 0.3)
		Effects.Burst(center, 26 + tier * 6, {
			Texture = TEX.Sparkle,
			Color = Effects.Seq(WHITE, r.Color),
			Speed = NumberRange.new(12, 26),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = Effects.NSeq(0.7, 0),
			Drag = 3,
			Acceleration = Vector3.new(0, -8, 0),
		})
		Effects.Burst(center, 10 + tier * 2, {
			Texture = TEX.Sparks,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Color = Effects.Seq(WHITE, r.Color),
			Speed = NumberRange.new(30, 50),
			Lifetime = NumberRange.new(0.15, 0.3),
			Size = Effects.NSeq(0.5, 0),
			Drag = 6,
		})
		Effects.Light(center, r.Color, 26, 6, 0.5)
		Effects.ScreenFlash(r.Color, 0.3, if huge then 0.5 else 0.75)
		Effects.Sound("CrateUpgrade", nil, { Pitch = 0.7 + tier * 0.11 })
		Effects.Shake(0.6 + tier * 0.2, 0.3)
		camGoal.Kick = if huge then 6 else 3.5
		showTier(r, true)
	end

	pipsHolder.Visible = true
	UI.Pop(pipsHolder, 0.6, 0.3)
	for tap = 1, 3 do
		setPrompt(if tap == 1 then "TAP THE CHEST!" elseif tap == 2 then "AGAIN!" else "ONE MORE!")
		waitTap(8)
		local col = Rarities.ByTier(displayTier).Color
		local vpPoint = cam:WorldToViewportPoint(crate:Center())
		impactLines(Vector2.new(vpPoint.X, vpPoint.Y), WHITE, 7)
		jolt = { Start = os.clock(), RX = rng:NextNumber(-0.22, 0.22), RZ = rng:NextNumber(-0.26, 0.26), Power = 0.8 + tap * 0.3 }
		flashChest(WHITE, 0.55, 0.18)
		camGoal.Kick = 2 + tap
		Effects.Shake(0.5 + tap * 0.35, 0.22)
		Effects.Sound("CrateTap", nil, { Pitch = 0.9 + tap * 0.12 })
		Effects.Sound("Impact", nil, { Volume = 0.35, Pitch = 1.3 + tap * 0.1 })
		for _ = 1, (if tap == 3 then 3 else 2) do
			crate:AddCrack(col)
		end
		local front = crate:PointAt(rng:NextNumber(-1.2, 1.2), 1.2, -1.5)
		Effects.Burst(front, 12 + tap * 4, {
			Texture = TEX.Sparks,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Color = Effects.Seq(WHITE, col),
			Speed = NumberRange.new(14, 28),
			Lifetime = NumberRange.new(0.2, 0.45),
			Size = Effects.NSeq(0.3, 0),
			Drag = 6,
			Acceleration = Vector3.new(0, -30, 0),
		})
		debris(front, 3 + tap, woodColor, Enum.Material.Wood, 12, floorAt)
		glow = math.min(1, glow + 0.08)
		crate:SetGlow(glow, 0.15)
		if increments[tap] > 0 then
			task.wait(0.14)
			for _ = 1, increments[tap] do
				displayTier += 1
				upgradeTo(displayTier, false)
				task.wait(0.4)
			end
		end
		local pip = tapPips[tap]
		pip.BackgroundColor3 = Rarities.ByTier(displayTier).Color
		UI.Pop(pip, 1.8, 0.3)
		anim.Shake = tap * 0.3
		anim.Bob = 0.05 * tap
	end
	setPrompt("")
	pipsHolder.Visible = false

	-- 3) Aufladen / Verwandlung -----------------------------------------------------------
	local finalColor = finalRarity.Color
	local rayAnchor: Part? = nil
	local rays: { Ray } = {}
	if finalTier >= 6 then
		setPrompt(if finalTier >= 7 then "A DIVINE POWER AWAKENS..." else "SOMETHING POWERFUL AWAKENS...")
		UI.Tween(darkOverlay, 0.6, { BackgroundTransparency = 0.45 })
		setMood(1, 0.8)
		Effects.ColorGrade({ Brightness = -0.06, Contrast = 0.25, Saturation = -0.35 }, 0.5, 2.3, 0.5)
		Effects.Sound("Rumble", nil, { Pitch = 0.55 })
		Effects.Sound("MythicReveal")
		camGoal.Pos = P + Vector3.new(0, 2.8, 9.2)
		camGoal.Look = P + Vector3.new(0, 3, 0)
		camGoal.Rate = 2
		local anchor, list = makeRays(s.Folder, crate:Center(), 8, Rarities.ByTier(displayTier).Color, -0.1, 7, 13)
		rayAnchor = anchor
		rays = list
		table.insert(trash, function()
			anchor:Destroy()
		end)
		local chargeT = 2.3
		local c0 = os.clock()
		local nextCrack = 0.5
		local nextSpark = 0
		while os.clock() - c0 < chargeT do
			local el = os.clock() - c0
			local a = el / chargeT
			anim.Hover = 2.4 * Effects.Ease(a, "OutCubic")
			anim.Shake = 1 + a * 3
			anchor.CFrame = CFrame.new(crate:Center()) * CFrame.Angles(0, el * 0.9, 0)
			setRays(rays, Effects.Ease(math.clamp(a * 1.3, 0, 1), "OutCubic"))
			if el > nextCrack then
				nextCrack += 0.5
				crate:AddCrack(Rarities.ByTier(displayTier).Color)
				glow = math.min(1, glow + 0.06)
				crate:SetGlow(glow, 0.2)
			end
			if el > nextSpark then
				nextSpark += 0.18
				Effects.Burst(crate:Center(), 6, {
					Texture = TEX.Sparks,
					Orientation = Enum.ParticleOrientation.VelocityParallel,
					Color = Effects.Seq(WHITE, Rarities.ByTier(displayTier).Color),
					Speed = NumberRange.new(16, 30),
					Lifetime = NumberRange.new(0.15, 0.3),
					Size = Effects.NSeq(0.3, 0),
					Drag = 5,
				})
			end
			task.wait()
		end
		while displayTier < finalTier do
			displayTier += 1
			upgradeTo(displayTier, true)
			recolorRays(rays, Rarities.ByTier(displayTier).Color)
			task.wait(0.45)
		end
		if finalTier >= 7 then
			-- GOETTLICH: nur der Edelstein wechselt langsam die Farbe
			task.spawn(function()
				local start = os.clock()
				while crate.Model.Parent and os.clock() - start < 30 do
					crate:SetGemColor(Color3.fromHSV(((os.clock() - start) * 0.12) % 1, 0.45, 1))
					task.wait(0.05)
				end
			end)
		end
	else
		local c0 = os.clock()
		Effects.Sound("Charge", nil, { Pitch = 1.3, Volume = 0.6 })
		camGoal.Pos = P + Vector3.new(0, 3.1, 11)
		while os.clock() - c0 < 0.65 do
			local a = (os.clock() - c0) / 0.65
			anim.Shake = 1 + a * 2
			anim.Hover = a * 0.5
			task.wait()
		end
	end
	setPrompt("")
	crate:SetGlow(1, 0.1)

	-- 4) Aufplatzen! -------------------------------------------------------------------
	local mythic = finalTier >= 6
	anim.Shake = 0
	anim.Bob = 0
	if not mythic then
		-- normale Truhen knallen zurueck auf den Sockel, MYTHISCH+ bleibt schweben
		anim.Hover = 0
		jolt = { Start = os.clock(), RX = 0.05, RZ = -0.04, Power = 0.6 }
	end
	task.wait(0.08) -- kurzer Moment Stille
	local top = crate:Top()
	anim.LidStart = os.clock()
	anim.LidSpin = rng:NextNumber(-1.2, 1.2)
	anim.LidMode = if mythic then "Blast" else "Swing"
	if mythic then
		task.delay(0.35, function()
			for _, p in crate:LidParts() do
				if p.Parent then
					UI.Tween(p, 0.4, { Transparency = 1 })
				end
			end
		end)
		debris(top + Vector3.new(0, 0.8, 0), 14, woodColor, Enum.Material.Wood, 20, floorAt)
	end
	if rayAnchor then
		local ra = rayAnchor
		Effects.Animate(0.35, function(a)
			setRays(rays, 1 + a * 0.6)
			for _, r in rays do
				r.Beam.Width1 = r.W * (1 - a)
			end
		end, function()
			ra:Destroy()
		end)
	end
	darkOverlay.BackgroundTransparency = 1
	setMood(0, 0.6)
	flashChest(WHITE, 0.9, 0.4)
	glowPop(top + Vector3.new(0, 1, 0), finalColor:Lerp(WHITE, 0.4), 22, 0.45)

	-- Lichtsaeule: weisser Kern + farbiger Mantel
	local pillar = Make("Part", {
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(top),
		Parent = s.Folder,
	})
	table.insert(trash, function()
		pillar:Destroy()
	end)
	local pa0 = Make("Attachment", { Parent = pillar })
	local pa1 = Make("Attachment", { Position = Vector3.new(0, 42, 0), Parent = pillar })
	local outer = Make("Beam", {
		Attachment0 = pa0,
		Attachment1 = pa1,
		Color = ColorSequence.new(finalColor),
		Width0 = 0.1,
		Width1 = 0.1,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Segments = 1,
		Brightness = 3,
		Parent = pillar,
	})
	local core = Make("Beam", {
		Attachment0 = pa0,
		Attachment1 = pa1,
		Color = ColorSequence.new(WHITE),
		Width0 = 0.05,
		Width1 = 0.05,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Segments = 1,
		Brightness = 4,
		Parent = pillar,
	})
	local pillarPower = 1 + math.max(0, finalTier - 3) * 0.12
	Effects.Animate(1.8, function(a)
		local grow = math.clamp(a / 0.12, 0, 1)
		local shrink = math.clamp((a - 0.3) / 0.7, 0, 1)
		local w = (1 - (1 - grow) ^ 3) * (1 - shrink * 0.78) * pillarPower
		outer.Width0 = 4.2 * w
		outer.Width1 = 3 * w
		core.Width0 = 1.4 * w
		core.Width1 = 1 * w
	end)

	-- Faecher aus Lichtstrahlen, der sich langsam dreht
	local fanAnchor, fanRays = makeRays(s.Folder, top, 6 + math.min(4, finalTier), finalColor:Lerp(WHITE, 0.25), 0.55, 12, 20)
	table.insert(trash, function()
		fanAnchor:Destroy()
	end)
	Effects.Animate(2.6, function(a)
		fanAnchor.CFrame = CFrame.new(top) * CFrame.Angles(0, a * 1.3, 0)
		local grow = Effects.Ease(math.clamp(a / 0.15, 0, 1), "OutCubic")
		local fadeOut = 1 - math.clamp((a - 0.45) / 0.55, 0, 1)
		setRays(fanRays, grow)
		for _, r in fanRays do
			r.Beam.Width1 = r.W * 1.4 * grow * fadeOut
			r.Beam.Width0 = 0.3 * grow * fadeOut
		end
	end)

	-- Funkenfontaene + Lichtstreifen + Bodenstaub
	Effects.BurstDir(top, Vector3.yAxis, 60 + finalTier * 14, {
		Texture = TEX.Sparkle,
		Color = Effects.Seq(WHITE, finalColor),
		Speed = NumberRange.new(26, 50),
		SpreadAngle = Vector2.new(28, 28),
		Lifetime = NumberRange.new(1, 1.8),
		Acceleration = Vector3.new(0, -32, 0),
		Size = Effects.NSeq(0.8, 0),
		Drag = 0.6,
	})
	Effects.BurstDir(top, Vector3.yAxis, 20 + finalTier * 3, {
		Texture = TEX.Sparks,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Color = Effects.Seq(WHITE, finalColor),
		Speed = NumberRange.new(50, 80),
		SpreadAngle = Vector2.new(40, 40),
		Lifetime = NumberRange.new(0.25, 0.4),
		Size = Effects.NSeq(0.55, 0),
		Drag = 4,
	})
	dustRing(P + Vector3.new(0, 0.2, 0), 22, 18, Color3.fromRGB(176, 160, 140))
	Effects.Light(top, finalColor, 50, 9, 1.6)
	Effects.Shake(2.2 + finalTier * 0.35, 0.6)
	camGoal.Kick = 7
	if finalTier >= 4 then
		Effects.ScreenFlash(WHITE, 0.3, 0.35)
	else
		Effects.ScreenFlash(finalColor, 0.35, 0.7)
	end
	Effects.Sound("CrateOpen")
	Effects.Sound(if mythic then "MythicReveal" else "Reveal")
	showTier(finalRarity, true)
	setAura(finalTier, finalColor)

	-- 5) Faehigkeit steigt als Symbol aus der Truhe -------------------------------------------
	task.wait(0.22)
	local orb = Make("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		CFrame = CFrame.new(crate:Center()),
		Parent = s.Folder,
	})
	table.insert(trash, function()
		orb:Destroy()
	end)
	local orbAtt = Make("Attachment", { Parent = orb })
	Effects.Emitter(orbAtt, {
		Texture = TEX.Glow,
		Rate = 6,
		LockedToPart = true,
		Color = ColorSequence.new(def.Color),
		Size = Effects.NSeq(5.5, 7),
		Transparency = Effects.NSeq(0.6, 1),
		Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(0),
		RotSpeed = NumberRange.new(-20, 20),
		LightEmission = 1,
	})
	Effects.Emitter(orb, {
		Texture = TEX.Sparkle,
		Rate = 16,
		Color = Effects.Seq(WHITE, def.Color2),
		Size = Effects.NSeq(0.35, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(0.5, 1.5),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LightEmission = 1,
	})
	Make("PointLight", { Color = def.Color, Range = 16, Brightness = 3, Shadows = false, Parent = orb })
	local px = math.floor(150 * UI.Scale)
	local bb = Make("BillboardGui", {
		Size = UDim2.fromOffset(px, px),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = orb,
	})
	local tile = UI.AbilityTile({ AbilityId = def.Id, Size = px, Parent = bb })
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	UI.Pop(tile, 0.2, 0.6)
	local orbTarget = top + Vector3.new(0, 3.6, 0)
	UI.Tween(orb, 0.8, { CFrame = CFrame.new(orbTarget) }, Enum.EasingStyle.Back)
	local wiggle = RunService.RenderStepped:Connect(function()
		tile.Rotation = math.sin(os.clock() * 2.2) * 4
	end)
	table.insert(trash, function()
		wiggle:Disconnect()
	end)
	Effects.Sound("Whoosh", nil, { Pitch = 1.3, Volume = 0.6 })

	-- Kamera so, dass Truhe + Symbol ueber der Ergebnis-Karte stehen
	local lift = anim.Hover * 0.65
	camGoal.Pos = P + Vector3.new(0, 3.4 + lift, 16)
	camGoal.Look = P + Vector3.new(0, 1.8 + lift, 0)
	camGoal.Rate = 3
	task.wait(0.55)

	-- 6) Ergebnis-Karte -------------------------------------------------------------------
	hideTier(0.3)
	local action: string? = nil
	showReveal(result, crateDef, coinsAfter, function(a)
		action = a
	end)
	while action == nil do
		task.wait()
	end
	fadeTo(0, 0.3)
	for _, c in revealHolder:GetChildren() do
		c:Destroy()
	end
	return action :: string
end

local savedFov = 70

local function restoreCamera()
	local cam = workspace.CurrentCamera :: Camera
	if State.MenuOpen then
		-- Das Startmenue steuert die Kamera selbst weiter
		cam.FieldOfView = savedFov
		return
	end
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

local function canAfford(def: any): boolean
	return def.Free == true or profileCoins() >= def.Price
end

-- Fragt den Server; liefert das Ergebnis oder (nil, Fehlermeldung)
local function requestOpen(crateId: string): (any, string?)
	local ok, result = pcall(function()
		return Net.Function("OpenCrate"):InvokeServer(crateId)
	end)
	if not ok then
		return nil, "Connection error"
	end
	if type(result) ~= "table" or not result.Ok then
		return nil, if type(result) == "table" and result.Message then tostring(result.Message) else "Error"
	end
	if not Abilities.Get(result.AbilityId) then
		return nil, "Unknown ability"
	end
	return result, nil
end

local function errorToast(text: string)
	HUD.Toast({ Text = text, Color = C.Red, Icon = "!" })
end

function CratesController.Purchase(crateId: string, sourceButton: GuiObject?)
	if busy then
		return
	end
	local def = Crates.Get(crateId)
	if not def then
		return
	end
	if not canAfford(def) then
		if sourceButton then
			UI.Shake(sourceButton)
		end
		errorToast("Not enough coins! Win rounds or grab coins in the shop.")
		return
	end
	busy = true
	local result, err = requestOpen(crateId)
	if not result then
		busy = false
		if sourceButton then
			UI.Shake(sourceButton)
		end
		errorToast(err or "Error")
		return
	end

	-- Sequenz starten
	UI.CloseAllWindows()
	local cam = workspace.CurrentCamera
	savedFov = if cam then cam.FieldOfView else 70
	State.InCrateOpening = true
	State.SetBusy("Crate", true)
	State.SetHUDHidden("Crate", true)
	local opened: { string } = {}
	local action = "Close"
	while true do
		table.insert(opened, result.AbilityId)
		local coinsAfter = tonumber(result.Coins) or profileCoins()
		local trash: { () -> () } = {}
		local seqOk, seqResult = pcall(runOpening, result, def, coinsAfter, trash)
		-- Aufraeumen (rueckwaerts), auch nach einem Fehler
		for i = #trash, 1, -1 do
			local ok, cleanErr = pcall(trash[i])
			if not ok then
				warn("[Crates] cleanup: " .. tostring(cleanErr))
			end
		end
		if seqOk then
			action = seqResult
		else
			warn("[Crates] " .. tostring(seqResult))
			pcall(function()
				RunService:UnbindFromRenderStep(CAM_BIND)
			end)
			action = "Close"
		end
		if action ~= "Again" then
			break
		end
		-- Noch eine: direkt weiter, der Bildschirm ist schon schwarz
		local coinsNow = tonumber(result.Coins) or profileCoins()
		if not def.Free and coinsNow < def.Price then
			errorToast("Not enough coins!")
			action = "Close"
			break
		end
		local nextResult, nextErr = requestOpen(crateId)
		if not nextResult then
			errorToast(nextErr or "Error")
			action = "Close"
			break
		end
		result = nextResult
	end

	restoreCamera()
	State.InCrateOpening = false
	State.SetBusy("Crate", false)
	State.SetHUDHidden("Crate", false)
	State.ProfileChanged:Fire()
	fadeTo(1, 0.35)
	openGui.Enabled = false
	busy = false
	for _, abilityId in opened do
		State.TutorialEvent:Fire("CrateOpened", abilityId)
	end

	if action == "Preview" then
		task.wait(0.3)
		VFXController.Preview(result.AbilityId)
	end
end

function CratesController.Init()
	window = UI.Window({ Title = "CRATES", Size = Vector2.new(1060, 660), Name = "Crates", Color = C.Gold })

	-- Muenzen in der Kopfleiste
	local wallet = Make("Frame", {
		Name = "Wallet",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -82, 0.5, 0),
		Size = UDim2.fromOffset(176, 48),
		Parent = window.Header,
	})
	local plate = UI.Panel({
		Name = "Plate",
		Color = C.PanelDark,
		Radius = 20,
		Position = UDim2.fromOffset(24, 5),
		Size = UDim2.fromOffset(152, 38),
		Parent = wallet,
	})
	local label = UI.Text({
		Name = "Amount",
		Text = "0",
		Font = F.Heading,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(32, 3),
		Size = UDim2.new(1, -42, 1, -6),
		Stroke = 2,
		Parent = plate,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12, Parent = label })
	walletLabel = label
	drawCoin(wallet, 46, UDim2.fromOffset(0, 1), 3)

	UI.Text({
		Name = "Info",
		Text = "Every chest holds one ability. Rarer drops have bigger effects – duplicates refund coins.",
		Font = F.Body,
		TextSize = 15,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(28, 10),
		Size = UDim2.new(1, -56, 0, 22),
		Parent = window.Content,
	})
	cardsHolder = Make("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -50),
		Parent = window.Content,
	})
	UI.List(cardsHolder, true, 20, Enum.HorizontalAlignment.Center)
	buildOpenGui()

	-- Vorschau-Truhen nur animieren, solange das Fenster offen ist
	window.Opened:Connect(function()
		setViewportsAnimating(true)
	end)
	window.Closed:Connect(function()
		setViewportsAnimating(false)
	end)
end

function CratesController.Start()
	State.ProfileChanged:Connect(function()
		updateWallet()
		if window.IsOpen and not busy then
			-- Gratis-Kiste ggf. ein-/ausblenden
			rebuildCards()
		end
	end)
	-- Grotte schon vorbauen (und sofort parken), damit die erste Oeffnung nicht stockt
	task.delay(4, function()
		if not stage and not busy then
			local ok, err = pcall(buildStage)
			if not ok then
				warn("[Crates] stage: " .. tostring(err))
			elseif not busy then
				setStageActive(false)
			end
		end
	end)
end

return CratesController
