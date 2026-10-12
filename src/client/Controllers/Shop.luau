-- Robux-Shop von NOVA CLASH.
-- Aufbau: Fenster mit Kategorien links (FEATURED / COINS) und einer Inhaltsseite rechts.
--  * FEATURED: Hero-Karte fuer die exklusive BLACK HOLE Faehigkeit (Game Pass) mit einem lebendigen
--    3D-Schwarzen-Loch im Viewport (Ereignishorizont, Photonenring, geneigte Akkretionsscheibe, Truemmer).
--  * COINS: Muenzpakete (Developer Products) mit 3D-Muenzbergen, die sich langsam drehen.
-- Alle Animationen laufen nur, solange das Fenster offen ist (RenderStepped wird beim Schliessen getrennt).
-- Kauf: Net.Function("BuyItem"):InvokeServer("BlackHole") bzw. ("Coins", index)
--       -> { Ok, Message?, Simulated?, Granted?, Prompted? }

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local VFXController = require(Controllers:WaitForChild("VFXController"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Shop = {}

local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local player = Players.LocalPlayer

-- Layout (alle Abstaende in 4er/8er-Schritten) -------------------------------------------
local WINDOW_SIZE = Vector2.new(1000, 640)
local MARGIN = 24 -- Aussenabstand links/rechts im Inhaltsbereich
local TOP = 16 -- Abstand oben/unten im Inhaltsbereich
local SIDEBAR_W = 196
local COLUMN_GAP = 20
local PAGE_X = MARGIN + SIDEBAR_W + COLUMN_GAP
local PAGE_W = WINDOW_SIZE.X - PAGE_X - MARGIN

local STAGE_W = 352 -- 3D-Buehne der Hero-Karte
local INFO_X = 16 + STAGE_W + 28 -- Textspalte rechts neben der Buehne
local INFO_RIGHT = 24
local INFO_W = PAGE_W - INFO_X - INFO_RIGHT

local CARD_GAP = 20

-- Farben der Hero-Karte: tiefes, ruhiges Violett (kein Neon)
local HERO_COLOR = Color3.fromRGB(48, 38, 80)
local HERO_STAGE = Color3.fromRGB(13, 10, 24)
local HERO_INSET = Color3.fromRGB(32, 25, 56)
local HERO_MUTED = Color3.fromRGB(176, 164, 214)

local HEADER_COLOR = C.Robux

local function isTestMode(): boolean
	if Config.Shop.BlackHoleGamePassId == 0 then
		return true
	end
	for _, pack in Config.Shop.CoinPacks do
		if pack.ProductId == 0 then
			return true
		end
	end
	return false
end
local TEST_MODE = isTestMode()
local FOOTER_H = if TEST_MODE then 28 else 0

-- Zustand ----------------------------------------------------------------------------------

type Scene = (dt: number) -> ()

type PriceButton = {
	Button: TextButton,
	Icon: Frame,
	Check: Frame,
	Dim: Frame,
	Price: string, -- angezeigter Preis ohne "R$" (z.B. "399")
	Numeric: boolean, -- false = Text ohne Robux-Symbol anzeigen
	Busy: boolean,
	Owned: boolean,
}

local window: UI.Window
local pages: { [string]: Frame } = {}
local categoryButtons: { [string]: TextButton } = {}
local currentPage = ""
local openedOnce = false

local buyButton: PriceButton? = nil
local previewButton: TextButton? = nil
local heroCard: Frame? = nil
local noteLabel: TextLabel? = nil
local noteOverrideUntil = 0
local balanceLabel: TextLabel? = nil
local shownBalance = 0
local lastOwned: boolean? = nil
local purchasing = false

local packButtons: { [number]: PriceButton } = {}
local packPrices: { [number]: number } = {}
local bonusSlots: { [number]: Frame } = {}

local holeScene: Scene? = nil
local coinScenes: { Scene } = {}
local animConn: RBXScriptConnection? = nil

-- Kleine Helfer ------------------------------------------------------------------------

local function ownsBlackHole(): boolean
	return State.Owned("BlackHole") > 0
end

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	return UI.Stroke(parent, color or C.Ink, thickness, 0)
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, result = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(4000, 400))
	end)
	if ok then
		return result.X
	end
	return #text * size * 0.62
end

-- Groesste Schriftgroesse, bei der der Text in die Breite passt
local function fitTextSize(plain: string, font: Enum.Font, maxSize: number, minSize: number, width: number): number
	local size = maxSize
	while size > minSize and textWidth(plain, size, font) > width do
		size -= 1
	end
	return size
end

-- "R$ 399" -> "399", true, 399   |   "Free" -> "Free", false, nil
local function parsePrice(display: string): (string, boolean, number?)
	local digits = string.match(display, "%d[%d,]*")
	if digits then
		return digits, true, tonumber((string.gsub(digits, ",", "")))
	end
	return display, false, nil
end

-- Verankertes Teil fuer die 3D-Vorschauen (keine Physik, keine Schatten)
local function part(props: { [string]: any }): Part
	local p = Make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Material = Enum.Material.SmoothPlastic,
	})
	for k, v in props do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- Gezeichnete Symbole (Flaechen + dicke Umrisse statt Emoji) ------------------------------

-- Muenze wie im HUD: Rand + goldene Flaeche + Innenring + Glanzpunkt
local function drawCoin(parent: Instance?, size: number, position: UDim2, z: number): Frame
	local edge = math.max(2, math.floor(size * 0.09))
	local outline = math.max(1.5, size * 0.055)
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
	stroke(rim, outline)
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = C.Coin,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -edge),
		ZIndex = z + 1,
		Parent = holder,
	})
	UI.Round(face)
	stroke(face, outline)
	local inner = Make("Frame", {
		Name = "Inner",
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
		Name = "Glint",
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

-- Zwei Muenzen uebereinander (Kategorie- und Kopfleisten-Symbol)
local function drawCoinPair(parent: Instance, holderSize: Vector2, position: UDim2, anchor: Vector2): Frame
	local g = Make("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(holderSize.X, holderSize.Y),
		Parent = parent,
	})
	local small = math.floor(holderSize.Y * 0.62)
	local big = math.floor(holderSize.Y * 0.74)
	drawCoin(g, small, UDim2.fromOffset(holderSize.X - small - 1, 0), 1)
	drawCoin(g, big, UDim2.fromOffset(1, holderSize.Y - big), 5)
	return g
end

-- Abgerundeter Balken von a nach b (fuer Haken & Co.)
local function drawBar(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, z: number): Frame
	local d = b - a
	local mid = (a + b) / 2
	local bar = Make("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Size = UDim2.fromOffset(d.Magnitude + thickness, thickness),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		ZIndex = z,
		Parent = parent,
	})
	UI.Round(bar)
	return bar
end

