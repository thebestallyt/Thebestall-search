-- Interaktives Tutorial im "Chunky Game UI"-Stil:
-- * Karte oben in der Mitte: Schritt-Schild "STEP 3/9" + Fortschritts-Punkte, Titel, Text,
--   Tasten-Kappen (PC), Fortschrittsbalken fuer Zaehl-Schritte, NEXT-Knopf fuer Info-Schritte
-- * Weg zu den Trainingspuppen: kleine leuchtende Pfeil-Markierungen am Boden (Pathfinding,
--   sonst gerade Linie), eine Welle laeuft Richtung Ziel; am Ziel ein pulsierender Bodenkreis
--   und ein schwebendes Schild mit Entfernung
-- * HUD-Knoepfe werden mit einem gezeichneten, huepfenden Pfeil und einem Rahmen hervorgehoben

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Tutorial = {}
Tutorial.Finished = Signal.new()

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local WHITE = Color3.new(1, 1, 1)

local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Masse der Karte (Design-Pixel, skaliert ueber UI.Scaled)
local CARD_W = 580
local PAD = 20
local TEXT_SIZE = 17
local TOP_OFFSET = 92 -- Platz fuer die Rundenanzeige oben in der Mitte

-- Farbe der Boden-Pfeile: warmes Gold, keine Neon-Cyan-Toene
local GUIDE_COLOR = Color3.fromRGB(255, 214, 96)

type Step = {
	Title: string,
	Text: string,
	Wait: string?,
	Count: number?,
	Button: string?,
	Highlight: string?,
	Guide: boolean?,
	Keys: { string }?,
	Skip: (() -> boolean)?,
}

-- "|text" in Keys = kleine Beschriftung statt Tasten-Kappe
local STEPS: { Step } = {
	{
		Title = "WELCOME TO NOVA CLASH!",
		Text = "Battle other fighters with flashy abilities. Let's learn the basics – it only takes a minute!",
		Button = "LET'S GO",
	},
	{
		Title = "MOVEMENT",
		Text = if TOUCH
			then "Use the joystick on the left to walk and the jump button to jump. Get moving!"
			else "Walk around and jump. Get moving!",
		Wait = "Move",
		Keys = if TOUCH then nil else { "W", "A", "S", "D", "|move", "SPACE", "|jump" },
	},
	{
		Title = "ATTACK",
		Text = (if TOUCH
			then "Follow the golden arrows to the training dummies and tap ATTACK to hit one."
			else "Follow the golden arrows to the training dummies and hit one with LEFT CLICK.")
			.. " Land 4 hits for a full combo!",
		Wait = "DummyHit",
		Count = 4,
		Guide = true,
		Keys = if TOUCH then nil else { "CLICK", "|attack" },
	},
	{
		Title = "BLOCK",
		Text = (if TOUCH then "Hold BLOCK to guard." else "Hold F to guard.")
			.. " Blocking cuts damage by 75% – but the 4th hit of a combo breaks your guard!",
		Wait = "Block",
		Keys = if TOUCH then nil else { "F", "|hold to block" },
	},
	{
		Title = "DASH",
		Text = (if TOUCH then "Tap DASH" else "Press Q") .. " to dash and dodge incoming attacks.",
		Wait = "Dash",
		Keys = if TOUCH then nil else { "Q", "|dash" },
	},
	{
		Title = "ABILITIES",
		Text = (if TOUCH then "Tap ability slot 1 at the bottom" else "Press 1")
			.. " to unleash your first ability: EMBER PUNCH! Try it on a dummy.",
		Wait = "AbilityUsed",
		Guide = true,
		Keys = if TOUCH then nil else { "1", "|ability" },
	},
	{
		Title = "CRATES",
		Text = "New abilities come from crates – the rarer the ability, the crazier its effects. Open your FREE starter crate!",
		Wait = "CrateOpened",
		Highlight = "Crates",
		Skip = function()
			return not (State.Profile and State.Profile.FreeCrate)
		end,
	},
	{
		Title = "YOUR LOADOUT",
		Text = "New abilities go on a free key automatically. Open ABILITIES to preview them or swap slots.",
		Button = "GOT IT",
		Highlight = "Inventory",
	},
	{
		Title = "ROUNDS",
		Text = "Rounds start on their own – the last fighter standing wins coins! MYTHIC and DIVINE abilities even have their own cutscenes. Check the SHOP for the exclusive BLACK HOLE!",
		Button = "START PLAYING",
		Highlight = "Shop",
	},
}

