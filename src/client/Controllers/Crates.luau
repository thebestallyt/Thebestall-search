-- Kisten-Shop + die befriedigende 3D-Oeffnungs-Sequenz:
-- Kiste faellt auf eine Buehne, man tippt 3x drauf, sie bekommt Risse und kann die Farbe
-- (Seltenheit) wechseln. Bei MYTHISCH/GOETTLICH verwandelt sie sich dramatisch, bevor sie aufplatzt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local TEX = Effects.Textures
local WHITE = Color3.new(1, 1, 1)

local window: UI.Window
local cardsHolder: Frame
local viewportCrates: { any } = {}
local busy = false

-- =============================================================================
-- Kisten-Fenster
-- =============================================================================

local function rarityOrder(): { any }
	local list = {}
	for _, r in Rarities.List do
		if r.Id ~= "Exclusive" then
			table.insert(list, r)
		end
	end
	return list
end

local function buildCard(def: any, order: number)
	local trim: Color3 = def.TrimColor
	local card = UI.Panel({
		Name = def.Id,
		Size = UDim2.fromOffset(222, 470),
		LayoutOrder = order,
		StrokeColor = ColorSequence.new(trim, trim:Lerp(WHITE, 0.5)),
		Parent = cardsHolder,
	})
	local vp = Make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 170),
		Ambient = Color3.fromRGB(150, 140, 180),
		LightColor = WHITE,
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = card,
	})
	local cam = Make("Camera", { FieldOfView = 40, Parent = vp })
	vp.CurrentCamera = cam
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 4.2, 10.5), Vector3.new(0, 2, 0))
	local crate = CrateModel.Build(def, vp, 1)
	crate:SetCFrame(CFrame.new())
	table.insert(viewportCrates, { crate = crate, phase = order })

	UI.Text({
		Text = string.upper(def.Name),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = trim:Lerp(WHITE, 0.4),
		Position = UDim2.fromOffset(0, 168),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = card,
	})
	UI.Text({
		Text = def.Description,
		Font = Theme.Fonts.Body,
		TextSize = 13,
		TextColor3 = C.SubText,
		Position = UDim2.fromOffset(12, 196),
		Size = UDim2.new(1, -24, 0, 50),
		Parent = card,
	})
	-- Chancen
	local odds = Crates.GetOdds(def)
	local oddsFrame = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(10, 8, 22),
		BackgroundTransparency = 0.3,
		Position = UDim2.fromOffset(12, 250),
		Size = UDim2.new(1, -24, 0, 140),
		Parent = card,
	})
	UI.Corner(oddsFrame, 10)
	UI.Padding(oddsFrame, 6)
	UI.List(oddsFrame, false, 1)
	for i, r in rarityOrder() do
		local pct = odds[r.Id]
		if pct then
			local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 17), LayoutOrder = i, Parent = oddsFrame })
			UI.Text({
				Text = r.Name,
				Font = Theme.Fonts.Title,
				TextSize = 12,
				TextColor3 = r.Color,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(0.7, 1),
				Parent = row,
			})
			UI.Text({
				Text = (if pct < 1 then string.format("%.1f", pct) else tostring(math.floor(pct + 0.5))) .. "%",
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromScale(0.7, 0),
				Size = UDim2.fromScale(0.3, 1),
				Parent = row,
			})
		end
	end
	local priceText = if def.Free then "FREE!" else "🪙 " .. UI.Format(def.Price)
	local button = UI.Button({
		Text = priceText,
		Style = if def.Free then "Success" else "Gold",
		Size = UDim2.new(1, -24, 0, 56),
		Position = UDim2.new(0, 12, 1, -68),
		TextSize = 22,
		Parent = card,
	})
	button.Activated:Connect(function()
		CratesController.Purchase(def.Id, button)
	end)
	if def.Free then
		local badge = UI.Text({
			Text = "🎉 GIFT",
			Font = Theme.Fonts.Title,
			TextSize = 14,
			TextColor3 = C.Success,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = card,
		})
		local _ = badge
	end
end

local function rebuildCards()
	for _, child in cardsHolder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(viewportCrates)
	local profile = State.Profile
	local list = table.clone(Crates.List)
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	local i = 0
	for _, def in list do
		if def.Free and not (profile and profile.FreeCrate) then
			continue
		end
		i += 1
		buildCard(def, i)
	end