-- Weisser Haken mit dunkler Kontur
local function drawCheck(size: number, outline: Color3): Frame
	local holder = Make("Frame", { Name = "Check", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	local s = size / 26
	local a, b, c = Vector2.new(5, 14) * s, Vector2.new(10.5, 19.5) * s, Vector2.new(21.5, 7) * s
	drawBar(holder, a, b, 8 * s, outline, 1)
	drawBar(holder, b, c, 8 * s, outline, 1)
	drawBar(holder, a, b, 4.5 * s, WHITE, 2)
	drawBar(holder, b, c, 4.5 * s, WHITE, 2)
	return holder
end

-- Robux-Symbol: Sechseck (Vereinigung dreier gedrehter Rechtecke) mit quadratischem Loch
local function drawRobux(size: number, outline: Color3, hole: Color3): Frame
	local holder = Make("Frame", { Name = "RobuxIcon", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	local function hexagon(radius: number, color: Color3, z: number)
		local w = radius * math.sqrt(3)
		for i = 0, 2 do
			local r = Make("Frame", {
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(w, radius),
				Rotation = i * 60,
				ZIndex = z,
				Parent = holder,
			})
			UI.Corner(r, math.max(1, math.floor(radius * 0.16)))
		end
	end
	local radius = size / 2
	hexagon(radius, outline, 1)
	hexagon(radius - 2.5, WHITE, 2)
	local holeSize = math.floor(radius * 0.74 + 0.5)
	local sq = Make("Frame", {
		Name = "Hole",
		BackgroundColor3 = hole,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(holeSize, holeSize),
		ZIndex = 3,
		Parent = holder,
	})
	UI.Corner(sq, 2)
	stroke(sq, 2, outline)
	return holder
end

-- Mini-Schwarzes-Loch als Kategorie-Symbol (Scheibe hinten, Loch, Scheibe vorne)
local function drawHoleGlyph(parent: Instance, z: number): Frame
	local g = Make("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = z,
		Parent = parent,
	})
	local back = Make("Frame", {
		Name = "DiskBack",
		BackgroundColor3 = Color3.fromRGB(255, 150, 52),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(38, 12),
		Rotation = -18,
		ZIndex = 1,
		Parent = g,
	})
	UI.Round(back)
	stroke(back, 2)
	local hole = Make("Frame", {
		Name = "Hole",
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 2,
		Parent = g,
	})
	UI.Round(hole)
	stroke(hole, 2, Color3.fromRGB(255, 232, 190))
	local front = Make("Frame", {
		Name = "DiskFront",
		BackgroundColor3 = Color3.fromRGB(255, 200, 104),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 3),
		Size = UDim2.fromOffset(30, 5),
		Rotation = -18,
		ZIndex = 3,
		Parent = g,
	})
	UI.Round(front)
	stroke(front, 1.5)
	return g
end

-- Schild mit Lippe (EXCLUSIVE, POPULAR, BEST VALUE, +x% BONUS ...)
type TagProps = {
	Text: string,
	Fill: Color3,
	Lip: Color3?,
	TextSize: number?,
	Height: number?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	Parent: Instance?,
}

local function makeTag(props: TagProps): Frame
	local textSize = props.TextSize or 16
	local h = props.Height or 30
	local lipH = 4
	local w = math.ceil(textWidth(props.Text, textSize, F.Heading)) + 28
	local lipColor = props.Lip or Theme.Darken(props.Fill, 0.4)
	local holder = Make("Frame", {
		Name = "Tag",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h + lipH),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
	})
	local lip = Make("Frame", {
		Name = "Lip",
		BackgroundColor3 = lipColor,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, lipH),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 1,
		Parent = holder,
	})
	UI.Corner(lip, 8)
	stroke(lip, 2.5)
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = props.Fill,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		ZIndex = 2,
		Parent = holder,
	})
	UI.Corner(face, 8)
	stroke(face, 2.5)
	UI.Shade(face)
	UI.Text({
		Name = "Label",
		Text = props.Text,
		Font = F.Heading,
		TextSize = textSize,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Stroke = 2,
		StrokeColor = Theme.Darken(lipColor, 0.45),
		Parent = face,
	})
	holder.Parent = props.Parent
	return holder
end

-- Kleiner Glanz-Funke ueber dem Muenzberg (vierzackig, Enden laufen weich aus)
local function makeGlint(parent: Instance): (Frame, UIScale)
	local g = Make("Frame", {
		Name = "Glint",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 3,
		Parent = parent,
	})
	local scale = Make("UIScale", { Scale = 0, Parent = g })
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	for i = 0, 1 do
		local bar = Make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 3),
			Rotation = i * 90,
			Parent = g,
		})
		UI.Round(bar)
		UI.Gradient(bar, nil, 0, fade)
	end
	local core = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 246, 210),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		Parent = g,
	})
	UI.Round(core)
	return g, scale
end