local PRAISE = { "NICE!", "GREAT!", "AWESOME!", "PERFECT!", "SWEET!" }

-- UI-Elemente
local gui: ScreenGui
local holder: Frame
local cardSlot: Frame
local cardShadow: Frame
local card: Frame
local stepPill: Frame
local stepLabel: TextLabel
local pipsFrame: Frame
local titleLabel: TextLabel
local textLabel: TextLabel
local keysRow: Frame
local progress: any
local nextButton: TextButton
local skipButton: TextButton
local stamp: TextLabel
local pointer: Frame
local ring: Frame
local ringStroke: UIStroke
local ringInk: UIStroke

-- Zustand
local running = false
local runId = 0
local hudHidden = false
local currentHighlight: string? = nil
local pips: { Frame } = {}
local skipArmedUntil = 0

local function measureText(text: string, size: number, font: Enum.Font, width: number): Vector2
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(width, 2000))
	end)
	if ok and v then
		return v
	end
	return Vector2.new(width, size * 1.3 * math.ceil(#text * size * 0.55 / width))
end

-- Gezeichnete Pfeile ---------------------------------------------------------------------
-- Drei Ebenen (Schatten, dunkle Kontur, goldene Fuellung) aus Rechteck + halber Raute,
-- dadurch ein sauberer Umriss ohne Emoji. dir = "Left" oder "Down".

local function drawArrow(parent: Instance, dir: string, scale: number, fill: Color3): Frame
	local L, T = 80 * scale, 50 * scale -- Laenge, Dicke
	local isDown = dir == "Down"
	local root = Make("Frame", {
		Name = "Arrow",
		BackgroundTransparency = 1,
		Size = if isDown then UDim2.fromOffset(T, L) else UDim2.fromOffset(L, T),
		Parent = parent,
	})
	-- Pfeil-Raum: u = entlang (Spitze bei u ~ 0), v = quer. Umrechnung in Bildschirm-Koordinaten.
	local function map(u: number, v: number): Vector2
		if isDown then
			return Vector2.new(v, L - u)
		end
		return Vector2.new(u, v)
	end
	local headC = 30 * scale -- Mitte der Raute
	local layers = {
		{ Color = Color3.new(0, 0, 0), Transparency = 0.6, Grow = 3, Off = Vector2.new(0, 5) },
		{ Color = C.Ink, Transparency = 0, Grow = 3, Off = Vector2.zero },
		{ Color = fill, Transparency = 0, Grow = 0, Off = Vector2.zero },
	}
	for z, l in layers do
		local g = l.Grow
		-- Schaft
		local shaftLen = L - headC - 6 * scale
		local sc = map(headC - 2 + shaftLen / 2, T / 2)
		local shaftSize = Vector2.new(shaftLen + 2 + g * 2, 18 * scale + g * 2)
		local shaft = Make("Frame", {
			Name = "Shaft",
			BackgroundColor3 = l.Color,
			BackgroundTransparency = l.Transparency,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(sc.X + l.Off.X, sc.Y + l.Off.Y),
			Size = if isDown then UDim2.fromOffset(shaftSize.Y, shaftSize.X) else UDim2.fromOffset(shaftSize.X, shaftSize.Y),
			ZIndex = z,
			Parent = root,
		})
		UI.Corner(shaft, math.floor(5 * scale) + g)
		-- Spitze: Raute, deren hintere Haelfte von einem Clip-Rahmen abgeschnitten wird
		local clipLen = headC + g
		local clipOrigin = map(0, -8 * scale)
		local clipEnd = map(clipLen, T + 8 * scale)
		local minX, minY = math.min(clipOrigin.X, clipEnd.X), math.min(clipOrigin.Y, clipEnd.Y)
		local maxX, maxY = math.max(clipOrigin.X, clipEnd.X), math.max(clipOrigin.Y, clipEnd.Y)
		local clip = Make("Frame", {
			Name = "HeadClip",
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(minX + l.Off.X, minY + l.Off.Y),
			Size = UDim2.fromOffset(maxX - minX, maxY - minY),
			ZIndex = z,
			Parent = root,
		})
		local hc = map(headC, T / 2)
		local side = 30 * scale + g * 2
		local head = Make("Frame", {
			Name = "Head",
			BackgroundColor3 = l.Color,
			BackgroundTransparency = l.Transparency,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(hc.X - minX, hc.Y - minY),
			Size = UDim2.fromOffset(side, side),
			Rotation = 45,
			ZIndex = z,
			Parent = clip,
		})
		UI.Corner(head, math.floor(5 * scale) + g)
	end
	return root
end

-- Tasten-Kappen ------------------------------------------------------------------------

local function keyCap(parent: Instance, text: string, order: number)
	local w = math.max(34, 16 + #text * 10)
	local cap = Make("Frame", {
		Name = "Key",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, 34),
		LayoutOrder = order,
		Parent = parent,
	})
	local lip = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(146, 154, 178),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 1, -4),
		Parent = cap,
	})
	UI.Corner(lip, 8)
	UI.Stroke(lip, C.Ink, 2, 0)
	local face = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(240, 242, 248),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -4),
		ZIndex = 2,
		Parent = cap,
	})
	UI.Corner(face, 8)
	UI.Stroke(face, C.Ink, 2, 0)
	UI.Text({
		Text = text,
		Font = F.Heading,
		TextSize = if #text > 2 then 14 else 17,
		TextColor3 = C.Ink,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = face,
	})
