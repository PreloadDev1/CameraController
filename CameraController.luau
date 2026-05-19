-- | --=> <~> | [Variables] | <~> <=-- | --
--=-== | Loading | ==-=--
if not game.Players.LocalPlayer.Character then game.Players.LocalPlayer.CharacterAdded:Wait() end
while not game.Workspace.PersistentLoaded do task.wait() end

--=-== | Services | ==-=--
local UIS = game:GetService("UserInputService")
local RPS = game:GetService("ReplicatedStorage")
local RPF = game:GetService("ReplicatedFirst")
local SSS = game:GetService("ServerScriptService")
local MPS = game:GetService("MarketplaceService")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local SS = game:GetService("SocialService")
local WS = game:GetService("Workspace")

local StarterPlayer = game:GetService("StarterPlayer")
local Lighting = game:GetService("Lighting")
local Collection = game:GetService("CollectionService")
local Players = game:GetService("Players")

--=-== | TruWorks | ==-=--
local src = RPS:FindFirstChild("TruWorks")
local TruWorks = require(src:WaitForChild("Client"))
local _Modules = src:FindFirstChild("Data"):WaitForChild("Modules")
local _Services = src:WaitForChild("Services")

local Signal = require(src.Data.Modules.Lib.Signal)

--=-== | Client Context | ==-=--
local Player:Player = game.Players.LocalPlayer
local Character:Model = Player.Character or Player.CharacterAdded:Wait()
local Camera:Camera = game.Workspace.CurrentCamera
local Humanoid:Humanoid = Character:WaitForChild("Humanoid")
local Root:BasePart = Character:WaitForChild("HumanoidRootPart")
local Mouse:Mouse = Player:GetMouse()
local PlayerControls = require(Player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()

--=-== | Storage | ==-=--
local PlayerScripts = script.Parent.Parent
local Shared = RPS:WaitForChild("Shared")
local Packages = RPS:WaitForChild("Packages")

local ClientScripts = PlayerScripts.Client
local Controllers = PlayerScripts.Controllers

local Components = Shared:WaitForChild("Components")
local Utilities = Shared:WaitForChild("Utilities")
local Templates = Shared:WaitForChild("Templates")
local DataModules = Shared:WaitForChild("Data")

local PlayerUI:PlayerGui = Player:WaitForChild("PlayerGui")
local MainScreen:ScreenGui = PlayerUI:FindFirstChild("Main") or warn("[Controllers.CameraController]: No Mainscreen Found.")

local HUD:Folder = MainScreen:FindFirstChild("HUD") or warn("[Controllers.CameraController]: No HUD Folder Found.")
local Frames:Folder = MainScreen:FindFirstChild("Frames") or warn("[Controllers.CameraController]: No Frames Folder Found.")

--=-== | Modules | ==-=--
local Packet = require(Packages:WaitForChild("Packet"))
local Pulse = require(Packages:WaitForChild("Pulse"))
local SpringMotion = TruWorks.Processing.SpringMotion
local TruWorksBezier = TruWorks.Processing.Bezier

--=-== | Types | ==-=--

export type PointsInfo = {
	Positions:{PVInstance | Vector3 | CFrame | {CFrame}},
	Duration:number,
	EasingStyle:Enum.EasingStyle?,
	EasingDirection:Enum.EasingDirection?,
	StartAtCamera:boolean,
	StartAtCurrentCamera:boolean,
	EndAtCamera:boolean,
	EndAtCurrentCamera:boolean,
}

-- | --=> <~> | [Functions] | <~> <=-- | --
--=-== | Module | ==-=--

local Controller = {}
local CutsceneService = {}
local OffsetEffects = {}

Controller.Default = {}
Controller.Spring = {}
Controller.Bezier = {}
Controller.Bezier.Return = {}
Controller.Bezier.TweenTo = {}

--=-== | Constants | ==-=--

local DefaultFOV:number = Camera.FieldOfView
local DefaultCameraMaxZoom:number = StarterPlayer.CameraMaxZoomDistance
local DefaultCameraMinZoom:number = StarterPlayer.CameraMinZoomDistance
local DefaultCameraZoom:number = 12.5
local DefaultCameraOffset:CFrame = CFrame.Angles(math.rad(-15), 0, 0)

local MIN_Y:number = math.rad(-80)
local MAX_Y:number = math.rad(80)

--=-== | State | ==-=--

local CameraSpring:Part
local ActiveBezierCancel:(() -> ())?

local Cutscene:((DeltaTime:number) -> CFrame)?
local Follow:((DeltaTime:number, DesiredCFrame:CFrame) -> CFrame)?
local LookAt:((DeltaTime:number, DesiredCFrame:CFrame) -> CFrame)?
local CurrentCameraVelocity:CFrame = CFrame.new()

local CameraOffset:CFrame
local BasePositionOffset:Vector3 = Vector3.zero
local BaseRotationOffset:Vector3 = Vector3.zero

local PositionOffset:Vector3 = Vector3.zero
local RotationOffset:Vector3 = Vector3.zero
local DesiredCFrame:CFrame = CFrame.new()
local EndCFrame:CFrame = CFrame.new()

--=-== | Internal | ==-=--

local function GetCFrameFromData(Data:{CFrame} | CFrame | PVInstance | Vector3) : CFrame
	if typeof(Data) == "table" then
		return GetCFrameFromData(Data[1]) * GetCFrameFromData(Data[2])
	elseif typeof(Data) == "Instance" or typeof(Data) == "PVInstance" then
		return Data:IsA("Model") and Data:GetPivot() or Data.CFrame
	elseif typeof(Data) == "CFrame" then
		return Data
	else
		return CFrame.new(Data)
	end
end

local function GetBezierCFrame(Positions:{any}, Alpha:number) : CFrame
	if not Positions then return CFrame.new() end

	local Points = {}

	for Index = 1, math.huge do
		local Value = Positions[Index]
		if Value == nil then break end

		Points[#Points + 1] = Value
	end

	if #Points == 0 then
		for Key, Value in Positions do if type(Key) == "number" then Points[Key] = Value end end
		local Compact = {}

		for Index = 1, #Points do Compact[#Compact + 1] = Points[Index] end
		Points = Compact
	end

	if #Points == 0 then return CFrame.new() end

	local Frames = {}

	for Index = 1, #Points do
		local Success, Result = pcall(GetCFrameFromData, Points[Index])
		Frames[Index] = (Success and Result) or CFrame.new()
	end

	while #Frames > 1 do
		local NextList = {}
		for Index = 1, #Frames - 1 do NextList[Index] = Frames[Index]:Lerp(Frames[Index + 1], Alpha) end

		Frames = NextList
	end

	return Frames[1] or CFrame.new()
end

local function CalculateNewLookCFrameFromArg(SuppliedLookVector:Vector3, RotateInput:Vector2) : CFrame
	local CurrentPitchAngle = math.asin(SuppliedLookVector.Y)
	local YTheta = math.clamp(RotateInput.Y, -MAX_Y + CurrentPitchAngle, -MIN_Y + CurrentPitchAngle)

	local ConstrainedInput = Vector2.new(RotateInput.X, YTheta)
	local StartCFrame = CFrame.new(Vector3.zero, SuppliedLookVector)

	return CFrame.Angles(0, -ConstrainedInput.X, 0) * StartCFrame * CFrame.Angles(-ConstrainedInput.Y, 0, 0)
end

local function CalculateNewClampedY(LookVector:Vector3, Y:number) : number
	local CurrentPitchAngle = math.asin(LookVector.Y)
	return math.clamp(Y, -MAX_Y + CurrentPitchAngle, -MIN_Y + CurrentPitchAngle)
end

--=-== | Camera Control | ==-=--

function Controller:AllowCameraMovement()
	if not CameraOffset then return end

	Camera.CameraType = Enum.CameraType.Custom
	CameraOffset = nil
end

function Controller:StopCameraMovement()
	if CameraOffset then return end

	Camera.CameraType = Enum.CameraType.Scriptable
	CameraOffset = Root.CFrame:ToObjectSpace(Camera.CFrame)
end

function Controller:SetFOV(FOV:number?)
	Camera.FieldOfView = FOV or DefaultFOV
end

function Controller:ClearOffsets()
	table.clear(OffsetEffects)
	BasePositionOffset = Vector3.zero
	BaseRotationOffset = Vector3.zero
end

function Controller:CancelAll()
	Cutscene = nil
	Follow = nil
	LookAt = nil

	if ActiveBezierCancel then ActiveBezierCancel() ActiveBezierCancel = nil end
	SpringMotion.Stop(CameraSpring)

	Controller:ClearOffsets()
	Controller:AllowCameraMovement()
end

--=-== | Screen Shake | ==-=--

local function CreateShake(Duration:number, Intensity:number, Speed:number, PositionInfluence:Vector3, RotationInfluence:Vector3, FadeInDuration:number, FadeOutDuration:number, FadeEasingStyle:Enum.EasingStyle, FadeEasingDirection:Enum.EasingDirection)
	local RNG = Random.new()
	local self = setmetatable({
		Duration = Duration,
		CurrentTime = 0,
		Intensity = Intensity,
		PositionInfluence = PositionInfluence,
		RotationInfluence = RotationInfluence,
		FadeInDuration = FadeInDuration,
		FadeOutDuration = FadeOutDuration,
		FadeEasingStyle = FadeEasingStyle,
		FadeEasingDirection = FadeEasingDirection,
		Tick = 0,
		Speed = Speed,
		PositionOffset = Vector3.zero,
		RotationOffset = Vector3.zero,
		Active = true,
		Stopping = false,
		StopElapsed = 0,
		StopDuration = FadeOutDuration,
		Seeds = {
			PX = RNG:NextNumber(-1000, 1000),
			PY = RNG:NextNumber(-1000, 1000),
			PZ = RNG:NextNumber(-1000, 1000),
			RX = RNG:NextNumber(-1000, 1000),
			RY = RNG:NextNumber(-1000, 1000),
			RZ = RNG:NextNumber(-1000, 1000),
		},
	}, {__index = OffsetEffects})

	function self:Stop(FadeOut:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
		if self.Stopping then return end

		self.Stopping = true
		self.StopElapsed = 0
		self.StopDuration = FadeOut or self.FadeOutDuration

		if EasingStyle then self.FadeEasingStyle = EasingStyle end
		if EasingDirection then self.FadeEasingDirection = EasingDirection end
	end

	function self:Destroy()
		self.Active = false

		local Index = table.find(OffsetEffects, self)
		if Index then table.remove(OffsetEffects, Index) end
	end

	function self:Update(DeltaTime:number)
		if not self.Active then return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero} end

		self.CurrentTime += DeltaTime
		self.Tick += DeltaTime * self.Speed

		local Strength = 1

		if self.FadeInDuration > 0 and self.CurrentTime < self.FadeInDuration then
			local Alpha = math.clamp(self.CurrentTime / self.FadeInDuration, 0, 1)
			Strength = TS:GetValue(Alpha, self.FadeEasingStyle, Enum.EasingDirection.Out)
		end

		if self.Duration > 0 then
			local TimeLeft = self.Duration - self.CurrentTime

			if self.FadeOutDuration > 0 and TimeLeft < self.FadeOutDuration then
				local Alpha = math.clamp(TimeLeft / self.FadeOutDuration, 0, 1)
				Strength = math.min(Strength, TS:GetValue(Alpha, self.FadeEasingStyle, self.FadeEasingDirection))
			end

			if self.CurrentTime >= self.Duration then
				self:Destroy()
				return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero}
			end
		end

		if self.Stopping then
			self.StopElapsed += DeltaTime

			if self.StopDuration > 0 then
				local Alpha = math.clamp(1 - (self.StopElapsed / self.StopDuration), 0, 1)
				Strength = math.min(Strength, TS:GetValue(Alpha, self.FadeEasingStyle, self.FadeEasingDirection))
			else
				Strength = 0
			end

			if self.StopElapsed >= self.StopDuration then
				self:Destroy()
				return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero}
			end
		end

		local Final = Strength * self.Intensity
		local T = self.Tick

		self.PositionOffset = Vector3.new(math.noise(T, self.Seeds.PX, 0) * self.PositionInfluence.X, math.noise(T, self.Seeds.PY, 0) * self.PositionInfluence.Y, math.noise(T, self.Seeds.PZ, 0) * self.PositionInfluence.Z) * Final
		self.RotationOffset = Vector3.new(math.noise(T, self.Seeds.RX, 0) * self.RotationInfluence.X, math.noise(T, self.Seeds.RY, 0) * self.RotationInfluence.Y, math.noise(T, self.Seeds.RZ, 0) * self.RotationInfluence.Z) * Final

		return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset}
	end

	table.insert(OffsetEffects, self)
	return self
