-- Robux-Shop: exklusive BLACK HOLE Faehigkeit (Game Pass) + Muenzpakete (Developer Products).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

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
local WHITE = Color3.new(1, 1, 1)

local window: UI.Window
local buyButton: TextButton
local spinners: { { obj: GuiObject, speed: number } } = {}

local function ownsBlackHole(): boolean
	return State.Owned("BlackHole") > 0
end

local function updateBuyButton()
	if not buyButton then
		return
	end
	if ownsBlackHole() then
		UI.SetButtonText(buyButton, "✓ OWNED")
		UI.SetButtonStyle(buyButton, "Success")
	else
		UI.SetButtonText(buyButton, "BUY  " .. Config.Shop.BlackHoleDisplayPrice)
		UI.SetButtonStyle(buyButton, "Robux")
	end
end

local function buy(kind: string, index: number?, button: GuiObject?)
	if kind == "BlackHole" and ownsBlackHole() then
		HUD.Toast({ Text = "You already own Black Hole! Equip it in your ABILITIES.", Color = C.Purple, Icon = "🕳️" })
		return
	end
	local ok, result = pcall(function()
		return Net.Function("BuyItem"):InvokeServer(kind, index)
	end)
	if not ok or type(result) ~= "table" or not result.Ok then
		if button then
			UI.Shake(button)
		end
		HUD.Toast({ Text = if ok and type(result) == "table" then result.Message else "Connection error", Color = C.Danger, Icon = "⚠️" })
		return
	end
	if result.Simulated then
		HUD.Toast({ Text = "Studio test mode: purchase simulated (set the IDs in Config.Shop).", Color = C.Gold, Icon = "🧪" })
	end
end

-- Animiertes Schwarzes Loch aus UI-Elementen
local function buildHoleVisual(parent: Frame)
	local center = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 300),
		Parent = parent,
	})
	-- Leuchtende Ringe (Akkretionsscheibe)
	local ringDefs = {
		{ size = 290, color = Theme.Gradients.Void, thick = 6, speed = 25 },
		{ size = 230, color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(150, 60, 255)), thick = 10, speed = -45 },
		{ size = 175, color = ColorSequence.new(Color3.fromRGB(255, 230, 160), Color3.fromRGB(255, 120, 40)), thick = 8, speed = 80 },
	}
	for _, rd in ringDefs do
		local ring = Make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(rd.size, rd.size * 0.42),
			Parent = center,
		})
		UI.Round(ring)
		local st = UI.Stroke(ring, WHITE, rd.thick, 0)
		local g = UI.Gradient(st, rd.color, 0)
		UI.Animate(g, rd.speed * 3, "Rotate")
		ring.Rotation = -12
	end
	-- Ereignishorizont
	local glow = Make("Frame", {
		BackgroundColor3 = C.Purple,
		BackgroundTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
		Parent = center,
	})
	UI.Round(glow)
	local core = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(120, 120),
		Parent = center,
	})
	UI.Round(core)
	local ps = UI.Stroke(core, Color3.fromRGB(255, 220, 170), 3, 0.1)
	local _ = ps
	-- Kreisende Partikel
	for i = 1, 14 do
		local dot = Make("Frame", {
			BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(255, 160, 60) else Color3.fromRGB(190, 120, 255),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			Parent = center,
		})
		UI.Round(dot)
		table.insert(spinners, { obj = dot, speed = 0.6 + (i % 5) * 0.25 })
		dot:SetAttribute("Radius", 70 + (i * 37) % 80)
		dot:SetAttribute("Phase", i * 0.9)
	end
	-- Pulsieren
	task.spawn(function()
		while glow.Parent do
			UI.Tween(glow, 1.2, { Size = UDim2.fromOffset(165, 165), BackgroundTransparency = 0.35 }, Enum.EasingStyle.Sine)
			task.wait(1.2)
			UI.Tween(glow, 1.2, { Size = UDim2.fromOffset(145, 145), BackgroundTransparency = 0.55 }, Enum.EasingStyle.Sine)
			task.wait(1.2)
		end
	end)
end

function Shop.Open()
	window:Open()
	updateBuyButton()
end

