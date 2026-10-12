-- AFK-Erkennung. Regel: kurz untaetig sein ist voellig okay – erst nach langer Zeit gilt man als AFK.
-- * merkt sich die letzte echte Eingabe (Tastatur, Maustasten/-bewegung/-rad, Touch, Gamepad-Tasten
--   und -Sticks) und ob sich die Figur bewegt (Humanoid.MoveDirection)
-- * wer laenger als Config.Round.AfkTimeout (Standard 300 s) nichts macht, wird EINMAL als AFK
--   gemeldet (Net "SetAFK" true) und sieht ein freundliches Banner; der Server teleportiert
--   AFK-Spieler nicht mehr in Runden
-- * bei der naechsten Eingabe: EINMAL "SetAFK" false, Banner weg, kurzer "Welcome back!"-Toast
-- * unterhalb der Zeitgrenze passiert NICHTS – untaetige Spieler werden weiter teleportiert
-- * Zeit im Startmenue zaehlt nicht (das Menue macht ohnehin "beschaeftigt"); schliesst das Menue,
--   startet die Uhr neu
-- * Nebenbei: Abgleich mit den Server-Attributen "AFK" und "Busy", damit ein haengender Status
--   (verlorene/ueberschriebene Meldung) einen Spieler nicht dauerhaft von Runden ausschliesst

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local AFK = {}

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Sekunden ohne Eingabe, bis man als AFK gilt (Fallback 300, falls die Config den Wert nicht hat)
local TIMEOUT: number = tonumber((Config.Round :: any).AfkTimeout) or 300
local CHECK_INTERVAL = 0.5
local STICK_DEADZONE = 0.25
local RESYNC_DELAY = 3 -- so lange nach dem letzten Senden keine Korrektur an den Server schicken
local BUSY_RESYNC_AFTER = 2.5 -- "Busy" ohne lokalen Grund so lange -> Status neu senden
local BUSY_RESYNC_EVERY = 10

-- Banner (Design-Pixel, skaliert ueber UI.Scaled)
local BANNER_W = 500
local BANNER_H = 92
local BELOW_ROUND = 116 -- oben Mitte, unter der Rundenanzeige (wie Tutorial.TOP_OFFSET)

-- Zustand
local lastInput = os.clock()
local isAfk = false
local menuWasOpen = true
local lastSent = -math.huge
local remote: RemoteEvent? = nil
local busyMismatchSince: number? = nil
local lastBusyResync = -math.huge
local lastMousePos: Vector2? = nil

-- UI
local gui: ScreenGui
local banner: Frame
local inner: Frame
local badgeScale: UIScale
local badgePulse: Tween? = nil
local bannerVisible = false
local bannerShown = false -- war das Banner in dieser AFK-Phase zu sehen? (dann "Welcome back!")
local hideToken = 0

-- Senden ------------------------------------------------------------------------------------

local function send(afk: boolean)
	lastSent = os.clock()
	local r = remote
	if not r then
		return
	end
	local ok, err = pcall(function()
		r:FireServer(afk)
	end)
	if not ok then
		warn("[AFK] SetAFK failed: " .. tostring(err))
	end
end

-- Banner ------------------------------------------------------------------------------------

local function place()
	if TOUCH_ONLY then
		-- Handy: oben Mitte liegen die Benachrichtigungen -> etwas ueber der Bildschirmmitte
		banner.AnchorPoint = Vector2.new(0.5, 0.5)
		banner.Position = UDim2.fromScale(0.5, 0.42)
	else
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Position = UDim2.new(0.5, 0, 0, math.floor(8 + BELOW_ROUND * UI.Scale))
	end
end