end

function Controller:ScreenShake(Duration:number?, Intensity:number?, Speed:number?, PositionInfluence:Vector3?, RotationInfluence:Vector3?, FadeInDuration:number?, FadeOutDuration:number?, FadeEasingStyle:Enum.EasingStyle?, FadeEasingDirection:Enum.EasingDirection?)
	return CreateShake(Duration or 1, Intensity or 1, Speed or 25, PositionInfluence or Vector3.new(0.3, 0.3, 0), RotationInfluence or Vector3.new(0.3, 0.3, 0.1), FadeInDuration or 0.1, FadeOutDuration or 0.4, FadeEasingStyle or Enum.EasingStyle.Quad, FadeEasingDirection or Enum.EasingDirection.Out)
end

function Controller:StartShake(Intensity:number?, Speed:number?, PositionInfluence:Vector3?, RotationInfluence:Vector3?, FadeInDuration:number?, FadeEasingStyle:Enum.EasingStyle?, FadeEasingDirection:Enum.EasingDirection?)
	return CreateShake(-1, Intensity or 1, Speed or 25, PositionInfluence or Vector3.new(0.3, 0.3, 0), RotationInfluence or Vector3.new(0.3, 0.3, 0.1), FadeInDuration or 0.15, 0.4, FadeEasingStyle or Enum.EasingStyle.Quad, FadeEasingDirection or Enum.EasingDirection.Out)
end