end

function CratesController.OpenWindow()
	if busy or State.InCrateOpening then
		return
	end
	rebuildCards()
	window:Open()
end

-- =============================================================================
-- Die Oeffnungs-Buehne
-- =============================================================================

local stage: any = nil

local function buildStage()
	if stage and stage.Folder.Parent then
		return stage
	end
	local base: Vector3 = Config.World.CrateStage
	local folder = Make("Folder", { Name = "CrateStage", Parent = Effects.Folder })
	local function part(props: { [string]: any }): Part
		props.Parent = folder
		return Effects.Part(props)
	end
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 90, 90),
		CFrame = CFrame.new(base - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.25,
		Color = Color3.fromRGB(12, 10, 26),
	})
	local pedestalTop = base + Vector3.new(0, 1.2, 0)
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 8.4, 8.4),
		CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(26, 22, 44),
	})
	local rim = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 8.9, 8.9),
		CFrame = CFrame.new(base + Vector3.new(0, 1.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Cyan,
	})
	local auraFloor = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, 22, 22),
		CFrame = CFrame.new(base + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Purple,
		Transparency = 0.8,
	})
	local auraWall = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 90, 90),
		CFrame = CFrame.new(base + Vector3.new(0, 14, -34)) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(40, 20, 80),
		Transparency = 0.55,
	})
	local rays = {}
	for i = 1, 7 do
		local x = (i - 4) * 5
		local ray = part({
			Size = Vector3.new(1.6, 70, 0.2),
			CFrame = CFrame.new(base + Vector3.new(x, 30, -20)) * CFrame.Angles(0, 0, math.rad(x * 0.8)),
			Color = C.Purple,
			Transparency = 0.9,
		})
		table.insert(rays, ray)
	end
	local lamp = part({ Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1, CFrame = CFrame.lookAt(base + Vector3.new(0, 20, 6), base) })
	Make("SpotLight", { Face = Enum.NormalId.Front, Angle = 50, Range = 40, Brightness = 5, Color = WHITE, Parent = lamp })
	local fill = part({ Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1, CFrame = CFrame.new(base + Vector3.new(0, 6, 10)) })
	local fillLight = Make("PointLight", { Range = 30, Brightness = 1.5, Color = C.Purple, Parent = fill })
	local dust = part({ Size = Vector3.new(40, 16, 30), Transparency = 1, CFrame = CFrame.new(base + Vector3.new(0, 8, -5)) })
	Effects.Emitter(dust, {
		Texture = TEX.Sparkle,
		Rate = 12,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(Color3.fromRGB(200, 180, 255)),
		Speed = NumberRange.new(0.2, 1),
		Lifetime = NumberRange.new(3, 5),
		Size = NumberSequence.new(0.25),
		Transparency = Effects.NSeq(1, 0.3, 1),
	})
	stage = {
		Folder = folder,
		Base = base,
		PedestalTop = pedestalTop,
		Rim = rim,
		AuraFloor = auraFloor,
		AuraWall = auraWall,
		Rays = rays,
		FillLight = fillLight,
	}
	return stage
end

local function setStageColor(color: Color3, time: number)
	if not stage then
		return
	end
	UI.Tween(stage.Rim, time, { Color = color })
	UI.Tween(stage.AuraFloor, time, { Color = color, Transparency = 0.65 })
	UI.Tween(stage.AuraWall, time, { Color = color:Lerp(Color3.new(0, 0, 0), 0.6) })
	UI.Tween(stage.FillLight, time, { Color = color })
	for _, r in stage.Rays do
		UI.Tween(r, time, { Color = color, Transparency = 0.8 })
	end
end

-- =============================================================================
-- Oeffnungs-Sequenz
-- =============================================================================

local openGui: ScreenGui
local fade: Frame
local tierLabel: TextLabel
local tierGradient: UIGradient
local promptLabel: TextLabel
local tapDots: { Frame } = {}
local tapCatcher: TextButton
local revealHolder: Frame
local tapSignal = Signal.new()
local waitingForTap = false

