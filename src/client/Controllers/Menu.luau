-- Startmenue im "Chunky Game UI"-Stil (siehe UI/Theme.luau):
-- * Kamera gleitet langsam ueber das Tal (Teil "MenuCamera" der Map, sonst Orbit um die Lobby)
-- * Logo "NOVA CLASH" aus einzelnen, dick umrandeten Buchstaben mit 3D-Kante und dunklem Schatten,
--   leicht schraeg gestellt. Erster Beitritt: Abblende aus Schwarz, Buchstaben knallen einzeln herein
--   (mit kleinem Kamera-Wackeln), danach gleitet der Untertitel herein.
-- * Knoepfe: PLAY (gross, gruen, Glanz), TUTORIAL, CRATES, SHOP; unten links Begruessung + Muenzen
-- * Dezente dunkle Vignette an den Raendern, damit Text ueber der Landschaft lesbar bleibt

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))
local VFX = Client:WaitForChild("VFX")
local CameraShake = require(VFX:WaitForChild("CameraShake"))

local Menu = {}
Menu.Played = Signal.new() -- (wantsTutorial: boolean)
Menu.OpenCrates = Signal.new()
Menu.OpenShop = Signal.new()

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local WHITE = Color3.new(1, 1, 1)

local CAM_BIND = "NovaMenuCam"
local MENU_FOV = 58
local CANVAS_W, CANVAS_H = 1400, 820
local LOGO_W, LOGO_H = 980, 330
local LOGO_TOP = 96
local TILT = -4 -- Grad, gegen den Uhrzeigersinn (rechte Seite hoeher)
-- Roblox begrenzt TextSize auf 100: groessere Buchstaben werden mit UIScale hochskaliert
local MAX_TEXT = 100

-- leichte Unregelmaessigkeit je Buchstabe: wirkt handgemacht statt "perfekt generiert"
local JITTER_ROT = { -3, 2, -2, 3, -1, 2, -3, 1, 2, -2, 1, -1 }
local JITTER_Y = { 0, -4, 2, -2, 3, -3, 1, -2, 2, 0, -1, 1 }

type Letter = {
	Labels: { TextLabel },
	Scales: { UIScale },
	Offsets: { number },
	X: number,
	Y: number,
	Rot: number,
	Spin: number,
	BaseScale: number,
	Order: number,
	Word: number,
	IsLast: boolean,
	Start: number?,
	Mode: string,
	Shown: boolean,
	Landed: boolean,
	Hidden: boolean,
}

type WordStyle = {
	Size: number,
	Face: ColorSequence,
	Edge: Color3,
	Stroke: number,
	Depth: number,
	Y: number,
}

-- Zustand -------------------------------------------------------------------------

local session = 0
local isOpen = false
local gui: ScreenGui? = nil
local conns: { RBXScriptConnection } = {}
local signalConns: { any } = {}

local camStart = 0
local camCF: CFrame? = nil
local camOverride: CFrame? = nil
local camAway = false
local menuCamPart: BasePart? = nil
local nextCamSearch = 0

-- Easing ----------------------------------------------------------------------------

local function inQuad(a: number): number
	return a * a
end

local function outQuad(a: number): number
	return 1 - (1 - a) * (1 - a)
end

local function outBack(a: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end

local function inOutSine(a: number): number
	return -(math.cos(math.pi * a) - 1) / 2
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(4000, 4000))
	end)
	if ok and v then
		return v.X
	end
	return size * 0.62 * #text
end

-- Kamera ------------------------------------------------------------------------------

local function findMenuCamera(): BasePart?
	local cached = menuCamPart
	if cached and cached.Parent then
		return cached
	end
	local now = os.clock()
	if now < nextCamSearch then
		return nil
	end
	-- die Map wird evtl. noch gebaut: hoechstens einmal pro Sekunde suchen
	nextCamSearch = now + 1
	local map = workspace:FindFirstChild("Map")
	local found = if map then map:FindFirstChild("MenuCamera", true) else nil
	if found and found:IsA("BasePart") then
		menuCamPart = found :: BasePart
		return found :: BasePart
	end
	return nil