function Controller:StopShake(Shake:any, FadeOutDuration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	if not Shake or not Shake.Stop then return end
	Shake:Stop(FadeOutDuration, EasingStyle, EasingDirection)
end

function Controller:SetShakeSpeed(Shake:any, Speed:number)
	if not Shake then return end
	Shake.Speed = Speed
end

function Controller:SetShakeIntensity(Shake:any, Intensity:number)
	if not Shake then return end
	Shake.Intensity = Intensity
end

--=-== | Spiral | ==-=--

function Controller:Spiral(Duration:number?, Intensity:number?, Loops:number?, FadeDuration:number?, FadeEasingStyle:Enum.EasingStyle?, FadeEasingDirection:Enum.EasingDirection?)
	local self = setmetatable({
		Duration = Duration or 0,
		CurrentTime = 0,
		RotationOffset = Vector3.zero,
		FadeTime = 1,
		FadeDuration = FadeDuration or 1,
		Intensity = Intensity or 1,
		FadeEasingStyle = FadeEasingStyle or Enum.EasingStyle.Circular,
		FadeEasingDirection = FadeEasingDirection or Enum.EasingDirection.InOut,
		Loops = Loops or 1,
	}, {__index = OffsetEffects})

	function self:Update(DeltaTime:number)
		self.CurrentTime += DeltaTime
		local Angle = (self.CurrentTime / self.Duration) * math.pi * 2 * self.Loops

		if self.Duration >= 0 and self.CurrentTime >= self.Duration then
			table.remove(OffsetEffects, table.find(OffsetEffects, self))
			self.RotationOffset = Vector3.zero
		else
			if self.Duration - self.CurrentTime < self.FadeDuration then self.FadeTime -= (DeltaTime / self.FadeDuration) end
			local FadeInOut = math.clamp(math.min(self.CurrentTime / (self.Duration - self.FadeDuration), 1) * TS:GetValue(self.FadeTime, self.FadeEasingStyle, self.FadeEasingDirection), 0, 1)

			if Camera.CameraType == Enum.CameraType.Scriptable and not Cutscene then
				local PreviousRotationOffset = self.RotationOffset
				self.RotationOffset = Vector3.new(math.sin(Angle), math.cos(Angle), 0) * self.Intensity * FadeInOut
				
				return {PositionOffset = Vector3.zero, RotationOffset = (self.RotationOffset - PreviousRotationOffset)}
			end
			
			self.RotationOffset = Vector3.new(math.sin(Angle), math.cos(Angle), 0) * self.Intensity * FadeInOut
		end

		return {PositionOffset = Vector3.zero, RotationOffset = self.RotationOffset}
	end

	table.insert(OffsetEffects, self)
	return self
end

--=-== | Offsets | ==-=--

function Controller:Offset(Position:Vector3?, Rotation:Vector3?, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	local self = setmetatable({
		Duration = Duration or 0,
		CurrentTime = 0,
		Rotation = Rotation or Vector3.zero,
		RotationOffset = Vector3.zero,
		Position = Position or Vector3.zero,
		PositionOffset = Vector3.zero,
		EasingStyle = EasingStyle or Enum.EasingStyle.Linear,
		EasingDirection = EasingDirection or Enum.EasingDirection.In,
	}, {__index = OffsetEffects})
	
	table.insert(OffsetEffects, self)

	function self:Update(DeltaTime:number)
		self.CurrentTime += DeltaTime

		if self.CurrentTime >= self.Duration then
			table.remove(OffsetEffects, table.find(OffsetEffects, self))
			
			BaseRotationOffset = self.Rotation
			BasePositionOffset = self.Position
			
			return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero}
		end

		local PreviousRotationOffset = self.RotationOffset
		local PreviousPositionOffset = self.PositionOffset
		local Progress = TS:GetValue(self.CurrentTime / self.Duration, self.EasingStyle, self.EasingDirection)

		self.PositionOffset = Vector3.zero:Lerp(self.Position - BasePositionOffset, Progress)
		self.RotationOffset = Vector3.zero:Lerp(self.Rotation - BaseRotationOffset, Progress)

		if Camera.CameraType == Enum.CameraType.Scriptable and not Cutscene then return {PositionOffset = self.PositionOffset - PreviousPositionOffset, RotationOffset = self.RotationOffset - PreviousRotationOffset} end

		return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset}
	end

	return self
end

function Controller:GhostOffset(Position:Vector3?, Rotation:Vector3?, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	local self = setmetatable({
		Duration = Duration or 0,
		CurrentTime = 0,
		Rotation = Rotation or Vector3.zero,
		RotationOffset = Vector3.zero,
		Position = Position or Vector3.zero,
		PositionOffset = Vector3.zero,
		EasingStyle = EasingStyle or Enum.EasingStyle.Linear,
		EasingDirection = EasingDirection or Enum.EasingDirection.In,
	}, {__index = OffsetEffects})
	
	table.insert(OffsetEffects, self)

	function self:Update(DeltaTime:number)
		self.CurrentTime += DeltaTime
		if self.CurrentTime >= self.Duration then table.remove(OffsetEffects, table.find(OffsetEffects, self)) return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero} end

		local PreviousRotationOffset = self.RotationOffset
		local PreviousPositionOffset = self.PositionOffset
		local Progress = TS:GetValue(self.CurrentTime / self.Duration, self.EasingStyle, self.EasingDirection)

		self.PositionOffset = Vector3.zero:Lerp(self.Position, Progress)
		self.RotationOffset = Vector3.zero:Lerp(self.Rotation, Progress)

		if Camera.CameraType == Enum.CameraType.Scriptable and not Cutscene then return {PositionOffset = self.PositionOffset - PreviousPositionOffset, RotationOffset = self.RotationOffset - PreviousRotationOffset} end
		if Camera.CameraType == Enum.CameraType.Custom then return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset - PreviousRotationOffset} end

		return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset}
	end

	return self
end

function Controller:OffsetRelative(Position:Vector3?, Rotation:Vector3?, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	local self = setmetatable({
		Duration = Duration or 0,
		CurrentTime = 0,
		Rotation = Rotation or Vector3.zero,
		RotationOffset = Vector3.zero,
		Position = Position or Vector3.zero,
		PositionOffset = Vector3.zero,
		EasingStyle = EasingStyle or Enum.EasingStyle.Linear,
		EasingDirection = EasingDirection or Enum.EasingDirection.In,
	}, {__index = OffsetEffects})
	table.insert(OffsetEffects, self)

	function self:Update(DeltaTime:number)
		self.CurrentTime += DeltaTime

		if self.CurrentTime >= self.Duration then
			table.remove(OffsetEffects, table.find(OffsetEffects, self))
			BaseRotationOffset += self.Rotation
			BasePositionOffset += self.Position
			
			return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero}
		end

		local PreviousRotationOffset = self.RotationOffset
		local PreviousPositionOffset = self.PositionOffset
		local Progress = TS:GetValue(self.CurrentTime / self.Duration, self.EasingStyle, self.EasingDirection)

		self.PositionOffset = Vector3.zero:Lerp(self.Position, Progress)
		self.RotationOffset = Vector3.zero:Lerp(self.Rotation, Progress)

		if Camera.CameraType == Enum.CameraType.Scriptable and not Cutscene then return {PositionOffset = self.PositionOffset - PreviousPositionOffset, RotationOffset = self.RotationOffset - PreviousRotationOffset} end
		if Camera.CameraType == Enum.CameraType.Custom then return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset} end

		return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset}
	end

	return self