local function buildOpenGui()
	openGui = UI.Screen("NovaCrateOpen", 30)
	openGui.Enabled = false
	tapCatcher = Make("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = openGui,
	})
	tapCatcher.Activated:Connect(function()
		if waitingForTap then
			tapSignal:Fire()
		end
	end)
	tierLabel = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 72,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.new(1, 0, 0, 90),
		TextWrapped = false,
		ZIndex = 5,
		Parent = openGui,
	})
	Make("UIStroke", { Thickness = 4, Color = Color3.new(0, 0, 0), Transparency = 0.2, Parent = tierLabel })
	tierGradient = UI.Gradient(tierLabel, Theme.Gradients.Main, 0)
	UI.Animate(tierGradient, 0.5, "Offset")
	UI.Scaled(tierLabel)
	promptLabel = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 5,
		Parent = openGui,
	})
	Make("UIStroke", { Thickness = 3, Parent = promptLabel })
	local dots = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.92),
		Size = UDim2.fromOffset(120, 26),
		Parent = openGui,
	})
	UI.List(dots, true, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, 3 do
		local d = Make("Frame", { BackgroundColor3 = C.Muted, Size = UDim2.fromOffset(20, 20), LayoutOrder = i, Parent = dots })
		UI.Round(d)
		UI.Stroke(d, WHITE, 2, 0.3)
		table.insert(tapDots, d)
	end
	revealHolder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = openGui })
	fade = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = openGui,
	})
end

local function fadeTo(transparency: number, time: number)
	UI.Tween(fade, time, { BackgroundTransparency = transparency }, Enum.EasingStyle.Quad)
	task.wait(time)
end

local function showTier(rarity: any, big: boolean)
	tierLabel.Text = rarity.Name .. (if big then "!" else "")
	tierGradient.Color = rarity.Gradient
	tierLabel.TextTransparency = 0
	UI.Pop(tierLabel, if big then 2.2 else 1.6, 0.4)
end

local function waitTap(timeout: number): boolean
	waitingForTap = true
	local done = false
	local conn = tapSignal:Once(function()
		done = true
	end)
	local start = os.clock()
	while not done and os.clock() - start < timeout do
		task.wait()
	end
	conn:Disconnect()
	waitingForTap = false
	return done
end

-- Ergebnis-Karte -----------------------------------------------------------------