end

-- Kamerafahrt: langsames Hin- und Herschwenken um den Blickpunkt (kein voller Orbit,
-- damit die Kamera nicht in Berge/Baeume faehrt), leichtes Heranfahren und Schweben.
local function menuShot(t: number): CFrame
	local part = findMenuCamera()
	if part then
		local base = part.Position
		local attr = part:GetAttribute("MenuFocus")
		local focus: Vector3 = if typeof(attr) == "Vector3" then attr else base + part.CFrame.LookVector * 120
		local offset = base - focus
		local yaw = math.sin(t * 0.09) * math.rad(6)
		local dolly = 1 + math.sin(t * 0.06 + 1.3) * 0.04
		local pos = focus + (CFrame.Angles(0, yaw, 0) * offset) * dolly + Vector3.new(0, math.sin(t * 0.21) * 1.2, 0)
		local look = focus + Vector3.new(math.sin(t * 0.15) * 4, math.sin(t * 0.11) * 1.5, math.cos(t * 0.13) * 2)
		return CFrame.lookAt(pos, look)
	end
	local center = Config.World.LobbyCenter + Vector3.new(0, 8, 0)
	local a = t * 0.045 + 0.6
	local pos = center + Vector3.new(math.cos(a) * 96, 44 + math.sin(t * 0.2) * 3, math.sin(a) * 96)
	return CFrame.lookAt(pos, center)
end

-- Wird jedes Bild NACH der Standard-Kamera gesetzt (CameraShake wackelt danach noch darauf)
local function stepCamera(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- Kistenoeffnung / Cutscene steuern die Kamera selbst
	if State.InCrateOpening or State.InCutscene then
		camAway = true
		return
	end
	if camAway then
		camAway = false
		camCF = nil
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local override = camOverride
	if override then
		cam.CFrame = override
		return
	end
	local target = menuShot(os.clock() - camStart)
	local nextCF: CFrame
	local current = camCF
	if current then
		-- weich nachziehen (z.B. wenn die Map-Kamera erst spaeter auftaucht)
		nextCF = current:Lerp(target, 1 - math.exp(-dt * 2.5))
	else
		nextCF = target
		cam.FieldOfView = MENU_FOV
	end
	camCF = nextCF
	cam.CFrame = nextCF
end

local function unbindCamera()
	pcall(function()
		RunService:UnbindFromRenderStep(CAM_BIND)
	end)
end

-- Vignette ----------------------------------------------------------------------------

local function buildVignette(parent: Instance): { Frame }
	local specs = {
		{ Pos = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.3), Rot = 90, Edge = 0.5 },
		{ Pos = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.4), Rot = 270, Edge = 0.35 },
		{ Pos = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.2, 1), Rot = 0, Edge = 0.55 },
		{ Pos = UDim2.fromScale(0.8, 0), Size = UDim2.fromScale(0.2, 1), Rot = 180, Edge = 0.55 },
	}
	local list = {}
	for _, s in specs do
		local f = Make("Frame", {
			Name = "Vignette",
			BackgroundColor3 = C.Ink,
			BorderSizePixel = 0,
			Position = s.Pos,
			Size = s.Size,
			ZIndex = 1,
			Parent = parent,
		})
		UI.Gradient(f, nil, s.Rot, NumberSequence.new({ NumberSequenceKeypoint.new(0, s.Edge), NumberSequenceKeypoint.new(1, 1) }))
		table.insert(list, f)
	end
	return list
end

-- Logo ----------------------------------------------------------------------------------
-- Drei Ebenen (alle Buchstaben je Ebene als Geschwister, damit sich nichts falsch ueberlappt):
--   1) "Back": dunkler Schatten, etwas dicker und weiter unten
--   2) "Edge": farbige 3D-Kante direkt unter dem Buchstaben
--   3) "Face": Buchstabe mit dicker dunkler Kontur und dezenter Schattierung