local function twinkle(frame: Frame, scale: UIScale, rng: Random)
	frame.Position = UDim2.fromScale(rng:NextNumber(0.3, 0.7), rng:NextNumber(0.34, 0.64))
	frame.Rotation = 0
	scale.Scale = 0
	UI.Tween(scale, 0.18, { Scale = rng:NextNumber(0.7, 1.05) }, Enum.EasingStyle.Back)
	UI.Tween(frame, 0.6, { Rotation = 45 }, Enum.EasingStyle.Quad)
	task.delay(0.22, function()
		UI.Tween(scale, 0.3, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
end

-- Robux-Kaufknopf -------------------------------------------------------------------------
-- Ein UI.Button (Stil Robux), dessen Label zusammen mit einem gezeichneten Robux-Symbol
-- zentriert in einer Zeile sitzt. Zustaende: Preis / "..." (wartet) / OWNED (gruen, gedimmt).

local function refreshPriceButton(pb: PriceButton)
	local button = pb.Button
	if pb.Owned then
		UI.SetButtonStyle(button, "Green")
		button:SetAttribute("Disabled", true)
		UI.SetButtonText(button, "OWNED")
		pb.Icon.Visible = false
		pb.Check.Visible = true
		pb.Dim.Visible = true
	else
		UI.SetButtonStyle(button, "Robux")
		button:SetAttribute("Disabled", false)
		UI.SetButtonText(button, if pb.Busy then "..." else pb.Price)
		pb.Icon.Visible = pb.Numeric and not pb.Busy
		pb.Check.Visible = false
		pb.Dim.Visible = false
	end
	local shine = button:FindFirstChild("Shine", true)
	if shine and shine:IsA("GuiObject") then
		(shine :: GuiObject).Visible = not pb.Owned
	end
end

local function makePriceButton(props: {
	Price: string,
	Size: UDim2,
	Position: UDim2?,
	TextSize: number,
	Shine: boolean?,
	Parent: Instance,
	OnClick: () -> (),
}): PriceButton
	local button = UI.Button({
		Name = "BuyButton",
		Text = "",
		Style = "Robux",
		Size = props.Size,
		Position = props.Position,
		TextSize = props.TextSize,
		Shine = props.Shine,
		Parent = props.Parent,
		OnClick = props.OnClick,
	})
	local face = button:FindFirstChild("Face") :: Frame
	local faceZ = face.ZIndex
	-- dunkler Schleier fuer den "deaktiviert"-Look (OWNED)
	local dim = Make("Frame", {
		Name = "Dim",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = faceZ + 2,
		Parent = face,
	})
	UI.Corner(dim, 12)
	local row = Make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = faceZ + 3,
		Parent = face,
	})
	UI.List(row, true, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local iconSize = math.floor(props.TextSize + 2)
	local icon = drawRobux(iconSize, Theme.Darken(C.RobuxDark, 0.45), C.RobuxDark)
	icon.LayoutOrder = 1
	icon.Parent = row
	local check = drawCheck(iconSize, Theme.Darken(C.GreenDark, 0.45))
	check.LayoutOrder = 1
	check.Visible = false
	check.Parent = row
	local label = face:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		local l = label :: TextLabel
		l.Parent = row
		l.LayoutOrder = 2
		l.Size = UDim2.fromScale(0, 1)
		l.AutomaticSize = Enum.AutomaticSize.X
	end
	local price, numeric = parsePrice(props.Price)
	local pb: PriceButton = {
		Button = button,
		Icon = icon,
		Check = check,
		Dim = dim,
		Price = price,
		Numeric = numeric,
		Busy = false,
		Owned = false,
	}
	refreshPriceButton(pb)
	return pb
end

-- Hinweiszeile, Besitz, Muenzstand --------------------------------------------------------

local function updateNote()
	local label = noteLabel
	if not label or os.clock() < noteOverrideUntil then
		return
	end
	if ownsBlackHole() then
		label.Text = "You own it! Equip it in ABILITIES."
		label.TextColor3 = C.Green
	else
		label.Text = "One-time purchase · Works in every round"
		label.TextColor3 = HERO_MUTED
	end
end

local function showNote(text: string, color: Color3)
	local label = noteLabel
	if not label then
		return
	end
	noteOverrideUntil = os.clock() + 3
	label.Text = text
	label.TextColor3 = color
	task.delay(3.05, updateNote)
end

local function refreshOwnership(celebrate: boolean)
	local pb = buyButton
	if not pb then
		return
	end
	local owned = ownsBlackHole()
	pb.Owned = owned
	refreshPriceButton(pb)
	updateNote()
	-- Gerade gekauft, waehrend der Shop offen ist: kleiner Jubel am Knopf
	local card = heroCard
	if celebrate and owned and lastOwned == false and window and window.IsOpen and card then
		UI.Pop(pb.Button, 0.7)
		UI.Burst(card, UDim2.new(0, INFO_X + 92, 1, -48), { C.Gold, C.Purple, WHITE, C.Green }, 26, 260)
	end
	-- erst ab geladenem Profil merken, sonst jubelt der Shop beim ersten Laden
	lastOwned = if State.Profile then owned else nil
end

local function refreshBalance(animate: boolean)
	local label = balanceLabel
	if not label then
		return
	end
	local profile = State.Profile
	local coins = if profile then tonumber(profile.Coins) or 0 else 0
	if animate and coins ~= shownBalance and window and window.IsOpen then
		UI.CountTo(label, shownBalance, coins, 0.6)
	else
		label.Text = UI.Format(coins)
	end
	shownBalance = coins
end

-- Bonus gegenueber dem kleinsten Paket (Muenzen pro Robux)
local function refreshBonuses()
	local packs = Config.Shop.CoinPacks
	local basePrice = packPrices[1]
	local base: number? = if packs[1] and basePrice and basePrice > 0 then packs[1].Coins / basePrice else nil
	for i, slot in bonusSlots do
		for _, child in slot:GetChildren() do
			child:Destroy()
		end
		local price = packPrices[i]
		local pct = 0
		if base and price and price > 0 and packs[i] then
			pct = math.floor(((packs[i].Coins / price) / base - 1) * 100 + 0.5)
		end
		if i > 1 and pct >= 5 then
			makeTag({
				Text = "+" .. pct .. "% BONUS",
				Fill = C.Green,
				Lip = C.GreenDark,
				TextSize = 14,
				Height = 24,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Parent = slot,
			})
		elseif i == 1 then
			UI.Text({
				Text = "STARTER PACK",
				Font = F.Heading,
				TextSize = 15,
				TextColor3 = C.Muted,
				TextWrapped = false,
				Size = UDim2.new(1, 0, 0, 24),
				Parent = slot,
			})
		end
	end
end

-- Kaufen & Vorschau ------------------------------------------------------------------------

local function buy(kind: string, index: number?, pb: PriceButton)
	if purchasing then
		return
	end
	if kind == "BlackHole" and ownsBlackHole() then
		HUD.Toast({ Text = "You already own BLACK HOLE! Equip it in ABILITIES.", Color = C.Purple, Icon = "!" })
		return
	end
	purchasing = true
	pb.Busy = true
	refreshPriceButton(pb)
	local ok, result = pcall(function()
		return Net.Function("BuyItem"):InvokeServer(kind, index)
	end)
	purchasing = false
	pb.Busy = false
	refreshPriceButton(pb)
	if not ok or type(result) ~= "table" or not result.Ok then
		UI.Shake(pb.Button)
		local message = if ok and type(result) == "table" and type(result.Message) == "string"
			then result.Message
			else "Connection error – please try again."
		HUD.Toast({ Text = message, Color = C.Red, Icon = "!" })
		return
	end
	if result.Simulated then
		HUD.Toast({ Text = "Studio test mode – purchase simulated.", Color = C.Gold, Icon = "i" })
	end
end

local function preview()
	local blocked: string? = nil
	if State.MenuOpen then
		blocked = "Press PLAY first to preview it."
	elseif State.InCutscene or State.InCrateOpening then
		blocked = "Not available right now."
	elseif not player.Character then
		blocked = "Wait until you have spawned."
	end
	if blocked then
		local b = previewButton
		if b then
			UI.Shake(b)
		end
		showNote(blocked, C.Gold)
		return
	end
	window:Close()
	task.wait(0.3)
	VFXController.Preview("BlackHole")
end

-- 3D: Schwarzes Loch ------------------------------------------------------------------------
-- Ereignishorizont = schwarze Neon-Kugel (unbeleuchtet, perfekt schwarz).
-- Photonenring = duenne Scheiben in der Mittelebene, immer zur Kamera gedreht: die Kugel verdeckt
-- ihre Mitte, sichtbar bleibt nur ein schmaler heller Ring (plus zwei weichere Saeume dahinter).
-- Akkretionsscheibe = geneigte Baender aus kurzen Streifen, innen weiss/orange (heiss), aussen
-- tiefrot/violett, jedes Band dreht sich mit eigener (Kepler-)Geschwindigkeit.

local RING_ALIGN = CFrame.Angles(0, math.pi / 2, 0) -- Zylinderachse (X) zeigt dann zur Kamera
local DISK_CF = CFrame.Angles(math.rad(20), 0, math.rad(-10))

local PHOTON_RINGS = {
	{ D = 2.64, Color = Color3.fromRGB(255, 246, 228), T = 0, Back = 0 },
	{ D = 2.98, Color = Color3.fromRGB(255, 178, 88), T = 0.4, Back = 0.05 },
	{ D = 3.5, Color = Color3.fromRGB(210, 90, 60), T = 0.8, Back = 0.1 },
}

local DISK_BANDS = {
	{ R = 1.5, W = 0.24, N = 20, Color = Color3.fromRGB(255, 248, 232), T = 0 },
	{ R = 1.78, W = 0.28, N = 24, Color = Color3.fromRGB(255, 210, 120), T = 0 },
	{ R = 2.1, W = 0.32, N = 26, Color = Color3.fromRGB(255, 142, 54), T = 0.05 },
	{ R = 2.48, W = 0.36, N = 28, Color = Color3.fromRGB(212, 70, 42), T = 0.15 },
	{ R = 2.9, W = 0.4, N = 28, Color = Color3.fromRGB(146, 34, 60), T = 0.3 },
	{ R = 3.34, W = 0.42, N = 26, Color = Color3.fromRGB(88, 34, 118), T = 0.5 },
}

local ROCK_COLORS = {
	Color3.fromRGB(74, 62, 68),
	Color3.fromRGB(96, 78, 70),
	Color3.fromRGB(60, 54, 70),
}

local HOLE_FIT_W = 3.75 -- halbe Breite (Studs), die im Viewport sichtbar sein soll
local HOLE_FIT_H = 2.6 -- halbe Hoehe

local function buildBlackHoleScene(vp: ViewportFrame, cam: Camera): Scene
	vp.Ambient = Color3.fromRGB(90, 78, 112)
	vp.LightColor = Color3.fromRGB(255, 198, 150)
	vp.LightDirection = Vector3.new(0.5, -0.6, -1)
	local rng = Random.new(4242)
	local root = Make("Model", { Name = "BlackHole", Parent = vp })

	part({
		Name = "Horizon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = CFrame.new(),
		Color = BLACK,
		Material = Enum.Material.Neon,
		Parent = root,
	})

	local rings: { { Part: Part, Back: number } } = {}
	for _, def in PHOTON_RINGS do
		local p = part({
			Name = "PhotonRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.02, def.D, def.D),
			Color = def.Color,
			Material = Enum.Material.Neon,
			Transparency = def.T,
			Parent = root,
		})
		table.insert(rings, { Part = p, Back = def.Back })
	end

	local bands: { { Model: Model, Angle: number, Speed: number } } = {}
	for bi, band in DISK_BANDS do
		local model = Make("Model", { Name = "Band" .. bi, Parent = root })
		local nextBand = DISK_BANDS[bi + 1]
		local nextColor = if nextBand then nextBand.Color else BLACK
		local arc = TAU * band.R / band.N
		for i = 1, band.N do
			local a = (i - 1 + rng:NextNumber(-0.35, 0.35)) / band.N * TAU
			local r = band.R + rng:NextNumber(-0.25, 0.25) * band.W
			local color = band.Color:Lerp(nextColor, rng:NextNumber(0, 0.3))
			if rng:NextNumber() < 0.15 then
				color = color:Lerp(WHITE, 0.35) -- heisse Klumpen, damit die Drehung sichtbar ist
			end
			part({
				Name = "Streak",
				Size = Vector3.new(band.W * rng:NextNumber(0.6, 1), 0.025, arc * rng:NextNumber(0.5, 1.05)),
				CFrame = CFrame.Angles(0, a, 0) * CFrame.new(r, rng:NextNumber(-0.012, 0.012), 0),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = math.clamp(band.T + rng:NextNumber(-0.05, 0.1), 0, 0.9),
				Parent = model,
			})
		end
		model.WorldPivot = CFrame.new()
		table.insert(bands, { Model = model, Angle = rng:NextNumber(0, TAU), Speed = 3 / band.R ^ 1.5 })
	end

	local debris: { { Part: Part, Radius: number, Angle: number, Speed: number, Incline: CFrame, Spin: Vector3 } } = {}
	for i = 1, 9 do
		local hot = i % 3 == 0
		local s = if hot then rng:NextNumber(0.06, 0.1) else rng:NextNumber(0.1, 0.2)
		local p = part({
			Name = "Debris",
			Size = Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.3)),
			Color = if hot then Color3.fromRGB(255, 172, 80) else ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
			Material = if hot then Enum.Material.Neon else Enum.Material.Slate,
			Parent = root,
		})
		local radius = rng:NextNumber(2.5, 3.8)
		table.insert(debris, {
			Part = p,
			Radius = radius,
			Angle = rng:NextNumber(0, TAU),
			Speed = 2.2 / radius ^ 1.5,
			Incline = CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)),
			Spin = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2)),
		})
	end

	local time = 0
	return function(dt: number)
		time += dt
		-- Kamera so weit weg, dass die Scheibe in jedes Seitenverhaeltnis passt; sanftes Schwanken
		local size = vp.AbsoluteSize
		local aspect = if size.Y > 1 then size.X / size.Y else 0.74
		local tanV = math.tan(math.rad(cam.FieldOfView / 2))
		local dist = math.max(HOLE_FIT_W / (tanV * aspect), HOLE_FIT_H / tanV)
		local yaw = math.sin(time * 0.31) * math.rad(9)
		local pitch = math.rad(6) + math.sin(time * 0.23) * math.rad(2)
		local camPos = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * Vector3.new(0, 0, dist)
		-- Blickpunkt etwas unter dem Loch: das Loch sitzt leicht oberhalb der Mitte (Platz fuers Schild)
		local focus = Vector3.new(0, -dist * tanV * 0.12, 0)
		cam.CFrame = CFrame.lookAt(camPos, focus)

		local dir = camPos.Unit
		for _, ring in rings do
			local pos = -dir * ring.Back
			ring.Part.CFrame = CFrame.lookAt(pos, pos + dir) * RING_ALIGN
		end
		for _, band in bands do
			band.Angle = (band.Angle + band.Speed * dt) % TAU
			band.Model:PivotTo(DISK_CF * CFrame.Angles(0, band.Angle, 0))
		end
		for _, d in debris do
			d.Angle = (d.Angle + d.Speed * dt) % TAU
			local orbit = DISK_CF * d.Incline * CFrame.Angles(0, d.Angle, 0) * CFrame.new(d.Radius, 0, 0)
			d.Part.CFrame = CFrame.new(orbit.Position) * CFrame.Angles(time * d.Spin.X, time * d.Spin.Y, time * d.Spin.Z)
		end
	end