end

-- | --=> <~> | [Default] | <~> <=-- | --
--=-== | Return | ==-=--

function Controller.Default.Return(Duration:number?, CurrentVelocity:CFrame?)
	LookAt = nil
	Follow = nil

	if not CameraOffset or not Root or not Root.Parent then Controller:AllowCameraMovement() return end

	local TotalDuration:number = math.max(Duration or 0.4, 0.001)
	local TimeRemaining:number = TotalDuration
	local Velocity:CFrame = CurrentVelocity or CurrentCameraVelocity or CFrame.new()

	Cutscene = function(DeltaTime:number) : CFrame
		if not Root or not Root.Parent then
			Cutscene = nil
			Controller:AllowCameraMovement()
			
			return Camera.CFrame
		end

		local TargetCFrame:CFrame = Root.CFrame * CameraOffset

		if Camera.CFrame:FuzzyEq(TargetCFrame, 5e-4) then
			Camera.CFrame = TargetCFrame
			Controller:AllowCameraMovement()
			Cutscene = nil
			
			return TargetCFrame
		end

		local Alpha:number = math.clamp(TimeRemaining / TotalDuration, 0, 1)
		local Damping:number = TS:GetValue(Alpha, Enum.EasingStyle.Circular, Enum.EasingDirection.In)

		local NewCFrame:CFrame, NewVelocity:CFrame = TS:SmoothDamp(Camera.CFrame, TargetCFrame, Velocity, Damping, nil, DeltaTime)
		Velocity = NewVelocity
		TimeRemaining -= DeltaTime

		if TimeRemaining <= 0 then
			Camera.CFrame = TargetCFrame
			Controller:AllowCameraMovement()
			Cutscene = nil
		end

		return NewCFrame
	end
end

--=-== | Zoom | ==-=--

function Controller.Default.Zoom(FOV:number?, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?) : Tween
	local TweenInstance:Tween = TS:Create(Camera, TweenInfo.new(Duration or 1, EasingStyle or Enum.EasingStyle.Sine, EasingDirection or Enum.EasingDirection.Out), {FieldOfView = FOV or DefaultFOV})

	TweenInstance:Play()
	return TweenInstance
end

--=-== | Kick | ==-=--

function Controller.Default.Kick(Intensity:number?, Duration:number?, FOVKick:number?, Speed:number?)
	local ShakeIntensity:number = Intensity or 1
	local ShakeDuration:number = Duration or 0.35
	local StartFOV:number = Camera.FieldOfView

	Controller:ScreenShake(ShakeDuration, ShakeIntensity, Speed or 35, Vector3.new(0.4, 0.4, 0) * ShakeIntensity, Vector3.new(0.4, 0.4, 0.15) * ShakeIntensity, 0.05, ShakeDuration * 0.7)

	if FOVKick and FOVKick ~= 0 then
		local OutTween:Tween = TS:Create(Camera, TweenInfo.new(ShakeDuration * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = StartFOV + FOVKick})
		OutTween:Play()

		OutTween.Completed:Once(function() TS:Create(Camera, TweenInfo.new(ShakeDuration * 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = StartFOV}):Play() end)
	end
end

--=-== | Bounce | ==-=--

function Controller.Default.Bounce(PositionVector:Vector3?, RotationVector:Vector3?, Duration:number?, FadeOut:number?)
	local BouncePosition:Vector3 = PositionVector or Vector3.zero
	local BounceRotation:Vector3 = RotationVector or Vector3.zero

	local self = setmetatable({
		CurrentTime = 0,
		Duration = Duration or 1,
		FadeOut = FadeOut or 0.5,
		PositionOffset = Vector3.zero,
		RotationOffset = Vector3.zero,
	}, {__index = OffsetEffects})

	function self:Update(DeltaTime:number)
		self.CurrentTime += DeltaTime
		local T:number = self.CurrentTime / self.Duration

		if T > 1 then
			local Index:number? = table.find(OffsetEffects, self)
			if Index then table.remove(OffsetEffects, Index) end
			
			return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero}
		end

		local function ElasticDecay(X:number) : number
			local A:number = 0.5
			local P:number = 0.3
			
			return A * (2 ^ (-8 * X)) * math.sin((X - P / 4) * (2 * math.pi) / P)
		end

		local Fade:number = 1
		if self.CurrentTime > self.Duration - self.FadeOut then Fade = (self.Duration - self.CurrentTime) / self.FadeOut end

		local Decay:number = ElasticDecay(T) * Fade * (1 / 10)
		self.PositionOffset = BouncePosition * Decay
		self.RotationOffset = BounceRotation * Decay

		return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset}
	end

	table.insert(OffsetEffects, self)
	return self
end

--=-== | TweenTo | ==-=--

function Controller.Default.TweenTo(Target:any, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?) : {Completed:any, Cancel:() -> ()}
	local GoalCF:CFrame = GetCFrameFromData(Target)

	if not Duration or Duration <= 0 then
		Controller:StopCameraMovement()
		Camera.CFrame = GoalCF
		
		return {Cancel = function() end, Completed = Signal.New()}
	end

	if GoalCF.LookVector == -Vector3.zAxis then GoalCF = CFrame.new(GoalCF.Position) * Camera.CFrame.Rotation end

	Controller:StopCameraMovement()

	local StartCF:CFrame = Camera.CFrame
	local TimeElapsed:number = 0
	local Completed = Signal.New()
	local Fired:boolean = false

	Cutscene = function(DeltaTime:number) : CFrame
		if Fired then return GoalCF end

		TimeElapsed += DeltaTime
		local Alpha:number = math.min(TimeElapsed / Duration, 1)
		local Progress:number = TS:GetValue(Alpha, EasingStyle or Enum.EasingStyle.Quad, EasingDirection or Enum.EasingDirection.Out)

		if Alpha >= 1 then
			Fired = true
			Cutscene = nil
			
			task.defer(function() Completed:Fire() Completed:Destroy() end)
			return GoalCF
		end

		return StartCF:Lerp(GoalCF, Progress)
	end

	return {
		Completed = Completed,
		Cancel = function() if Fired then return end Cutscene = nil end,
	}
end

-- | --=> <~> | [Spring] | <~> <=-- | --
--=-== | Return | ==-=--

function Controller.Spring.Return(Damping:number?, Frequency:number?, Speed:number?)
	LookAt = nil
	Follow = nil

	if not CameraOffset or not Root or not Root.Parent then Controller:AllowCameraMovement() return end

	local SpringDamping:number = Damping or 0.8
	local SpringFrequency:number = Frequency or 2.5
	local SpringSpeed:number = Speed or 1

	CameraSpring.CFrame = Camera.CFrame
	SpringMotion.Target(CameraSpring, SpringDamping, SpringFrequency, SpringSpeed, {CFrame = Root.CFrame * CameraOffset})

	Cutscene = function(_DeltaTime:number) : CFrame
		if not Root or not Root.Parent then
			Cutscene = nil
			SpringMotion.Stop(CameraSpring)
			Controller:AllowCameraMovement()
			
			return Camera.CFrame
		end

		local TargetCF:CFrame = Root.CFrame * CameraOffset
		SpringMotion.Target(CameraSpring, SpringDamping, SpringFrequency, SpringSpeed, {CFrame = TargetCF})

		if CameraSpring.CFrame:FuzzyEq(TargetCF, 5e-4) then
			Cutscene = nil
			SpringMotion.Stop(CameraSpring)
			Controller:AllowCameraMovement()
			
			return TargetCF
		end

		return CameraSpring.CFrame
	end
