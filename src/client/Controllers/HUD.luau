-- HUD im "Chunky Game UI"-Stil (siehe UI/Theme.luau):
-- * oben rechts: Muenz-Anzeige (gezeichnete Muenze + "+"-Knopf) und darunter der Killfeed
-- * oben Mitte: kompakte Rundenanzeige (Status-Schild, grosser Timer, "x / y left")
-- * unten Mitte: Faehigkeiten-Leiste (UI.AbilityTile) mit Cooldowns, Lebensbalken, Dash-Anzeige
-- * links: Menue-Knoepfe mit gezeichneten Symbolen
-- * unten rechts: Benachrichtigungen, rechts: Kombo-Zaehler, Mitte: grosse Ansagen
-- Jede Gruppe haengt an einer Bildschirmecke und skaliert ueber UI.Scaled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local HUD = {}
HUD.MenuButtonPressed = Signal.new() -- (name)
HUD.AbilitySlotPressed = Signal.new() -- (slot)
HUD.DashReadyAt = 0 -- wird von Combat.luau geschrieben

local player = Players.LocalPlayer
local C = Theme.Colors
local F = Theme.Fonts
local Make = UI.Make
local WHITE = Color3.new(1, 1, 1)
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Masse der Faehigkeiten-Leiste
local SLOT = 80
local SLOT_GAP = 12
local SLOT_LIP = math.max(3, math.floor(SLOT * 0.06)) -- wie in UI.AbilityTile
local FACE_H = SLOT - SLOT_LIP
local SLOT_RADIUS = math.floor(SLOT * 0.18)
local BAR_W = SLOT * 4 + SLOT_GAP * 3

local gui: ScreenGui
local root: Frame
local cooldowns: { [string]: { Start: number, Duration: number } } = {}
local menuButtons: { [string]: GuiObject } = {}
HUD.MenuButtons = menuButtons

type Slot = {
	Index: number,
	Button: TextButton,
	Tile: Instance?,
	Overlay: Frame,
	OverlayGrad: UIGradient,
	Edge: Frame,
	CDText: TextLabel,
	NameLabel: TextLabel,
	Flash: Frame,
	Bump: UIScale,
	Id: string?,
	WasReady: boolean,
}
local slots: { Slot } = {}

-- oben rechts
local topRight: Frame
local coinLabel: TextLabel
local coinIcon: Frame
local shownCoins = 0
local rewardsActive = 0
local feed: Frame
local feedRows: { Frame } = {}
local feedCounter = 0

-- Runde
local roundPlate: Frame
local roundTag: Frame
local roundTagLabel: TextLabel
local roundTimer: TextLabel
local roundSub: TextLabel
local lastRoundState = ""
local lastTimeLeft = -1
local botHintShown = false

-- unten
local healthBar: any
local healthHolder: Frame
local healthBase: UDim2
local lastHealth = 100
local dashFill: Frame
local dashGrad: UIGradient
local dashBump: UIScale
local dashRatioShown = 1

-- sonstiges
local lowHealth: Frame
local hurtFlash: Frame
local stage: Frame
local stageBase: UDim2
local confettiLayer: Frame
local flashFrame: Frame
local toastHolder: Frame
local toastCounter = 0
local toastList: { Frame } = {}
local comboHolder: Frame
local comboCount: TextLabel
local comboShadow: TextLabel
local comboWord: TextLabel
local comboPunch: UIScale
local comboFades: { Tween } = {}
local combo = 0
local lastHit = 0

-- Hilfsfunktionen ------------------------------------------------------------------

local function fmtTime(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 200))
	end)
	if ok and typeof(v) == "Vector2" then
		return math.ceil(v.X)
	end
	return math.ceil(#text * size * 0.62)
end

-- Transparenz-Sequenz, die nur den unteren Anteil "ratio" sichtbar macht (scharfe Kante).
-- So bleibt die runde Ecke der Kachel erhalten (ClipsDescendants schneidet nicht rund).
local function revealSeq(ratio: number, alpha: number): NumberSequence
	local r = math.clamp(ratio, 0, 1)
	if r <= 0.002 then
		return NumberSequence.new(1)
	elseif r >= 0.998 then
		return NumberSequence.new(alpha)
	end
	local edge = 1 - r
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(edge, 1),
		NumberSequenceKeypoint.new(edge + 0.0008, alpha),
		NumberSequenceKeypoint.new(1, alpha),
	})
end

-- Text + Kontur gemeinsam ein-/ausblenden
local function setTextAlpha(label: TextLabel, a: number)
	label.TextTransparency = a
	local s = label:FindFirstChildOfClass("UIStroke")
	if s then
		s.Transparency = a
	end
end

local function tweenTextAlpha(label: TextLabel, time: number, a: number, delay: number?)
	UI.Tween(label, time, { TextTransparency = a }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)
	local s = label:FindFirstChildOfClass("UIStroke")
	if s then
		UI.Tween(s, time, { Transparency = a }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)
	end
end