end

-- 3D: Muenzberge -----------------------------------------------------------------------------
-- Muenzen = flache Zylinder. Die Kamera kreist (statt die Teile zu bewegen) und nimmt das Licht mit,
-- das wirkt wie ein Drehteller, kostet aber pro Frame nur eine Kamera-Aenderung.

local GOLD_COLORS = {
	Color3.fromRGB(255, 200, 56),
	Color3.fromRGB(250, 186, 42),
	Color3.fromRGB(255, 212, 84),
	Color3.fromRGB(242, 176, 36),
}
local GOLD_FACE = Color3.fromRGB(222, 148, 24)
local COIN_D = 1
local COIN_T = 0.15
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- Zylinderachse (X) -> nach oben
local KEY_LIGHT = Vector3.new(1, -1.4, -0.9) -- Licht von oben links (im Kameraraum)
local COIN_FIT_W = 2.55
local COIN_FIT_H = 1.95

local function addCoin(model: Model, cf: CFrame, rng: Random, emboss: boolean)
	part({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(COIN_T, COIN_D, COIN_D),
		CFrame = cf * FLAT,
		Color = GOLD_COLORS[rng:NextInteger(1, #GOLD_COLORS)],
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	if emboss then
		-- erhabene Praegung auf sichtbaren Muenzen: wirkt sofort wie eine Muenze
		part({
			Name = "Emboss",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.04, COIN_D * 0.66, COIN_D * 0.66),
			CFrame = cf * CFrame.new(0, COIN_T / 2 + 0.008, 0) * FLAT,
			Color = GOLD_FACE,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
end

local function addStack(model: Model, rng: Random, x: number, z: number, count: number)
	local yaw = rng:NextNumber(0, TAU)
	for k = 0, count - 1 do
		local cf = CFrame.new(x + rng:NextNumber(-0.05, 0.05), COIN_T / 2 + k * COIN_T, z + rng:NextNumber(-0.05, 0.05))
			* CFrame.Angles(rng:NextNumber(-0.04, 0.04), yaw + rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.04, 0.04))
		addCoin(model, cf, rng, k == count - 1)
	end
end

local function addLoose(model: Model, rng: Random, x: number, z: number)
	local cf = CFrame.new(x, COIN_T / 2 + 0.01, z)
		* CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, TAU), rng:NextNumber(-0.06, 0.06))
	addCoin(model, cf, rng, true)
end

-- Muenze, die schraeg an einem Stapel (Mitte sx/sz) lehnt; a = Richtung vom Stapel weg
local function addLeaning(model: Model, rng: Random, sx: number, sz: number, a: number, tilt: number)
	local dist = 0.5 + 0.5 * math.cos(tilt) + 0.04
	local x, z = sx + math.cos(a) * dist, sz + math.sin(a) * dist
	local y = 0.5 * math.sin(tilt) + (COIN_T / 2) * math.cos(tilt)
	local yaw = math.atan2(math.cos(a), math.sin(a))
	addCoin(model, CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0), rng, true)
end

-- Haufen aus Ringen, die nach aussen kippen, plus eine Muenze obenauf
local function addMound(model: Model, rng: Random, cx: number, cz: number, layers: { { R: number, N: number, Y: number, Tilt: number } }, topY: number)
	for li, layer in layers do
		local offset = rng:NextNumber(0, TAU)
		for i = 1, layer.N do
			local a = offset + (i - 1) / layer.N * TAU + rng:NextNumber(-0.15, 0.15)
			local r = layer.R + rng:NextNumber(-0.06, 0.06)
			local pos = Vector3.new(cx + math.cos(a) * r, layer.Y + rng:NextNumber(-0.02, 0.03), cz + math.sin(a) * r)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
			local tilt = layer.Tilt + rng:NextNumber(-0.08, 0.08)
			local cf = CFrame.new(pos) * CFrame.fromAxisAngle(tangent, -tilt) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			addCoin(model, cf, rng, li == 1)
		end
	end
	addCoin(model, CFrame.new(cx, topY, cz) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), rng:NextNumber(0, TAU), rng:NextNumber(-0.1, 0.1)), rng, true)