end

local function setKeys(keys: { string }?)
	for _, c in keysRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not keys then
		return
	end
	for i, k in keys do
		if string.sub(k, 1, 1) == "|" then
			UI.Text({
				Name = "Caption",
				Text = string.upper(string.sub(k, 2)),
				Font = F.Heading,
				TextSize = 14,
				TextColor3 = C.Muted,
				TextWrapped = false,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 30),
				LayoutOrder = i,
				Parent = keysRow,
			})
		else
			keyCap(keysRow, k, i)
		end
	end
end

-- Fortschritts-Punkte (ein Punkt pro Schritt)
local function buildPips(total: number)
	for _, p in pips do
		p:Destroy()
	end
	table.clear(pips)
	for i = 1, total do
		local pip = Make("Frame", {
			Name = "Pip",
			BackgroundColor3 = C.PanelDark,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(16, 10),
			LayoutOrder = i,
			Parent = pipsFrame,
		})
		UI.Round(pip)
		UI.Stroke(pip, C.Ink, 2, 0)
		table.insert(pips, pip)
	end
end

local function setPips(current: number)
	for i, p in pips do
		local color = if i < current then C.Green elseif i == current then C.Gold else C.PanelDark
		UI.Tween(p, 0.2, { BackgroundColor3 = color, Size = UDim2.fromOffset(if i == current then 26 else 16, 10) })
	end
end

-- Leitpfad zu den Trainingspuppen ----------------------------------------------------------

type Marker = { Left: Part, Right: Part, D: number, Along: number, Active: boolean }

local guide = {
	Folder = nil :: Folder?,
	Markers = {} :: { Marker },
	Disc = nil :: Part?,
	Sign = nil :: Part?,
	DistLabel = nil :: TextLabel?,
	Bob = nil :: Frame?,
	Route = nil :: { Vector3 }?,
	RouteFrom = nil :: Vector3?,
	Target = nil :: Vector3?,
	Gen = 0,
	Arrived = false,
	Conn = nil :: RBXScriptConnection?,
}

local MAX_MARKERS = 26
local SPACING = 4
local CHEVRON = 1.4 -- Groesse der Pfeil-Markierungen

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true

-- Boden unter einem Punkt (Terrain + Map, nur feste Teile, damit Blaetter ignoriert werden)
local function groundRay(pos: Vector3, up: number, down: number): RaycastResult?
	local list: { Instance } = { workspace.Terrain }
	local map = workspace:FindFirstChild("Map")
	if map then
		table.insert(list, map)
	end
	rayParams.FilterDescendantsInstances = list
	return workspace:Raycast(pos + Vector3.new(0, up, 0), Vector3.new(0, -(up + down), 0), rayParams)
end

local function trainingTarget(): Vector3
	local map = workspace:FindFirstChild("Map")
	local area = if map then map:FindFirstChild("TrainingArea", true) else nil
	local pos: Vector3 = Config.World.LobbyCenter
	if area and area:IsA("BasePart") then
		local part = area :: BasePart
		pos = part.Position - Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	end
	local hit = groundRay(pos, 4, 14)
	return if hit then hit.Position else pos
end

local function rootPart(): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r :: BasePart
	end
	return nil
end

local function guidePart(props: { [string]: any }): Part
	local p = Make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = GUIDE_COLOR,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	})
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function hideMarker(m: Marker)
	m.Active = false
	m.Left.Transparency = 1
	m.Right.Transparency = 1
