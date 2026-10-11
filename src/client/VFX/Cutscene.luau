-- Kino-Kamera fuer Faehigkeiten mit Cutscene:
-- * Letterbox-Balken + Titelkarte im "Chunky Game UI"-Stil (siehe UI/Theme.luau)
-- * Kameraeinstellungen als Funktion der Zeit (Shot / Move / Orbit / Whip)
-- * Impact-Frames (2-3 Bilder Hochkontrast), Hit-Stop, Tiefenunschaerfe (Focus)
-- Die Kamera wird am Ende IMMER auf Custom + eigenen Humanoid zurueckgesetzt (auch bei Tod/Respawn).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Controllers = (VFX.Parent :: Instance):WaitForChild("Controllers")
local State = require(Controllers:WaitForChild("State"))
local UIFolder = (VFX.Parent :: Instance):WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))

local Cutscene = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = Theme.Colors.Ink
local F = Theme.Fonts

local BAR = 0.1 -- Hoehe der Letterbox-Balken (Anteil am Bildschirm)
local DEFAULT_FOV = 70 -- Standard-Sichtfeld des Spiels

local active = false
local token = 0
local shotFn: ((number) -> CFrame)? = nil
local shotStart = 0
local lastCF: CFrame? = nil
local freezeCF: CFrame? = nil
local freezeUntil = 0
local focusFn: (() -> Vector3)? = nil
local dof: DepthOfFieldEffect? = nil
local fovTween: Tween? = nil
local currentCard: Frame? = nil
local diedConn: RBXScriptConnection? = nil

local gui = Make("ScreenGui", {
	Name = "NovaCutscene",
	DisplayOrder = 40,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = true,
	Parent = player:WaitForChild("PlayerGui"),
})

local topBar = Make("Frame", {
	Name = "TopBar",
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 0),
	Position = UDim2.fromScale(0, 0),
	ZIndex = 5,
	Parent = gui,
})
local bottomBar = Make("Frame", {
	Name = "BottomBar",
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.fromScale(1, 0),
	Position = UDim2.fromScale(0, 1),
	ZIndex = 5,
	Parent = gui,
})

local function camera(): Camera
	return workspace.CurrentCamera :: Camera
end

-- Kamera-Logik -------------------------------------------------------------------

local function step()
	if not active then
		return
	end
	local cam = camera()
	local now = os.clock()
	-- Hit-Stop: Kamera kurz einfrieren (Wackeln laeuft trotzdem obendrauf)
	if freezeCF then
		if now < freezeUntil then
			cam.CFrame = freezeCF :: CFrame
			return
		end
		freezeCF = nil
	end
	local fn = shotFn
	if fn then
		local ok, cf = pcall(fn, now - shotStart)
		if ok and typeof(cf) == "CFrame" then
			cam.CFrame = cf
			lastCF = cf
		elseif lastCF then
			cam.CFrame = lastCF :: CFrame
		end
	end
	-- Tiefenunschaerfe folgt dem Motiv
	local d = dof
	local ff = focusFn
	if d and ff then
		local ok, p = pcall(ff)
		if ok and typeof(p) == "Vector3" then
			d.FocusDistance = math.clamp((cam.CFrame.Position - p).Magnitude, 0.5, 200)
		end
	end
end