end

-- Groessere Pakete = groesserer Berg
local function buildPile(model: Model, rng: Random, tier: number)
	if tier <= 1 then
		addStack(model, rng, -0.5, -0.15, 5)
		addStack(model, rng, 0.6, -0.45, 3)
		addLeaning(model, rng, -0.5, -0.15, math.rad(70), 0.6)
		addLoose(model, rng, 0.75, 0.6)
		addLoose(model, rng, -1.25, 0.6)
	elseif tier == 2 then
		addMound(model, rng, 0.1, 0.15, {
			{ R = 0.8, N = 7, Y = 0.12, Tilt = 0.25 },
			{ R = 0.42, N = 4, Y = 0.26, Tilt = 0.35 },
		}, 0.38)
		addStack(model, rng, -1.35, -0.5, 6)
		addStack(model, rng, 1.35, -0.55, 4)
		addLeaning(model, rng, -1.35, -0.5, math.rad(120), 0.95)
		addLoose(model, rng, 1.2, 0.95)
		addLoose(model, rng, -1.05, 1.0)
		addLoose(model, rng, -0.1, 1.45)
	else
		addMound(model, rng, 0, 0.1, {
			{ R = 1.2, N = 11, Y = 0.12, Tilt = 0.22 },
			{ R = 0.88, N = 8, Y = 0.27, Tilt = 0.3 },
			{ R = 0.56, N = 6, Y = 0.41, Tilt = 0.36 },
			{ R = 0.26, N = 3, Y = 0.54, Tilt = 0.4 },
		}, 0.66)
		addStack(model, rng, -1.45, -0.8, 9)
		addStack(model, rng, 1.5, -0.7, 7)
		addStack(model, rng, 0.05, -1.65, 10)
		addStack(model, rng, -1.6, 0.75, 4)
		addLoose(model, rng, 1.4, 1.05)
		addLoose(model, rng, 0.4, 1.65)
		addLoose(model, rng, -0.6, 1.55)
	end
end