-- Alles in einem Container ausblenden (Text, Konturen, Flaechen)
local function fadeOut(container: Instance, time: number)
	for _, d in container:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.Tween(d, time, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
		elseif d:IsA("UIStroke") then
			UI.Tween(d, time, { Transparency = 1 }, Enum.EasingStyle.Quad)
		elseif d:IsA("Frame") then
			UI.Tween(d, time, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		end
	end
end

-- Kurzes Wackeln um eine feste Grundposition
local function jiggle(obj: GuiObject, base: UDim2, strength: number)
	task.spawn(function()
		for i = 1, 5 do
			local s = strength * (1 - (i - 1) / 5)
			obj.Position = base + UDim2.fromOffset((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)
			task.wait(0.03)
		end
		obj.Position = base
	end)
end

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	return UI.Stroke(parent, color or C.Ink, thickness, 0)
end

-- Gezeichnete Muenze: Rand (Dicke) + goldene Flaeche + dunklerer Innenring + Glanzpunkt
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

-- Muenzen (oben rechts) ------------------------------------------------------------

local function buildTopRight()
	topRight = Make("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(330, 320),
		ZIndex = 2,
		Parent = root,
	})
	UI.Scaled(topRight)

	local wallet = Make("Frame", {
		Name = "Wallet",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(216, 52),
		Parent = topRight,
	})
	local plate = UI.Panel({
		Name = "Plate",
		Color = C.PanelDark,
		Radius = 20,
		Position = UDim2.fromOffset(24, 6),
		Size = UDim2.fromOffset(142, 40),
		Parent = wallet,
	})
	coinLabel = UI.Text({
		Name = "Amount",
		Text = "0",
		Font = F.Heading,
		TextSize = 26,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(34, 2),
		Size = UDim2.new(1, -44, 1, -4),
		Stroke = 2.5,
		Parent = plate,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 12, Parent = coinLabel })
	coinIcon = drawCoin(wallet, 50, UDim2.fromOffset(0, 0), 3)
	UI.Button({
		Name = "AddCoins",
		Text = "+",
		Style = "Green",
		TextSize = 30,
		Lip = 4,
		Size = UDim2.fromOffset(44, 46),
		Position = UDim2.fromOffset(172, 3),
		Parent = wallet,
		OnClick = function()
			HUD.MenuButtonPressed:Fire("Shop")
		end,
	})

	feed = Make("Frame", {
		Name = "KillFeed",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 230),
		Parent = topRight,
	})
	UI.List(feed, false, 6, Enum.HorizontalAlignment.Right)
end

local function setCoins(value: number, animate: boolean)
	if animate and value ~= shownCoins then
		UI.CountTo(coinLabel, shownCoins, value, 0.7)
		if value > shownCoins then
			UI.Pop(coinIcon, 1.3, 0.35)
		end
	else
		coinLabel.Text = UI.Format(value)
	end
	shownCoins = value
end

-- "+120 VICTORY" erscheint links neben der Muenze und fliegt dann hinein
function HUD.RewardPopup(amount: number, reason: string)
	local n = tonumber(amount) or 0
	local stackIndex = rewardsActive
	rewardsActive += 1
	local restX = 330 - 216 - 6
	local y = 26 + stackIndex * 44
	local pop = Make("Frame", {
		Name = "Reward",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(restX - 40, y),
		Size = UDim2.fromOffset(260, 46),
		ZIndex = 5,
		Parent = topRight,
	})
	local scale = Make("UIScale", { Parent = pop })
	local amountLabel = UI.Text({
		Text = "+" .. UI.Format(n),
		Font = F.Heading,
		TextSize = 30,
		TextColor3 = C.Coin,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 30),
		Stroke = 3,
		ZIndex = 5,
		Parent = pop,
	})
	local reasonLabel = UI.Text({
		Text = string.upper(tostring(reason or "")),
		Font = F.Heading,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 29),
		Size = UDim2.new(1, 0, 0, 16),
		Stroke = 2,
		ZIndex = 5,
		Parent = pop,
	})
	setTextAlpha(amountLabel, 1)
	setTextAlpha(reasonLabel, 1)
	UI.Tween(pop, 0.3, { Position = UDim2.fromOffset(restX, y) }, Enum.EasingStyle.Back)
	tweenTextAlpha(amountLabel, 0.15, 0)
	tweenTextAlpha(reasonLabel, 0.15, 0)
	UI.Sound("Coins")
	task.delay(1.15, function()
		-- in die Muenze hineinfliegen
		local target = UDim2.fromOffset(330 - 216 + 46, 24)
		UI.Tween(pop, 0.32, { Position = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UI.Tween(scale, 0.32, { Scale = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenTextAlpha(amountLabel, 0.3, 1)
		tweenTextAlpha(reasonLabel, 0.18, 1)
		task.delay(0.32, function()
			rewardsActive = math.max(0, rewardsActive - 1)
			if coinIcon then
				UI.Pop(coinIcon, 1.35, 0.35)
			end
			UI.Sound("Coins", 1.15)
			pop:Destroy()
		end)
	end)
end

-- Killfeed ------------------------------------------------------------------------

local function koIcon(parent: Instance, x: number, z: number)
	local holder = Make("Frame", {
		Name = "KO",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, x, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = z,
		Parent = parent,
	})
	for _, rot in { 45, -45 } do
		local bar = Make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 5),
			Rotation = rot,
			ZIndex = z,
			Parent = holder,
		})
		UI.Corner(bar, 2)
		stroke(bar, 1.5)
	end
end

local function botChip(parent: Instance, x: number, z: number)
	local chip = Make("Frame", {
		Name = "Bot",
		BackgroundColor3 = C.Grey,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, x, 0.5, 0),
		Size = UDim2.fromOffset(30, 16),
		ZIndex = z,
		Parent = parent,
	})
	UI.Corner(chip, 5)
	stroke(chip, 1.5)
	UI.Text({
		Text = "BOT",
		Font = F.Heading,
		TextSize = 11,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = chip,
	})
end