local function setFov(fov: number, time: number?, style: Enum.EasingStyle?)
	if fovTween then
		(fovTween :: Tween):Cancel()
		fovTween = nil
	end
	local cam = camera()
	if not time or time <= 0.02 then
		cam.FieldOfView = fov
	else
		fovTween = Effects.Tween(cam, time, { FieldOfView = fov }, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

-- Kurzer Unschaerfe-Impuls (fuer Reissschwenks)
local function blurPulse(size: number, time: number)
	local blur = Make("BlurEffect", { Name = "NovaWhipBlur", Size = size, Parent = Lighting })
	Effects.Tween(blur, time, { Size = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Effects.Clean(blur, time + 0.05)
end

local function ensureDof(): DepthOfFieldEffect
	local existing = dof
	if existing and existing.Parent then
		return existing
	end
	local created = Make("DepthOfFieldEffect", {
		Name = "NovaCutsceneDOF",
		FarIntensity = 0,
		NearIntensity = 0,
		FocusDistance = 20,
		InFocusRadius = 10,
		Parent = Lighting,
	})
	dof = created
	return created
end

-- Titelkarte ---------------------------------------------------------------------

local function screenScale(): number
	local v = camera().ViewportSize
	return math.clamp(math.min(v.X / 1400, v.Y / 820), 0.5, 1.2)
end

local function measure(text: string, size: number, font: Enum.Font): Vector2
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(4000, 400))
	end)
	if ok and typeof(v) == "Vector2" then
		return v
	end
	return Vector2.new(#text * size * 0.62, size)
end

local function corner(parent: Instance, radius: number)
	Make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function outline(parent: Instance, thickness: number, transparency: number?): UIStroke
	return Make("UIStroke", {
		Color = INK,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function textOutline(label: Instance, thickness: number, transparency: number?): UIStroke
	return Make("UIStroke", {
		Color = INK,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
end

local function fadeLabel(label: TextLabel, to: number, time: number)
	Effects.Tween(label, time, { TextTransparency = to })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		Effects.Tween(stroke, time, { Transparency = to })
	end
end

-- Kurzes Ruetteln eines GUI-Elements (Aufprall)
local function jolt(obj: GuiObject, px: number, time: number)
	local base = obj.Position
	Effects.Animate(time, function(a)
		local k = (1 - a) * px
		obj.Position = base + UDim2.fromOffset(math.random(-100, 100) / 100 * k, math.random(-100, 100) / 100 * k * 0.6)
	end, function()
		obj.Position = base
	end)
end

local function removeCard(fast: boolean?)
	local card = currentCard
	currentCard = nil
	if not card or not card.Parent then
		return
	end
	local t = if fast then 0.18 else 0.3
	Effects.Tween(card, t, { Position = card.Position - UDim2.fromOffset(70, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in card:GetDescendants() do
		if d:IsA("TextLabel") then
			Effects.Tween(d, t, { TextTransparency = 1 })
		elseif d:IsA("Frame") then
			Effects.Tween(d, t, { BackgroundTransparency = 1 })
		elseif d:IsA("UIStroke") then
			Effects.Tween(d, t, { Transparency = 1 })
		end
	end
	Effects.Clean(card, t + 0.05)
end

-- Dezenter Glitch fuer den Titel (Black Hole): zwei versetzte Farbkopien zucken kurz
local function glitch(group: Frame, main: TextLabel, colorA: Color3, colorB: Color3, duration: number)
	local ghosts: { TextLabel } = {}
	for i, c in { colorA, colorB } do
		local g = Make("TextLabel", {
			Name = "Ghost" .. i,
			BackgroundTransparency = 1,
			Size = main.Size,
			Position = main.Position,
			Font = main.Font,
			Text = main.Text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = c,
			TextTransparency = 0.25,
			ZIndex = 0,
			Parent = group,
		})
		Make("UITextSizeConstraint", { MaxTextSize = 78, Parent = g })
		table.insert(ghosts, g)
	end
	local base = main.Position
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and main.Parent do
			for i, g in ghosts do
				local dir = if i == 1 then -1 else 1
				g.Position = base + UDim2.fromOffset(dir * math.random(3, 9), math.random(-3, 3))
				g.Visible = math.random() > 0.25
			end
			main.Position = base + UDim2.fromOffset(if math.random() > 0.7 then math.random(-4, 4) else 0, 0)
			task.wait(0.045)
		end
		main.Position = base
		for _, g in ghosts do
			g:Destroy()
		end
	end)
end

local function titleCard(opts: { [string]: any })
	removeCard(true)
	local color: Color3 = if typeof(opts.Color) == "Color3" then opts.Color else Theme.Colors.Gold
	local title = tostring(opts.Title or "")
	local subtitle = tostring(opts.Subtitle or "")

	local holder = Make("Frame", {
		Name = "TitleCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 48, 1 - BAR, -12),
		Size = UDim2.fromOffset(980, 150),
		ZIndex = 10,
		Parent = gui,
	})
	Make("UIScale", { Scale = screenScale(), Parent = holder })
	currentCard = holder

	-- Seltenheits-Plakette (3D mit dunkler Lippe, leicht schraeg)
	local plateW = math.ceil(measure(subtitle, 22, F.Heading).X) + 40
	local plate = Make("Frame", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-plateW - 160, 0),
		Size = UDim2.fromOffset(plateW, 46),
		Rotation = -2,
		Parent = holder,
	})
	local lip = Make("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Darken(color, 0.45),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromOffset(plateW, 38),
		ZIndex = 1,
		Parent = plate,
	})
	corner(lip, 9)
	outline(lip, 3)
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(plateW, 38),
		ZIndex = 2,
		Parent = plate,
	})
	corner(face, 9)
	outline(face, 3)
	Make("UIGradient", { Color = Theme.Gradients.Shade, Rotation = 90, Parent = face })
	local sub = Make("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = F.Heading,
		Text = subtitle,
		TextSize = 22,
		TextColor3 = WHITE,
		ZIndex = 3,
		Parent = face,
	})
	textOutline(sub, 2)

	-- Grosser Titel mit dunklem 3D-Schatten
	local group = Make("Frame", {
		Name = "TitleGroup",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(2, 100),
		Size = UDim2.fromOffset(980, 88),
		Parent = holder,
	})
	local slam = Make("UIScale", { Scale = 1.9, Parent = group })
	local function titleLabel(name: string, textColor: Color3, offset: Vector2, z: number): TextLabel
		local l = Make("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(offset.X, offset.Y),
			Size = UDim2.fromScale(1, 1),
			Font = F.Display,
			Text = title,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = textColor,
			TextTransparency = 1,
			ZIndex = z,
			Parent = group,
		})
		Make("UITextSizeConstraint", { MaxTextSize = 78, Parent = l })
		textOutline(l, 5, 1)
		return l
	end
	local shadow = titleLabel("Shadow", INK, Vector2.new(4, 7), 1)
	local main = titleLabel("Title", WHITE, Vector2.zero, 2)
	-- dezente Licht-von-oben-Schattierung, leicht in der Seltenheitsfarbe
	Make("UIGradient", { Color = ColorSequence.new(WHITE, Theme.Lighten(color, 0.72)), Rotation = 90, Parent = main })

	-- Animation: Plakette gleitet rein, Titel knallt drauf
	Effects.Tween(plate, 0.34, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.12, function()
		if not holder.Parent then
			return
		end
		Effects.Tween(slam, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		fadeLabel(shadow, 0, 0.1)
		fadeLabel(main, 0, 0.1)
		task.delay(0.17, function()
			if holder.Parent then
				jolt(group, 6, 0.18)
				Effects.Sound("HeavyPunch", nil, { Volume = 0.3, Pitch = 1.25 })
			end
		end)
		if opts.Glitch then
			local alt: Color3 = if typeof(opts.GlitchColor) == "Color3" then opts.GlitchColor else Color3.fromRGB(255, 150, 70)
			task.delay(0.2, function()
				if holder.Parent then
					glitch(group, main, color, alt, 0.4)
				end
			end)
			task.delay(1.1, function()
				if holder.Parent then
					glitch(group, main, color, alt, 0.16)
				end
			end)
		end
	end)

	local hold = if typeof(opts.Hold) == "number" then opts.Hold else 1.9
	task.delay(hold, function()
		if currentCard == holder then
			removeCard(false)
		end
	end)
end

-- Oeffentliche API ---------------------------------------------------------------

function Cutscene.IsActive(): boolean
	return active
end

-- Ist diese Cutscene (Token) noch die aktuelle?
function Cutscene.IsCurrent(myToken: number?): boolean
	return active and myToken ~= nil and myToken == token
end

-- Startet die Kino-Ansicht. Gibt ein Token zurueck, mit dem nur DIESE Cutscene beendet werden kann.
-- opts: Title, Subtitle, Color, Gradient (ignoriert, Kompatibilitaet), Glitch, GlitchColor, Hold, MaxDuration
function Cutscene.Begin(opts: { [string]: any }): number
	token += 1
	local myToken = token
	local cam = camera()
	active = true
	State.SetCutscene(true)
	cam.CameraType = Enum.CameraType.Scriptable
	-- bis zur ersten Einstellung haelt die Kamera still (verhindert, dass Wackeln sich aufsummiert)
	local startCF = cam.CFrame
	lastCF = startCF
	shotFn = function()
		return startCF
	end
	shotStart = os.clock()
	freezeCF = nil
	focusFn = nil
	RunService:UnbindFromRenderStep("NovaCutscene")
	RunService:BindToRenderStep("NovaCutscene", Enum.RenderPriority.Camera.Value + 1, step)
	ensureDof()
	Effects.Tween(topBar, 0.35, { Size = UDim2.fromScale(1, BAR) }, Enum.EasingStyle.Quint)
	Effects.Tween(bottomBar, 0.35, { Size = UDim2.fromScale(1, BAR) }, Enum.EasingStyle.Quint)
	if opts.Title then
		titleCard(opts)
	end

	-- Sicherheitsnetze: Tod des eigenen Charakters / maximale Laufzeit
	if diedConn then
		(diedConn :: RBXScriptConnection):Disconnect()
		diedConn = nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		diedConn = hum.Died:Connect(function()
			task.delay(0.35, function()
				Cutscene.End(myToken)
			end)
		end)
	end
	local maxDuration = if typeof(opts.MaxDuration) == "number" then opts.MaxDuration else 15
	task.delay(maxDuration, function()
		Cutscene.End(myToken)
	end)
	return myToken
end

-- Setzt die aktuelle Kameraeinstellung als Funktion der Zeit
function Cutscene.Shot(fn: (number) -> CFrame, fov: number?, fovTime: number?)
	shotFn = fn
	shotStart = os.clock()
	freezeCF = nil
	if fov then
		setFov(fov, fovTime)
	end
end

-- Kamerafahrt von A nach B
function Cutscene.Move(fromCF: CFrame, toCF: CFrame, duration: number, ease: string?, fov: number?)
	local d = math.max(duration, 0.01)
	Cutscene.Shot(function(t)
		local a = math.clamp(t / d, 0, 1)
		return fromCF:Lerp(toCF, Effects.Ease(a, ease or "InOut"))
	end, fov, 0.01)
end

-- Kamera kreist um einen (beweglichen) Punkt
function Cutscene.Orbit(
	center: () -> Vector3,
	radius0: number,
	radius1: number,
	height0: number,
	height1: number,
	angle0: number,
	angle1: number,
	duration: number,
	lookOffset: Vector3?
)
	local d = math.max(duration, 0.01)
	Cutscene.Shot(function(t)
		local a = Effects.Ease(math.clamp(t / d, 0, 1), "InOut")
		local c = center()
		local r = radius0 + (radius1 - radius0) * a
		local h = height0 + (height1 - height0) * a
		local ang = angle0 + (angle1 - angle0) * a
		local pos = c + Vector3.new(math.cos(ang) * r, h, math.sin(ang) * r)
		return CFrame.lookAt(pos, c + (lookOffset or Vector3.zero))
	end)
end

-- Reissschwenk: schneller, weicher Uebergang von der aktuellen Kamera in eine neue Einstellung (mit Unschaerfe)
function Cutscene.Whip(nextFn: (number) -> CFrame, duration: number, fov: number?, fovTime: number?)
	local from = lastCF or camera().CFrame
	local d = math.max(duration, 0.01)
	Cutscene.Shot(function(t)
		local target = nextFn(t)
		if t >= d then
			return target
		end
		local a = t / d
		local e = if a < 0.5 then 16 * a ^ 5 else 1 - ((-2 * a + 2) ^ 5) / 2
		return from:Lerp(target, e)
	end)
	if fov then
		setFov(fov, fovTime or d, Enum.EasingStyle.Quint)
	end
	blurPulse(14, d * 1.5)
end

function Cutscene.FOV(fov: number, time: number)
	if not active then
		return
	end
	setFov(fov, time)
end

-- Haelt die Kamera kurz an (Treffer-Gewicht). Die laufende Einstellung macht danach nahtlos weiter.
function Cutscene.HitStop(duration: number)
	if not active then
		return
	end
	freezeCF = lastCF or camera().CFrame
	freezeUntil = os.clock() + duration
	shotStart += duration
end

-- Tiefenunschaerfe: scharf auf target(), Hintergrund weich. target = nil schaltet sie ab.
function Cutscene.Focus(target: (() -> Vector3)?, farIntensity: number?, radius: number?)
	if not active then
		return
	end
	focusFn = target
	local d = ensureDof()
	if target then
		Effects.Tween(d, 0.35, { FarIntensity = farIntensity or 0.4, NearIntensity = 0, InFocusRadius = radius or 6 })
	else
		Effects.Tween(d, 0.35, { FarIntensity = 0, NearIntensity = 0 })
	end
end

-- Impact-Frame: 2-3 Bilder Hochkontrast in Schwarz-Weiss mit Silhouetten, dann invertiert.
-- opts: Characters = { Model }, Tint = Color3 (Farbe des zweiten Bildes), FrameTime = Sekunden pro Bild
function Cutscene.ImpactFrame(opts: { [string]: any }?)
	local o = opts or {}
	local frameTime: number = if typeof(o.FrameTime) == "number" then o.FrameTime else 0.05
	local tint: Color3 = if typeof(o.Tint) == "Color3" then o.Tint else WHITE
	local cc = Make("ColorCorrectionEffect", {
		Name = "NovaImpactFrame",
		Brightness = 0.32,
		Contrast = 1,
		Saturation = -1,
		TintColor = WHITE,
		Parent = Lighting,
	})
	local highlights: { Highlight } = {}
	if type(o.Characters) == "table" then
		for _, ch in o.Characters do
			if typeof(ch) == "Instance" and ch.Parent and #highlights < 8 then
				table.insert(
					highlights,
					Make("Highlight", {
						Name = "NovaImpactSilhouette",
						Adornee = ch,
						FillColor = BLACK,
						FillTransparency = 0,
						OutlineColor = BLACK,
						OutlineTransparency = 0,
						DepthMode = Enum.HighlightDepthMode.Occluded,
						Parent = Effects.Folder,
					})
				)
			end
		end
	end
	task.delay(frameTime, function()
		if cc.Parent then
			cc.Brightness = -0.3
			cc.TintColor = tint
		end
		for _, h in highlights do
			if h.Parent then
				h.FillColor = WHITE
				h.OutlineColor = WHITE
			end
		end
	end)
	task.delay(frameTime * 2, function()
		cc:Destroy()
		for _, h in highlights do
			h:Destroy()
		end
	end)
	Effects.Clean(cc, frameTime * 2 + 1)
	for _, h in highlights do
		Effects.Clean(h, frameTime * 2 + 1)
	end
end

function Cutscene.End(myToken: number?)
	if myToken and myToken ~= token then
		return
	end
	if not active then
		return
	end
	active = false
	shotFn = nil
	freezeCF = nil
	focusFn = nil
	lastCF = nil
	RunService:UnbindFromRenderStep("NovaCutscene")
	if diedConn then
		(diedConn :: RBXScriptConnection):Disconnect()
		diedConn = nil
	end
	if fovTween then
		(fovTween :: Tween):Cancel()
		fovTween = nil
	end
	-- kurzer Schwarzblitz verdeckt den Kameraschnitt
	Effects.ScreenFlash(BLACK, 0.35, 0)
	local cam = camera()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	-- Kamera hinter den Charakter setzen, damit die Standardkamera sauber uebernimmt
	if root and root:IsA("BasePart") then
		local rcf = (root :: BasePart).CFrame
		local look = Vector3.new(rcf.LookVector.X, 0, rcf.LookVector.Z)
		look = if look.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else look.Unit
		local focus = rcf.Position + Vector3.new(0, 1.5, 0)
		cam.CFrame = CFrame.lookAt(focus - look * 12 + Vector3.new(0, 3.5, 0), focus)
	end
	cam.CameraType = Enum.CameraType.Custom
	if hum then
		cam.CameraSubject = hum
	end
	cam.FieldOfView = DEFAULT_FOV
	local d = dof
	dof = nil
	if d then
		d:Destroy()
	end
	removeCard(true)
	Effects.Tween(topBar, 0.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint)
	Effects.Tween(bottomBar, 0.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint)
	State.SetCutscene(false)
end

-- Sicherheitsnetz: nach dem Respawn immer beenden
player.CharacterAdded:Connect(function()
	if active then
		Cutscene.End()
	end
end)

return Cutscene