local function buildCoinScene(vp: ViewportFrame, cam: Camera, tier: number, seed: number, hover: { Hover: boolean }): Scene
	vp.Ambient = Color3.fromRGB(150, 138, 124)
	vp.LightColor = Color3.fromRGB(255, 242, 220)
	local rng = Random.new(seed)
	local model = Make("Model", { Name = "CoinPile", Parent = vp })
	-- Sockel mit dunklerem Rand darunter
	part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.36, 4.4, 4.4),
		CFrame = CFrame.new(0, -0.18, 0) * FLAT,
		Color = Color3.fromRGB(66, 74, 98),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	part({
		Name = "BaseRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 4.7, 4.7),
		CFrame = CFrame.new(0, -0.42, 0) * FLAT,
		Color = Color3.fromRGB(38, 43, 60),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	buildPile(model, rng, tier)

	local angle = rng:NextNumber(0, TAU)
	local speed = 0.35
	local elevation = math.rad(26)
	local focus = Vector3.new(0, 0.3, 0)
	return function(dt: number)
		local target = if hover.Hover then 1.8 else 0.35
		speed += (target - speed) * math.min(1, dt * 5)
		angle = (angle + speed * dt) % TAU
		local size = vp.AbsoluteSize
		local aspect = if size.Y > 1 then size.X / size.Y else 1
		local tanV = math.tan(math.rad(cam.FieldOfView / 2))
		local dist = math.max(COIN_FIT_W / (tanV * aspect), COIN_FIT_H / tanV)
		local flat = math.cos(elevation)
		local camPos = focus + Vector3.new(math.sin(angle) * flat, math.sin(elevation), math.cos(angle) * flat) * dist
		cam.CFrame = CFrame.lookAt(camPos, focus)
		vp.LightDirection = cam.CFrame:VectorToWorldSpace(KEY_LIGHT)
	end
end

-- Seitenwechsel & Animations-Schleife ------------------------------------------------------

local CATEGORIES = {
	{ Id = "FEATURED", Style = "Purple", Glyph = "hole" },
	{ Id = "COINS", Style = "Gold", Glyph = "coins" },
}

local function pageBasePosition(): UDim2
	return UDim2.fromOffset(PAGE_X, TOP)
end

local function selectPage(id: string, instant: boolean?)
	if id == currentPage or not pages[id] then
		return
	end
	currentPage = id
	for _, cat in CATEGORIES do
		local b = categoryButtons[cat.Id]
		if b then
			UI.SetButtonStyle(b, if cat.Id == id then cat.Style else "Dark")
		end
		local page = pages[cat.Id]
		if page then
			page.Visible = cat.Id == id
		end
	end
	local page = pages[id]
	if instant then
		page.Position = pageBasePosition()
	else
		page.Position = pageBasePosition() + UDim2.fromOffset(0, 12)
		UI.Tween(page, 0.22, { Position = pageBasePosition() })
	end
end

local function stopAnimation()
	local conn = animConn
	if conn then
		conn:Disconnect()
		animConn = nil
	end
end

local function step(dt: number)
	if not window.IsOpen then
		stopAnimation()
		return
	end
	local d = math.min(dt, 1 / 20)
	if currentPage == "FEATURED" then
		local scene = holeScene
		if scene then
			scene(d)
		end
	elseif currentPage == "COINS" then
		for _, scene in coinScenes do
			scene(d)
		end
	end
end

local function startAnimation()
	if animConn then
		return
	end
	animConn = RunService.RenderStepped:Connect(step)
end

-- Aufbau der Oberflaeche ---------------------------------------------------------------

-- Kopfleiste: gezeichnetes Muenz-Symbol links vom Titel (statt Emoji)
local function decorateHeader()
	local header = window.Header
	local title: TextLabel? = nil
	for _, child in header:GetChildren() do
		if child:IsA("TextLabel") then
			title = child :: TextLabel
			break
		end
	end
	if not title then
		return
	end
	title.Position = UDim2.fromOffset(76, 0)
	title.Size = UDim2.new(1, -170, 1, 0)
	drawCoinPair(header, Vector2.new(44, 38), UDim2.new(0, 22, 0.5, 0), Vector2.new(0, 0.5))
end

local function buildSidebar(content: Frame)
	local side = UI.Inset({
		Name = "Sidebar",
		Position = UDim2.fromOffset(MARGIN, TOP),
		Size = UDim2.new(0, SIDEBAR_W, 1, -TOP * 2),
		Parent = content,
	})
	local list = Make("Frame", {
		Name = "Categories",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 200),
		Parent = side,
	})
	UI.List(list, false, 12)
	for i, cat in CATEGORIES do
		local b = UI.Button({
			Name = cat.Id,
			Text = cat.Id,
			Style = "Dark",
			Size = UDim2.new(1, 0, 0, 60),
			TextSize = 19,
			LayoutOrder = i,
			Parent = list,
			OnClick = function()
				selectPage(cat.Id)
			end,
		})
		local face = b:FindFirstChild("Face") :: Frame
		local label = face:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			local l = label :: TextLabel
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Position = UDim2.fromOffset(60, 0)
			l.Size = UDim2.new(1, -68, 1, 0)
		end
		if cat.Glyph == "hole" then
			drawHoleGlyph(face, face.ZIndex + 1)
		else
			local g = drawCoinPair(face, Vector2.new(36, 34), UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
			g.ZIndex = face.ZIndex + 1
		end
		categoryButtons[cat.Id] = b
	end

	-- Muenzstand unten in der Seitenleiste
	local wallet = UI.Card({
		Name = "Wallet",
		Radius = 10,
		Position = UDim2.new(0, 12, 1, -96),
		Size = UDim2.new(1, -24, 0, 84),
		Parent = side,
	})
	UI.Text({
		Text = "YOUR COINS",
		Font = F.Bold,
		TextSize = 12,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 16),
		Parent = wallet,
	})
	drawCoin(wallet, 28, UDim2.fromOffset(14, 38), 2)
	local amount = UI.Text({
		Name = "Balance",
		Text = "0",
		Font = F.Heading,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(50, 34),
		Size = UDim2.new(1, -62, 0, 36),
		Stroke = 2,
		Parent = wallet,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 12, Parent = amount })
	balanceLabel = amount
end

local function makePage(content: Frame, name: string): Frame
	return Make("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Position = pageBasePosition(),
		Size = UDim2.new(1, -(PAGE_X + MARGIN), 1, -(TOP * 2 + FOOTER_H)),
		Visible = false,
		Parent = content,
	})
end

