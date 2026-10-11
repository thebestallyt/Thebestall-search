-- Prozedurale Posen (ohne Animations-Assets): dreht Schulter/Huefte/Taille ueber Motor6D.C0.
-- Funktioniert mit R15 und R6. Rotationen sind im Raum des Oberkoerpers angegeben:
-- X = rechts, Y = oben, -Z = vorne.  CFrame.Angles(math.rad(90),0,0) hebt einen Arm nach vorne.

local TweenService = game:GetService("TweenService")

local Poser = {}

local originals: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local JOINTS = {
	RightShoulder = { { "RightUpperArm", "RightShoulder" }, { "Torso", "Right Shoulder" } },
	LeftShoulder = { { "LeftUpperArm", "LeftShoulder" }, { "Torso", "Left Shoulder" } },
	RightHip = { { "RightUpperLeg", "RightHip" }, { "Torso", "Right Hip" } },
	LeftHip = { { "LeftUpperLeg", "LeftHip" }, { "Torso", "Left Hip" } },
	Waist = { { "UpperTorso", "Waist" } },
	Neck = { { "Head", "Neck" }, { "Torso", "Neck" } },
}

local function getJoint(character: Model, name: string): Motor6D?
	local options = JOINTS[name]
	if not options then
		return nil
	end
	for _, opt in options do
		local part = character:FindFirstChild(opt[1])
		local joint = part and part:FindFirstChild(opt[2])
		if joint and joint:IsA("Motor6D") then
			return joint
		end
	end
	return nil
end

export type Pose = { [string]: CFrame }

-- Wendet eine Pose an (weich ueber "time" Sekunden)
function Poser.Apply(character: Model?, pose: Pose, time: number?, style: Enum.EasingStyle?)
	if not character then
		return
	end
	local info = TweenInfo.new(time or 0.12, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for name, rot in pose do
		local joint = getJoint(character, name)
		if joint then
			local orig = originals[joint]
			if not orig then
				orig = joint.C0
				originals[joint] = orig
			end
			local target = CFrame.new(orig.Position) * rot * orig.Rotation
			TweenService:Create(joint, info, { C0 = target }):Play()
		end
	end
end

function Poser.Reset(character: Model?, time: number?)
	if not character then
		return
	end
	local info = TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for name in JOINTS do
		local joint = getJoint(character, name)
		if joint and originals[joint] then
			TweenService:Create(joint, info, { C0 = originals[joint] }):Play()
		end
	end
end

-- Spielt eine Folge von Posen ab: { {Pose, Dauer bis zur naechsten}, ... } und setzt danach zurueck
function Poser.Sequence(character: Model?, frames: { { any } }, resetTime: number?)
	if not character then
		return
	end
	local token = (tokens[character] or 0) + 1
	tokens[character] = token
	task.spawn(function()
		for _, frame in frames do
			if tokens[character] ~= token then
				return
			end
			local pose, hold, blend = frame[1], frame[2] or 0.1, frame[3]
			Poser.Apply(character, pose, blend or math.min(hold, 0.12))
			task.wait(hold)
		end
		if tokens[character] == token then
			Poser.Reset(character, resetTime or 0.25)
		end
	end)
end

local rad = math.rad
local A = CFrame.Angles

-- Fertige Posen
Poser.Poses = {
	PunchRight = { RightShoulder = A(rad(95), 0, rad(-8)), LeftShoulder = A(rad(20), 0, rad(-10)), Waist = A(0, rad(28), 0) },
	PunchLeft = { LeftShoulder = A(rad(95), 0, rad(8)), RightShoulder = A(rad(20), 0, rad(10)), Waist = A(0, rad(-28), 0) },
	Uppercut = { RightShoulder = A(rad(150), 0, rad(-10)), Waist = A(rad(-8), rad(20), 0) },
	HeavyWindup = { RightShoulder = A(rad(-40), 0, rad(30)), LeftShoulder = A(rad(40), 0, rad(-20)), Waist = A(0, rad(-35), 0) },
	HeavyStrike = { RightShoulder = A(rad(100), 0, rad(-20)), LeftShoulder = A(rad(-20), 0, rad(-15)), Waist = A(rad(-8), rad(40), 0) },
	CastForward = { RightShoulder = A(rad(90), 0, 0), LeftShoulder = A(rad(10), 0, rad(-10)) },
	PushBoth = { RightShoulder = A(rad(90), 0, rad(-12)), LeftShoulder = A(rad(90), 0, rad(12)) },
	ArmsUp = { RightShoulder = A(rad(170), 0, rad(-15)), LeftShoulder = A(rad(170), 0, rad(15)), Neck = A(rad(15), 0, 0) },
	RightUp = { RightShoulder = A(rad(175), 0, 0), Neck = A(rad(18), 0, 0) },
	ArmsOut = { RightShoulder = A(0, 0, rad(80)), LeftShoulder = A(0, 0, rad(-80)), Neck = A(rad(10), 0, 0) },
	Slam = { RightShoulder = A(rad(40), 0, rad(-10)), LeftShoulder = A(rad(40), 0, rad(10)), Waist = A(rad(-25), 0, 0) },
	Block = { RightShoulder = A(rad(100), 0, rad(-40)), LeftShoulder = A(rad(100), 0, rad(40)) },
	Slash = { RightShoulder = A(rad(60), 0, rad(70)), Waist = A(0, rad(-30), 0) },
	Sheath = { RightShoulder = A(rad(-15), 0, rad(15)), LeftShoulder = A(rad(10), 0, rad(-15)), Neck = A(rad(-10), 0, 0) },
	Victory = { RightShoulder = A(rad(170), 0, rad(-10)), LeftShoulder = A(rad(10), 0, rad(-20)), Neck = A(rad(12), 0, 0) },
}

return Poser