end

--=-== | Zoom | ==-=--

function Controller.Spring.Zoom(FOV:number?, Damping:number?, Frequency:number?, Speed:number?)
	SpringMotion.Target(Camera, Damping or 0.65, Frequency or 2, Speed or 0.8, {FieldOfView = FOV or DefaultFOV})
end

--=-== | Kick | ==-=--

function Controller.Spring.Kick(Intensity:number?, Duration:number?, FOVKick:number?, Speed:number?)
	local ShakeIntensity:number = Intensity or 1
	local ShakeDuration:number = Duration or 0.35
	local StartFOV:number = Camera.FieldOfView

	Controller:ScreenShake(ShakeDuration, ShakeIntensity, Speed or 35, Vector3.new(0.4, 0.4, 0) * ShakeIntensity, Vector3.new(0.4, 0.4, 0.15) * ShakeIntensity, 0.05, ShakeDuration * 0.7)

	if FOVKick and FOVKick ~= 0 then
		SpringMotion.Target(Camera, 0.5, 5, 1, {FieldOfView = StartFOV})
		SpringMotion.Shove(Camera, 0.5, 5, 1, {FieldOfView = FOVKick})
	end
end

--=-== | Bounce | ==-=--

function Controller.Spring.Bounce(PositionVector:Vector3?, RotationVector:Vector3?, Damping:number?, Frequency:number?)
	local BouncePosition:Vector3 = PositionVector or Vector3.zero
	local BounceRotation:Vector3 = RotationVector or Vector3.zero
	local BDamping:number = Damping or 0.3
	local BFrequency:number = Frequency or 8
	local Stiffness:number = BFrequency * BFrequency
	local Drag:number = 2 * BDamping * BFrequency

	local self = setmetatable({
		PositionVelocity = Vector3.zero,
		RotationVelocity = Vector3.zero,
		PositionOffset = BouncePosition,
		RotationOffset = BounceRotation,
	}, {__index = OffsetEffects})

	function self:Update(DeltaTime:number)
		local PositionForce:Vector3 = -self.PositionOffset * Stiffness - self.PositionVelocity * Drag
		local RotationForce:Vector3 = -self.RotationOffset * Stiffness - self.RotationVelocity * Drag

		self.PositionVelocity += PositionForce * DeltaTime
		self.RotationVelocity += RotationForce * DeltaTime
		self.PositionOffset += self.PositionVelocity * DeltaTime
		self.RotationOffset += self.RotationVelocity * DeltaTime

		if self.PositionOffset.Magnitude < 5e-4 and self.PositionVelocity.Magnitude < 5e-4
			and self.RotationOffset.Magnitude < 5e-4 and self.RotationVelocity.Magnitude < 5e-4 then
			
			local Index:number? = table.find(OffsetEffects, self)
			if Index then table.remove(OffsetEffects, Index) end
			
			return {PositionOffset = Vector3.zero, RotationOffset = Vector3.zero}
		end

		return {PositionOffset = self.PositionOffset, RotationOffset = self.RotationOffset}
	end

	table.insert(OffsetEffects, self)
	return self
end

--=-== | TweenTo | ==-=--

function Controller.Spring.TweenTo(Target:any, Damping:number?, Frequency:number?, Speed:number?) : {Completed:any, Cancel:() -> ()}
	local GoalCF:CFrame = GetCFrameFromData(Target)

	if GoalCF.LookVector == -Vector3.zAxis then GoalCF = CFrame.new(GoalCF.Position) * Camera.CFrame.Rotation end

	Controller:StopCameraMovement()

	local Completed = Signal.New()
	local Fired:boolean = false

	CameraSpring.CFrame = Camera.CFrame
	SpringMotion.Target(CameraSpring, Damping or 0.8, Frequency or 2.5, Speed or 1, {CFrame = GoalCF})

	Cutscene = function(_DeltaTime:number) : CFrame
		if Fired then return GoalCF end

		if CameraSpring.CFrame:FuzzyEq(GoalCF, 0.01) then
			Fired = true
			Cutscene = nil
			SpringMotion.Stop(CameraSpring)
			
			task.defer(function() Completed:Fire() Completed:Destroy() end)
			return GoalCF
		end

		return CameraSpring.CFrame
	end

	return {
		Completed = Completed,
		Cancel = function()
			if Fired then return end
			
			Cutscene = nil
			SpringMotion.Stop(CameraSpring)
		end,
	}
end

-- | --=> <~> | [Bezier] | <~> <=-- | --
--=-== | TweenTo | ==-=--

function Controller.Bezier.TweenTo.BezierTween(Target:any, ControlDirection:Vector3, Harshness:number, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?) : {Completed:any, Cancel:() -> ()}
	local GoalCF:CFrame = GetCFrameFromData(Target)

	if GoalCF.LookVector == -Vector3.zAxis then GoalCF = CFrame.new(GoalCF.Position) * Camera.CFrame.Rotation end

	Controller:StopCameraMovement()

	local BezierCurve = TruWorksBezier.New(Camera.CFrame, GoalCF, ControlDirection, Harshness)
	local TimeElapsed:number = 0
	local TotalDuration:number = Duration or 1
	local Style:Enum.EasingStyle = EasingStyle or Enum.EasingStyle.Quad
	local Dir:Enum.EasingDirection = EasingDirection or Enum.EasingDirection.Out
	local Completed = Signal.New()
	local Fired:boolean = false

	Cutscene = function(DeltaTime:number) : CFrame
		if Fired then return GoalCF end

		TimeElapsed += DeltaTime
		local Alpha:number = math.min(TimeElapsed / TotalDuration, 1)
		local Progress:number = TS:GetValue(Alpha, Style, Dir)

		if Alpha >= 1 then
			Fired = true
			Cutscene = nil
			BezierCurve:Destroy()
			
			task.defer(function() Completed:Fire() Completed:Destroy() end)
			return GoalCF
		end

		return BezierCurve:GetCFrame(Progress)
	end

	return {
		Completed = Completed,
		Cancel = function()
			if Fired then return end
			
			Cutscene = nil
			BezierCurve:Destroy()
		end,
	}
end