local function addKillFeed(data: any)
	if type(data) ~= "table" then
		return
	end
	local victim = tostring(data.Victim or "?")
	local killer: string? = if data.Killer ~= nil then tostring(data.Killer) else nil
	local me = player.DisplayName
	local involvesMe = (killer == me and not data.KillerIsBot) or (victim == me and not data.VictimIsBot)
	local NAME = 16
	local GAP = 8
	local z = 3

	-- Breite vorab berechnen (UIListLayout ignoriert Positionen, darum innen animieren)
	local killerW = if killer then textWidth(killer, NAME, F.Heading) + 2 else 0
	local victimW = textWidth(victim, NAME, F.Heading) + 2
	local suffix = "was knocked out"
	local suffixW = if killer then 0 else textWidth(suffix, 13, F.Bold) + 2
	local width = 12
	if killer then
		width += killerW + GAP
		if data.KillerIsBot then
			width += 30 + GAP
		end
	end
	width += 16 + GAP + victimW
	if data.VictimIsBot then
		width += GAP + 30
	end
	if not killer then
		width += GAP + suffixW
	end
	width += 12

	feedCounter += 1
	local row = Make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 32),
		LayoutOrder = -feedCounter, -- neueste oben
		Parent = feed,
	})
	local plate = UI.Panel({
		Name = "Plate",
		Color = if involvesMe then C.PanelLight else C.PanelDark,
		StrokeColor = if involvesMe then C.Gold else C.Ink,
		Radius = 8,
		NoShade = true,
		BackgroundTransparency = 0.08,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	local ps = plate:FindFirstChildOfClass("UIStroke")
	if ps then
		ps.Thickness = 2
	end

	local x = 12
	local function name(text: string, w: number, color: Color3)
		UI.Text({
			Text = text,
			Font = F.Heading,
			TextSize = NAME,
			TextColor3 = color,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, w, 1, 0),
			Stroke = 2,
			ZIndex = z,
			Parent = plate,
		})
		x += w
	end
	if killer then
		name(killer, killerW, C.Gold)
		x += GAP
		if data.KillerIsBot then
			botChip(plate, x, z)
			x += 30 + GAP
		end
	end
	koIcon(plate, x, z)
	x += 16 + GAP
	name(victim, victimW, Color3.fromRGB(255, 92, 92))
	if data.VictimIsBot then
		x += GAP
		botChip(plate, x, z)
		x += 30
	end
	if not killer then
		x += GAP
		UI.Text({
			Text = suffix,
			Font = F.Bold,
			TextSize = 13,
			TextColor3 = C.SubText,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, suffixW, 1, 0),
			ZIndex = z,
			Parent = plate,
		})
	end

	UI.Tween(plate, 0.28, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	table.insert(feedRows, row)
	while #feedRows > 5 do
		local old = table.remove(feedRows, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(6, function()
		if not row.Parent then
			return
		end
		UI.Tween(plate, 0.35, { Position = UDim2.fromOffset(40, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeOut(row, 0.3)
		task.delay(0.36, function()
			local i = table.find(feedRows, row)
			if i then
				table.remove(feedRows, i)
			end
			row:Destroy()
		end)
	end)
end

-- Menue-Knoepfe (links) -----------------------------------------------------------------
-- Symbole sind aus Flaechen gezeichnet (weiss mit dunklem Umriss), damit sie auf jeder
-- Knopffarbe lesbar sind und nicht wie Emoji wirken.

local function glyphHolder(face: Instance, w: number, h: number): Frame
	return Make("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 6,
		Parent = face,
	})
end

local function glyphBox(parent: Instance, color: Color3, pos: UDim2, size: UDim2, radius: number, z: number, thickness: number?): Frame
	local f = Make("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = pos,
		Size = size,
		ZIndex = z,
		Parent = parent,
	})
	UI.Corner(f, radius)
	stroke(f, thickness or 2)
	return f
end

local function drawGlyph(face: Frame, kind: string, accent: Color3)
	if kind == "crate" then
		local g = glyphHolder(face, 36, 30)
		glyphBox(g, WHITE, UDim2.fromOffset(2, 10), UDim2.new(1, -4, 1, -10), 4, 6)
		glyphBox(g, WHITE, UDim2.fromOffset(0, 2), UDim2.new(1, 0, 0, 10), 3, 7)
		local strap = glyphBox(g, accent, UDim2.new(0.5, -4, 0, 2), UDim2.new(0, 8, 1, -2), 2, 8, 1.5)
		strap.ZIndex = 8
	elseif kind == "grid" then
		local g = glyphHolder(face, 32, 32)
		for i = 0, 3 do
			local cx, cy = i % 2, i // 2
			glyphBox(g, if i == 0 then C.Gold else WHITE, UDim2.fromOffset(cx * 18, cy * 18), UDim2.fromOffset(14, 14), 4, 6)
		end
	elseif kind == "coins" then
		local g = glyphHolder(face, 40, 34)
		drawCoin(g, 24, UDim2.fromOffset(15, 0), 6)
		drawCoin(g, 28, UDim2.fromOffset(2, 6), 10)
	elseif kind == "help" then
		local g = glyphHolder(face, 40, 40)
		UI.Text({
			Text = "?",
			Font = F.Heading,
			TextSize = 38,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Stroke = 2.5,
			ZIndex = 6,
			Parent = g,
		})
	elseif kind == "eye" then
		local g = glyphHolder(face, 38, 24)
		local white = Make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = g,
		})
		UI.Round(white)
		stroke(white, 2)
		local iris = Make("Frame", {
			BackgroundColor3 = C.Blue,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			ZIndex = 7,
			Parent = white,
		})
		UI.Round(iris)
		stroke(iris, 2)
		local pupil = Make("Frame", {
			BackgroundColor3 = C.Ink,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 8,
			Parent = iris,
		})
		UI.Round(pupil)
		local glint = Make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.18, 0.14),
			Size = UDim2.fromOffset(4, 4),
			ZIndex = 9,
			Parent = iris,
		})
		UI.Round(glint)
	end
end

local MENU = {
	{ Name = "Crates", Caption = "CRATES", Style = "Gold", Glyph = "crate" },
	{ Name = "Inventory", Caption = "ABILITIES", Style = "Blue", Glyph = "grid" },
	{ Name = "Shop", Caption = "SHOP", Style = "Green", Glyph = "coins" },
	{ Name = "Tutorial", Caption = "HELP", Style = "Grey", Glyph = "help" },
	{ Name = "Spectate", Caption = "SPECTATE", Style = "Purple", Glyph = "eye" },
}

local function cornerBadge(button: Instance, name: string, text: string, w: number, color: Color3): Frame
	local badge = Make("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(w, 22),
		ZIndex = 10,
		Parent = button,
	})
	UI.Corner(badge, 11)
	stroke(badge, 2)
	UI.Text({
		Text = text,
		Font = F.Heading,
		TextSize = if #text > 1 then 11 else 15,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
		Stroke = 1.5,
		Parent = badge,
	})
	-- sanftes Pulsieren
	local pulse = Make("UIScale", { Parent = badge })
	TweenService:Create(pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.16 }):Play()
	return badge
end

