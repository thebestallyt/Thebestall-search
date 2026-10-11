-- UI-Bausteine: Panels, animierte Buttons, Fenster, Zaehler, UI-Partikel.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Signal = require(Shared:WaitForChild("Signal"))

local UIFolder = script.Parent :: Instance
local Theme = require(UIFolder:WaitForChild("Theme"))
local Client = UIFolder.Parent :: Instance
local VFX = Client:WaitForChild("VFX")
local Effects = require(VFX:WaitForChild("Effects"))

local UI = {}
UI.Make = Make
UI.Theme = Theme

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C = Theme.Colors

-- Allgemein ----------------------------------------------------------------

function UI.Tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
	t:Play()
	return t
end

function UI.Sound(name: string, pitch: number?)
	Effects.Sound(name, nil, { Pitch = pitch or 1, Variance = 0.02 })
end

function UI.Format(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return formatted
end

function UI.Screen(name: string, displayOrder: number): ScreenGui
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return Make("ScreenGui", {
		Name = name,
		DisplayOrder = displayOrder,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
end

-- Globale Skalierung je nach Bildschirmgroesse
UI.ScaleChanged = Signal.new()
UI.Scale = 1
local scaled: { UIScale } = {}

local function computeScale(): number
	local cam = workspace.CurrentCamera
	if not cam then
		return 1
	end
	local v = cam.ViewportSize
	return math.clamp(math.min(v.X / 1400, v.Y / 820), 0.5, 1.2)
end

local function updateScale()
	UI.Scale = computeScale()
	for i = #scaled, 1, -1 do
		local s = scaled[i]
		if s.Parent then
			s.Scale = UI.Scale
		else
			table.remove(scaled, i)
		end
	end
	UI.ScaleChanged:Fire(UI.Scale)
end

function UI.Scaled(obj: GuiObject): UIScale
	local s = Make("UIScale", { Name = "AutoScale", Scale = UI.Scale, Parent = obj })
	table.insert(scaled, s)
	return s
end

task.defer(function()
	updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end)

-- Dekoration ------------------------------------------------------------------

function UI.Corner(parent: Instance, radius: number?): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function UI.Round(parent: Instance): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function UI.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Make("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UI.Gradient(parent: Instance, color: ColorSequence?, rotation: number?, transparency: NumberSequence?): UIGradient
	return Make("UIGradient", {
		Color = color or ColorSequence.new(Color3.new(1, 1, 1)),
		Rotation = rotation or 0,
		Transparency = transparency or NumberSequence.new(0),
		Parent = parent,
	})
end

function UI.Padding(parent: Instance, px: number)
	return Make("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UI.List(parent: Instance, horizontal: boolean?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Make("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UI.Text(props: { [string]: any }): TextLabel
	local label = Make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Text,
		TextSize = 18,
		Text = "",
		TextWrapped = true,
		RichText = true,
	})
	for k, v in props do
		if k ~= "Parent" then
			(label :: any)[k] = v
		end
	end
	label.Parent = props.Parent
	return label
end

-- Panel mit Verlauf und leuchtendem Rand
function UI.Panel(props: { [string]: any }): Frame
	local frame = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "StrokeColor" and k ~= "Radius" and k ~= "NoStroke" then
			(frame :: any)[k] = v
		end
	end
	UI.Gradient(frame, Theme.Gradients.Panel, 90)
	UI.Corner(frame, props.Radius or 16)
	if not props.NoStroke then
		local stroke = UI.Stroke(frame, Color3.new(1, 1, 1), 2, 0.25)
		local g = UI.Gradient(stroke, props.StrokeColor or Theme.Gradients.Main, 45)
		UI.Animate(g, 40, "Rotate")
	end
	frame.Parent = props.Parent
	return frame
end

-- Animierte Verlaeufe (ein gemeinsamer Loop) ------------------------------------

type GradAnim = { g: UIGradient, speed: number, mode: string }
local gradAnims: { GradAnim } = {}

function UI.Animate(g: UIGradient, speed: number, mode: string?)
	table.insert(gradAnims, { g = g, speed = speed, mode = mode or "Offset" })
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for i = #gradAnims, 1, -1 do
		local a = gradAnims[i]
		if not a.g.Parent then
			table.remove(gradAnims, i)
			continue
		end
		if a.mode == "Rotate" then
			a.g.Rotation = (a.g.Rotation + a.speed * dt) % 360
		else
			local x = ((t * a.speed) % 2) - 1
			a.g.Offset = Vector2.new(x, 0)
		end
	end
end)

-- Buttons -----------------------------------------------------------------------

local STYLES = {
	Primary = { Gradient = Theme.Gradients.Main, Text = Color3.new(1, 1, 1), Shine = true },
	Gold = { Gradient = Theme.Gradients.Gold, Text = Color3.fromRGB(60, 30, 0), Shine = true },
	Robux = { Gradient = Theme.Gradients.Robux, Text = Color3.new(1, 1, 1), Shine = true },
	Danger = { Gradient = Theme.Gradients.Danger, Text = Color3.new(1, 1, 1), Shine = false },
	Success = { Gradient = Theme.Gradients.Success, Text = Color3.fromRGB(10, 40, 20), Shine = true },
	Secondary = { Gradient = ColorSequence.new(C.PanelLighter, C.PanelLight), Text = C.Text, Shine = false },
	Ghost = { Gradient = ColorSequence.new(C.Panel), Text = C.SubText, Shine = false },
}

function UI.Shine(button: GuiObject, interval: number?)
	local shine = Make("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(0.25, 0, 2, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.3, 0.5),
		Rotation = 20,
		BackgroundTransparency = 0.75,
		ZIndex = button.ZIndex + 2,
		Parent = button,
	})
	UI.Gradient(shine, nil, 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}))
	task.spawn(function()
		while shine.Parent do
			shine.Position = UDim2.fromScale(-0.3, 0.5)
			UI.Tween(shine, 0.7, { Position = UDim2.fromScale(1.3, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			task.wait((interval or 2.6) + math.random() * 0.8)
		end
	end)
end

export type ButtonProps = {
	Text: string?,
	Style: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Parent: Instance?,
	OnClick: (() -> ())?,
	LayoutOrder: number?,
	Font: Enum.Font?,
	ZIndex: number?,
	Name: string?,
}

function UI.Button(props: ButtonProps): TextButton
	local style = STYLES[props.Style or "Primary"] or STYLES.Primary
	local button = Make("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Size = props.Size or UDim2.fromOffset(200, 54),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
		ZIndex = props.ZIndex or 1,
	})
	local grad = UI.Gradient(button, style.Gradient, 0)
	UI.Corner(button, 12)
	local stroke = UI.Stroke(button, Color3.new(1, 1, 1), 2, 0.65)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local label = UI.Text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = props.Text or "",
		TextColor3 = style.Text,
		TextSize = props.TextSize or 22,
		Font = props.Font or Theme.Fonts.Title,
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})
	local _ = grad
	local scale = Make("UIScale", { Parent = button })
	if style.Shine then
		UI.Shine(button)
	end
	button.MouseEnter:Connect(function()
		UI.Tween(scale, 0.15, { Scale = 1.06 })
		UI.Tween(stroke, 0.15, { Transparency = 0.1 })
		UI.Sound("Hover")
	end)
	button.MouseLeave:Connect(function()
		UI.Tween(scale, 0.2, { Scale = 1 })
		UI.Tween(stroke, 0.2, { Transparency = 0.65 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.Tween(scale, 0.08, { Scale = 0.93 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.Tween(scale, 0.15, { Scale = 1.04 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		UI.Sound("Click")
		if props.OnClick then
			task.spawn(props.OnClick)
		end
	end)
	button.Parent = props.Parent
	local __ = label
	return button
end

function UI.SetButtonText(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function UI.SetButtonStyle(button: GuiObject, styleName: string)
	local style = STYLES[styleName]
	local g = button:FindFirstChildOfClass("UIGradient")
	local label = button:FindFirstChild("Label")
	if style and g then
		g.Color = style.Gradient
	end
	if style and label and label:IsA("TextLabel") then
		label.TextColor3 = style.Text
	end
end

-- Animationen -------------------------------------------------------------------

function UI.Pop(obj: GuiObject, from: number?, time: number?)
	local s = obj:FindFirstChild("PopScale") :: UIScale?
	if not s then
		s = Make("UIScale", { Name = "PopScale", Parent = obj })
	end
	local sc = s :: UIScale
	sc.Scale = from or 0.5
	UI.Tween(sc, time or 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UI.Shake(obj: GuiObject)
	local origin = obj.Position
	task.spawn(function()
		for i = 1, 6 do
			local dx = (if i % 2 == 0 then 1 else -1) * (8 - i)
			obj.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		obj.Position = origin
	end)
	UI.Sound("Error")
end

-- Zahl hochzaehlen
function UI.CountTo(label: TextLabel, from: number, to: number, time: number, fmt: ((number) -> string)?)
	local f = fmt or UI.Format
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / time, 0, 1)
		local e = 1 - (1 - a) ^ 3
		label.Text = f(from + (to - from) * e)
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

-- Schwebende Partikel im Hintergrund (Sterne / Funken)
function UI.Ambient(container: Instance, opts: { [string]: any }?): () -> ()
	local o = opts or {}
	local running = true
	local colors: { Color3 } = o.Colors or { C.Cyan, C.Magenta, C.Purple, Color3.new(1, 1, 1) }
	task.spawn(function()
		while running and container.Parent do
			local size = math.random(o.MinSize or 2, o.MaxSize or 6)
			local dot = Make("Frame", {
				BackgroundColor3 = colors[math.random(1, #colors)],
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(size, size),
				Position = UDim2.fromScale(math.random(), 1.05),
				BackgroundTransparency = 0.2,
				ZIndex = o.ZIndex or 1,
				Parent = container,
			})
			UI.Round(dot)
			local life = math.random(40, 90) / 10
			UI.Tween(dot, life, {
				Position = UDim2.fromScale(dot.Position.X.Scale + (math.random() - 0.5) * 0.15, -0.05),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Linear)
			task.delay(life, function()
				dot:Destroy()
			end)
			task.wait(o.Interval or 0.12)
		end
	end)
	return function()
		running = false
	end
end

-- Konfetti-Explosion von einem Punkt aus
function UI.Burst(container: Instance, at: UDim2, colors: { Color3 }, count: number, spread: number?)
	for _ = 1, count do
		local s = math.random(5, 12)
		local piece = Make("Frame", {
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(s, s * (if math.random() > 0.5 then 2 else 1)),
			Position = at,
			Rotation = math.random(0, 360),
			ZIndex = 20,
			Parent = container,
		})
		local ang = math.random() * math.pi * 2
		local dist = math.random(80, spread or 380)
		local life = math.random(6, 12) / 10
		UI.Tween(piece, life, {
			Position = at + UDim2.fromOffset(math.cos(ang) * dist, math.sin(ang) * dist + 60),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quart)
		task.delay(life, function()
			piece:Destroy()
		end)
	end
end

-- Weichzeichner hinter Fenstern ---------------------------------------------------

local blur = Lighting:FindFirstChild("NovaUIBlur") or Make("BlurEffect", { Name = "NovaUIBlur", Size = 0, Parent = Lighting })
local blurUsers = 0

function UI.SetBlur(on: boolean)
	blurUsers = math.max(0, blurUsers + (if on then 1 else -1))
	UI.Tween(blur, 0.3, { Size = if blurUsers > 0 then 14 else 0 })
end

-- Fenster -------------------------------------------------------------------------

export type Window = {
	Root: Frame,
	Panel: Frame,
	Content: Frame,
	IsOpen: boolean,
	Opened: any,
	Closed: any,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
}

local windowsGui: ScreenGui? = nil
local openWindows: { Window } = {}

function UI.Window(opts: { Title: string, Icon: string?, Size: Vector2, Name: string }): Window
	if not windowsGui then
		windowsGui = UI.Screen("NovaWindows", 20)
	end
	local gui = windowsGui :: ScreenGui
	local root = Make("Frame", {
		Name = opts.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local panel = UI.Panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(opts.Size.X, opts.Size.Y),
		Parent = root,
	})
	local autoScale = UI.Scaled(panel)
	local _ = autoScale
	local popScale = Make("UIScale", { Name = "PopScale", Parent = panel })

	-- Kopfzeile
	local header = Make("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = panel,
	})
	local title = UI.Text({
		Text = (if opts.Icon then opts.Icon .. "  " else "") .. opts.Title,
		Font = Theme.Fonts.Title,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Parent = header,
	})
	local tg = UI.Gradient(title, Theme.Gradients.Main, 0)
	UI.Animate(tg, 0.25, "Offset")
	local line = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 24, 1, -2),
		Size = UDim2.new(1, -48, 0, 2),
		Parent = header,
	})
	UI.Gradient(line, Theme.Gradients.Main, 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	}))
	local content = Make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 1, -66),
		Parent = panel,
	})

	local win = {
		Root = root,
		Panel = panel,
		Content = content,
		IsOpen = false,
		Opened = Signal.new(),
		Closed = Signal.new(),
	} :: any

	local closeBtn = UI.Button({
		Text = "✕",
		Style = "Danger",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -60, 0, 12),
		TextSize = 22,
		Parent = panel,
		OnClick = function()
			win:Close()
		end,
	})
	local __ = closeBtn

	function win.Open(self: Window)
		if self.IsOpen then
			return
		end
		for _, other in table.clone(openWindows) do
			other:Close()
		end
		self.IsOpen = true
		table.insert(openWindows, self)
		root.Visible = true
		root.BackgroundTransparency = 1
		UI.Tween(root, 0.25, { BackgroundTransparency = 0.45 })
		popScale.Scale = 0.75
		UI.Tween(popScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.SetBlur(true)
		UI.Sound("Open")
		self.Opened:Fire()
	end

	function win.Close(self: Window)
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		local i = table.find(openWindows, self)
		if i then
			table.remove(openWindows, i)
		end
		UI.Tween(root, 0.2, { BackgroundTransparency = 1 })
		UI.Tween(popScale, 0.2, { Scale = 0.8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UI.SetBlur(false)
		UI.Sound("Close")
		task.delay(0.2, function()
			if not self.IsOpen then
				root.Visible = false
			end
		end)
		self.Closed:Fire()
	end

	-- Klick auf den dunklen Hintergrund schliesst
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local ap, as = panel.AbsolutePosition, panel.AbsoluteSize
			if pos.X < ap.X or pos.X > ap.X + as.X or pos.Y < ap.Y or pos.Y > ap.Y + as.Y then
				win:Close()
			end
		end
	end)
	return win :: Window
end

function UI.CloseAllWindows()
	for _, w in table.clone(openWindows) do
		w:Close()
	end
end

function UI.AnyWindowOpen(): boolean
	return #openWindows > 0
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Escape or (input.KeyCode == Enum.KeyCode.ButtonB and not processed) then
		UI.CloseAllWindows()
	end
end)

-- Zentriertes Raster in einem ScrollingFrame
function UI.Scroll(parent: Instance, props: { [string]: any }): ScrollingFrame
	local sf = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Purple,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	for k, v in props do
		(sf :: any)[k] = v
	end
	sf.Parent = parent
	return sf
end

return UI