end

local function placeMarker(m: Marker, pos: Vector3, dir: Vector3, normal: Vector3)
	local n = if normal.Y > 0.5 then normal else Vector3.yAxis
	local flat = dir - n * dir:Dot(n)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.zAxis
		end
	end
	local p = pos + n * 0.14
	local base = CFrame.lookAt(p, p + flat.Unit, n)
	local s = CHEVRON
	m.Left.CFrame = base * CFrame.new(-0.42 * s, 0, -0.12 * s) * CFrame.Angles(0, math.rad(-45), 0)
	m.Right.CFrame = base * CFrame.new(0.42 * s, 0, -0.12 * s) * CFrame.Angles(0, math.rad(45), 0)
	m.Active = true
end

-- Punkte entlang einer Linie im Abstand d vom ENDE (bleiben stehen, waehrend man laeuft)
local function pointAtDistanceFromEnd(poly: { Vector3 }, cum: { number }, total: number, d: number): (Vector3, Vector3)
	local along = total - d
	for i = 2, #poly do
		if cum[i] >= along then
			local segLen = cum[i] - cum[i - 1]
			local a = if segLen > 0 then (along - cum[i - 1]) / segLen else 0
			local dir = poly[i] - poly[i - 1]
			return poly[i - 1]:Lerp(poly[i], a), dir
		end
	end
	local n = #poly
	return poly[n], if n > 1 then poly[n] - poly[n - 1] else Vector3.zAxis
end

local function refreshGuide()
	local target = guide.Target
	local root = rootPart()
	if not target or not root then
		for _, m in guide.Markers do
			hideMarker(m)
		end
		return
	end
	local feet = root.Position - Vector3.new(0, 3, 0)
	local flatDist = Vector3.new(target.X - feet.X, 0, target.Z - feet.Z).Magnitude
	guide.Arrived = flatDist < 10
	local distLabel = guide.DistLabel
	if distLabel then
		distLabel.Text = if guide.Arrived then "HIT THEM!" else tostring(math.floor(flatDist + 0.5)) .. "m"
	end
	if guide.Arrived then
		for _, m in guide.Markers do
			hideMarker(m)
		end
		return
	end

	-- Linie: Spieler -> (Pathfinding-Route ab dem naechsten Punkt) -> Ziel
	local poly: { Vector3 } = { feet }
	local route = guide.Route
	if route and #route > 0 then
		local best, bestD = 1, math.huge
		for i, p in route do
			local d = (p - feet).Magnitude
			if d < bestD then
				best, bestD = i, d
			end
		end
		if bestD < 14 then
			for i = best + 1, #route do
				table.insert(poly, route[i])
			end
		end
	end
	if (poly[#poly] - target).Magnitude > 1 then
		table.insert(poly, target)
	end
	local cum: { number } = { 0 }
	for i = 2, #poly do
		cum[i] = cum[i - 1] + (poly[i] - poly[i - 1]).Magnitude
	end
	local total = cum[#poly]

	-- Markierungen ab 5 Studs vor dem Ziel rueckwaerts, nur die naechsten MAX_MARKERS zum Spieler
	local endTrim = 5
	local count = math.floor((total - endTrim - 3) / SPACING) + 1
	local first = math.max(0, count - MAX_MARKERS)
	local used = 0
	for k = first, count - 1 do
		used += 1
		local m = guide.Markers[used]
		if not m then
			break
		end
		local d = endTrim + k * SPACING
		local pos, dir = pointAtDistanceFromEnd(poly, cum, total, d)
		-- erst knapp ueber dem Punkt suchen (keine Daecher), sonst von weiter oben (Huegel)
		local hit = groundRay(pos, 4, 10) or groundRay(pos, 26, 8)
		placeMarker(m, if hit then hit.Position else pos, dir, if hit then hit.Normal else Vector3.yAxis)
		m.D = d
		m.Along = total - d
	end
	for i = used + 1, #guide.Markers do
		hideMarker(guide.Markers[i])
	end
end

-- Route per Pathfinding (im Hintergrund, faellt auf die gerade Linie zurueck)
local function routeLoop(gen: number)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
	})
	while guide.Gen == gen do
		local root = rootPart()
		local target = guide.Target
		if root and target and not guide.Arrived then
			local from = guide.RouteFrom
			if not guide.Route or not from or (root.Position - from).Magnitude > 6 then
				local start = root.Position
				local ok = pcall(function()
					path:ComputeAsync(start, target)
				end)
				if guide.Gen ~= gen then
					break
				end
				if ok and path.Status == Enum.PathStatus.Success then
					local pts = {}
					for _, w in path:GetWaypoints() do
						table.insert(pts, w.Position)
					end
					guide.Route = pts
				else
					guide.Route = nil
				end
				guide.RouteFrom = start
			end
		end
		task.wait(0.8)
	end
	pcall(function()
		path:Destroy()
	end)
end

local function buildSign(parent: Instance, at: Vector3): (Part, TextLabel, Frame)
	local anchor = guidePart({
		Name = "SignAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(at + Vector3.new(0, 7.5, 0)),
		Parent = parent,
	})
	local bb = Make("BillboardGui", {
		Name = "Sign",
		Size = UDim2.fromOffset(150, 130),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 500,
		ResetOnSpawn = false,
		Parent = anchor,
	})
	local bob = Make("Frame", { Name = "Bob", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = bb })
	local plate = UI.Panel({
		Name = "Plate",
		Color = C.Panel,
		Radius = 10,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(132, 52),
		Parent = bob,
	})
	UI.Text({
		Text = "DUMMIES",
		Font = F.Heading,
		TextSize = 20,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 22),
		Stroke = 2,
		Parent = plate,
	})
	local dist = UI.Text({
		Text = "",
		Font = F.Heading,
		TextSize = 16,
		TextColor3 = C.Gold,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 20),
		Stroke = 2,
		Parent = plate,
	})
	local arrow = drawArrow(bob, "Down", 0.7, C.Gold)
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Position = UDim2.new(0.5, 0, 0, 60)
	return anchor, dist, bob