local function showReveal(result: any, crateDef: any, onAction: (string) -> ())
	for _, c in revealHolder:GetChildren() do
		c:Destroy()
	end
	local def = Abilities.Get(result.AbilityId) :: any
	local rarity = Rarities.Get(def.Rarity)
	local card = UI.Panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1.5, 0),
		Size = UDim2.fromOffset(700, 260),
		StrokeColor = rarity.Gradient,
		ZIndex = 10,
		Parent = revealHolder,
	})
	UI.Scaled(card)
	UI.Tween(card, 0.6, { Position = UDim2.new(0.5, 0, 0.8, 0) }, Enum.EasingStyle.Back)
	local iconBox = Make("Frame", {
		BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(24, 30),
		Size = UDim2.fromOffset(200, 200),
		Parent = card,
	})
	UI.Corner(iconBox, 24)
	UI.Gradient(iconBox, ColorSequence.new(rarity.Color, rarity.Dark), 135)
	local iconStroke = UI.Stroke(iconBox, WHITE, 4, 0.2)
	local sg = UI.Gradient(iconStroke, rarity.Gradient, 0)
	UI.Animate(sg, 120, "Rotate")
	local icon = UI.Text({ Text = def.Icon, TextSize = 110, Size = UDim2.fromScale(1, 1), Parent = iconBox })
	UI.Pop(iconBox, 0.2, 0.6)
	local _ = icon
	local tag = UI.Text({
		Text = "✦ " .. rarity.Name .. " ✦",
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextColor3 = rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(248, 26),
		Size = UDim2.fromOffset(420, 26),
		Parent = card,
	})
	local _t = tag
	local name = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(246, 52),
		Size = UDim2.fromOffset(440, 54),
		TextWrapped = false,
		Parent = card,
	})
	UI.Gradient(name, ColorSequence.new(WHITE, rarity.Glow), 90)
	task.spawn(function()
		local full = string.upper(def.Name)
		for i = 1, #full do
			name.Text = string.sub(full, 1, i)
			task.wait(0.03)
		end
	end)
	UI.Text({
		Text = def.Description,
		Font = Theme.Fonts.Body,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(248, 108),
		Size = UDim2.fromOffset(430, 60),
		Parent = card,
	})
	local stats = "⚔️ " .. def.Damage .. " Damage     ⏱ " .. def.Cooldown .. "s Cooldown"
	if def.Cutscene then
		stats ..= "     🎬 <font color='#ffd34a'>CUTSCENE</font>"
	end
	UI.Text({
		Text = stats,
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(248, 172),
		Size = UDim2.fromOffset(430, 24),
		Parent = card,
	})
	local badge = UI.Text({
		Text = if result.IsNew then "★ NEW!" else "DUPLICATE  +" .. result.Refund .. " 🪙",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = if result.IsNew then C.Gold else C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(248, 200),
		Size = UDim2.fromOffset(420, 30),
		Parent = card,
	})
	if result.IsNew then
		UI.Gradient(badge, Theme.Gradients.Gold, 0)
		UI.Pop(badge, 2, 0.5)
	end

	-- Knoepfe
	local row = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 16),
		Size = UDim2.fromOffset(700, 58),
		Parent = card,
	})
	UI.List(row, true, 14, Enum.HorizontalAlignment.Center)
	local profile = State.Profile
	if not crateDef.Free and profile and profile.Coins >= crateDef.Price then
		UI.Button({
			Text = "AGAIN  🪙 " .. UI.Format(crateDef.Price),
			Style = "Gold",
			Size = UDim2.fromOffset(250, 56),
			LayoutOrder = 1,
			Parent = row,
			OnClick = function()
				onAction("Again")
			end,
		})
	end
	UI.Button({
		Text = "▶ PREVIEW",
		Style = "Primary",
		Size = UDim2.fromOffset(190, 56),
		LayoutOrder = 2,
		Parent = row,
		OnClick = function()
			onAction("Preview")
		end,
	})
	UI.Button({
		Text = "CONTINUE",
		Style = "Secondary",
		Size = UDim2.fromOffset(170, 56),
		LayoutOrder = 3,
		Parent = row,
		OnClick = function()
			onAction("Close")
		end,
	})
	UI.Burst(revealHolder, UDim2.fromScale(0.5, 0.45), { rarity.Color, rarity.Glow, WHITE, C.Gold }, 50 + rarity.Tier * 12, 520)
end

-- Hauptablauf ---------------------------------------------------------------------