local function buildLogo(parent: Instance): { Letter }
	local layers: { Frame } = {}
	for i, name in { "Back", "Edge", "Face" } do
		layers[i] = Make("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = i + 1,
			Parent = parent,
		})
	end
	local styles: { WordStyle } = {
		{
			Size = 112,
			Face = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 178, 34)),
			Edge = C.GoldDark,
			Stroke = 6,
			Depth = 7,
			Y = 92,
		},
		{
			Size = 160,
			Face = ColorSequence.new(WHITE, Color3.fromRGB(206, 222, 246)),
			Edge = C.BlueDark,
			Stroke = 7,
			Depth = 9,
			Y = 222,
		},
	}
	local words = string.split(Config.GameName, " ")
	if #words > 2 then
		words = { words[1], table.concat(words, " ", 2) }
	end
	local letters: { Letter } = {}
	local order = 0
	local tiltSin = math.sin(math.rad(TILT))
	for w, word in words do
		-- ein einzelnes Wort bekommt den grossen Stil und sitzt mittig
		local st = if #words == 1 then styles[2] else styles[w]
		local baseY = if #words == 1 then LOGO_H / 2 else st.Y
		local chars: { string } = {}
		local widths: { number } = {}
		local spacing = -3
		local total = 0
		-- echte Schriftgroesse (max. 100) und Faktor bis zur gewuenschten Groesse
		local textSize = math.min(st.Size, MAX_TEXT)
		local baseScale = st.Size / textSize
		for i = 1, #word do
			local ch = string.sub(word, i, i)
			local cw = if ch == " " then st.Size * 0.3 else textWidth(ch, textSize, F.Display) * baseScale
			table.insert(chars, ch)
			table.insert(widths, cw)
			total += cw + (if i > 1 then spacing else 0)
		end
		local cursor = LOGO_W / 2 - total / 2
		for i, ch in chars do
			local cw = widths[i]
			local cx = cursor + cw / 2
			cursor += cw + spacing
			if ch == " " then
				continue
			end
			order += 1
			local labels: { TextLabel } = {}
			local scales: { UIScale } = {}
			for layer = 1, 3 do
				local fill = if layer == 1 then C.Ink elseif layer == 2 then st.Edge else WHITE
				local label = Make("TextLabel", {
					Name = ch,
					BackgroundTransparency = 1,
					Text = ch,
					Font = F.Display,
					TextSize = textSize,
					TextColor3 = fill,
					TextWrapped = false,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(math.ceil(cw / baseScale) + 20, textSize + 20),
					Visible = false,
					Parent = layers[layer],
				})
				Make("UIStroke", {
					Color = if layer == 2 then st.Edge else C.Ink,
					-- UIScale skaliert auch die Kontur mit, daher hier zurueckrechnen
					Thickness = (if layer == 1 then st.Stroke + 3 else st.Stroke) / baseScale,
					LineJoinMode = Enum.LineJoinMode.Round,
					Parent = label,
				})
				if layer == 3 then
					UI.Gradient(label, st.Face, 90)
				end
				labels[layer] = label
				scales[layer] = Make("UIScale", { Parent = label })
			end
			table.insert(letters, {
				Labels = labels,
				Scales = scales,
				Offsets = { st.Depth + 4, st.Depth, 0 },
				X = cx,
				Y = baseY + (cx - LOGO_W / 2) * tiltSin + (JITTER_Y[order] or 0),
				Rot = TILT + (JITTER_ROT[order] or 0),
				Spin = (if order % 2 == 0 then 1 else -1) * 16,
				BaseScale = baseScale,
				Order = order,
				Word = w,
				IsLast = false,
				Start = nil,
				Mode = "Bounce",
				Shown = false,
				Landed = false,
				Hidden = false,
			})
		end
	end
	if #letters > 0 then
		letters[#letters].IsLast = true
	end
	return letters
end

local function placeLetter(L: Letter, dx: number, dy: number, dr: number, s: number)
	for j = 1, 3 do
		local label = L.Labels[j]
		label.Position = UDim2.fromOffset(L.X + dx, L.Y + dy + L.Offsets[j] * s)
		label.Rotation = L.Rot + dr
		L.Scales[j].Scale = s * L.BaseScale
	end
end

local function setLetterVisible(L: Letter, visible: boolean)
	for _, label in L.Labels do
		label.Visible = visible
	end
end

-- Kleine Comic-Staubwoelkchen unter dem Logo, wenn der letzte Buchstabe aufschlaegt
local function dustPuffs(parent: Instance, y: number)
	for i = 1, 10 do
		local side = if i % 2 == 0 then 1 else -1
		local size = math.random(18, 30)
		local startX = LOGO_W / 2 + side * math.random(40, 240)
		local puff = Make("Frame", {
			Name = "Puff",
			BackgroundColor3 = Color3.fromRGB(236, 232, 222),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(startX, y + math.random(-6, 6)),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 1,
			Parent = parent,
		})
		UI.Round(puff)
		local stroke = UI.Stroke(puff, C.Ink, 2.5, 0)
		local life = 0.45 + math.random() * 0.2
		UI.Tween(puff, life, {
			Position = UDim2.fromOffset(startX + side * math.random(50, 110), y + math.random(-26, 4)),
			Size = UDim2.fromOffset(size * 1.7, size * 1.7),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad)
		UI.Tween(stroke, life, { Transparency = 1 }, Enum.EasingStyle.Quad)
		task.delay(life + 0.05, function()
			puff:Destroy()
		end)
	end
end

-- Kleine Bausteine ---------------------------------------------------------------------

local function drawCoin(parent: Instance, size: number, position: UDim2): Frame
	local coin = Make("Frame", {
		Name = "Coin",
		BackgroundColor3 = C.Coin,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
		Parent = parent,
	})
	UI.Round(coin)
	UI.Stroke(coin, C.Ink, 2.5, 0)
	local inner = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 222, 110),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56),
		ZIndex = 4,
		Parent = coin,
	})
	UI.Round(inner)
	UI.Stroke(inner, C.GoldDark, 2, 0)
	return coin