local function buildMenu()
	local size = 72
	local gap = 10
	-- PC: links mittig. Touch: oben links (unten links liegt der Bewegungs-Stick)
	local holder = Make("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = if TOUCH_ONLY then Vector2.new(0, 0) else Vector2.new(0, 0.5),
		Position = if TOUCH_ONLY then UDim2.new(0, 12, 0, 64) else UDim2.new(0, 16, 0.5, 0),
		-- Platz fuer 6 Knoepfe (5 + Admin)
		Size = UDim2.fromOffset(size, size * 6 + gap * 5),
		ZIndex = 2,
		Parent = root,
	})
	UI.Scaled(holder)
	UI.List(holder, false, gap, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	for i, e in MENU do
		local btn = UI.IconButton({
			Name = e.Name,
			Icon = "",
			Caption = e.Caption,
			Style = e.Style,
			Size = size,
			LayoutOrder = i,
			Parent = holder,
			OnClick = function()
				HUD.MenuButtonPressed:Fire(e.Name)
			end,
		})
		local face = btn:FindFirstChild("Face") :: Frame?
		if face then
			local style = Theme.ButtonStyles[e.Style] or Theme.ButtonStyles.Grey
			drawGlyph(face, e.Glyph, style.Lip)
		end
		menuButtons[e.Name] = btn
		if e.Name == "Crates" then
			-- roter Punkt, wenn eine Gratis-Kiste wartet
			local dot = cornerBadge(btn, "Dot", "!", 22, C.Red)
			dot.Visible = false
		elseif e.Name == "Spectate" then
			cornerBadge(btn, "Live", "LIVE", 38, C.Red)
			btn.Visible = false
		end
	end
end

-- Rundenstatus (oben Mitte) --------------------------------------------------------------

local function buildRound()
	roundPlate = UI.Panel({
		Name = "Round",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(268, 76),
		Radius = 14,
		ZIndex = 2,
		Parent = root,
	})
	UI.Scaled(roundPlate)
	roundTag = UI.Panel({
		Name = "Tag",
		Color = C.Grey,
		Radius = 8,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = roundPlate,
	})
	local ts = roundTag:FindFirstChildOfClass("UIStroke")
	if ts then
		ts.Thickness = 2
	end
	Make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = roundTag })
	roundTagLabel = UI.Text({
		Text = "LOBBY",
		Font = F.Heading,
		TextSize = 14,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Stroke = 1.5,
		Parent = roundTag,
	})
	roundTimer = UI.Text({
		Text = "",
		Font = F.Heading,
		TextSize = 30,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 29),
		Size = UDim2.new(1, 0, 0, 28),
		Stroke = 2.5,
		Parent = roundPlate,
	})
	roundSub = UI.Text({
		Text = "",
		Font = F.Bold,
		TextSize = 13,
		TextColor3 = C.SubText,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 56),
		Size = UDim2.new(1, -16, 0, 16),
		Parent = roundPlate,
	})
end

local function showBotHint()
	local r = State.Round
	if botHintShown or not r or r.State ~= "Fighting" or not r.BotOnly then
		return
	end
	if player:GetAttribute("InRound") == true or State.IsHUDHidden() then
		return
	end
	botHintShown = true
	HUD.Toast({ Text = "Bots are battling it out! Press SPECTATE on the left to watch.", Color = C.Purple, Icon = "!", Duration = 5 })
end

local function updateRound()
	local r = State.Round or {}
	local s = r.State or "Waiting"
	local inRound = player:GetAttribute("InRound") == true
	local timeLeft = tonumber(r.TimeLeft) or 0
	local alive = tonumber(r.Alive) or 0
	local total = tonumber(r.Total) or 0
	local tag, tagColor, timer, sub = "LOBBY", C.Grey, "WAITING", "Waiting for fighters..."
	local timerColor = WHITE
	local timerSize = 30
	if s == "Waiting" then
		timerSize = 24
	elseif s == "Intermission" then
		tag, tagColor = "NEXT ROUND", C.Gold
		timer = fmtTime(timeLeft)
		sub = "Everyone in the lobby joins!"
	elseif s == "Countdown" then
		tag, tagColor = "GET READY", C.Red
		timer = tostring(math.max(0, math.floor(timeLeft)))
		sub = total .. " fighters in the arena"
	elseif s == "Fighting" then
		if r.BotOnly then
			tag, tagColor = "BOT BATTLE", C.Purple
		else
			tag, tagColor = "FIGHT", C.Red
		end
		timer = fmtTime(timeLeft)
		if timeLeft <= 10 then
			timerColor = Color3.fromRGB(255, 96, 80)
		end
		sub = alive .. " / " .. total .. " left"
		if not inRound then
			sub ..= "  •  Spectate to watch"
		end
	elseif s == "Ended" then
		tag, tagColor = "ROUND OVER", C.Gold
		timer = "GG!"
		sub = "Back to the lobby..."
	end
	roundTagLabel.Text = tag
	roundTag.BackgroundColor3 = tagColor
	roundTimer.Text = timer
	roundTimer.TextSize = timerSize
	roundTimer.TextColor3 = timerColor
	roundSub.Text = sub

	if s ~= lastRoundState then
		-- (kein UI.Pop auf roundPlate: dort sitzt schon die AutoScale-UIScale)
		if lastRoundState ~= "" then
			UI.Pop(roundTag, 0.6, 0.35)
		end
		lastRoundState = s
	elseif (s == "Fighting" and timeLeft <= 10 or s == "Countdown") and timeLeft ~= lastTimeLeft then
		UI.Pop(roundTimer, 1.3, 0.3)
	end
	lastTimeLeft = timeLeft

	if s ~= "Fighting" then
		botHintShown = false
	end
	local spectate = menuButtons.Spectate
	if spectate then
		spectate.Visible = s == "Fighting" and not inRound
	end
	showBotHint()
end

-- Faehigkeiten + Lebensbalken (unten Mitte) ----------------------------------------------