function Controller.Bezier.TweenTo.BezierSpring(Target:any, ControlOffset:Vector3, Damping:number?, Frequency:number?, Speed:number?) : {Completed:any, Cancel:() -> ()}
	local GoalCF:CFrame = GetCFrameFromData(Target)

	if GoalCF.LookVector == -Vector3.zAxis then GoalCF = CFrame.new(GoalCF.Position) * Camera.CFrame.Rotation end

	Controller:StopCameraMovement()

	local SpringDamping:number = Damping or 0.75
	local SpringFrequency:number = Frequency or 2
	local SpringSpeed:number = Speed or 1

	CameraSpring.CFrame = Camera.CFrame

	if ActiveBezierCancel then ActiveBezierCancel() end
	ActiveBezierCancel = SpringMotion.Bezier3D(CameraSpring, GoalCF, ControlOffset, SpringDamping, SpringFrequency, SpringSpeed)

	local Completed = Signal.New()
	local Fired:boolean = false

	Cutscene = function(_DeltaTime:number) : CFrame
		if Fired then return GoalCF end

		if CameraSpring.CFrame:FuzzyEq(GoalCF, 0.01) then
			Fired = true
			Cutscene = nil
			
			if ActiveBezierCancel then ActiveBezierCancel() ActiveBezierCancel = nil end
			task.defer(function() Completed:Fire() Completed:Destroy() end)
			
			return GoalCF
		end

		return CameraSpring.CFrame
	end

	return {
		Completed = Completed,
		Cancel = function()
			if Fired then return end
			Cutscene = nil
			
			if ActiveBezierCancel then ActiveBezierCancel() ActiveBezierCancel = nil end
		end,
	}
end

--=-== | Return | ==-=--