end

local function cornerBadge(button: Instance, text: string): Frame
	local badge = Make("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Red,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0, 2),
		Size = UDim2.fromOffset(56, 24),
		Rotation = 8,
		ZIndex = 10,
		Parent = button,
	})
	UI.Corner(badge, 12)
	UI.Stroke(badge, C.Ink, 2.5, 0)
	UI.Text({
		Text = text,
		Font = F.Heading,
		TextSize = 14,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
		Stroke = 1.5,
		Parent = badge,
	})
	local pulse = Make("UIScale", { Parent = badge })
	TweenService:Create(pulse, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 }):Play()
	return badge
end

-- Untertitel mit kleinen Rauten links und rechts
local function buildSubtitle(parent: Instance, centerY: number): Frame
	local text = Config.Subtitle
	local size = 26
	local tw = textWidth(text, size, F.Heading)
	local group = Make("Frame", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CANVAS_W / 2, centerY),
		Size = UDim2.fromOffset(tw + 200, 40),
		ZIndex = 3,
		Parent = parent,
	})
	UI.Text({
		Name = "Label",
		Text = text,
		Font = F.Heading,
		TextSize = size,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Stroke = 3,
		Parent = group,
	})
	local mid = (tw + 200) / 2
	for _, side in { -1, 1 } do
		local diamond = Make("Frame", {
			Name = "Diamond",
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mid + side * (tw / 2 + 20), 20),
			Size = UDim2.fromOffset(12, 12),
			Rotation = 45,
			ZIndex = 4,
			Parent = group,
		})
		diamond:SetAttribute("Fill", true)
		UI.Corner(diamond, 2)
		UI.Stroke(diamond, C.Ink, 2.5, 0)
		local bar = Make("Frame", {
			Name = "Bar",
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mid + side * (tw / 2 + 56), 20),
			Size = UDim2.fromOffset(40, 6),
			ZIndex = 3,
			Parent = group,
		})
		bar:SetAttribute("Fill", true)
		UI.Corner(bar, 3)
		UI.Stroke(bar, C.Ink, 2.5, 0)
	end
	return group