local function buildFeatured(page: Frame)
	local shadow = Make("Frame", {
		Name = "HeroShadow",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		Parent = page,
	})
	UI.Corner(shadow, 16)
	local card = UI.Card({
		Name = "Hero",
		Color = HERO_COLOR,
		Radius = 16,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = page,
	})
	heroCard = card

	-- 3D-Buehne links: Sternenhimmel (Frames) hinter dem Viewport
	local stage = UI.Inset({
		Name = "Stage",
		Color = HERO_STAGE,
		Radius = 12,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(0, STAGE_W, 1, -32),
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Gradient(stage, ColorSequence.new(WHITE, Color3.fromRGB(150, 140, 172)), 90)
	local starRng = Random.new(2024)
	for _ = 1, 44 do
		local big = starRng:NextNumber() < 0.12
		local s = if big then 3 else starRng:NextInteger(1, 2)
		local star = Make("Frame", {
			Name = "Star",
			BackgroundColor3 = if starRng:NextNumber() < 0.3 then Color3.fromRGB(255, 214, 170) else Color3.fromRGB(214, 222, 255),
			BackgroundTransparency = if big then 0.15 else starRng:NextNumber(0.35, 0.8),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(starRng:NextNumber(0.06, 0.94), starRng:NextNumber(0.05, 0.95)),
			Size = UDim2.fromOffset(s, s),
			Parent = stage,
		})
		if s > 1 then
			UI.Round(star)
		end
	end
	local vp, cam = UI.Viewport({ Size = UDim2.fromScale(1, 1), Parent = stage, FieldOfView = 34 })
	vp.ZIndex = 2
	local scene = buildBlackHoleScene(vp, cam)
	scene(0)
	holeScene = scene
	local rarity = Rarities.Get("Exclusive")
	makeTag({
		Text = string.upper(rarity.Name),
		Fill = rarity.Color,
		TextSize = 15,
		Height = 28,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		ZIndex = 3,
		Parent = stage,
	})

	-- Textspalte rechts
	local info = Make("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(INFO_X, 0),
		Size = UDim2.new(1, -(INFO_X + INFO_RIGHT), 1, 0),
		Parent = card,
	})
	makeTag({ Text = "EXCLUSIVE", Fill = C.Gold, Lip = C.GoldDark, TextSize = 16, Height = 30, Position = UDim2.fromOffset(0, 18), Parent = info })
	local title = UI.Text({
		Name = "Title",
		Text = "BLACK HOLE",
		Font = F.Heading,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 58),
		Stroke = 3,
		Parent = info,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 54, MinTextSize = 24, Parent = title })
	UI.Text({
		Text = "The rarest ability in NOVA CLASH.",
		Font = F.Body,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = info,
	})
	local divider = Make("Frame", {
		Name = "Divider",
		BackgroundColor3 = HERO_INSET,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 154),
		Size = UDim2.new(1, 0, 0, 3),
		Parent = info,
	})
	UI.Round(divider)

	-- Merkmale mit gezeichneten Rauten als Aufzaehlungszeichen
	local features = {
		{ "Cinematic", "cutscene camera" },
		{ "Pulls in", "every enemy nearby" },
		{ "Colossal", "implosion finisher" },
		{ "Yours forever", "– not in crates" },
	}
	local featureSize = 17
	for _, f in features do
		featureSize = math.min(featureSize, fitTextSize(f[1] .. " " .. f[2], F.Bold, 17, 13, INFO_W - 28))
	end
	for i, f in features do
		local y = 172 + (i - 1) * 32
		local bullet = Make("Frame", {
			Name = "Bullet",
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(8, y + 14),
			Size = UDim2.fromOffset(10, 10),
			Rotation = 45,
			Parent = info,
		})
		UI.Corner(bullet, 2)
		stroke(bullet, 2)
		UI.Text({
			Text = string.format('<font color="#FFFFFF"><b>%s</b></font> %s', f[1], f[2]),
			Font = F.Body,
			TextSize = featureSize,
			TextColor3 = C.SubText,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(24, y),
			Size = UDim2.new(1, -24, 0, 28),
			Parent = info,
		})
	end

	-- Werte als kleine Kacheln (aus Abilities, damit sie immer stimmen)
	local def = Abilities.Get("BlackHole")
	local stats = {
		{ "DAMAGE", if def then tostring(def.Damage) else "-" },
		{ "COOLDOWN", if def then tostring(def.Cooldown) .. "s" else "-" },
		{ "RANGE", if def then tostring(def.Range) else "-" },
	}
	local chips = Make("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 312),
		Size = UDim2.new(1, 0, 0, 58),
		Parent = info,
	})
	for i, s in stats do
		local chip = UI.Inset({
			Name = s[1],
			Color = HERO_INSET,
			Radius = 10,
			Position = UDim2.new((i - 1) / 3, (i - 1) * 4, 0, 0),
			Size = UDim2.new(1 / 3, -8, 1, 0),
			Parent = chips,
		})
		UI.Text({
			Text = s[1],
			Font = F.Bold,
			TextSize = 11,
			TextColor3 = HERO_MUTED,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = chip,
		})
		UI.Text({
			Text = s[2],
			Font = F.Heading,
			TextSize = 24,
			TextWrapped = false,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 30),
			Stroke = 2,
			Parent = chip,
		})
	end

	-- Hinweis + Knoepfe unten (Unterkante buendig mit der Buehne)
	noteLabel = UI.Text({
		Name = "Note",
		Text = "",
		Font = F.Body,
		TextSize = 14,
		TextColor3 = HERO_MUTED,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 0, 1, -112),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = info,
	})
	local pb: PriceButton
	pb = makePriceButton({
		Price = Config.Shop.BlackHoleDisplayPrice,
		Size = UDim2.fromOffset(184, 64),
		Position = UDim2.new(0, 0, 1, -80),
		TextSize = 28,
		Shine = true,
		Parent = info,
		OnClick = function()
			buy("BlackHole", nil, pb)
		end,
	})
	-- Im OWNED-Zustand ist der Knopf deaktiviert (wackelt) – kurz erklaeren, warum
	pb.Button.Activated:Connect(function()
		if pb.Owned then
			HUD.Toast({ Text = "You already own BLACK HOLE! Equip it in ABILITIES.", Color = C.Purple, Icon = "!" })
		end
	end)
	buyButton = pb
	previewButton = UI.Button({
		Name = "Preview",
		Text = "PREVIEW",
		Style = "Blue",
		Size = UDim2.new(1, -196, 0, 64),
		Position = UDim2.new(0, 196, 1, -80),
		TextSize = 20,
		Parent = info,
		OnClick = preview,
	})
	updateNote()
end