local function buildBanner()
	gui = UI.Screen("NovaAFK", 9) -- ueber dem HUD, unter Menue/Fenstern/Tutorial
	banner = Make("Frame", {
		Name = "AFKBanner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(BANNER_W, BANNER_H + 6),
		Visible = false,
		Parent = gui,
	})
	UI.Scaled(banner)
	-- innerer Rahmen: UI.Pop legt hier seine eigene UIScale an (kollidiert nicht mit AutoScale)
	inner = Make("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = banner,
	})
	local shadow = Make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, BANNER_H),
		Parent = inner,
	})
	UI.Corner(shadow, 16)
	local plate = UI.Panel({
		Name = "Plate",
		Radius = 16,
		Size = UDim2.new(1, 0, 0, BANNER_H),
		Parent = inner,
	})

	-- runder Abzeichen-Knopf mit "Zz" (sanftes Pulsieren, solange das Banner zu sehen ist)
	local badge = Make("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Purple,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(58, 58),
		ZIndex = 2,
		Parent = plate,
	})
	UI.Round(badge)
	UI.Shade(badge)
	UI.Stroke(badge, C.Ink, 3, 0)
	badgeScale = Make("UIScale", { Parent = badge })
	UI.Text({
		Name = "Zz",
		Text = "Zz",
		Font = F.Heading,
		TextSize = 26,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Stroke = 2,
		StrokeColor = Theme.Darken(C.PurpleDark, 0.45),
		Parent = badge,
	})

	UI.Text({
		Name = "Title",
		Text = "YOU ARE AFK",
		Font = F.Heading,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(90, 10),
		Size = UDim2.new(1, -106, 0, 30),
		Stroke = 2.5,
		Parent = plate,
	})
	UI.Text({
		Name = "Body",
		Text = "You won't be put into rounds. "
			.. (if TOUCH_ONLY then "Move or tap the screen to come back." else "Move or press any key to come back."),
		Font = F.Body,
		TextSize = 15,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = false,
		Position = UDim2.fromOffset(90, 42),
		Size = UDim2.new(1, -106, 0, 40),
		Parent = plate,
	})
	place()
end