local function runOpening(result: any, crateDef: any): string
	local s = buildStage()
	local finalRarity = Rarities.Get(result.Rarity)
	local finalTier = finalRarity.Tier
	local def = Abilities.Get(result.AbilityId) :: any

	-- Start-Stufe = niedrigste Stufe, die in dieser Kiste vorkommt
	local startTier = finalTier
	for rid in crateDef.Weights do
		startTier = math.min(startTier, Rarities.Get(rid).Tier)
	end
	local increments = { 0, 0, 0, 0 }
	local ups = finalTier - startTier
	for i = 1, ups do
		local slot = if finalTier >= 6 and i == ups then 4 else math.random(1, 3)
		increments[slot] += 1
	end
	local displayTier = startTier

	-- Erst schwarz abblenden, dann die Kamera umschalten
	openGui.Enabled = true
	tierLabel.Text = ""
	promptLabel.Text = ""
	fadeTo(0, 0.25)

	-- Kamera
	local cam = workspace.CurrentCamera :: Camera
	local pedestal = s.PedestalTop
	local lookAt = pedestal + Vector3.new(0, 2.2, 0)
	local camBase = pedestal + Vector3.new(0, 3.8, 14)
	local zoom = 0
	local camStart = os.clock()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 50
	RunService:BindToRenderStep("NovaCrateCam", Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - camStart
		local sway = Vector3.new(math.sin(t * 0.6) * 0.6, math.sin(t * 0.8) * 0.25, 0)
		local pos = camBase + sway
		pos = pos:Lerp(lookAt + Vector3.new(0, 0.8, 7.5), zoom)
		cam.CFrame = CFrame.lookAt(pos, lookAt)
	end)

	-- Kiste
	local crate = CrateModel.Build(crateDef, s.Folder, 1)
	local startRarity = Rarities.ByTier(startTier)
	crate:SetTrim(startRarity.Color)
	setStageColor(startRarity.Color, 0.1)
	local hover, bob, shake = 14, 0, 0
	local jolt: { Start: number, RX: number, RZ: number, Power: number }? = nil
	local yaw = 0
	local animConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cf = CFrame.new(pedestal) * CFrame.new(0, hover + math.sin(t * 2.2) * bob, 0) * CFrame.Angles(0, math.sin(t * 0.7) * 0.12 + yaw, 0)
		if jolt then
			local j = jolt
			local a = math.clamp((t - j.Start) / 0.3, 0, 1)
			local k = math.sin(a * math.pi) * (1 - a * 0.3)
			cf = cf * CFrame.new(0, k * 0.7 * j.Power, 0) * CFrame.Angles(j.RX * (1 - a), 0, j.RZ * (1 - a))
			if a >= 1 then
				jolt = nil
			end
		end
		if shake > 0 then
			local r = Effects.Random
			cf = cf
				* CFrame.new(r:NextNumber(-1, 1) * shake * 0.08, r:NextNumber(-1, 1) * shake * 0.05, r:NextNumber(-1, 1) * shake * 0.08)
				* CFrame.Angles(r:NextNumber(-1, 1) * shake * 0.03, r:NextNumber(-1, 1) * shake * 0.03, r:NextNumber(-1, 1) * shake * 0.03)
		end
		crate:SetCFrame(cf)
	end)
	local crateCenter = function(): Vector3
		return crate.Base.Position + Vector3.new(0, 1.8, 0)
	end

	for _, d in tapDots do
		d.BackgroundColor3 = C.Muted
	end
	fadeTo(1, 0.35)

	-- 1) Kiste faellt herunter
	Effects.Sound("Whoosh", pedestal, { Pitch = 0.7 })
	local dropStart = os.clock()
	while os.clock() - dropStart < 0.5 do
		local a = (os.clock() - dropStart) / 0.5
		hover = 14 * (1 - a * a)
		task.wait()
	end
	hover = 0
	Effects.Sound("CrateLand", pedestal)
	Effects.Shake(1.4, 0.35)
	Effects.GroundRing(pedestal + Vector3.new(0, 0.1, 0), 1, 9, startRarity.Color, 0.5, 1.2)
	Effects.Burst(pedestal + Vector3.new(0, 0.3, 0), 22, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(150, 140, 180)),
		LightEmission = 0,
		LightInfluence = 0.6,
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(90, 10),
		Size = Effects.NSeq(1.2, 3),
		Transparency = Effects.NSeq(0.4, 1),
	})
	jolt = { Start = os.clock(), RX = 0.05, RZ = -0.04, Power = 0.4 }
	showTier(startRarity, false)
	task.wait(0.45)
	bob = 0.12

	-- 2) Drei Mal tippen
	local tierEffects: { () -> () } = {}
	local function upgradeTo(tier: number, huge: boolean)
		local r = Rarities.ByTier(tier)
		local center = crateCenter()
		crate:SetTrim(r.Color, 0.12)
		setStageColor(r.Color, 0.25)
		Effects.Flash(center, WHITE, if huge then 16 else 9, 0.25)
		Effects.Flash(center, r.Color, if huge then 22 else 13, 0.45)
		Effects.GroundRing(pedestal + Vector3.new(0, 0.12, 0), 1, if huge then 18 else 11, r.Color, 0.55, 1.4)
		Effects.Burst(center, 40 + tier * 8, {
			Texture = TEX.Sparkle,
			Color = Effects.Seq(WHITE, r.Color),
			Speed = NumberRange.new(10, 26),
			Size = Effects.NSeq(0.8, 0),
			Drag = 2,
		})
		Effects.ScreenFlash(r.Color, 0.35, if huge then 0.2 else 0.65)
		Effects.Sound("CrateUpgrade", center, { Pitch = 0.75 + tier * 0.12 })
		Effects.Shake(0.6 + tier * 0.18, 0.3)
		showTier(r, true)
		if tier >= 5 and not tierEffects[5] then
			tierEffects[5] = function() end
			Effects.Stream(crate.Entries[1].part, 30, {
				Texture = TEX.Sparkle,
				Rate = 30,
				Color = Effects.Seq(WHITE, C.Gold),
				Speed = NumberRange.new(2, 5),
				Size = Effects.NSeq(0.6, 0),
				Lifetime = NumberRange.new(0.6, 1),
			})
		end
	end

	for tap = 1, 3 do
		promptLabel.Text = if tap == 1 then "👆 TAP THE CRATE!" else "👆 AGAIN! (" .. (4 - tap) .. ")"
		UI.Pop(promptLabel, 0.8, 0.25)
		waitTap(7)
		tapDots[tap].BackgroundColor3 = Rarities.ByTier(displayTier + increments[tap]).Color
		UI.Pop(tapDots[tap], 1.8, 0.3)
		local r = Effects.Random
		jolt = { Start = os.clock(), RX = r:NextNumber(-0.25, 0.25), RZ = r:NextNumber(-0.3, 0.3), Power = 0.8 + tap * 0.3 }
		Effects.Sound("CrateTap", crateCenter(), { Pitch = 1 + tap * 0.15 })
		Effects.Shake(0.5 + tap * 0.3, 0.2)
		crate:AddCrack(Rarities.ByTier(displayTier).Color)
		crate:AddCrack(Rarities.ByTier(displayTier).Color)
		Effects.Burst(crateCenter() + Vector3.new(0, 0, -1.5), 14, {
			Texture = TEX.Sparks,
			Color = Effects.Seq(WHITE, Rarities.ByTier(displayTier).Color),
			Speed = NumberRange.new(12, 24),
			Size = Effects.NSeq(0.4, 0),
			Drag = 4,
		})
		if increments[tap] > 0 then
			task.wait(0.12)
			for _ = 1, increments[tap] do
				displayTier += 1
				upgradeTo(displayTier, false)
				task.wait(0.32)
			end
		end
		shake = tap * 0.35
	end
	promptLabel.Text = ""

	-- 3) Aufladen / Verwandlung
	local finalColor = finalRarity.Color
	if finalTier >= 6 then
		promptLabel.Text = if finalTier >= 7 then "✨ A DIVINE POWER AWAKENS..." else "⚠ SOMETHING POWERFUL AWAKENS..."
		UI.Pop(promptLabel, 1.4, 0.4)
		Effects.ColorGrade({ Brightness = -0.15, Contrast = 0.3, Saturation = -0.3 }, 0.4, 1.6, 0.4)
		Effects.Sound("Rumble", pedestal, { Pitch = 0.6 })
		Effects.Sound("MythicReveal", pedestal)
		local t0 = os.clock()
		local boltTimer = 0
		while os.clock() - t0 < 2 do
			local a = (os.clock() - t0) / 2
			hover = 2.4 * Effects.Ease(a, "OutCubic")
			shake = 1 + a * 3
			zoom = a * 0.55
			boltTimer += task.wait()
			if boltTimer > 0.12 then
				boltTimer = 0
				local c = crateCenter()
				local dir = Vector3.new(math.random() - 0.5, math.random() - 0.2, math.random() - 0.5).Unit
				Effects.Bolt(c + dir * 2, c + dir * math.random(6, 10), {
					Color = Rarities.ByTier(displayTier).Color,
					Width = 0.2,
					Duration = 0.18,
					Segments = 5,
				})
			end
		end
		while displayTier < finalTier do
			displayTier += 1
			upgradeTo(displayTier, true)
			task.wait(0.4)
		end
		if finalTier >= 7 then
			-- Regenbogen-Kanten
			local rainbowStart = os.clock()
			task.spawn(function()
				while crate.Model.Parent and os.clock() - rainbowStart < 6 do
					crate:SetTrim(Color3.fromHSV(((os.clock() - rainbowStart) * 0.6) % 1, 0.6, 1))
					task.wait(0.05)
				end
			end)
		end
	else
		local t0 = os.clock()
		Effects.Sound("Charge", pedestal, { Pitch = 1.3, Volume = 0.6 })
		while os.clock() - t0 < 0.6 do
			local a = (os.clock() - t0) / 0.6
			shake = 1 + a * 2
			hover = a * 0.8
			zoom = a * 0.2
			task.wait()
		end
	end
	promptLabel.Text = ""

	-- 4) Aufplatzen!
	shake = 0
	local top = crateCenter() + Vector3.new(0, 1.5, 0)
	local lidStart = os.clock()
	local lidSpin = (math.random() - 0.5) * 2
	task.spawn(function()
		while os.clock() - lidStart < 0.8 and crate.Model.Parent do
			local a = (os.clock() - lidStart) / 0.8
			local e = Effects.Ease(a, "OutCubic")
			crate.LidTransform = CFrame.new(0, 3.4 + e * 8, 1.6 + e * 4)
				* CFrame.Angles(math.rad(-130 * e), lidSpin * e, 0)
				* CFrame.new(0, -3.4, -1.6)
			task.wait()
		end
		for _, p in crate:LidParts() do
			UI.Tween(p, 0.3, { Transparency = 1 })
		end
	end)
	Effects.Flash(top, WHITE, 18, 0.45)
	Effects.Flash(top, finalColor, 26, 0.7)
	Effects.GroundRing(pedestal + Vector3.new(0, 0.15, 0), 1, 22, finalColor, 0.8, 2.5)
	Effects.Shockwave(top, 50, finalColor, 0.6)
	Effects.BurstDir(top, Vector3.yAxis, 70 + finalTier * 15, {
		Texture = TEX.Sparkle,
		Color = finalRarity.Gradient,
		Speed = NumberRange.new(25, 55),
		SpreadAngle = Vector2.new(35, 35),
		Lifetime = NumberRange.new(0.8, 1.5),
		Acceleration = Vector3.new(0, -25, 0),
		Size = Effects.NSeq(1.1, 0),
		Drag = 1,
	})
	local beam = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 2, 2),
		CFrame = CFrame.new(top + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = finalColor,
		Transparency = 0.15,
		Parent = s.Folder,
	})
	UI.Tween(beam, 0.3, { Size = Vector3.new(60, 6, 6) }, Enum.EasingStyle.Back)
	UI.Tween(beam, 1.6, { Transparency = 1, Size = Vector3.new(60, 1, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.5)
	Effects.Clean(beam, 2.2)
	Effects.Light(top, finalColor, 40, 10, 1.2)
	Effects.Shake(1.5 + finalTier * 0.4, 0.6)
	if finalTier >= 4 then
		Effects.ScreenFlash(WHITE, 0.5, 0.15)
	end
	Effects.Sound("CrateOpen", top)
	Effects.Sound(if finalTier >= 6 then "MythicReveal" else "Reveal", top)

	-- 5) Faehigkeits-Kugel steigt auf
	local orb = Effects.Ball(CFrame.new(crateCenter()), 2.2, def.Color, { Parent = s.Folder })
	local orbGlow = Effects.Ball(CFrame.new(crateCenter()), 3.6, def.Color2, { Transparency = 0.6, Parent = s.Folder })
	Make("PointLight", { Color = def.Color, Range = 18, Brightness = 5, Parent = orb })
	Effects.Stream(orb, 30, {
		Texture = TEX.Sparkle,
		Rate = 40,
		Color = Effects.Seq(WHITE, def.Color),
		Speed = NumberRange.new(2, 6),
		Size = Effects.NSeq(0.7, 0),
	})
	local orbTarget = crateCenter() + Vector3.new(0, 4.6, 0)
	UI.Tween(orb, 0.7, { CFrame = CFrame.new(orbTarget) }, Enum.EasingStyle.Back)
	UI.Tween(orbGlow, 0.7, { CFrame = CFrame.new(orbTarget) }, Enum.EasingStyle.Back)
	local ringAnchor = Effects.Anchor(orbTarget)
	ringAnchor.Parent = s.Folder
	local orbitRing = Make("CylinderHandleAdornment", {
		Adornee = ringAnchor,
		Color3 = def.Color2,
		Radius = 2.6,
		InnerRadius = 2.4,
		Height = 0.1,
		Transparency = 0.2,
		Parent = ringAnchor,
	})
	local orbConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		orbitRing.CFrame = CFrame.Angles(t * 2, t * 1.3, 0)
		orbGlow.Size = Vector3.one * (3.6 + math.sin(t * 6) * 0.3)
	end)
	task.wait(0.5)
	zoom = 0.25

	-- 6) Ergebnis-Karte
	local action: string? = nil
	showReveal(result, crateDef, function(a)
		action = a
	end)
	while action == nil do
		task.wait()
	end

	-- Aufraeumen
	fadeTo(0, 0.3)
	orbConn:Disconnect()
	animConn:Disconnect()
	RunService:UnbindFromRenderStep("NovaCrateCam")
	crate:Destroy()
	ringAnchor:Destroy()
	orb:Destroy()
	orbGlow:Destroy()
	if beam.Parent then
		beam:Destroy()
	end
	for _, c in revealHolder:GetChildren() do
		c:Destroy()
	end
	tierLabel.Text = ""
	return action :: string
