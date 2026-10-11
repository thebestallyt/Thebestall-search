-- Kino-Kamera fuer Faehigkeiten mit Cutscene: Letterbox-Balken, Titelkarte, Kamerafahrten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Controllers = (VFX.Parent :: Instance):WaitForChild("Controllers")
local State = require(Controllers:WaitForChild("State"))

local Cutscene = {}

local player = Players.LocalPlayer
local active = false
local token = 0
local shotFn: ((number) -> CFrame)? = nil
local shotStart = 0
local savedFov = 70

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
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 0),
	Position = UDim2.fromScale(0, 0),
	Parent = gui,
})
local bottomBar = Make("Frame", {
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.fromScale(1, 0),
	Position = UDim2.fromScale(0, 1),
	Parent = gui,
})

local function camera(): Camera
	return workspace.CurrentCamera :: Camera
end

local function step()
	if not active or not shotFn then
		return
	end
	local fn = shotFn :: (number) -> CFrame
	local ok, cf = pcall(fn, os.clock() - shotStart)
	if ok and typeof(cf) == "CFrame" then
		camera().CFrame = cf
	end
end

local function titleCard(opts: { [string]: any })
	local holder = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(-0.6, 0, 0.84, 0),
		Size = UDim2.fromScale(0.6, 0.2),
		Parent = gui,
	})
	local tag = Make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.24),
		Text = opts.Subtitle or "",
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = opts.Color or Color3.new(1, 1, 1),
		TextTransparency = 0,
		Parent = holder,
	})
	local title = Make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.24),
		Size = UDim2.fromScale(1, 0.6),
		Text = opts.Title or "",
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = holder,
	})
	Make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 0.2, Parent = title })
	local gradient = Make("UIGradient", {
		Color = opts.Gradient or ColorSequence.new(Color3.new(1, 1, 1), opts.Color or Color3.new(1, 1, 1)),
		Rotation = 0,
		Parent = title,
	})
	local line = Make("Frame", {
		BackgroundColor3 = opts.Color or Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.9),
		Size = UDim2.fromScale(0, 0.04),
		Parent = holder,
	})
	Make("UIGradient", { Transparency = Effects.NSeq(0, 1), Parent = line })

	Effects.Tween(holder, 0.45, { Position = UDim2.new(0.05, 0, 0.84, 0) }, Enum.EasingStyle.Quint)
	Effects.Tween(line, 0.7, { Size = UDim2.fromScale(0.9, 0.04) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.15)
	-- Schimmer, der ueber den Titel laeuft
	Effects.Animate(1.6, function(a)
		gradient.Offset = Vector2.new(-1 + a * 2, 0)
	end)

	-- Glitch-Effekt (Black Hole)
	if opts.Glitch then
		local ghosts = {}
		for _, c in { Color3.fromRGB(255, 40, 120), Color3.fromRGB(40, 220, 255) } do
			local g = title:Clone()
			for _, ch in g:GetChildren() do
				ch:Destroy()
			end
			g.TextColor3 = c
			g.TextTransparency = 0.35
			g.ZIndex = 0
			g.Parent = holder
			table.insert(ghosts, g)
		end
		task.spawn(function()
			for _ = 1, 14 do
				for _, g in ghosts do
					g.Position = UDim2.new(0, math.random(-10, 10), 0.24, math.random(-4, 4))
					g.Visible = math.random() > 0.3
				end
				task.wait(0.05)
			end
			for _, g in ghosts do
				g:Destroy()
			end
		end)
	end

	task.delay(opts.Hold or 1.9, function()
		Effects.Tween(holder, 0.35, { Position = UDim2.new(-0.6, 0, 0.84, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Effects.Tween(tag, 0.3, { TextTransparency = 1 })
		task.delay(0.4, function()
			holder:Destroy()
		end)
	end)
end

function Cutscene.IsActive(): boolean
	return active
end

-- Ist diese Cutscene (Token) noch die aktuelle?
function Cutscene.IsCurrent(myToken: number?): boolean
	return active and myToken ~= nil and myToken == token
end

-- Startet die Kino-Ansicht. Gibt ein Token zurueck, mit dem nur DIESE Cutscene beendet werden kann.
function Cutscene.Begin(opts: { [string]: any }): number
	token += 1
	active = true
	State.SetCutscene(true)
	local cam = camera()
	savedFov = 70
	cam.CameraType = Enum.CameraType.Scriptable
	shotFn = nil
	RunService:UnbindFromRenderStep("NovaCutscene")
	RunService:BindToRenderStep("NovaCutscene", Enum.RenderPriority.Camera.Value + 1, step)
	Effects.Tween(topBar, 0.35, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quint)
	Effects.Tween(bottomBar, 0.35, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quint)
	if opts.Title then
		titleCard(opts)
	end
	return token
end

-- Setzt die aktuelle Kameraeinstellung als Funktion der Zeit
function Cutscene.Shot(fn: (number) -> CFrame, fov: number?, fovTime: number?)
	shotFn = fn
	shotStart = os.clock()
	if fov then
		Effects.Tween(camera(), fovTime or 0.01, { FieldOfView = fov })
	end
end

-- Lineare Kamerafahrt von A nach B
function Cutscene.Move(fromCF: CFrame, toCF: CFrame, duration: number, ease: string?, fov: number?)
	Cutscene.Shot(function(t)
		local a = math.clamp(t / duration, 0, 1)
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
	Cutscene.Shot(function(t)
		local a = Effects.Ease(math.clamp(t / duration, 0, 1), "InOut")
		local c = center()
		local r = radius0 + (radius1 - radius0) * a
		local h = height0 + (height1 - height0) * a
		local ang = angle0 + (angle1 - angle0) * a
		local pos = c + Vector3.new(math.cos(ang) * r, h, math.sin(ang) * r)
		return CFrame.lookAt(pos, c + (lookOffset or Vector3.zero))
	end)
end

function Cutscene.FOV(fov: number, time: number)
	Effects.Tween(camera(), time, { FieldOfView = fov }, Enum.EasingStyle.Quad)
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
	RunService:UnbindFromRenderStep("NovaCutscene")
	-- kurzer Schwarzblitz verdeckt den Kameraschnitt
	Effects.ScreenFlash(Color3.new(0, 0, 0), 0.35, 0)
	local cam = camera()
	cam.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	cam.FieldOfView = savedFov
	Effects.Tween(topBar, 0.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint)
	Effects.Tween(bottomBar, 0.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint)
	State.SetCutscene(false)
end

-- Sicherheitsnetz: nach dem Tod immer beenden
player.CharacterAdded:Connect(function()
	if active then
		Cutscene.End()
	end
end)

return Cutscene