local function buildSlot(parent: Instance, index: number): Slot
	local button = Make("TextButton", {
		Name = "Slot" .. index,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(SLOT, SLOT),
		LayoutOrder = index,
		Parent = parent,
	})
	local bump = Make("UIScale", { Name = "Bump", Parent = button })
	local overlay = Make("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, FACE_H),
		ZIndex = 4,
		Parent = button,
	})
	UI.Corner(overlay, SLOT_RADIUS)
	local grad = UI.Gradient(overlay, nil, 90, NumberSequence.new(1))
	local edge = Make("Frame", {
		Name = "Edge",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 0, 2),
		Position = UDim2.fromOffset(6, 0),
		Visible = false,
		ZIndex = 5,
		Parent = button,
	})
	local flash = Make("Frame", {
		Name = "Flash",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, FACE_H),
		ZIndex = 6,
		Parent = button,
	})
	UI.Corner(flash, SLOT_RADIUS)
	local cdText = UI.Text({
		Name = "CDText",
		Text = "",
		Font = F.Heading,
		TextSize = 32,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, FACE_H),
		Stroke = 3,
		ZIndex = 7,
		Parent = button,
	})
	-- Tasten-Schild (auf reinen Touch-Geraeten ausgeblendet)
	local key = Make("Frame", {
		Name = "Key",
		BackgroundColor3 = C.PanelDark,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-7, -7),
		Size = UDim2.fromOffset(24, 24),
		Visible = not TOUCH_ONLY,
		ZIndex = 8,
		Parent = button,
	})
	UI.Corner(key, 6)
	stroke(key, 2)
	UI.Text({
		Text = tostring(index),
		Font = F.Heading,
		TextSize = 15,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Parent = key,
	})
	local nameLabel = UI.Text({
		Name = "AbilityName",
		Text = "",
		Font = F.Heading,
		TextSize = 12,
		TextScaled = true,
		TextWrapped = false,
		TextColor3 = C.SubText,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 3),
		Size = UDim2.fromOffset(SLOT + SLOT_GAP - 2, 14),
		Stroke = 1.5,
		Parent = button,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 7, Parent = nameLabel })

	button.MouseEnter:Connect(function()
		UI.Tween(bump, 0.12, { Scale = 1.06 })
	end)
	button.MouseLeave:Connect(function()
		UI.Tween(bump, 0.15, { Scale = 1 })
	end)
	button.Activated:Connect(function()
		HUD.AbilitySlotPressed:Fire(index)
	end)
	return {
		Index = index,
		Button = button,
		Tile = nil,
		Overlay = overlay,
		OverlayGrad = grad,
		Edge = edge,
		CDText = cdText,
		NameLabel = nameLabel,
		Flash = flash,
		Bump = bump,
		Id = nil,
		WasReady = true,
	}
end

local function buildBottom()
	local holder = Make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(BAR_W, 154),
		ZIndex = 2,
		Parent = root,
	})
	UI.Scaled(holder)

	local bar = Make("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, SLOT),
		Parent = holder,
	})
	UI.List(bar, true, SLOT_GAP, Enum.HorizontalAlignment.Center)
	for i = 1, 4 do
		slots[i] = buildSlot(bar, i)
	end

	-- Lebensbalken (Zahl im Balken)
	healthBase = UDim2.fromOffset(0, 116)
	healthHolder = Make("Frame", {
		Name = "Health",
		BackgroundTransparency = 1,
		Position = healthBase,
		Size = UDim2.fromOffset(BAR_W, 30),
		Parent = holder,
	})
	healthBar = UI.ProgressBar({
		Size = UDim2.fromScale(1, 1),
		Color = C.Health,
		Text = "100 / 100",
		Parent = healthHolder,
	})
	healthBar.Label.TextSize = 17
	healthBar.Trail.BackgroundColor3 = Color3.fromRGB(255, 236, 214)

	-- Dash-Anzeige (Q) rechts neben dem Balken
	local pip = Make("Frame", {
		Name = "Dash",
		BackgroundColor3 = C.PanelDark,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 10, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		Parent = healthHolder,
	})
	UI.Round(pip)
	stroke(pip, 2.5)
	dashBump = Make("UIScale", { Parent = pip })
	dashFill = Make("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.Blue,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = pip,
	})
	UI.Round(dashFill)
	dashGrad = UI.Gradient(dashFill, nil, 90, NumberSequence.new(0))
	UI.Text({
		Text = if TOUCH_ONLY then "DASH" else "Q",
		Font = F.Heading,
		TextSize = if TOUCH_ONLY then 10 else 17,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Stroke = 2,
		ZIndex = 3,
		Parent = pip,
	})
end