end

local function setGuide(on: boolean)
	guide.Gen += 1
	local conn = guide.Conn
	if conn then
		conn:Disconnect()
		guide.Conn = nil
	end
	local folder = guide.Folder
	if folder then
		folder:Destroy()
	end
	guide.Folder = nil
	guide.Markers = {}
	guide.Disc = nil
	guide.Sign = nil
	guide.DistLabel = nil
	guide.Bob = nil
	guide.Route = nil
	guide.RouteFrom = nil
	guide.Arrived = false
	if not on then
		return
	end

	local gen = guide.Gen
	local target = trainingTarget()
	guide.Target = target
	local newFolder = Make("Folder", { Name = "TutorialGuide", Parent = workspace })
	guide.Folder = newFolder

	-- Pfeil-Markierungen (Pool)
	for _ = 1, MAX_MARKERS do
		local size = Vector3.new(0.34 * CHEVRON, 0.12, 1.25 * CHEVRON)
		table.insert(guide.Markers, {
			Left = guidePart({ Name = "Chevron", Size = size, Transparency = 1, Parent = newFolder }),
			Right = guidePart({ Name = "Chevron", Size = size, Transparency = 1, Parent = newFolder }),
			D = 0,
			Along = 0,
			Active = false,
		})
	end

	-- weicher, pulsierender Bodenkreis am Ziel
	local hit = groundRay(target, 4, 10)
	local normal = if hit and hit.Normal.Y > 0.5 then hit.Normal else Vector3.yAxis
	local discCF = CFrame.lookAt(target + normal * 0.08, target + normal * 0.08 + Vector3.zAxis, normal)
		* CFrame.Angles(0, 0, math.rad(90))
	guide.Disc = guidePart({
		Name = "TargetDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 8, 8),
		CFrame = discCF,
		Transparency = 0.75,
		Parent = newFolder,
	})
	local sign, dist, bob = buildSign(newFolder, target)
	guide.Sign = sign
	guide.DistLabel = dist
	guide.Bob = bob

	refreshGuide()
	task.spawn(routeLoop, gen)
	task.spawn(function()
		while guide.Gen == gen do
			refreshGuide()
			task.wait(0.25)
		end
	end)

	-- Animation: Welle laeuft Richtung Ziel, Kreis pulsiert, Schild schwebt
	guide.Conn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, m in guide.Markers do
			if m.Active then
				local wave = 0.5 + 0.5 * math.sin(t * 5 + m.D * 0.5)
				local tr = 0.1 + 0.55 * (1 - wave)
				-- direkt am Spieler sanft ausblenden
				if m.Along < 7 then
					tr += (1 - m.Along / 7) * 0.6
				end
				tr = math.min(tr, 1)
				m.Left.Transparency = tr
				m.Right.Transparency = tr
			end
		end
		local disc = guide.Disc
		if disc then
			local p = 0.5 + 0.5 * math.sin(t * 3)
			local d = 7 + p * 1.6
			disc.Size = Vector3.new(0.12, d, d)
			disc.Transparency = 0.62 + 0.22 * p
		end
		local b = guide.Bob
		if b then
			b.Position = UDim2.fromOffset(0, math.sin(t * 4) * 6)
		end
	end)