end

local function fadeGroup(group: Instance, visible: boolean, time: number)
	local target = if visible then 0 else 1
	for _, d in group:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.Tween(d, time, { TextTransparency = target })
		elseif d:IsA("UIStroke") then
			UI.Tween(d, time, { Transparency = target })
		elseif d:IsA("Frame") and d:GetAttribute("Fill") then
			UI.Tween(d, time, { BackgroundTransparency = target })
		end
	end
end

local function setGroupTransparent(group: Instance)
	for _, d in group:GetDescendants() do
		if d:IsA("TextLabel") then
			(d :: TextLabel).TextTransparency = 1
		elseif d:IsA("UIStroke") then
			(d :: UIStroke).Transparency = 1
		elseif d:IsA("Frame") and d:GetAttribute("Fill") then
			(d :: Frame).BackgroundTransparency = 1
		end
	end
end

-- Begruessung unten links: Avatar, Name, Muenzen
local function buildWelcome(parent: Instance): (Frame, () -> ())
	local holder = Make("Frame", {
		Name = "Welcome",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(400, 72),
		ZIndex = 4,
		Parent = parent,
	})
	UI.Scaled(holder)
	local slide = Make("Frame", {
		Name = "Slide",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-480, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	local shadow = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		Parent = slide,
	})
	UI.Corner(shadow, 16)
	local plate = UI.Panel({ Name = "Plate", Radius = 16, Size = UDim2.fromScale(1, 1), Parent = slide })

	local avatar = Make("Frame", {
		Name = "Avatar",
		BackgroundColor3 = C.PanelLight,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		Parent = plate,
	})
	UI.Round(avatar)
	UI.Stroke(avatar, C.Ink, 2.5, 0)
	local img = Make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
		Parent = avatar,
	})
	UI.Round(img)

	local greet = UI.Text({
		Name = "Greeting",
		Text = "WELCOME",
		Font = F.Heading,
		TextSize = 14,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(76, 12),
		Size = UDim2.fromOffset(170, 16),
		Parent = plate,
	})
	UI.Text({
		Name = "PlayerName",
		Text = player.DisplayName,
		Font = F.Heading,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(76, 30),
		Size = UDim2.fromOffset(168, 28),
		Stroke = 2,
		Parent = plate,
	})
	local pill = UI.Inset({
		Name = "Coins",
		Radius = 14,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(132, 40),
		Parent = plate,
	})
	drawCoin(pill, 26, UDim2.new(0, 7, 0.5, 0))
	local coins = UI.Text({
		Name = "Amount",
		Text = "...",
		Font = F.Heading,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -50, 1, 0),
		Stroke = 2,
		Parent = pill,
	})
	local function update()
		local p = State.Profile
		if p then
			greet.Text = if p.TutorialDone then "WELCOME BACK" else "WELCOME"
			coins.Text = UI.Format(tonumber(p.Coins) or 0)
		end
	end
	update()
	return slide, update
end

-- Aufraeumen ------------------------------------------------------------------------------

local function disconnectAll()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	for _, c in signalConns do
		c:Disconnect()
	end
	table.clear(signalConns)
end

local function restoreCamera()
	unbindCamera()
	camOverride = nil
	local cam = workspace.CurrentCamera
	if not cam then
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