local function updateSlots()
	local profile = State.Profile
	for i, s in slots do
		local id: string = if profile and profile.Equipped then (profile.Equipped[i] or "") else ""
		if s.Id == id then
			continue
		end
		local first = s.Id == nil
		s.Id = id
		if s.Tile then
			s.Tile:Destroy()
			s.Tile = nil
		end
		local def = Abilities.Get(id)
		if def then
			s.Tile = UI.AbilityTile({ AbilityId = id, Size = SLOT, Parent = s.Button })
			s.NameLabel.Text = string.upper(def.Name)
			s.NameLabel.TextColor3 = Theme.Lighten(Rarities.Get(def.Rarity).Color, 0.35)
		else
			local empty = UI.Inset({
				Name = "Empty",
				Radius = SLOT_RADIUS,
				Position = UDim2.fromOffset(0, SLOT_LIP),
				Size = UDim2.new(1, 0, 0, FACE_H),
				Parent = s.Button,
			})
			UI.Text({
				Text = "+",
				Font = F.Heading,
				TextSize = 34,
				TextColor3 = C.Muted,
				TextWrapped = false,
				Size = UDim2.fromScale(1, 1),
				Parent = empty,
			})
			s.Tile = empty
			s.NameLabel.Text = "EMPTY"
			s.NameLabel.TextColor3 = C.Muted
		end
		if not first then
			s.Bump.Scale = 0.8
			UI.Tween(s.Bump, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

local function readyPop(s: Slot)
	s.Bump.Scale = 1.2
	UI.Tween(s.Bump, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	s.Flash.BackgroundTransparency = 0.2
	UI.Tween(s.Flash, 0.35, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	UI.Sound("Hover", 1.3)
end

local function healthColor(r: number): Color3
	if r > 0.5 then
		return C.Health
	elseif r > 0.25 then
		return C.Gold:Lerp(C.Health, (r - 0.25) / 0.25)
	end
	return C.HealthLow:Lerp(C.Gold, math.clamp((r - 0.1) / 0.15, 0, 1))
end

local function updateHealth(humanoid: Humanoid, instant: boolean?)
	local maxH = math.max(humanoid.MaxHealth, 1)
	local hp = math.max(0, humanoid.Health)
	local ratio = math.clamp(hp / maxH, 0, 1)
	healthBar.Set(ratio, instant)
	healthBar.Label.Text = math.ceil(hp) .. " / " .. math.floor(maxH)
	local color = healthColor(ratio)
	if instant then
		healthBar.Fill.BackgroundColor3 = color
	else
		UI.Tween(healthBar.Fill, 0.2, { BackgroundColor3 = color })
	end
	local damage = lastHealth - hp
	if not instant and damage > 0.5 then
		jiggle(healthHolder, healthBase, math.clamp(damage * 0.5, 2, 7))
		-- kurzer roter Rand-Blitz, staerker bei viel Schaden
		for _, edgeFrame in hurtFlash:GetChildren() do
			if edgeFrame:IsA("Frame") then
				local f = edgeFrame :: Frame
				f.BackgroundTransparency = math.clamp(0.75 - damage / 40, 0.35, 0.75)
				UI.Tween(f, 0.45, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			end
		end
	end
	lastHealth = hp
	lowHealth.Visible = ratio < 0.3 and hp > 0
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local hum = humanoid :: Humanoid
	lastHealth = hum.Health
	updateHealth(hum, true)
	hum.HealthChanged:Connect(function()
		updateHealth(hum)
	end)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateHealth(hum, true)
	end)
end

-- Bildschirmrand-Vignette (4 Kanten mit Verlauf nach innen)
local function buildVignette(name: string, color: Color3, edgeAlpha: number, thickness: number): Frame
	local v = Make("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
	})
	local edges = {
		{ UDim2.fromScale(1, thickness), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, thickness), UDim2.fromScale(0, 1 - thickness), -90 },
		{ UDim2.fromScale(thickness * 0.6, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(thickness * 0.6, 1), UDim2.fromScale(1 - thickness * 0.6, 0), 180 },
	}
	for _, e in edges do
		local f = Make("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = e[1],
			Position = e[2],
			ZIndex = 1,
			Parent = v,
		})
		UI.Gradient(f, nil, e[3], NumberSequence.new({
			NumberSequenceKeypoint.new(0, edgeAlpha),
			NumberSequenceKeypoint.new(1, 1),
		}))
	end
	return v
end

-- Ansagen (Mitte) ----------------------------------------------------------------

local ANNOUNCE: { [string]: { [string]: any } } = {
	Count = { Size = 170, Stroke = 6, From = 1.9, Rot = 12, Rest = 0, Time = 0.3, Ease = Enum.EasingStyle.Back },
	Fight = {
		Size = 130,
		Stroke = 6,
		From = 0.25,
		Rot = -14,
		Rest = -4,
		Time = 0.35,
		Ease = Enum.EasingStyle.Back,
		Gradient = ColorSequence.new(Color3.fromRGB(255, 228, 92), Color3.fromRGB(240, 82, 36)),
	},
	Victory = {
		Size = 104,
		Stroke = 5,
		From = 0.3,
		Rot = 10,
		Rest = -3,
		Time = 0.45,
		Ease = Enum.EasingStyle.Back,
		Gradient = ColorSequence.new(Color3.fromRGB(255, 242, 160), Color3.fromRGB(255, 168, 28)),
	},
	Eliminated = { Size = 100, Stroke = 5, From = 1.5, Rot = 0, Rest = 0, Time = 0.3, Ease = Enum.EasingStyle.Quart, Color = C.Red },
	Big = { Size = 80, Stroke = 5, From = 0.55, Rot = 0, Rest = 0, Time = 0.35, Ease = Enum.EasingStyle.Back },
}

local function displayLabel(parent: Instance, text: string, size: number, color: Color3, strokeW: number, yOffset: number, z: number): TextLabel
	-- Roblox begrenzt TextSize auf 100 -> groessere Texte per UIScale hochskalieren
	local scaleUp = math.max(1, size / 100)
	local inner = math.min(size, 100)
	local label = UI.Text({
		Text = text,
		Font = F.Display,
		TextSize = inner,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, yOffset),
		Size = UDim2.new(1 / scaleUp, 0, 0, inner + 24),
		Stroke = strokeW,
		ZIndex = z,
		Parent = parent,
	})
	Make("UITextSizeConstraint", { MaxTextSize = inner, MinTextSize = 24, Parent = label })
	if scaleUp > 1 then
		Make("UIScale", { Scale = scaleUp, Parent = label })
	end
	return label
end