local function setBanner(show: boolean)
	if show == bannerVisible then
		return
	end
	bannerVisible = show
	hideToken += 1
	local pulse = badgePulse
	if pulse then
		pulse:Cancel()
		badgePulse = nil
	end
	if show then
		bannerShown = true
		place()
		banner.Visible = true
		UI.Pop(inner, 0.6, 0.35)
		badgeScale.Scale = 1
		local tw = TweenService:Create(
			badgeScale,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.1 }
		)
		tw:Play()
		badgePulse = tw
	else
		-- kurz zusammenschrumpfen, dann ausblenden
		local token = hideToken
		local pop = inner:FindFirstChild("PopScale")
		if pop and pop:IsA("UIScale") then
			UI.Tween(pop, 0.15, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.delay(0.15, function()
			if hideToken == token then
				banner.Visible = false
			end
		end)
	end
end

-- Banner nur zeigen, wenn es Sinn ergibt: nicht waehrend des Tutorials (dort ist man ohnehin
-- pausiert und die Tutorial-Karte sitzt an derselben Stelle) und nicht bei verstecktem HUD
-- (Kisten-Oeffnung, Cutscene, Startmenue).
local function updateBanner()
	setBanner(isAfk and not State.TutorialActive and not State.IsHUDHidden())
end

-- AFK-Zustand -------------------------------------------------------------------------------

local function goAfk()
	if isAfk then
		return
	end
	isAfk = true
	bannerShown = false
	send(true)
	updateBanner()
end

-- notifyServer = false, wenn der Server uns schon selbst zurueckgeholt hat
local function comeBack(notifyServer: boolean)
	if not isAfk then
		return
	end
	isAfk = false
	if notifyServer then
		send(false)
	end
	local wasShown = bannerShown
	bannerShown = false
	updateBanner()
	if wasShown then
		HUD.Toast({ Text = "Welcome back! You'll be put into rounds again.", Color = C.Green, Icon = "!", Duration = 3.5 })
	end
end

-- Jede echte Eingabe: Uhr zuruecksetzen, und wer AFK war, ist wieder da
local function onActivity()
	lastInput = os.clock()
	if isAfk then
		comeBack(true)
	end
end

local function isGamepad(t: Enum.UserInputType): boolean
	return string.sub(t.Name, 1, 7) == "Gamepad"
end

local function step()
	local now = os.clock()
	-- Startmenue: zaehlt nicht als AFK-Zeit; beim Schliessen startet die Uhr neu
	if State.MenuOpen then
		menuWasOpen = true
		lastInput = now
	elseif menuWasOpen then
		menuWasOpen = false
		lastInput = now
	end

	-- Figur bewegt sich (Taste/Stick gehalten -> kein neues InputBegan, trotzdem aktiv)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MoveDirection.Magnitude > 0.05 then
		onActivity()
	end

	if not isAfk and now - lastInput >= TIMEOUT then
		goAfk()
	end

	-- Abgleich: Server haelt uns noch fuer AFK, obwohl wir aktiv sind (z.B. verlorene Meldung)
	if not isAfk and player:GetAttribute("AFK") == true and now - lastSent > RESYNC_DELAY then
		send(false)
	end

	-- Selbstheilung "Busy": Der Server haelt uns fuer beschaeftigt, obwohl lokal kein bekannter
	-- Grund (Menue, Kiste, Tutorial) aktiv ist – z.B. weil der Status beim Serverstart
	-- ueberschrieben wurde. State meldet nur Aenderungen, also wuerde das nie mehr korrigiert und
	-- man kaeme nie wieder in eine Runde. Kurzes Setzen + Loeschen eines eigenen Grundes schickt
	-- den echten Gesamtstatus erneut; gibt es doch noch einen anderen Grund, aendert sich nichts.
	local localBusy = State.MenuOpen or State.InCrateOpening or State.TutorialActive
	if player:GetAttribute("Busy") == true and not localBusy then
		local since = busyMismatchSince or now
		busyMismatchSince = since
		if now - since >= BUSY_RESYNC_AFTER and now - lastBusyResync >= BUSY_RESYNC_EVERY then
			lastBusyResync = now
			State.SetBusy("Resync", true)
			State.SetBusy("Resync", false)
		end
	else
		busyMismatchSince = nil
	end

	updateBanner()
end

-- Oeffentliche API --------------------------------------------------------------------------

function AFK.IsAfk(): boolean
	return isAfk
end

function AFK.Init()
	buildBanner()

	UserInputService.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if
			t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.MouseButton3
			or t == Enum.UserInputType.Touch
			or isGamepad(t)
		then
			onActivity()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement then
			-- nur echte Bewegung zaehlen: bei gesperrter Maus (Shift-Lock/Ego-Sicht) kann das Event
			-- ohne Bewegung kommen (Delta 0, gleiche Position) -> sonst wuerde man nie AFK
			local p = input.Position
			local pos2 = Vector2.new(p.X, p.Y)
			local moved = input.Delta.Magnitude > 0.01 or (lastMousePos ~= nil and (pos2 - lastMousePos).Magnitude > 0.5)
			lastMousePos = pos2
			if moved then
				onActivity()
			end
		elseif t == Enum.UserInputType.MouseWheel or t == Enum.UserInputType.Touch then
			onActivity()
		elseif isGamepad(t) then
			local k = input.KeyCode
			if k == Enum.KeyCode.Thumbstick1 or k == Enum.KeyCode.Thumbstick2 then
				local p = input.Position
				if Vector2.new(p.X, p.Y).Magnitude > STICK_DEADZONE then
					onActivity()
				end
			end
		end
	end)
end

function AFK.Start()
	-- Remote im Hintergrund holen (Net.Event wartet bis zu 10 s, falls es fehlt)
	task.spawn(function()
		local ok, result = pcall(Net.Event, "SetAFK")
		if ok then
			remote = result
		else
			warn("[AFK] SetAFK remote missing – AFK state is only shown locally: " .. tostring(result))
		end
	end)

	-- Der Server kann uns selbst zurueckholen (z.B. bei einer Kampfeingabe)
	player:GetAttributeChangedSignal("AFK"):Connect(function()
		if player:GetAttribute("AFK") ~= true and isAfk then
			lastInput = os.clock()
			comeBack(false)
		end
	end)
	State.HUDVisibilityChanged:Connect(updateBanner)
	UI.ScaleChanged:Connect(place)

	task.spawn(function()
		local warned = false
		while true do
			task.wait(CHECK_INTERVAL)
			local ok, err = pcall(step)
			if not ok and not warned then
				warned = true
				warn("[AFK] " .. tostring(err))
			end
		end
	end)
end

return AFK