end

local function restoreCamera()
	local cam = workspace.CurrentCamera :: Camera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

function CratesController.Purchase(crateId: string, sourceButton: GuiObject?)
	if busy then
		return
	end
	local def = Crates.Get(crateId)
	if not def then
		return
	end
	local profile = State.Profile
	if not def.Free and profile and profile.Coins < def.Price then
		if sourceButton then
			UI.Shake(sourceButton)
		end
		HUD.Toast({ Text = "Not enough coins! Win rounds or grab coins in the shop.", Color = C.Danger, Icon = "🪙" })
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Net.Function("OpenCrate"):InvokeServer(crateId)
	end)
	if not ok or type(result) ~= "table" or not result.Ok then
		busy = false
		if sourceButton then
			UI.Shake(sourceButton)
		end
		HUD.Toast({
			Text = if ok and type(result) == "table" then result.Message or "Error" else "Connection error",
			Color = C.Danger,
			Icon = "⚠️",
		})
		return
	end

	-- Sequenz starten
	window:Close()
	State.InCrateOpening = true
	State.SetBusy("Crate", true)
	State.SetHUDHidden("Crate", true)
	local seqOk, action = pcall(runOpening, result, def)
	if not seqOk then
		warn("[Crates] " .. tostring(action))
		action = "Close"
		RunService:UnbindFromRenderStep("NovaCrateCam")
	end
	restoreCamera()
	State.InCrateOpening = false
	State.SetBusy("Crate", false)
	State.SetHUDHidden("Crate", false)
	State.ProfileChanged:Fire()
	fadeTo(1, 0.35)
	openGui.Enabled = false
	busy = false
	State.TutorialEvent:Fire("CrateOpened", result.AbilityId)

	if action == "Again" then
		CratesController.Purchase(crateId)
	elseif action == "Preview" then
		task.wait(0.3)
		VFXController.Preview(result.AbilityId)
	end