local function screenFlash(alpha: number, time: number)
	flashFrame.BackgroundTransparency = alpha
	UI.Tween(flashFrame, time, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

function HUD.Announce(data: any)
	if type(data) ~= "table" then
		return
	end
	for _, c in stage:GetChildren() do
		if c.Name == "Announcement" then
			c:Destroy()
		end
	end
	local style = if ANNOUNCE[data.Style] then data.Style else "Big"
	local cfg = ANNOUNCE[style]
	local duration = tonumber(data.Duration) or 2
	local text = tostring(data.Text or "")
	local size: number = cfg.Size
	local group = Make("Frame", {
		Name = "Announcement",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = stage,
	})
	local scale = Make("UIScale", { Scale = cfg.From, Parent = group })

	-- Eliminiert: dunkles Band quer ueber den Bildschirm
	if style == "Eliminated" then
		local bandH = size + (if data.Sub then 84 else 36)
		local band = Make("Frame", {
			Name = "Band",
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.42, if data.Sub then 22 else 0),
			Size = UDim2.new(4, 0, 0, 0),
			ZIndex = 1,
			Parent = group,
		})
		for _, y in { 0, 1 } do
			Make("Frame", {
				BackgroundColor3 = C.Red,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, y),
				Position = UDim2.fromScale(0, y),
				Size = UDim2.new(1, 0, 0, 4),
				ZIndex = 1,
				Parent = band,
			})
		end
		UI.Tween(band, 0.25, { Size = UDim2.new(4, 0, 0, bandH) }, Enum.EasingStyle.Quart)
	end

	local custom: Color3? = if typeof(data.Color) == "Color3" then data.Color else nil
	local color: Color3 = custom or cfg.Color or WHITE
	local useGradient = custom == nil and cfg.Gradient ~= nil
	local shadow = displayLabel(group, text, size, C.Ink, cfg.Stroke, 7, 2)
	local main = displayLabel(group, text, size, if useGradient then WHITE else color, cfg.Stroke, 0, 3)
	if useGradient then
		UI.Gradient(main, cfg.Gradient, 90)
	end
	local rot = cfg.Rot
	if style == "Count" then
		rot = (if math.random() < 0.5 then -1 else 1) * cfg.Rot
	end
	shadow.Rotation = rot
	main.Rotation = rot
	UI.Tween(scale, cfg.Time, { Scale = 1 }, cfg.Ease)
	UI.Tween(shadow, cfg.Time, { Rotation = cfg.Rest }, Enum.EasingStyle.Back)
	UI.Tween(main, cfg.Time, { Rotation = cfg.Rest }, Enum.EasingStyle.Back)

	if data.Sub then
		local sub = UI.Text({
			Name = "Sub",
			Text = tostring(data.Sub),
			Font = F.Heading,
			TextSize = 30,
			TextScaled = true,
			TextWrapped = true,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.42, size / 2 + 30),
			Size = UDim2.new(1, 0, 0, 40),
			Stroke = 3,
			ZIndex = 3,
			Parent = group,
		})
		Make("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14, Parent = sub })
		setTextAlpha(sub, 1)
		tweenTextAlpha(sub, 0.3, 0, 0.18)
		UI.Tween(sub, 0.35, { Position = UDim2.new(0.5, 0, 0.42, size / 2 + 18) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.18)
	end

	if style == "Count" then
		local n = tonumber(text) or 3
		UI.Sound("Countdown", 1 + math.clamp(3 - n, 0, 4) * 0.08)
	elseif style == "Fight" then
		UI.Sound("Fight")
		screenFlash(0.6, 0.3)
		jiggle(stage, stageBase, 10)
	elseif style == "Victory" then
		UI.Sound("Victory")
		local colors = { C.Gold, C.Green, C.Blue, C.Red, WHITE }
		UI.Burst(confettiLayer, UDim2.fromScale(0.5, 0.42), colors, 60, 560)
		task.delay(0.25, function()
			if confettiLayer.Parent then
				UI.Burst(confettiLayer, UDim2.fromScale(0.5, 0.42), colors, 30, 420)
			end
		end)
	elseif style == "Eliminated" then
		UI.Sound("Error")
		jiggle(stage, stageBase, 6)
	end

	task.delay(duration, function()
		if not group.Parent then
			return
		end
		UI.Tween(scale, 0.25, { Scale = if style == "Count" then 0.7 else 1.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeOut(group, 0.25)
		task.delay(0.3, function()
			group:Destroy()
		end)
	end)
end

-- Benachrichtigungen (unten rechts) -----------------------------------------------------

function HUD.Toast(data: any)
	if type(data) ~= "table" then
		return
	end
	local color: Color3 = if typeof(data.Color) == "Color3" then data.Color else C.Blue
	local width = 330
	toastCounter += 1
	local wrapper = Make("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = toastCounter,
		Parent = toastHolder,
	})
	local card = UI.Panel({
		Name = "Card",
		Radius = 12,
		Position = UDim2.fromOffset(width + 40, 0),
		Size = UDim2.new(1, 0, 0, 58),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = wrapper,
	})
	-- farbiger Akzent-Streifen links
	local accent = Make("Frame", {
		Name = "Accent",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.new(0, 6, 1, -18),
		ZIndex = 2,
		Parent = card,
	})
	UI.Round(accent)
	local badge = Make("Frame", {
		Name = "Icon",
		BackgroundColor3 = Theme.Darken(color, 0.15),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 2,
		Parent = card,
	})
	UI.Round(badge)
	stroke(badge, 2)
	UI.Text({
		Text = tostring(data.Icon or "!"),
		Font = F.Heading,
		TextSize = 18,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Stroke = 1.5,
		ZIndex = 3,
		Parent = badge,
	})
	local label = UI.Text({
		Name = "Message",
		Text = tostring(data.Text or ""),
		Font = F.Bold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -82, 0, 58),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
		Parent = card,
	})
	Make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = label })

	UI.Tween(card, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	UI.Sound("Open", 1.3)
	table.insert(toastList, wrapper)
	while #toastList > 4 do
		local old = table.remove(toastList, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(tonumber(data.Duration) or 4.5, function()
		if not wrapper.Parent then
			return
		end
		UI.Tween(card, 0.3, { Position = UDim2.fromOffset(width + 40, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			local i = table.find(toastList, wrapper)
			if i then
				table.remove(toastList, i)
			end
			wrapper:Destroy()
		end)
	end)
end

-- Kombo-Zaehler (rechts) -------------------------------------------------------------

local function buildCombo()
	comboHolder = Make("Frame", {
		Name = "Combo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.46, 0),
		Size = UDim2.fromOffset(240, 110),
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	UI.Scaled(comboHolder)
	local inner = Make("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = comboHolder,
	})
	comboPunch = Make("UIScale", { Parent = inner })
	local function big(yOffset: number, color: Color3, z: number): TextLabel
		return UI.Text({
			Text = "",
			Font = F.Display,
			TextSize = 68,
			TextColor3 = color,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(0, yOffset),
			Size = UDim2.new(1, 0, 0, 72),
			Rotation = -6,
			Stroke = 4,
			ZIndex = z,
			Parent = inner,
		})
	end
	comboShadow = big(6, C.Ink, 1)
	comboCount = big(0, WHITE, 2)
	comboWord = UI.Text({
		Text = "COMBO",
		Font = F.Heading,
		TextSize = 24,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0, 0, 0, 74),
		Size = UDim2.new(1, -6, 0, 28),
		Rotation = -6,
		Stroke = 2.5,
		ZIndex = 3,
		Parent = inner,
	})
end

local function comboColor(n: number): Color3
	if n >= 20 then
		return C.Red
	elseif n >= 10 then
		return Color3.fromRGB(255, 132, 40)
	elseif n >= 5 then
		return C.Gold
	end
	return WHITE
end

function HUD.RegisterHit()
	local t = os.clock()
	if t - lastHit > 1.6 then
		combo = 0
	end
	lastHit = t
	combo += 1
	if combo < 2 then
		return
	end
	for _, tw in comboFades do
		tw:Cancel()
	end
	table.clear(comboFades)
	comboHolder.Visible = true
	for _, l in { comboCount, comboShadow, comboWord } do
		setTextAlpha(l, 0)
	end
	local text = "x" .. combo
	comboCount.Text = text
	comboShadow.Text = text
	comboCount.TextColor3 = comboColor(combo)
	local rot = -4 - math.random() * 6
	comboCount.Rotation = rot
	comboShadow.Rotation = rot
	comboPunch.Scale = 1.5
	UI.Tween(comboPunch, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.7, function()
		if os.clock() - lastHit < 1.6 then
			return
		end
		for _, l in { comboCount, comboShadow, comboWord } do
			table.insert(comboFades, UI.Tween(l, 0.3, { TextTransparency = 1 }))
			local s = l:FindFirstChildOfClass("UIStroke")
			if s then
				table.insert(comboFades, UI.Tween(s, 0.3, { Transparency = 1 }))
			end
		end
		task.delay(0.32, function()
			if os.clock() - lastHit >= 1.6 then
				comboHolder.Visible = false
			end
		end)
	end)
end

-- Cooldowns -----------------------------------------------------------------------------

function HUD.IsOnCooldown(abilityId: string): boolean
	local cd = cooldowns[abilityId]
	return cd ~= nil and os.clock() < cd.Start + cd.Duration
end

function HUD.StartCooldown(abilityId: string, duration: number)
	if abilityId == "*" then
		table.clear(cooldowns)
		return
	end
	cooldowns[abilityId] = { Start = os.clock(), Duration = tonumber(duration) or 0 }
end

local function stepCooldowns()
	local t = os.clock()
	for _, s in slots do
		local cd = if s.Id and s.Id ~= "" then cooldowns[s.Id] else nil
		local remaining = if cd then (cd.Start + cd.Duration) - t else 0
		if cd and remaining > 0 then
			local ratio = remaining / math.max(cd.Duration, 0.01)
			s.OverlayGrad.Transparency = revealSeq(ratio, 0.28)
			s.CDText.Text = if remaining < 1 then string.format("%.1f", remaining) else tostring(math.ceil(remaining))
			local y = (1 - ratio) * FACE_H
			s.Edge.Visible = y > 5 and y < FACE_H - 5
			s.Edge.Position = UDim2.fromOffset(6, math.floor(y) - 1)
			if s.WasReady then
				-- gerade eingesetzt: kurz eindruecken
				s.WasReady = false
				s.Bump.Scale = 0.86
				UI.Tween(s.Bump, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		elseif not s.WasReady then
			s.WasReady = true
			s.OverlayGrad.Transparency = NumberSequence.new(1)
			s.CDText.Text = ""
			s.Edge.Visible = false
			readyPop(s)
		end
	end

	local readyAt = HUD.DashReadyAt or 0
	local ratio = if readyAt > t then 1 - (readyAt - t) / math.max(Config.Combat.DashCooldown, 0.01) else 1
	ratio = math.clamp(ratio, 0, 1)
	if ratio ~= dashRatioShown then
		local wasReady = dashRatioShown >= 1
		dashRatioShown = ratio
		dashGrad.Transparency = revealSeq(ratio, 0)
		if ratio >= 1 then
			dashFill.BackgroundColor3 = C.Blue
			if not wasReady then
				dashBump.Scale = 1.3
				UI.Tween(dashBump, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		else
			dashFill.BackgroundColor3 = Theme.Darken(C.Blue, 0.3)
		end
	end
end

-- Aufbau ----------------------------------------------------------------------------

function HUD.SetVisible(visible: boolean)
	root.Visible = visible
end

function HUD.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	gui = UI.Screen("NovaHUD", 5)
	root = Make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })

	-- Rand-Vignetten: dezentes Pulsieren bei wenig Leben + kurzer Blitz bei Schaden
	lowHealth = buildVignette("LowHealth", C.HealthLow, 0.55, 0.16)
	lowHealth.Visible = false
	for _, f in lowHealth:GetChildren() do
		if f:IsA("Frame") then
			TweenService:Create(f, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.5 }):Play()
		end
	end
	hurtFlash = buildVignette("HurtFlash", C.HealthLow, 0.3, 0.12)
	for _, f in hurtFlash:GetChildren() do
		if f:IsA("Frame") then
			(f :: Frame).BackgroundTransparency = 1
		end
	end

	buildTopRight()
	buildMenu()
	buildRound()
	buildBottom()
	buildCombo()

	-- Ansagen liegen ausserhalb von Root, damit sie auch bei verstecktem HUD sichtbar sind
	local announceHolder = Make("Frame", { Name = "Announce", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = gui })
	flashFrame = Make("Frame", {
		Name = "Flash",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = announceHolder,
	})
	stageBase = UDim2.fromScale(0.5, 0.4)
	stage = Make("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = stageBase,
		Size = UDim2.fromOffset(900, 340),
		ZIndex = 2,
		Parent = announceHolder,
	})
	UI.Scaled(stage)
	confettiLayer = Make("Frame", { Name = "Confetti", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = stage })

	-- Benachrichtigungen: unten rechts (auf Handys oben Mitte, dort liegen Sprung-/Kampfknoepfe)
	toastHolder = Make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = if TOUCH_ONLY then Vector2.new(0.5, 0) else Vector2.new(1, 1),
		Position = if TOUCH_ONLY then UDim2.new(0.5, 0, 0, 96) else UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(340, 330),
		ZIndex = 4,
		Parent = gui,
	})
	UI.Scaled(toastHolder)
	UI.List(
		toastHolder,
		false,
		8,
		if TOUCH_ONLY then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Right,
		if TOUCH_ONLY then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	)

	State.HUDVisibilityChanged:Connect(function(hidden: boolean)
		root.Visible = not hidden
		if not hidden then
			showBotHint()
		end
	end)
	root.Visible = not State.IsHUDHidden()