local function buildPackCard(parent: Instance, index: number, pack: any, cardW: number, count: number)
	local ribbon: { Text: string, Fill: Color3, Lip: Color3 }? = nil
	if count >= 2 and index == count then
		ribbon = { Text = "BEST VALUE", Fill = C.Gold, Lip = C.GoldDark }
	elseif count >= 3 and index == 2 then
		ribbon = { Text = "POPULAR", Fill = C.Red, Lip = C.RedDark }
	end

	-- Slot haelt den Schatten fest, die Karte hebt sich beim Hovern davon ab
	local slot = Make("Frame", {
		Name = "Pack" .. index,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, cardW, 1, -8),
		LayoutOrder = index,
		Parent = parent,
	})
	local shadow = Make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	})
	UI.Corner(shadow, 14)
	local card = UI.Card({ Name = "Card", Radius = 14, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = slot })
	if ribbon then
		-- farbiger Innenrahmen fuer hervorgehobene Pakete
		local rim = Make("Frame", {
			Name = "Rim",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -12, 1, -12),
			Parent = card,
		})
		UI.Corner(rim, 10)
		UI.Stroke(rim, ribbon.Fill, 3, 0.15)
	end

	-- Buehne mit dem 3D-Muenzberg
	local stage = UI.Inset({
		Name = "Stage",
		Radius = 10,
		Position = UDim2.fromOffset(12, 24),
		Size = UDim2.new(1, -24, 1, -216),
		ClipsDescendants = true,
		Parent = card,
	})
	UI.Gradient(stage, ColorSequence.new(WHITE, Color3.fromRGB(170, 170, 186)), 90)
	local vp, cam = UI.Viewport({ Size = UDim2.fromScale(1, 1), Parent = stage, FieldOfView = 30 })
	vp.ZIndex = 2
	local hover = { Hover = false }
	local scene = buildCoinScene(vp, cam, math.clamp(index, 1, 3), 100 + index * 17, hover)
	scene(0)
	local glintRng = Random.new(index * 31)
	local glints: { { Frame: Frame, Scale: UIScale, Timer: number } } = {}
	for _ = 1, 2 do
		local g, sc = makeGlint(stage)
		table.insert(glints, { Frame = g, Scale = sc, Timer = glintRng:NextNumber(0.4, 2.2) })
	end
	-- Hover per Mausposition (robuster als MouseEnter/Leave, die beim Wechsel auf den Kaufknopf flackern)
	local lifted = false
	table.insert(coinScenes, function(dt: number)
		-- GetMouseLocation zaehlt ab der echten Bildschirmecke (inkl. Topbar), AbsolutePosition
		-- dagegen ab Unterkante der Topbar -> Inset abziehen, sonst ist der Hover-Bereich verschoben
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local pos, size = slot.AbsolutePosition, slot.AbsoluteSize
		local inside = mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
		if inside ~= lifted then
			lifted = inside
			hover.Hover = inside
			UI.Tween(card, if inside then 0.16 else 0.2, { Position = UDim2.fromOffset(0, if inside then -6 else 0) }, Enum.EasingStyle.Quad)
		end
		scene(dt)
		for _, gl in glints do
			gl.Timer -= dt
			if gl.Timer <= 0 then
				gl.Timer = glintRng:NextNumber(1.6, 3.4)
				twinkle(gl.Frame, gl.Scale, glintRng)
			end
		end
	end)

	-- Name, Menge, Bonus, Preis (von unten nach oben verankert)
	UI.Text({
		Name = "PackName",
		Text = string.upper(tostring(pack.Name)),
		Font = F.Heading,
		TextSize = fitTextSize(string.upper(tostring(pack.Name)), F.Heading, 22, 14, cardW - 32),
		TextWrapped = false,
		Position = UDim2.new(0, 0, 1, -184),
		Size = UDim2.new(1, 0, 0, 28),
		Stroke = 2,
		Parent = card,
	})
	local amountRow = Make("Frame", {
		Name = "Amount",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -152),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = card,
	})
	UI.List(amountRow, true, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local coinIcon = drawCoin(amountRow, 28, UDim2.new(), 1)
	coinIcon.LayoutOrder = 1
	UI.Text({
		Name = "Coins",
		Text = UI.Format(pack.Coins),
		Font = F.Heading,
		TextSize = 32,
		TextColor3 = C.Coin,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Stroke = 2.5,
		Parent = amountRow,
	})
	bonusSlots[index] = Make("Frame", {
		Name = "Bonus",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -108),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = card,
	})
	local _, _, priceValue = parsePrice(tostring(pack.DisplayPrice))
	if priceValue then
		packPrices[index] = priceValue
	end
	packButtons[index] = makePriceButton({
		Price = tostring(pack.DisplayPrice),
		Size = UDim2.new(1, -24, 0, 60),
		Position = UDim2.new(0, 12, 1, -72),
		TextSize = 24,
		Parent = card,
		OnClick = function()
			local pb = packButtons[index]
			if pb then
				buy("Coins", index, pb)
			end
		end,
	})

	if ribbon then
		makeTag({
			Text = ribbon.Text,
			Fill = ribbon.Fill,
			Lip = ribbon.Lip,
			TextSize = 15,
			Height = 28,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			ZIndex = 5,
			Parent = card,
		})
	end

end

local function buildCoins(page: Frame)
	UI.Text({
		Text = "COIN PACKS",
		Font = F.Heading,
		TextSize = 30,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 36),
		Stroke = 2.5,
		Parent = page,
	})
	UI.Text({
		Text = "Coins open crates – and crates unlock new abilities.",
		Font = F.Body,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = page,
	})
	local packs = Config.Shop.CoinPacks
	local count = math.max(1, #packs)
	local cardW = math.floor((PAGE_W - (count - 1) * CARD_GAP) / count)
	local row = Make("Frame", {
		Name = "Packs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 1, -88),
		Parent = page,
	})
	UI.List(row, true, CARD_GAP, Enum.HorizontalAlignment.Center)
	for i, pack in packs do
		buildPackCard(row, i, pack, cardW, count)
	end
	refreshBonuses()
end

local function buildFooter(content: Frame)
	if not TEST_MODE then
		return
	end
	local footer = Make("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, PAGE_X, 1, -(TOP + 18)),
		Size = UDim2.new(1, -(PAGE_X + MARGIN), 0, 18),
		Parent = content,
	})
	local dot = Make("Frame", {
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		Parent = footer,
	})
	UI.Round(dot)
	UI.Text({
		Text = "Studio test mode – purchases are simulated",
		Font = F.Body,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Parent = footer,
	})
end

-- Echte Preise laden, falls IDs eingetragen sind
local function fetchPrice(id: number, infoType: Enum.InfoType, apply: (number) -> ())
	if type(id) ~= "number" or id == 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			apply(info.PriceInRobux)
		end
	end)
end

-- Oeffentliche API ----------------------------------------------------------------------

function Shop.Open()
	if not window then
		return
	end
	if not openedOnce then
		openedOnce = true
		-- Wer Black Hole schon hat, landet direkt bei den Muenzen
		selectPage(if ownsBlackHole() then "COINS" else "FEATURED", true)
	end
	refreshOwnership(false)
	refreshBalance(false)
	window:Open()
end

function Shop.Init()
	window = UI.Window({ Title = "SHOP", Size = WINDOW_SIZE, Name = "Shop", Color = HEADER_COLOR })
	decorateHeader()
	local content = window.Content
	buildSidebar(content)
	pages.FEATURED = makePage(content, "Featured")
	buildFeatured(pages.FEATURED)
	pages.COINS = makePage(content, "Coins")
	buildCoins(pages.COINS)
	buildFooter(content)
	selectPage("FEATURED", true)

	window.Opened:Connect(startAnimation)
	window.Closed:Connect(stopAnimation)
end

function Shop.Start()
	State.ProfileChanged:Connect(function()
		refreshOwnership(true)
		refreshBalance(true)
	end)
	refreshOwnership(false)
	refreshBalance(false)

	fetchPrice(Config.Shop.BlackHoleGamePassId, Enum.InfoType.GamePass, function(robux: number)
		local pb = buyButton
		if pb then
			pb.Price = UI.Format(robux)
			pb.Numeric = true
			refreshPriceButton(pb)
		end
	end)
	for i, pack in Config.Shop.CoinPacks do
		fetchPrice(pack.ProductId, Enum.InfoType.Product, function(robux: number)
			packPrices[i] = robux
			local pb = packButtons[i]
			if pb then
				pb.Price = UI.Format(robux)
				pb.Numeric = true
				refreshPriceButton(pb)
			end
			refreshBonuses()
		end)
	end
end

return Shop