function Controller.Bezier.Return.BezierTween(ControlDirection:Vector3, Harshness:number, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	LookAt = nil
	Follow = nil

	if not CameraOffset or not Root or not Root.Parent then Controller:AllowCameraMovement() return end

	local TargetCF:CFrame = Root.CFrame * CameraOffset
	local BezierCurve = TruWorksBezier.New(Camera.CFrame, TargetCF, ControlDirection, Harshness)
	local TimeElapsed:number = 0
	local TotalDuration:number = Duration or 0.6
	local Style:Enum.EasingStyle = EasingStyle or Enum.EasingStyle.Quad
	local Dir:Enum.EasingDirection = EasingDirection or Enum.EasingDirection.Out

	Cutscene = function(DeltaTime:number) : CFrame
		if not Root or not Root.Parent then
			Cutscene = nil
			BezierCurve:Destroy()
			Controller:AllowCameraMovement()
			
			return Camera.CFrame
		end

		TimeElapsed += DeltaTime
		local Alpha:number = math.min(TimeElapsed / TotalDuration, 1)
		local Progress:number = TS:GetValue(Alpha, Style, Dir)

		if Alpha >= 1 then
			Cutscene = nil
			BezierCurve:Destroy()
			Controller:AllowCameraMovement()
			
			return Root.CFrame * CameraOffset
		end

		return BezierCurve:GetCFrame(Progress)
	end
end

function Controller.Bezier.Return.BezierSpring(ControlOffset:Vector3, Damping:number?, Frequency:number?, Speed:number?)
	LookAt = nil
	Follow = nil

	if not CameraOffset or not Root or not Root.Parent then Controller:AllowCameraMovement() return end

	local SpringDamping:number = Damping or 0.8
	local SpringFrequency:number = Frequency or 2.5
	local SpringSpeed:number = Speed or 1

	CameraSpring.CFrame = Camera.CFrame

	if ActiveBezierCancel then ActiveBezierCancel() end
	ActiveBezierCancel = SpringMotion.Bezier3D(CameraSpring, Root.CFrame * CameraOffset, ControlOffset, SpringDamping, SpringFrequency, SpringSpeed)

	Cutscene = function(_DeltaTime:number) : CFrame
		if not Root or not Root.Parent then
			Cutscene = nil
			if ActiveBezierCancel then ActiveBezierCancel() ActiveBezierCancel = nil end
			
			Controller:AllowCameraMovement()
			return Camera.CFrame
		end

		local TargetCF:CFrame = Root.CFrame * CameraOffset

		if CameraSpring.CFrame:FuzzyEq(TargetCF, 5e-4) then
			Cutscene = nil
			if ActiveBezierCancel then ActiveBezierCancel() ActiveBezierCancel = nil end
			
			Controller:AllowCameraMovement()
			return TargetCF
		end

		return CameraSpring.CFrame
	end
end

-- | --=> <~> | [Shared] | <~> <=-- | --
--=-== | Focus | ==-=--

function Controller:VertigoZoom(Target:any, TargetFOV:number, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	local StartFOV = Camera.FieldOfView
	local StartCFrame = Camera.CFrame
	local StartTargetPosition = GetCFrameFromData(Target).Position
	local StartDistance = (StartCFrame.Position - StartTargetPosition).Magnitude

	Controller:StopCameraMovement()

	local TimeElapsed = 0
	local TotalDuration = Duration or 1
	local Style = EasingStyle or Enum.EasingStyle.Sine
	local Direction = EasingDirection or Enum.EasingDirection.Out
	local TweenFinished = false
	local Cancelled = false
	local Velocity = CFrame.new()
	local Connection

	Connection = RS.Heartbeat:Connect(function(DeltaTime:number)
		if Cancelled then return end

		local CurrentTargetPosition = GetCFrameFromData(Target).Position
		local CurrentDistance = (Camera.CFrame.Position - CurrentTargetPosition).Magnitude
		local DistanceRatio = CurrentDistance / StartDistance
		local DesiredFOV = math.clamp(TargetFOV * DistanceRatio, 1, 110)
		local DesiredRotation = CFrame.new(Camera.CFrame.Position, CurrentTargetPosition)

		if not TweenFinished then
			TimeElapsed += DeltaTime
			local Alpha = math.min(TimeElapsed / TotalDuration, 1)
			local Progress = TS:GetValue(Alpha, Style, Direction)

			Camera.FieldOfView = StartFOV + (DesiredFOV - StartFOV) * Progress
			Camera.CFrame = StartCFrame:Lerp(DesiredRotation, Progress)

			if Alpha >= 1 then TweenFinished = true end
		else
			local SmoothedCFrame
			SmoothedCFrame, Velocity = TS:SmoothDamp(Camera.CFrame, DesiredRotation, Velocity, 0.15, nil, DeltaTime)

			Camera.CFrame = CFrame.new(Camera.CFrame.Position) * SmoothedCFrame.Rotation
			Camera.FieldOfView = Camera.FieldOfView + (DesiredFOV - Camera.FieldOfView) * math.min(DeltaTime * 8, 1)
		end
	end)

	return {
		Cancel = function() Cancelled = true if Connection then Connection:Disconnect() end end,
	}
end

function Controller:FrameSubject(Object:PVInstance, Padding:number?, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	local PaddingFactor = Padding or 1.2
	local TotalDuration = Duration or 0.5
	local Style = EasingStyle or Enum.EasingStyle.Quad
	local Direction = EasingDirection or Enum.EasingDirection.Out

	Controller:StopCameraMovement()

	local StartCFrame = Camera.CFrame
	local StartFOV = Camera.FieldOfView
	local TweenFinished = false
	local Cancelled = false
	local TimeElapsed = 0
	local Velocity = CFrame.new()
	local Connection

	local function GetDesiredFOV() : number
		local ObjectSize = Object:IsA("Model") and Object:GetExtentsSize() or Object.Size
		local MaxExtent = math.max(ObjectSize.X, ObjectSize.Y, ObjectSize.Z) * PaddingFactor
		local Distance = (Camera.CFrame.Position - (Object:IsA("Model") and Object:GetPivot().Position or Object.CFrame.Position)).Magnitude
		
		return math.clamp(math.deg(2 * math.atan(MaxExtent / (2 * Distance))), 1, 120)
	end

	Connection = RS.Heartbeat:Connect(function(DeltaTime:number)
		if Cancelled then return end

		local ObjectPosition = Object:IsA("Model") and Object:GetPivot().Position or Object.CFrame.Position
		local DesiredFOV = GetDesiredFOV()
		local DesiredRotation = CFrame.new(Camera.CFrame.Position, ObjectPosition)

		if not TweenFinished then
			TimeElapsed += DeltaTime
			local Alpha = math.min(TimeElapsed / TotalDuration, 1)
			local Progress = TS:GetValue(Alpha, Style, Direction)

			Camera.CFrame = StartCFrame:Lerp(DesiredRotation, Progress)
			Camera.FieldOfView = StartFOV + (DesiredFOV - StartFOV) * Progress

			if Alpha >= 1 then TweenFinished = true end
		else
			local SmoothedCFrame
			SmoothedCFrame, Velocity = TS:SmoothDamp(Camera.CFrame, DesiredRotation, Velocity, 0.15, nil, DeltaTime)

			Camera.CFrame = CFrame.new(Camera.CFrame.Position) * SmoothedCFrame.Rotation
			Camera.FieldOfView = Camera.FieldOfView + (DesiredFOV - Camera.FieldOfView) * math.min(DeltaTime * 8, 1)
		end
	end)

	return {
		Cancel = function() Cancelled = true if Connection then Connection:Disconnect() end end,
	}
end

--=-== | Look At | ==-=--

function Controller:LookAt(Target:PVInstance | Vector3 | CFrame, Smoothness:number?, Duration:number?, EasingStyle:Enum.EasingStyle?, EasingDirection:Enum.EasingDirection?)
	Controller:StopCameraMovement()
	local self = {CurrentTime = 0, Duration = Duration or -1, Smoothness = Smoothness or 0.4,}

	if (EasingStyle or EasingDirection) and not Smoothness then
		local Style = EasingStyle or Enum.EasingStyle.Linear
		local LocalDirection = EasingDirection or Enum.EasingDirection.Out
		local StartRotation = Camera.CFrame.Rotation

		LookAt = function(DeltaTime:number, Desired:CFrame) : CFrame
			self.CurrentTime += DeltaTime
			
			if self.CurrentTime > self.Duration and self.Duration ~= -1 then LookAt = nil return Desired end
			if not Target then LookAt = nil return Camera.CFrame.Rotation end

			local Delta = TS:GetValue(self.CurrentTime / self.Duration, Style, LocalDirection)
			return StartRotation:Lerp(CFrame.new(Camera.CFrame.Position, GetCFrameFromData(Target).Position), Delta).Rotation + Desired.Position
		end
	else
		LookAt = function(DeltaTime:number, Desired:CFrame) : CFrame
			self.CurrentTime += DeltaTime
			
			if self.CurrentTime > self.Duration and self.Duration ~= -1 then LookAt = nil return Desired end
			if not Target then LookAt = nil return Camera.CFrame.Rotation end

			return Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, GetCFrameFromData(Target).Position), self.Smoothness).Rotation + Desired.Position
		end
	end

	return self
end

--=-== | Follow | ==-=--

function Controller:Follow(Object:PVInstance, Duration:number?, Position:Vector3?, Rotation:Vector3?, FadeDuration:number?, FadeEasingStyle:Enum.EasingStyle?, FadeEasingDirection:Enum.EasingDirection?)
	if not Object or not Object.Parent then warn(`[Controllers.CameraController].Follow: Object passed through {Object} is not valid.`) return end
	Controller:StopCameraMovement()

	local self = {
		CurrentTime = 0,
		Duration = Duration or -1,
		Position = Position or Vector3.new(1, 1, 1),
		Rotation = Rotation or Vector3.zero,
		FadeDuration = FadeDuration or 0,
		FadeTime = 1,
		FadeEasingStyle = FadeEasingStyle or Enum.EasingStyle.Quad,
		FadeEasingDirection = FadeEasingDirection or Enum.EasingDirection.Out,
	}

	local LastObjectCF = Object.CFrame

	Follow = function(DeltaTime:number, Desired:CFrame) : CFrame
		if not Object or not Object.Parent then Follow = nil return Desired end

		self.CurrentTime += DeltaTime
		if self.CurrentTime > self.Duration and Duration ~= -1 then Follow = nil return Desired end

		if self.Duration - self.CurrentTime < self.FadeDuration and Duration ~= -1 then self.FadeTime = math.clamp(self.FadeTime - (DeltaTime / self.FadeDuration), 0, 1) end

		local Fade = TS:GetValue(self.FadeTime, self.FadeEasingStyle, self.FadeEasingDirection)
		local DeltaPosition = Object.CFrame.Position - LastObjectCF.Position
		local DesiredPosition = Vector3.new(DeltaPosition.X * self.Position.X, DeltaPosition.Y * self.Position.Y, DeltaPosition.Z * self.Position.Z)

		local XO, YO, ZO = Object.CFrame:ToEulerAngles()
		local XP, YP, ZP = LastObjectCF:ToEulerAngles()

		local DesiredRotation = CFrame.fromEulerAngles((XO - XP) * self.Rotation.X * Fade, (YO - YP) * self.Rotation.Y * Fade, (ZO - ZP) * self.Rotation.Z * Fade)

		LastObjectCF = Object.CFrame
		return (Desired + DesiredPosition * Fade) * DesiredRotation
	end

	return self
end

--=-== | Cutscene | ==-=--

function Controller:CreateCutscene(Data:{PointsInfo}?)
	local self = setmetatable({}, {__index = CutsceneService})

	self.Started = Signal.New()
	self.Paused = Signal.New()
	self.Stopped = Signal.New()
	self.Finished = Signal.New()

	self.Started:Connect(function() if not CameraOffset then Controller:StopCameraMovement() end end)

	self.CurrentTime = 0
	self.Positions = {} :: {{CFrame}}
	self.Beziers = {}
	self.CurrentBezier = 1

	if Data then self:UpdateData(Data) end

	return self
end

function CutsceneService:UpdateData(Data:{PointsInfo})
	self.Positions = not self.Positions and table.clear(self.Positions) or {}

	for Index, BezierData in Data do
		self.Positions[Index] = {}
		for CFrameIndex, Position in BezierData.Positions or {} do self.Positions[Index][CFrameIndex] = Position end

		self.Beziers[Index] = {
			StartAtCurrentCamera = BezierData.StartAtCurrentCamera or false,
			EndAtCurrentCamera = BezierData.EndAtCurrentCamera or false,
			StartAtCamera = BezierData.StartAtCamera or false,
			EndAtCamera = BezierData.EndAtCamera or false,
			Duration = BezierData.Duration or 1,
			EasingStyle = BezierData.EasingStyle or Enum.EasingStyle.Linear,
			EasingDirection = BezierData.EasingDirection or Enum.EasingDirection.In,
		}
	end
end

function CutsceneService:Play()
	if Cutscene then warn("[Controllers.CameraController]: A cutscene is already running.") return end

	self.Started:Fire()

	for Index, BezierData in self.Beziers do
		if BezierData.StartAtCurrentCamera then table.insert(self.Positions[Index], 1, Camera.CFrame) end
		if BezierData.EndAtCurrentCamera then table.insert(self.Positions[Index], Camera.CFrame) end
		if BezierData.StartAtCamera then table.insert(self.Positions[Index], 1, {Root, CameraOffset}) end
		if BezierData.EndAtCamera then table.insert(self.Positions[Index], {Root, CameraOffset}) end
	end

	Cutscene = function(DeltaTime:number)
		self.CurrentTime += DeltaTime
		local CurrentBezier = self.Beziers[self.CurrentBezier]

		if self.CurrentTime > CurrentBezier.Duration then
			if self.CurrentBezier == #self.Beziers then Cutscene = nil self.Finished:Fire() return GetCFrameFromData(self.Positions[self.CurrentBezier][#self.Positions[self.CurrentBezier]]) end

			self.CurrentTime = 0
			self.CurrentBezier += 1
			CurrentBezier = self.Beziers[self.CurrentBezier]
		end

		local BezierCFrame = GetBezierCFrame(self.Positions[self.CurrentBezier], TS:GetValue(self.CurrentTime / CurrentBezier.Duration, CurrentBezier.EasingStyle, CurrentBezier.EasingDirection))

		if self.CameraModel then self.CameraModel.CFrame = BezierCFrame end
		return BezierCFrame
	end
end

function CutsceneService:Pause(TimeDelay:number?)
	Cutscene = nil
	self.Paused:Fire()
	
	if TimeDelay then task.delay(TimeDelay, function() if not Cutscene then self:Play() end end) end
end

function CutsceneService:Stop()
	Cutscene = nil
	self.Stopped:Fire()
end

function CutsceneService:Display()
	if self._DisplayFolder then self._DisplayFolder:Destroy() end

	local Folder = Instance.new("Folder")
	Folder.Name = "CutsceneDisplay"
	Folder.Parent = WS
	
	self._DisplayFolder = Folder

	local function CreateOrb(CF:CFrame, Colour:Color3) : BasePart
		local Part = Instance.new("Part")
		Part.Size = Vector3.new(1, 1, 1)
		Part.Shape = Enum.PartType.Ball
		Part.Anchored = true
		Part.CanCollide = false
		Part.Color = Colour
		Part.CFrame = CF
		Part.Parent = Folder
		
		return Part
	end

	local function CreateArrow(StartCF:CFrame, EndCF:CFrame, Colour:Color3)
		local Start = Instance.new("Part")
		Start.Size = Vector3.new(0.2, 0.2, 0.2)
		Start.Anchored = true
		Start.CanCollide = false
		Start.Transparency = 1
		Start.CFrame = StartCF
		Start.Parent = Folder

		local Finish = Start:Clone()
		Finish.CFrame = EndCF
		Finish.Parent = Folder

		local A0 = Instance.new("Attachment", Start)
		local A1 = Instance.new("Attachment", Finish)

		local Beam = Instance.new("Beam")
		Beam.Attachment0 = A0
		Beam.Attachment1 = A1
		Beam.Width0 = 0.15
		Beam.Width1 = 0.05
		Beam.Color = ColorSequence.new(Colour)
		Beam.Parent = Start
	end

	for BezierIndex, Positions in self.Positions do
		local LastOrb:PVInstance
		
		for Index = 1, #Positions do
			local Orb = CreateOrb(GetCFrameFromData(Positions[Index]), Color3.fromRGB(0, 255, 255))
			Orb.Name = `Point_{BezierIndex}_{Index}`

			if LastOrb then CreateArrow(LastOrb.CFrame, Orb.CFrame, Color3.fromRGB(255, 255, 0)) end
			LastOrb = Orb
		end
	end

	local Current = self.Positions[self.CurrentBezier]
	
	if Current then
		local CurrentCFrame = GetCFrameFromData(Current[1])
		
		self.CameraModel = Instance.new("Part")
		self.CameraModel.Anchored = true
		self.CameraModel.CanCollide = false
		self.CameraModel.CFrame = CurrentCFrame
		self.CameraModel.Parent = Folder
	end
end

function CutsceneService:Destroy()
	if self._DisplayFolder then self._DisplayFolder:Destroy() end
	setmetatable(self, nil)
end

--=-== | Render Steps | ==-=--

local function PreCamera(DeltaTime:number)
	PositionOffset = Vector3.zero
	RotationOffset = Vector3.zero

	for _, Effect in ipairs(OffsetEffects) do
		local Offset = Effect:Update(DeltaTime)
		
		PositionOffset += Offset.PositionOffset or Vector3.zero
		RotationOffset += Offset.RotationOffset or Vector3.zero
	end

	if Cutscene then
		PositionOffset += BasePositionOffset
		RotationOffset += BaseRotationOffset
	end

	DesiredCFrame = Camera.CFrame

	if Follow then DesiredCFrame = Follow(DeltaTime, DesiredCFrame) end
	if Cutscene then DesiredCFrame = Cutscene(DeltaTime) end
	if LookAt then DesiredCFrame = LookAt(DeltaTime, DesiredCFrame) end

	if Camera.CameraType == Enum.CameraType.Custom then
		PositionOffset += BasePositionOffset
		RotationOffset += BaseRotationOffset

		EndCFrame = CFrame.new(DesiredCFrame.Position) * CalculateNewLookCFrameFromArg(DesiredCFrame.LookVector, Vector2.new(CalculateNewClampedY(DesiredCFrame.LookVector, math.rad(RotationOffset.Y)), math.rad(RotationOffset.X)))
	else
		EndCFrame = DesiredCFrame * CFrame.Angles(math.rad(RotationOffset.X), math.rad(RotationOffset.Y), 0)

		local XE, YE, ZE = EndCFrame:ToOrientation()
		local XD, YD, ZD = DesiredCFrame:ToOrientation()
		
		EndCFrame = EndCFrame * CFrame.Angles(0, 0, -(ZE - ZD))
	end

	Camera.CFrame = EndCFrame
end

local function PostCamera(DeltaTime:number)
	local Temp = Camera.CFrame:ToObjectSpace(EndCFrame * CFrame.Angles(0, 0, math.rad(RotationOffset.Z)) * CFrame.new(PositionOffset))
	CurrentCameraVelocity = CFrame.new(Temp.Position * (1 / DeltaTime)) * Temp.Rotation

	Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, math.rad(RotationOffset.Z)) * CFrame.new(PositionOffset)
end

--=-== | Init | ==-=--

function Controller:Initialize()
	CameraSpring = Instance.new("Part")
	CameraSpring.Name = "CameraSpring"
	CameraSpring.Anchored = true
	CameraSpring.CanCollide = false
	CameraSpring.CastShadow = false
	CameraSpring.Transparency = 1
	CameraSpring.Size = Vector3.one
	CameraSpring.CFrame = Camera.CFrame
	CameraSpring.Parent = WS

	RS:BindToRenderStep("TruWorks_CameraController_PreCamera", Enum.RenderPriority.Camera.Value - 1, PreCamera)
	RS:BindToRenderStep("TruWorks_CameraController_PostCamera", Enum.RenderPriority.Camera.Value + 1, PostCamera)
end

function Controller:Start()

end

return Controller