-- Kamerafahrt vom Menue-Blick hinter den eigenen Charakter (kleiner Bogen nach oben)
local function flyToCharacter(mySession: number)
	local hrp: BasePart? = nil
	local deadline = os.clock() + 4
	while os.clock() < deadline and session == mySession do
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			hrp = r :: BasePart
			break
		end
		task.wait(0.1)
	end
	local cam = workspace.CurrentCamera
	local root = hrp
	if not root or not cam or session ~= mySession or State.InCrateOpening or State.InCutscene then
		return
	end
	local from = camCF or cam.CFrame
	local look = root.Position + Vector3.new(0, 2, 0)
	local toPos = (root.CFrame * CFrame.new(0, 4.5, 13)).Position
	local fromFocus = from.Position + from.LookVector * (look - from.Position).Magnitude
	local startFov = cam.FieldOfView
	local duration = 1.3
	local t0 = os.clock()
	while session == mySession do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local e = inOutSine(a)
		local pos = from.Position:Lerp(toPos, e) + Vector3.new(0, math.sin(e * math.pi) * 10, 0)
		local focus = fromFocus:Lerp(look, outQuad(math.min(1, a * 1.25)))
		camOverride = CFrame.lookAt(pos, focus)
		cam.FieldOfView = startFov + (70 - startFov) * e
		if a >= 1 then
			break
		end
		task.wait()
	end
end

-- Oeffentliche API ----------------------------------------------------------------------------