end

-- Karte ------------------------------------------------------------------------------------

local function layoutCard(step: Step, animate: boolean)
	local textW = CARD_W - PAD * 2
	local textH = math.ceil(measureText(step.Text, TEXT_SIZE, F.Body, textW).Y) + 2
	local hasFooter = step.Keys ~= nil or step.Count ~= nil or step.Button ~= nil
	textLabel.Size = UDim2.fromOffset(textW, textH)
	local footerY = 86 + textH + 14
	local height = if hasFooter then footerY + 48 + 18 else 86 + textH + 20
	keysRow.Position = UDim2.fromOffset(PAD, footerY)
	keysRow.Visible = step.Keys ~= nil
	progress.Frame.Position = UDim2.new(1, -PAD, 0, footerY + 24)
	nextButton.Position = UDim2.new(1, -PAD, 0, footerY)
	local size = UDim2.fromOffset(CARD_W, height)
	if animate then
		UI.Tween(card, 0.25, { Size = size })
		UI.Tween(cardShadow, 0.25, { Size = size })
	else
		card.Size = size
		cardShadow.Size = size
	end
end

local function showCard(index: number, total: number, step: Step)
	stepLabel.Text = "STEP " .. index .. "/" .. total
	titleLabel.Text = step.Title
	textLabel.Text = step.Text
	setKeys(step.Keys)
	setPips(index)
	progress.Frame.Visible = step.Count ~= nil
	if step.Count then
		progress.Set(0, true)
		progress.Label.Text = "0 / " .. step.Count
	end
	nextButton.Visible = step.Button ~= nil
	if step.Button then
		UI.SetButtonText(nextButton, step.Button)
	end
	currentHighlight = step.Highlight
	layoutCard(step, index > 1)
	-- kleiner Hereinfall-Effekt (Karte, Schatten und Stempel bewegen sich zusammen)
	cardSlot.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET - 14)
	UI.Tween(cardSlot, 0.35, { Position = UDim2.new(0.5, 0, 0, TOP_OFFSET) }, Enum.EasingStyle.Back)
	UI.Pop(cardSlot, 0.92, 0.3)
	UI.Sound("Tutorial")
end