end

function CratesController.Init()
	window = UI.Window({ Title = "CRATES", Icon = "🎁", Size = Vector2.new(1010, 600), Name = "Crates" })
	local info = UI.Text({
		Text = "Open crates for new abilities – the rarer, the more spectacular! Duplicates refund coins.",
		Font = Theme.Fonts.Body,
		TextSize = 15,
		TextColor3 = C.SubText,
		Position = UDim2.fromOffset(26, 4),
		Size = UDim2.new(1, -52, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window.Content,
	})
	local _ = info
	cardsHolder = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 36),
		Size = UDim2.new(1, -40, 1, -50),
		Parent = window.Content,
	})
	UI.List(cardsHolder, true, 18, Enum.HorizontalAlignment.Center)
	buildOpenGui()

	-- Kisten in den Vorschau-Fenstern drehen
	RunService.RenderStepped:Connect(function()
		if not window.IsOpen then
			return
		end
		local t = os.clock()
		for _, v in viewportCrates do
			v.crate:SetCFrame(CFrame.new(0, math.sin(t * 2 + v.phase) * 0.15, 0) * CFrame.Angles(0, t * 0.8 + v.phase, 0))
		end
	end)
end

function CratesController.Start()
	State.ProfileChanged:Connect(function()
		if window.IsOpen and not busy then
			-- Gratis-Kiste ggf. ausblenden
			local profile = State.Profile
			local hasStarter = cardsHolder:FindFirstChild("Starter") ~= nil
			if profile and hasStarter ~= (profile.FreeCrate == true) then
				rebuildCards()
			end
		end
	end)
end

return CratesController