function Shop.Init()
	window = UI.Window({ Title = "SHOP", Icon = "💎", Size = Vector2.new(1000, 640), Name = "Shop" })
	local content = window.Content

	-- Hero: Black Hole
	local hero = UI.Panel({
		Position = UDim2.fromOffset(20, 6),
		Size = UDim2.new(1, -40, 0, 360),
		StrokeColor = Theme.Gradients.Void,
		Parent = content,
	})
	local heroBg = hero:FindFirstChildOfClass("UIGradient")
	if heroBg then
		heroBg.Color = ColorSequence.new(Color3.fromRGB(28, 10, 50), Color3.fromRGB(6, 3, 14))
		heroBg.Rotation = 0
	end
	hero.ClipsDescendants = true
	local visual = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.45, 0, 1, 0), Parent = hero })
	buildHoleVisual(visual)
	UI.Ambient(hero, { Colors = { Color3.fromRGB(190, 120, 255), Color3.fromRGB(255, 160, 60), WHITE }, Interval = 0.2 })

	local info = Make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.45, 0), Size = UDim2.new(0.55, -20, 1, 0), Parent = hero })
	UI.Text({
		Text = "✦ EXCLUSIVE ABILITY ✦",
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 170, 80),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = info,
	})
	local title = UI.Text({
		Text = "BLACK HOLE",
		Font = Theme.Fonts.Title,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 72),
		TextWrapped = false,
		Parent = info,
	})
	local tg = UI.Gradient(title, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 120, 255)),
		ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 60)),
	}), 0)
	UI.Animate(tg, 0.4, "Offset")
	Make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(30, 0, 50), Parent = title })
	local features = {
		"🎬  Epic cinematic cutscene with its own camera",
		"🌀  Sucks every enemy into the singularity",
		"💥  Colossal implosion – 50 damage",
		"♾️  Yours forever – never in any crate",
	}
	for i, f in features do
		UI.Text({
			Text = f,
			Font = Theme.Fonts.Bold,
			TextSize = 17,
			TextColor3 = C.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(4, 128 + (i - 1) * 30),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = info,
		})
	end
	buyButton = UI.Button({
		Text = "BUY",
		Style = "Robux",
		Size = UDim2.fromOffset(250, 62),
		Position = UDim2.new(0, 0, 1, -86),
		TextSize = 26,
		Parent = info,
	})
	buyButton.Activated:Connect(function()
		buy("BlackHole", nil, buyButton)
	end)
	UI.Button({
		Text = "▶ PREVIEW",
		Style = "Secondary",
		Size = UDim2.fromOffset(190, 62),
		Position = UDim2.new(0, 266, 1, -86),
		TextSize = 20,
		Parent = info,
		OnClick = function()
			window:Close()
			task.wait(0.25)
			VFXController.Preview("BlackHole")
		end,
	})

	-- Muenzpakete
	UI.Text({
		Text = "🪙 COIN PACKS",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(26, 376),
		Size = UDim2.fromOffset(400, 28),
		Parent = content,
	})
	local row = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 410),
		Size = UDim2.new(1, -40, 0, 150),
		Parent = content,
	})
	UI.List(row, true, 18, Enum.HorizontalAlignment.Center)
	for i, pack in Config.Shop.CoinPacks do
		local card = UI.Panel({
			Size = UDim2.fromOffset(290, 150),
			LayoutOrder = i,
			StrokeColor = Theme.Gradients.Gold,
			Radius = 14,
			Parent = row,
		})
		UI.Text({ Text = pack.Icon, TextSize = 46, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(70, 70), Parent = card })
		UI.Text({
			Text = string.upper(pack.Name),
			Font = Theme.Fonts.Title,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(86, 16),
			Size = UDim2.fromOffset(190, 24),
			Parent = card,
		})
		local amount = UI.Text({
			Text = "🪙 " .. UI.Format(pack.Coins),
			Font = Theme.Fonts.Title,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(86, 42),
			Size = UDim2.fromOffset(190, 32),
			Parent = card,
		})
		UI.Gradient(amount, Theme.Gradients.Gold, 90)
		local priceLabel = pack.DisplayPrice
		local b = UI.Button({
			Text = priceLabel,
			Style = "Robux",
			Size = UDim2.new(1, -24, 0, 50),
			Position = UDim2.new(0, 12, 1, -62),
			TextSize = 22,
			Parent = card,
		})
		b.Activated:Connect(function()
			buy("Coins", i, b)
		end)
		-- Echten Preis laden, falls eingerichtet
		if pack.ProductId ~= 0 then
			task.spawn(function()
				local ok, infoData = pcall(function()
					return MarketplaceService:GetProductInfo(pack.ProductId, Enum.InfoType.Product)
				end)
				if ok and infoData and infoData.PriceInRobux then
					UI.SetButtonText(b, "R$ " .. infoData.PriceInRobux)
				end
			end)
		end
	end
	if Config.Shop.BlackHoleGamePassId == 0 or Config.Shop.CoinPacks[1].ProductId == 0 then
		UI.Text({
			Text = "🧪 Studio test mode: IDs in Config.Shop are 0 – purchases are simulated in Studio.",
			Font = Theme.Fonts.Body,
			TextSize = 13,
			TextColor3 = C.Muted,
			Position = UDim2.new(0, 0, 1, -24),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = content,
		})
	end

	RunService.RenderStepped:Connect(function()
		if not window.IsOpen then
			return
		end
		local t = os.clock()
		for _, s in spinners do
			local r = s.obj:GetAttribute("Radius") or 80
			local ph = s.obj:GetAttribute("Phase") or 0
			local a = t * s.speed + ph
			s.obj.Position = UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r * 0.42)
		end
	end)
end

function Shop.Start()
	State.ProfileChanged:Connect(updateBuyButton)
	updateBuyButton()
end

return Shop