function Menu.Show(firstTime: boolean)
	-- falls das Menue schon offen ist: altes sauber entfernen
	session += 1
	local mySession = session
	disconnectAll()
	local old = gui
	if old then
		old:Destroy()
	end

	isOpen = true
	State.MenuOpen = true
	State.SetBusy("Menu", true)
	State.SetHUDHidden("Menu", true)

	-- Kamera
	camCF = nil
	camOverride = nil
	camAway = false
	camStart = os.clock() - math.random() * 30
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = MENU_FOV
	end
	unbindCamera()
	RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Camera.Value + 1, stepCamera)

	-- Oberflaeche
	local screen = UI.Screen("NovaMenu", 15)
	gui = screen
	local root = Make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen })
	local vignette = buildVignette(root)

	local canvas = Make("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CANVAS_W, CANVAS_H),
		ZIndex = 2,
		Parent = root,
	})
	UI.Scaled(canvas)

	local logoBase = UDim2.fromOffset(CANVAS_W / 2, LOGO_TOP)
	local logo = Make("Frame", {
		Name = "Logo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = logoBase,
		Size = UDim2.fromOffset(LOGO_W, LOGO_H),
		ZIndex = 2,
		Parent = canvas,
	})
	local fx = Make("Frame", { Name = "Fx", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = logo })
	local letters = buildLogo(logo)
	for _, L in letters do
		placeLetter(L, 0, 0, 0, 1)
	end

	local subtitleY = LOGO_TOP + LOGO_H + 16
	local subtitle = buildSubtitle(canvas, subtitleY)
	local subtitleBase = subtitle.Position
	setGroupTransparent(subtitle)

	-- Knoepfe
	local buttonsTop = subtitleY + 44
	local buttons = Make("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(CANVAS_W / 2, buttonsTop),
		Size = UDim2.fromOffset(432, 168),
		ZIndex = 3,
		Parent = canvas,
	})
	local played = false
	local play: (boolean) -> ()

	local playButton = UI.Button({
		Name = "Play",
		Text = "PLAY",
		Style = "Green",
		Size = UDim2.fromOffset(432, 88),
		TextSize = 44,
		Lip = 7,
		Shine = true,
		Parent = buttons,
		OnClick = function()
			play(false)
		end,
	})
	local small: { TextButton } = {}
	local smallSpecs = {
		{ Name = "Tutorial", Text = "TUTORIAL", Style = "Blue" },
		{ Name = "Crates", Text = "CRATES", Style = "Gold" },
		{ Name = "Shop", Text = "SHOP", Style = "Purple" },
	}
	for i, spec in smallSpecs do
		local b = UI.Button({
			Name = spec.Name,
			Text = spec.Text,
			Style = spec.Style,
			Position = UDim2.fromOffset((i - 1) * 148, 104),
			Size = UDim2.fromOffset(136, 60),
			TextSize = 21,
			Parent = buttons,
			OnClick = function()
				if played then
					return
				end
				if spec.Name == "Tutorial" then
					play(true)
				elseif spec.Name == "Crates" then
					Menu.OpenCrates:Fire()
				else
					Menu.OpenShop:Fire()
				end
			end,
		})
		table.insert(small, b)
	end
	local freeBadge = cornerBadge(small[2], "FREE")
	local allButtons: { TextButton } = { playButton, small[1], small[2], small[3] }
	for _, b in allButtons do
		b.Visible = false
	end

	local welcome, updateWelcome = buildWelcome(root)
	local function onProfile()
		updateWelcome()
		local p = State.Profile
		freeBadge.Visible = p ~= nil and p.FreeCrate == true
	end
	onProfile()
	table.insert(signalConns, State.ProfileChanged:Connect(onProfile))

	-- Schwarzblende (nur fuer das Intro)
	local black = Make("Frame", {
		Name = "Fade",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = root,
	})

	-- Buchstaben-Animation (ein Loop fuer alles) --------------------------------------
	local idleStart: number? = nil
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			-- waehrend Kistenoeffnung / Cutscene ausblenden
			screen.Enabled = not (State.InCrateOpening or State.InCutscene)
			local now = os.clock()
			local float = math.sin(now * 1.4) * 5
			local hopT = if idleStart then (now - idleStart) % 6 else -1
			for _, L in letters do
				local start = L.Start
				if L.Hidden or not start or now < start then
					continue
				end
				if not L.Shown then
					L.Shown = true
					setLetterVisible(L, true)
					if L.Mode == "Bounce" then
						UI.Sound("Hover", 0.85 + L.Order * 0.06)
					end
				end
				local e = now - start
				local dx, dy, dr, s = 0, 0, 0, 1
				if L.Mode == "Slam" then
					local fall, settle = 0.13, 0.17
					if e < fall then
						local a = e / fall
						s = 2.6 + (0.86 - 2.6) * inQuad(a)
						dr = (1 - a) * L.Spin
						dy = -26 * (1 - a)
					elseif e < fall + settle then
						s = 0.86 + 0.14 * outBack((e - fall) / settle)
					end
					if e >= fall and not L.Landed then
						L.Landed = true
						if L.IsLast then
							UI.Sound("HeavyPunch", 0.95)
							CameraShake.Shake(1.8, 0.4)
							dustPuffs(fx, L.Y + 70)
						else
							UI.Sound("Punch", 1 + L.Order * 0.03)
							CameraShake.Shake(0.7, 0.16)
						end
					end
				elseif L.Mode == "Bounce" then
					local a = math.clamp(e / 0.5, 0, 1)
					dy = -80 * (1 - outBack(a))
					s = 0.55 + 0.45 * outBack(a)
				elseif L.Mode == "Out" then
					local a = math.clamp(e / 0.35, 0, 1)
					dy = -560 * inQuad(a)
					dr = a * L.Spin
					s = 1 + 0.25 * a
					if a >= 1 then
						L.Hidden = true
						setLetterVisible(L, false)
						continue
					end
				end
				-- Ruhe: ganzes Logo schwebt, ab und zu huepft eine kleine Welle durch die Buchstaben
				if hopT >= 0 and L.Mode ~= "Out" then
					local h = hopT - L.Order * 0.07
					if h > 0 and h < 0.32 then
						dy -= math.sin(h / 0.32 * math.pi) * 12
					end
				end
				placeLetter(L, dx, dy + float, dr, s)
			end
		end)
	)

	-- Starten / Tutorial --------------------------------------------------------------------
	play = function(wantsTutorial: boolean)
		if played or session ~= mySession then
			return
		end
		played = true
		UI.CloseAllWindows()
		UI.Sound("Fight")

		-- alles aus dem Bild schieben
		for i, b in allButtons do
			local s = b:FindFirstChild("PopScale") :: UIScale?
			if s then
				UI.Tween(s, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In, (i - 1) * 0.04)
			end
		end
		local now = os.clock()
		for _, L in letters do
			if not L.Hidden then
				L.Mode = "Out"
				L.Start = now + L.Order * 0.03
				if not L.Shown then
					L.Hidden = true
					setLetterVisible(L, false)
				end
			end
		end
		fadeGroup(subtitle, false, 0.25)
		UI.Tween(welcome, 0.35, { Position = UDim2.fromOffset(-480, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		for _, v in vignette do
			UI.Tween(v, 0.8, { BackgroundTransparency = 1 })
		end
		black.Visible = false

		flyToCharacter(mySession)
		if session ~= mySession then
			return
		end

		-- zurueck ins Spiel
		restoreCamera()
		disconnectAll()
		screen:Destroy()
		if gui == screen then
			gui = nil
		end
		isOpen = false
		State.MenuOpen = false
		State.SetHUDHidden("Menu", false)
		State.SetBusy("Menu", false)
		Menu.Played:Fire(wantsTutorial)
	end

	-- Intro -------------------------------------------------------------------------------
	local function revealRest(fast: boolean)
		if session ~= mySession or played then
			return
		end
		-- Untertitel gleitet von unten herein
		subtitle.Position = subtitleBase + UDim2.fromOffset(0, 28)
		fadeGroup(subtitle, true, if fast then 0.25 else 0.4)
		UI.Tween(subtitle, if fast then 0.3 else 0.5, { Position = subtitleBase }, Enum.EasingStyle.Back)
		task.wait(if fast then 0.12 else 0.3)
		if session ~= mySession or played then
			return
		end
		-- Knoepfe ploppen nacheinander auf
		for i, b in allButtons do
			task.delay((i - 1) * 0.07, function()
				if session ~= mySession or played then
					return
				end
				b.Visible = true
				UI.Pop(b, 0.3, 0.4)
				if i == 1 then
					UI.Sound("Open")
				end
			end)
		end
		UI.Tween(welcome, 0.5, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.2)
		task.wait(0.6)
		if session == mySession and not played then
			idleStart = os.clock() + 2
		end
	end

	task.spawn(function()
		if firstTime then
			-- langes Intro: langsam aus Schwarz auftauchen, dann knallen die Buchstaben herein
			task.wait(0.4)
			UI.Sound("Whoosh", 0.6)
			UI.Tween(black, 1.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
			task.delay(1.85, function()
				black.Visible = false
			end)
			task.wait(1.3)
			if session ~= mySession or played then
				return
			end
			local t = os.clock()
			for _, L in letters do
				L.Mode = "Slam"
				-- kleine Pause zwischen den Woertern
				L.Start = t + (L.Order - 1) * 0.13 + (L.Word - 1) * 0.22
			end
			task.wait((#letters - 1) * 0.13 + 0.22 + 0.45)
			revealRest(false)
		else
			UI.Tween(black, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(0.65, function()
				black.Visible = false
			end)
			task.wait(0.15)
			if session ~= mySession or played then
				return
			end
			local t = os.clock()
			for _, L in letters do
				L.Mode = "Bounce"
				L.Start = t + (L.Order - 1) * 0.045
			end
			task.wait((#letters - 1) * 0.045 + 0.3)
			revealRest(true)
		end
	end)

	-- Logo kurz anstossen, wenn man es anklickt (kleines Detail fuer Neugierige)
	local logoButton = Make("TextButton", {
		Name = "LogoHit",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = logo,
	})
	logoButton.Activated:Connect(function()
		if idleStart and not played then
			idleStart = os.clock() - 0.01
			UI.Sound("Hover", 1.2)
		end
	end)
end

function Menu.IsOpen(): boolean
	return isOpen
end

function Menu.Init() end

function Menu.Start() end

return Menu