-- Stempel "NICE!" + etwas Konfetti, wenn ein Schritt geschafft ist
local function completeFlash()
	stamp.Text = PRAISE[math.random(1, #PRAISE)]
	stamp.Visible = true
	stamp.TextTransparency = 0
	local st = stamp:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	stamp.Rotation = -18
	UI.Pop(stamp, 1.8, 0.3)
	UI.Tween(stamp, 0.3, { Rotation = -8 }, Enum.EasingStyle.Back)
	UI.Sound("Coins", 1.3)
	UI.Burst(holder, UDim2.fromOffset(CARD_W - 90, TOP_OFFSET + 30), { C.Gold, C.Green, WHITE }, 18, 200)
	task.delay(0.55, function()
		UI.Tween(stamp, 0.2, { TextTransparency = 1 })
		if st then
			UI.Tween(st, 0.2, { Transparency = 1 })
		end
	end)
end

-- Sichtbarkeit: versteckt bei verstecktem HUD (Kiste, Cutscene ...) und offenen Fenstern
local function updateVisibility()
	local windowOpen = UI.AnyWindowOpen()
	gui.Enabled = running and not hudHidden
	holder.Visible = not windowOpen
end

-- Warten auf die Aktion eines Schritts ---------------------------------------------------------

local function waitFor(step: Step, myRun: number): boolean
	local function alive(): boolean
		return running and runId == myRun
	end
	if step.Button then
		local pressed = false
		local conn = nextButton.Activated:Connect(function()
			pressed = true
		end)
		while alive() and not pressed do
			task.wait()
		end
		conn:Disconnect()
		return alive()
	end
	if step.Wait == "Move" then
		local start: Vector3? = nil
		while alive() do
			local r = rootPart()
			if r then
				local s = start
				if not s then
					start = r.Position
				elseif (r.Position - s).Magnitude > 12 then
					break
				end
			end
			task.wait(0.1)
		end
		return alive()
	end
	local needed = step.Count or 1
	local count = 0
	local conn = State.TutorialEvent:Connect(function(name)
		if name ~= step.Wait or count >= needed then
			return
		end
		count += 1
		if step.Count then
			progress.Set(count / needed)
			progress.Label.Text = count .. " / " .. needed
			UI.Sound("Hover", 1 + count * 0.15)
		end
	end)
	while alive() and count < needed do
		task.wait()
	end
	conn:Disconnect()
	return alive()
end

local function finish(completed: boolean)
	if not running then
		return
	end
	running = false
	runId += 1
	currentHighlight = nil
	setGuide(false)
	gui.Enabled = false
	State.TutorialActive = false
	State.SetBusy("Tutorial", false)
	pcall(function()
		Net.Event("TutorialDone"):FireServer()
	end)
	if completed then
		HUD.Announce({ Text = "YOU'RE READY!", Sub = "Win rounds, open crates, collect them all.", Style = "Victory", Duration = 3 })
	end
	Tutorial.Finished:Fire()
end

-- Oeffentliche API ---------------------------------------------------------------------------

function Tutorial.Begin()
	if running then
		return
	end
	running = true
	runId += 1
	local myRun = runId
	State.TutorialActive = true
	State.SetBusy("Tutorial", true)
	skipArmedUntil = 0
	skipButton.Text = "Skip tutorial"
	hudHidden = State.IsHUDHidden()
	updateVisibility()

	-- Schritte, die schon jetzt uebersprungen werden (z.B. keine Gratis-Kiste), nicht mitzaehlen
	local active: { Step } = {}
	for _, step in STEPS do
		if not (step.Skip and step.Skip()) then
			table.insert(active, step)
		end
	end
	buildPips(#active)

	task.spawn(function()
		for i, step in active do
			if not running or runId ~= myRun then
				return
			end
			if step.Skip and step.Skip() then
				continue
			end
			showCard(i, #active, step)
			setGuide(step.Guide == true)
			if not waitFor(step, myRun) then
				return
			end
			setGuide(false)
			currentHighlight = nil
			completeFlash()
			task.wait(0.7)
		end
		if running and runId == myRun then
			finish(true)
		end
	end)
end

function Tutorial.IsRunning(): boolean
	return running
end

function Tutorial.Init()
	gui = UI.Screen("NovaTutorial", 25)
	gui.Enabled = false

	-- Haelter oben in der Mitte (skaliert mit dem Bildschirm)
	holder = Make("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(CARD_W, TOP_OFFSET + 260),
		Parent = gui,
	})
	UI.Scaled(holder)
	cardSlot = Make("Frame", {
		Name = "CardSlot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP_OFFSET),
		Size = UDim2.fromOffset(CARD_W, 240),
		Parent = holder,
	})
	cardShadow = Make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.fromOffset(CARD_W, 200),
		Parent = cardSlot,
	})
	UI.Corner(cardShadow, 16)
	card = UI.Panel({
		Name = "Card",
		Radius = 16,
		Size = UDim2.fromOffset(CARD_W, 200),
		Parent = cardSlot,
	})

	-- obere Zeile: Schritt-Schild, Punkte, Ueberspringen
	stepPill = UI.Panel({
		Name = "StepPill",
		Color = C.Gold,
		Radius = 12,
		Position = UDim2.fromOffset(PAD, 16),
		Size = UDim2.fromOffset(92, 26),
		Parent = card,
	})
	local pillStroke = stepPill:FindFirstChildOfClass("UIStroke")
	if pillStroke then
		pillStroke.Thickness = 2.5
	end
	stepLabel = UI.Text({
		Name = "Step",
		Text = "STEP 1/9",
		Font = F.Heading,
		TextSize = 15,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Stroke = 2,
		StrokeColor = Theme.Darken(C.GoldDark, 0.45),
		Parent = stepPill,
	})
	pipsFrame = Make("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD + 92 + 14, 16),
		Size = UDim2.fromOffset(260, 26),
		Parent = card,
	})
	UI.List(pipsFrame, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	skipButton = Make("TextButton", {
		Name = "Skip",
		Text = "Skip tutorial",
		Font = F.Heading,
		TextSize = 14,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 16),
		Size = UDim2.fromOffset(150, 26),
		Parent = card,
	})
	skipButton.MouseEnter:Connect(function()
		skipButton.TextColor3 = C.Text
	end)
	skipButton.MouseLeave:Connect(function()
		skipButton.TextColor3 = if os.clock() < skipArmedUntil then C.Red else C.Muted
	end)
	-- zweimal klicken zum Ueberspringen (verhindert versehentliches Abbrechen)
	skipButton.Activated:Connect(function()
		if not running then
			return
		end
		if os.clock() < skipArmedUntil then
			UI.Sound("Close")
			finish(false)
			return
		end
		skipArmedUntil = os.clock() + 3
		skipButton.Text = "Click again to skip"
		skipButton.TextColor3 = C.Red
		UI.Sound("Click")
		task.delay(3.05, function()
			if os.clock() >= skipArmedUntil then
				skipButton.Text = "Skip tutorial"
				skipButton.TextColor3 = C.Muted
			end
		end)
	end)

	titleLabel = UI.Text({
		Name = "Title",
		Text = "",
		Font = F.Heading,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(PAD, 48),
		Size = UDim2.fromOffset(CARD_W - PAD * 2, 34),
		Stroke = 2.5,
		Parent = card,
	})
	textLabel = UI.Text({
		Name = "Body",
		Text = "",
		Font = F.Body,
		TextSize = TEXT_SIZE,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = false,
		Position = UDim2.fromOffset(PAD, 86),
		Size = UDim2.fromOffset(CARD_W - PAD * 2, 40),
		Parent = card,
	})

	-- Fusszeile: Tasten links, Balken oder Knopf rechts
	keysRow = Make("Frame", {
		Name = "Keys",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD, 140),
		Size = UDim2.fromOffset(320, 48),
		Parent = card,
	})
	UI.List(keysRow, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	progress = UI.ProgressBar({
		Size = UDim2.fromOffset(200, 26),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PAD, 0, 164),
		Color = C.Green,
		Text = "",
		Parent = card,
	})
	progress.Frame.Visible = false
	nextButton = UI.Button({
		Name = "Next",
		Text = "NEXT",
		Style = "Green",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 140),
		Size = UDim2.fromOffset(176, 48),
		TextSize = 20,
		Parent = card,
	})
	nextButton.Visible = false

	-- Stempel fuer geschaffte Schritte
	stamp = UI.Text({
		Name = "Stamp",
		Text = "NICE!",
		Font = F.Display,
		TextSize = 44,
		TextColor3 = C.Green,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -96, 0, 34),
		Size = UDim2.fromOffset(220, 56),
		Rotation = -8,
		Visible = false,
		ZIndex = 5,
		Stroke = 4,
		Parent = cardSlot,
	})

	-- Hervorhebung von HUD-Knoepfen: Rahmen + huepfender Pfeil (absolute Pixel, eigene Skalierung)
	ring = Make("Frame", {
		Name = "HighlightRing",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 9,
		Parent = gui,
	})
	UI.Corner(ring, 18)
	ringInk = UI.Stroke(ring, C.Ink, 8, 0)
	local ringInner = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = ring,
	})
	UI.Corner(ringInner, 18)
	ringStroke = UI.Stroke(ringInner, C.Gold, 4, 0)

	pointer = Make("Frame", {
		Name = "Pointer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(80, 50),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	UI.Scaled(pointer)
	drawArrow(pointer, "Left", 1, C.Gold)

	State.HUDVisibilityChanged:Connect(function(hidden: boolean)
		hudHidden = hidden
		if running then
			updateVisibility()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not running then
			return
		end
		holder.Visible = not UI.AnyWindowOpen()
		local name = currentHighlight
		local target = if name then HUD.MenuButtons[name] else nil
		local show = target ~= nil and target.Visible and holder.Visible
		pointer.Visible = show
		ring.Visible = show
		if not show or not target then
			return
		end
		local t = os.clock()
		local pos = target.AbsolutePosition
		local size = target.AbsoluteSize
		local pulse = 0.5 + 0.5 * math.sin(t * 6)
		local grow = 10 + pulse * 4
		ring.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2)
		ring.Size = UDim2.fromOffset(size.X + grow, size.Y + grow)
		ringStroke.Transparency = 0.15 * pulse
		ringInk.Transparency = 0.2 * pulse
		local bounce = math.abs(math.sin(t * 4.5)) * 12
		pointer.Position = UDim2.fromOffset(pos.X + size.X + 14 + bounce, pos.Y + size.Y / 2)
	end)
end

function Tutorial.Start() end

return Tutorial