end

function HUD.Start()
	State.ProfileChanged:Connect(function()
		local p = State.Profile
		if not p then
			return
		end
		setCoins(tonumber(p.Coins) or 0, not State.InCrateOpening)
		updateSlots()
		local crates = menuButtons.Crates
		local dot = crates and crates:FindFirstChild("Dot", true)
		if dot and dot:IsA("GuiObject") then
			(dot :: GuiObject).Visible = p.FreeCrate == true
		end
	end)
	State.RoundChanged:Connect(updateRound)
	player:GetAttributeChangedSignal("InRound"):Connect(updateRound)

	Net.Event("Announce").OnClientEvent:Connect(HUD.Announce)
	Net.Event("KillFeed").OnClientEvent:Connect(addKillFeed)
	Net.Event("Notify").OnClientEvent:Connect(HUD.Toast)
	Net.Event("Reward").OnClientEvent:Connect(function(amount, reason)
		HUD.RewardPopup(amount, reason)
	end)
	Net.Event("CooldownStart").OnClientEvent:Connect(function(abilityId, duration)
		HUD.StartCooldown(abilityId, duration)
		State.TutorialEvent:Fire("AbilityUsed", abilityId)
	end)
	Net.Event("HitConfirm").OnClientEvent:Connect(function(data)
		HUD.RegisterHit()
		if type(data) == "table" and data.IsDummy then
			State.TutorialEvent:Fire("DummyHit")
		end
	end)

	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	RunService.RenderStepped:Connect(stepCooldowns)

	updateSlots()
	updateRound()
end

return HUD
