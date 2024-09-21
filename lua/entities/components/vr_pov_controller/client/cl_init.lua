--[[
    Copyright (C) 2024 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

local Component = util.register_class("ents.VrPovController", BaseEntityComponent)

include("forearm_control.lua")

Component:RegisterMember("Pov", ents.MEMBER_TYPE_BOOLEAN, true, {
	onChange = function(self)
		self:UpdatePovState()
	end,
}, "def+is")
Component:RegisterMember("UpperBodyOnly", udm.TYPE_BOOLEAN, true, {
	onChange = function(self)
		self:UpdateUpperBodyState()
	end,
}, "def+is")
Component:RegisterMember("ShowHead", udm.TYPE_BOOLEAN, false, {
	onChange = function(self)
		self:UpdateHeadVisibilityState()
	end,
}, "def")
function Component:Initialize()
	--[[
		This component allows controlling a character in POV using VR. It will only work if the character possesses a meta rig, as well as a full-body IK rig.
		There are several steps to make this work:
		1) All parent bones of the head IK control (including the head bone itself) have to be animated.
		The HMD pose is defined relative to the character's animated head pose. At the same time, the head IK control is attached to the HMD pose,
		which causes the character's head to move towards it. This causes a feedback loop.
		This feedback loop can be avoided by making the head pose (and parents) animated, which causes them to reset every frame.
		
		2) The head IK control has to be updated *after* the animations have been updated, but *before* the IK is about to be simulated.
		Since all non-HMD tracked devices are relative to the HMD, their controls will also have to be updated at this time.
		This is handled in :UpdateHeadIkControl()

		3) The HMD pose may be out-of-reach of the character's IK simulation, which means the character's head position may
		end up somewhere else. We have to move the HMD's pose accordingly (as well as the poses for the other tracked devices).
		This means that the HMD's pose in the simulation may not match the reported pose by the VR system.
		This is handled in :UpdateHmdPose()
	]]
end
function Component:GetTargetActor()
	return self:GetEntity()
end
function Component:SetHMD(hmd)
	util.remove(self.m_cbHmdInteractionStateChanged)
	self.m_hmd = hmd
	self.m_wasPov = false
	self.m_prePovPose = nil

	local tdC = hmd:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	if tdC ~= nil then
		self.m_cbHmdInteractionStateChanged = tdC:AddEventCallback(
			ents.VRTrackedDevice.EVENT_ON_USER_INTERACTION_STATE_CHANGED,
			function()
				self:UpdateAvailability()
			end
		)
	end
	self:UpdateAvailability()
end
function Component:UpdateAvailability()
	local tdC = util.is_valid(self.m_hmd) and self.m_hmd:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE) or nil
	if tdC ~= nil then
		local active = tdC:GetUserInteractionState() == ents.VRTrackedDevice.USER_INTERACTION_ACTIVE
		if self:IsActive() ~= active then
			self:SetActive(active)
		else
			self:OnActivate()
		end
	end
	self:BroadcastEvent(Component.EVENT_ON_UPDATE_AVAILABILITY)
end
function Component:GetHMD()
	return self.m_hmd
end
function Component:SetCamera(cam)
	self.m_camera = cam
end
function Component:GetCamera()
	return self.m_camera
end
function Component:Clear()
	if self.m_ownedIkSolver then
		self:GetEntity():RemoveComponent(ents.COMPONENT_IK_SOLVER)
	end
	self.m_ownedIkSolver = nil
	self.m_headIkControlIdx = nil
	self.m_leftHandIkControlIdx = nil
	self.m_rightHandIkControlIdx = nil
	self.m_targetActorHeadData = nil
	self.m_curHeadVisibility = nil
	util.remove(self.m_cbUpdateHmdPose)
	util.remove(self.m_cbOnAnimationsUpdated)
end
function Component:ResetPose()
	local ent = self:GetEntity()
	local ikC = ent:GetComponent(ents.COMPONENT_IK_SOLVER)
	-- We want to reset to the base animation pose without IK, so we temporarily disable it
	if ikC ~= nil then
		ikC:SetAutoSimulate(false)
	end
	local animC = ent:GetComponent(ents.COMPONENT_ANIMATED)
	if animC ~= nil then
		animC:ResetPose()
	end
	if ikC ~= nil then
		ikC:SetAutoSimulate(true)
	end
end
function Component:OnDeactivate()
	self:UpdateHeadVisibility()
	self:ResetPose()
	self:SetMetaBonesAnimated(false)
	self:Clear()
end
local BONE_ZERO_SCALE = Vector(0.0001, 0.0001, 0.0001) -- Not quite zero, since that can cause some odd graphical glitches in some cases
function Component:OnActiveStateChanged(active)
	if active then
		self:OnActivate()
	else
		self:OnDeactivate()
	end
end
function Component:OnActivate()
	self:Clear()
	local ent = self:GetEntity()
	local ikC = ent:GetComponent(ents.COMPONENT_IK_SOLVER)
	self.m_ownedIkSolver = false
	if ikC == nil then
		ikC = ent:AddComponent(ents.COMPONENT_IK_SOLVER)
		self.m_ownedIkSolver = true
		if ikC == nil then
			return
		end
		ikC:SetMultiThreaded(true)
	end

	-- We'll disable the swing-limit of the head control because it restricts head movement with the HMD
	-- too much.
	util.remove(self.m_cbOnRigInitialized)
	local mdl = ent:GetModel()
	local metaRig = (mdl ~= nil) and mdl:GetMetaRig() or nil
	if metaRig ~= nil then
		local metaBoneHead = metaRig:GetBone(Model.MetaRig.BONE_TYPE_HEAD)
		if metaBoneHead ~= nil then
			local skel = mdl:GetSkeleton()
			local bone = skel:GetBone(metaBoneHead.boneId)
			if bone ~= nil then
				local headBoneName = bone:GetName()
				self.m_cbOnRigInitialized = ikC:AddEventCallback(
					ents.IkSolverComponent.EVENT_ON_IK_RIG_INITIALIZED,
					function()
						local ikSolver = ikC:GetIkSolver()
						local numJoints = ikSolver:GetJointCount()
						for i = 0, numJoints - 1 do
							local joint = ikSolver:GetJoint(i)
							local bone1 = joint:GetConnectionB()
							if
								bone1 ~= nil
								and joint:GetType() == ik.Joint.TYPE_SWING_LIMIT
								and bone1:GetName() == headBoneName
							then
								joint:SetEnabled(false)
							end
						end
					end
				)
			end
		end
	end
	--

	self:ResetPose()
	self:SetMetaBonesAnimated(true)

	if self.m_ownedIkSolver then
		if rig == nil then
			engine.load_library("pr_rig")
		end
		if rig ~= nil then
			local ikRigData, ikRigPath = rig.generate_cached_ik_rig(mdl)
			if ikRigPath ~= nil then
				ikRigPath = file.to_relative_path(ikRigPath)
				ikRigPath = file.make_relative(ikRigPath, rig.get_ik_rig_base_path())
				ikC:SetMemberValue("rigConfigFile", ikRigPath)
			end
		end
	end
	if metaRig == nil then
		self:LogWarn("Model '" .. mdl:GetName() .. "' has no meta-rig!")
	else
		local function getIkControlIdx(metaBoneId, propName)
			propName = propName or "pose"
			local metaBone = metaRig:GetBone(metaBoneId)
			if metaBone ~= nil then
				local skel = mdl:GetSkeleton()
				local bone = skel:GetBone(metaBone.boneId)
				local memberPath = "control/" .. bone:GetName() .. "/" .. propName
				local memberIdx = ikC:GetMemberIndex(memberPath)
				if memberIdx ~= nil then
					return memberIdx
				else
					self:LogWarn("Member '" .. memberPath .. "' does not exist!")
				end
			end
		end
		self.m_headIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_HEAD)
		self.m_leftHandIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_LEFT_HAND)
		self.m_rightHandIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_RIGHT_HAND)

		for i = Model.MetaRig.BONE_TYPE_SPINE3, Model.MetaRig.BONE_TYPE_SPINE, -1 do
			local metaBone = metaRig:GetBone(i)
			if metaBone ~= nil then
				self.m_spineMetaBoneId = i
				break
			end
		end
		self.m_leftForearmIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_LEFT_LOWER_ARM, "position")
		self.m_rightForearmIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_RIGHT_LOWER_ARM, "position")

		local realTimeSolver = false
		ikC:SetResetSolver(not realTimeSolver)
		local function getMetaRigSkeletalBone(metaBoneId)
			local metaBone = metaRig:GetBone(metaBoneId)
			if metaBone == nil then
				return
			end
			local skel = mdl:GetSkeleton()
			local bone = (skel ~= nil) and skel:GetBone(metaBone.boneId) or nil
			if bone == nil then
				return
			end
			return bone
		end
		-- We need to enable some IK controls that are disabled by default
		local boneHead = getMetaRigSkeletalBone(Model.MetaRig.BONE_TYPE_HEAD)
		if boneHead ~= nil then
			ikC:SetMemberValue("control/" .. boneHead:GetName() .. "/strength", 4.0)
		end

		if realTimeSolver then
			local boneLeftForearm = getMetaRigSkeletalBone(Model.MetaRig.BONE_TYPE_LEFT_LOWER_ARM)
			-- Pole targets don't behave properly in real-time IK, so we'll disable them for now.
			-- TODO: Figure out what's causing it.
			if boneLeftForearm ~= nil then
				ikC:SetMemberValue("control/" .. boneLeftForearm:GetName() .. "/strength", 0.0)
			end

			local boneRightForearm = getMetaRigSkeletalBone(Model.MetaRig.BONE_TYPE_RIGHT_LOWER_ARM)
			if boneRightForearm ~= nil then
				ikC:SetMemberValue("control/" .. boneRightForearm:GetName() .. "/strength", 0.0)
			end
		end

		local ikSolver = ikC:GetIkSolver()
		ikC:Flush()
		local skel = mdl:GetSkeleton()
		local entRef = self:GetTargetActor()
		local animC = util.is_valid(entRef) and entRef:GetComponent(ents.COMPONENT_ANIMATED) or nil
		if animC ~= nil and ikSolver ~= nil then
			local n = ikSolver:GetControlCount()
			for i = 0, n - 1 do
				local ctrl = ikSolver:GetControl(i)
				local bone = ctrl:GetTargetBone()
				local boneName = bone:GetName()
				local boneId = skel:LookupBone(boneName)
				if boneId ~= -1 then
					local metaBoneId = metaRig:FindMetaBoneType(boneId)
					if metaBoneId ~= nil then
						local pose = animC:GetMetaBonePose(metaBoneId, math.COORDINATE_SPACE_OBJECT)
						if pose ~= nil then
							if ctrl:GetType() == util.IkRigConfig.Control.TYPE_POLE_TARGET then
								-- Move the pole targets to pre-determined locations (relative to the bone)
								-- for more realistic character movements
								local pos
								if
									metaBoneId == Model.MetaRig.BONE_TYPE_LEFT_LOWER_ARM
									or metaBoneId == Model.MetaRig.BONE_TYPE_RIGHT_LOWER_ARM
								then
									local xFactor = 1.0
									if metaBoneId == Model.MetaRig.BONE_TYPE_RIGHT_LOWER_ARM then
										xFactor = -1.0
									end
									local offset = Vector(20.0 * xFactor, -15.0, -10.0) * metaRig:GetReferenceScale()
									pos = pose:GetOrigin() + offset
								elseif
									metaBoneId == Model.MetaRig.BONE_TYPE_LEFT_LOWER_LEG
									or metaBoneId == Model.MetaRig.BONE_TYPE_RIGHT_LOWER_LEG
								then
									local offset = (pose:GetUp() * 20.0 - pose:GetForward() * 20.0)
										* metaRig:GetReferenceScale()
									pos = pose:GetOrigin() + offset
								end
								if pos ~= nil then
									ikC:SetMemberValue("control/" .. boneName .. "/position", pos)
								end
							else
								ikC:SetMemberValue("control/" .. boneName .. "/position", pose:GetOrigin())
								ikC:SetMemberValue("control/" .. boneName .. "/rotation", pose:GetRotation())
							end

							local ikBoneId = ikC:GetIkBoneId(boneId)
							if ikBoneId ~= nil then
								local bone = ikSolver:GetBone(ikBoneId)
								bone:SetPos(pose:GetOrigin())
								bone:SetRot(pose:GetRotation())
							end
						end
					end
				end
			end
		end

		if animC ~= nil then
			-- The character's head may have an initial pitch and/or roll angle,
			-- but the VR reference pose should always be on the horizontal plane, so we
			-- calculate an offset rotation to compensate.
			local pose = animC:GetMetaBonePose(Model.MetaRig.BONE_TYPE_HEAD, math.COORDINATE_SPACE_OBJECT)
			local ang = pose:GetRotation():ToEulerAngles()
			ang.y = 0.0
			self.m_hmdOffsetPose = math.Transform(Vector(), ang:ToQuaternion():GetInverse())
		else
			self.m_hmdOffsetPose = math.Transform()
		end

		local lowerBodyEnabled = not self:IsUpperBodyOnly()
		local lowerBodyMetaIds = Model.MetaRig.get_meta_rig_bone_ids(Model.MetaRig.BODY_PART_LOWER_BODY)
		for _, metaId in ipairs(lowerBodyMetaIds) do
			local bone = getMetaRigSkeletalBone(metaId)
			if bone ~= nil then
				if metaId == Model.MetaRig.BONE_TYPE_HIPS then
					ikC:SetBoneLocked(bone:GetID(), not lowerBodyEnabled)
				else
					ikC:SetBoneEnabled(bone:GetID(), lowerBodyEnabled)
				end
			end
		end
	end

	self.m_targetActorHeadData = {}
	self.m_curHeadVisibility = nil
	local target = self:GetTargetActor()
	if util.is_valid(target) then
		local panimaC = target:GetComponent(ents.COMPONENT_PANIMA)
		if panimaC ~= nil then
			self.m_cbOnAnimationsUpdated = panimaC:AddEventCallback(
				ents.PanimaComponent.EVENT_ON_ANIMATIONS_UPDATED,
				function()
					self:UpdateHeadIkControl()
					self:UpdateHeadVisibility()
					-- self:UpdateForearmControls()
				end
			)
		end

		local headhackC = target:GetComponent(ents.COMPONENT_VRP_HEADHACK)
		if headhackC ~= nil then
			self.m_targetActorHeadData.headEntity = headhackC:GetHeadEntity()
		else
			local mdl = target:GetModel()
			local metaRig = (mdl ~= nil) and mdl:GetMetaRig() or nil
			if metaRig ~= nil then
				local metaBoneHead = metaRig:GetBone(Model.MetaRig.BONE_TYPE_HEAD)
				local metaBoneNeck = metaRig:GetBone(Model.MetaRig.BONE_TYPE_NECK)
				self.m_targetActorHeadData = {
					headBoneId = (metaBoneHead ~= nil) and metaBoneHead.boneId or nil,
					neckBoneId = (metaBoneNeck ~= nil) and metaBoneNeck.boneId or nil,
				}
			end
		end
	else
		self:LogWarn("No target actor has been set!")
	end

	local entHmd = self:GetHMD()
	if util.is_valid(entHmd) then
		local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
		if hmdC ~= nil then
			util.remove(self.m_cbUpdateHmdPose)
			self.m_cbUpdateHmdPose = hmdC:AddEventCallback(ents.VRHMD.EVENT_UPDATE_HMD_POSE, function(hmdPoseData)
				self:UpdateHmdPose(hmdPoseData)
				return util.EVENT_REPLY_HANDLED
			end)
		end
	else
		self:LogWarn("No HMD has been set!")
	end
end
function Component:GetIkControllerIndices()
	local indices = {}
	if self.m_headIkControlIdx ~= nil then
		table.insert(indices, self.m_headIkControlIdx)
	end
	if self.m_leftHandIkControlIdx ~= nil then
		table.insert(indices, self.m_leftHandIkControlIdx)
	end
	if self.m_rightHandIkControlIdx ~= nil then
		table.insert(indices, self.m_rightHandIkControlIdx)
	end
	if self.m_leftForearmIkControlIdx ~= nil then
		table.insert(indices, self.m_leftForearmIkControlIdx)
	end
	if self.m_rightForearmIkControlIdx ~= nil then
		table.insert(indices, self.m_rightForearmIkControlIdx)
	end
	return indices
end
function Component:GetHeadIkControlIndex()
	return self.m_headIkControlIdx
end
function Component:GetLeftHandIkControlIndex()
	return self.m_leftHandIkControlIdx
end
function Component:GetRightHandIkControlIndex()
	return self.m_rightHandIkControlIdx
end
function Component:GetLeftForearmIkControlIndex()
	return self.m_leftForearmIkControlIdx
end
function Component:GetRightForearmIkControlIndex()
	return self.m_rightForearmIkControlIdx
end
function Component:UpdateUpperBodyState() end
function Component:UpdateHeadVisibilityState() end
function Component:OnEntitySpawn()
	-- We'll apply an offset to the HMD pose, which will make the IK pose match the real-world pose
	-- more closely.
	local offset = self:CalcHmdOffset()
	self.m_hmdCameraOffsetPose = math.Transform(offset, Quaternion())
end
function Component:OnRemove()
	util.remove(self.m_cbOnRigInitialized)
	util.remove(self.m_cbHmdInteractionStateChanged)
end
function Component:UpdatePovState()
	if self:IsPov() == false and self.m_prePovPose ~= nil then
		local entHmd = self:GetHMD()
		if util.is_valid(entHmd) then
			entHmd:SetPose(self.m_prePovPose)
		end
		local entCam = self:GetCamera()
		if util.is_valid(entCam) then
			entCam:SetPose(self.m_prePovPose)
		end
		self.m_prePovPose = nil
		self.m_wasPov = false
	end
end
function Component:SetPovCamera(cc)
	self:SetCamera(cc)
end
function Component:GetHeadBoneId()
	local ent = self:GetEntity()
	local mdl = ent:GetModel()
	local metaRig = (mdl ~= nil) and mdl:GetMetaRig() or nil
	if metaRig == nil then
		return
	end
	local headBone = metaRig:GetBone(Model.MetaRig.BONE_TYPE_HEAD)
	if headBone == nil then
		return
	end
	return headBone.boneId
end
function Component:ResetIk()
	-- TODO
end
-- Makes the head bone (and its parents) animated to avoid an IK feedback loop
function Component:SetMetaBonesAnimated(animated)
	local entRef = self:GetTargetActor()
	local mdl = util.is_valid(entRef) and entRef:GetModel() or nil
	if mdl == nil then
		self:LogWarn("Unable to make meta-bones animated: Entity has no model!")
		return
	end
	local metaRig = mdl:GetMetaRig()
	if metaRig == nil then
		self:LogWarn("Unable to make meta-bones animated: Model '" .. mdl:GetName() .. "' has no meta-rig!")
		return
	end
	--local metaBoneId = Model.MetaRig.BONE_TYPE_HEAD
	--local metaBone = metaRig:GetBone(metaBoneId)
	local ikC = self:GetEntity():GetComponent(ents.COMPONENT_IK_SOLVER)
	if ikC == nil then
		self:LogWarn("Unable to make meta-bones animated: Entity has no ik-solver component!")
		return
	end
	local boneIds = {}
	local ikSolver = ikC:GetIkSolver()
	local n = ikSolver:GetBoneCount()
	local skel = mdl:GetSkeleton()
	for i = 0, n - 1 do
		local bone = ikSolver:GetBone(i)
		local boneName = bone:GetName()
		local boneId = skel:LookupBone(boneName)
		table.insert(boneIds, boneId)
	end
	--[[while metaBone ~= nil do
		table.insert(boneIds, metaBone.boneId)
		metaBoneId = mdl:GetMetaRigBoneParentId(metaBoneId)
		metaBone = (metaBoneId ~= nil) and metaRig:GetBone(metaBoneId) or nil
	end]]

	local animC = entRef:GetComponent(ents.COMPONENT_ANIMATED)
	if animC == nil then
		self:LogWarn("Unable to make meta-bones animated: Entity has no animated component!")
		return
	end

	entRef:AddComponent(ents.COMPONENT_PANIMA)
	local skel = mdl:GetSkeleton()
	for _, boneId in ipairs(boneIds) do
		local bone = skel:GetBone(boneId)
		if bone ~= nil then
			local boneName = bone:GetName()
			-- Just take the current bone pose and make it animated
			if animated then
				animC:SetPropertyAnimated("bone/" .. boneName .. "/position", animated)
				animC:SetPropertyAnimated("bone/" .. boneName .. "/rotation", animated)
			end
		end
	end
end
-- The default meta-bone pose for the hands makes the palm face downwards, with the hand point forward along the z-axis.
-- However, the default pose when holding a VR controller has the palm face sideways. We have to rotate by 90 degrees to adjust.
local HMD_TO_IK_POSE_OFFSET_LEFT_HAND = math.Transform(Vector(2, -3.5, -2.5), EulerAngles(0, 0, -90))
local HMD_TO_IK_POSE_OFFSET_RIGHT_HAND = math.Transform(Vector(-2, -3.5, -2.5), EulerAngles(0, 0, 90))

local HMD_TO_IK_POSE_OFFSET_LEFT_HAND_INV = HMD_TO_IK_POSE_OFFSET_LEFT_HAND:GetInverse()
local HMD_TO_IK_POSE_OFFSET_RIGHT_HAND_INV = HMD_TO_IK_POSE_OFFSET_RIGHT_HAND:GetInverse()

-- Moves the HMD to the post-IK head location
function Component:UpdateHmdPose(hmdPoseData)
	local entHmd = self:GetHMD()
	if util.is_valid(entHmd) == false then
		return
	end
	local headPose = self:GetHeadPose()
	if headPose == nil then
		return
	end
	self.m_prevHmdHeadPose = headPose
	local entPose = self:GetEntity():GetPose()
	headPose = entPose * headPose

	local entCam = self:GetCamera()
	if self.m_wasPov == false and self:IsPov() then
		self.m_wasPov = true
		if util.is_valid(entCam) then
			self.m_prePovPose = entCam:GetPose()
		end
	end
	entHmd:SetPose(math.Transform(headPose) * self.m_hmdCameraOffsetPose)

	local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
	if hmdC ~= nil then
		local leftController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_LEFT_HAND)[1]
		if util.is_valid(leftController) then
			local pose = self:GetMetaBonePose(Model.MetaRig.BONE_TYPE_LEFT_HAND)
			pose = pose * HMD_TO_IK_POSE_OFFSET_LEFT_HAND_INV
			leftController:GetEntity():SetPose(math.Transform(entPose * pose))
		end

		local rightController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_RIGHT_HAND)[1]
		if util.is_valid(rightController) then
			local pose = self:GetMetaBonePose(Model.MetaRig.BONE_TYPE_RIGHT_HAND)
			pose = pose * HMD_TO_IK_POSE_OFFSET_RIGHT_HAND_INV
			rightController:GetEntity():SetPose(math.Transform(entPose * pose))
		end
	end

	if self:IsPov() then
		if util.is_valid(entCam) then
			entCam:SetPose(math.Transform(headPose))
		end
	else
		hmdPoseData.cameraPose = entCam:GetPose()
	end
end
function Component:GetMetaBonePose(metaBoneId)
	local entRef = self:GetTargetActor()
	local animC = util.is_valid(entRef) and entRef:GetComponent(ents.COMPONENT_ANIMATED) or nil
	if animC == nil then
		return
	end
	local propPose = animC:GetMetaBonePose(metaBoneId, math.COORDINATE_SPACE_OBJECT)
	return propPose
end
function Component:CalcHmdOffset()
	local entRef = self:GetTargetActor()
	local mdl = util.is_valid(entRef) and entRef:GetModel() or nil
	if mdl == nil then
		return Vector()
	end
	local ref = mdl:GetReferencePose()
	local eyeballs = mdl:GetEyeballs()
	local eyeballPositions = {}
	for _, eyeball in ipairs(eyeballs) do
		local boneIndex = eyeball.boneIndex
		local pose = ref:GetBonePose(boneIndex)
		if pose ~= nil then
			pose:TranslateLocal(eyeball.origin)
			table.insert(eyeballPositions, pose:GetOrigin())
		end
	end
	if #eyeballPositions > 0 then
		local pos = vector.calc_average(eyeballPositions)
		local headPose = mdl:GetMetaRigReferencePose(Model.MetaRig.BONE_TYPE_HEAD)
		pos = headPose:GetInverse() * pos
		return pos
	end
	local metaRig = mdl:GetMetaRig()
	local metaHeadBone = metaRig:GetBone(Model.MetaRig.BONE_TYPE_HEAD)
	local offset = (metaHeadBone.min + metaHeadBone.max) / 2.0
	offset.z = metaHeadBone.max.z
	offset.x = 0
	return offset
end
-- Animated head pose in object space
function Component:GetHeadPose()
	return self:GetMetaBonePose(Model.MetaRig.BONE_TYPE_HEAD)
end
-- HMD moves relative to animated head pose.
-- The return value is the desired HMD pose in object space.
function Component:CalculateDesiredHMDPose()
	local entHmd = self:GetHMD()
	if util.is_valid(entHmd) == false then
		return
	end
	local headPose = self:GetHeadPose()
	local tdC = entHmd:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	if tdC == nil or headPose == nil then
		return
	end
	local hmdPose = tdC:GetDevicePose()
	headPose:SetRotation(self.m_hmdOffsetPose:GetRotation() * headPose:GetRotation())
	return headPose * hmdPose, headPose
end
-- Attempts to move the head towards the desired HMD pose using IK
function Component:UpdateHeadIkControl()
	local hmdPose, refPose = self:CalculateDesiredHMDPose()
	local entRef = self:GetTargetActor()
	local ikC = util.is_valid(entRef) and entRef:GetComponent(ents.COMPONENT_IK_SOLVER) or nil
	if hmdPose == nil or ikC == nil then
		return
	end
	if self.m_headIkControlIdx == nil then
		return
	end
	ikC:SetDirty()

	ikC:SetTransformMemberPose(self.m_headIkControlIdx, math.COORDINATE_SPACE_OBJECT, hmdPose)

	-- For our POV perspective, we'll use the character's head as the VR camera view, instead of the actual HMD position.
	-- As long as the HMD is within the IK bounds, they should be the same, but if the HMD is moved too far away from the IK,
	-- they may differ (because the IK cannot reach the position).
	-- This creates a problem: The non-HMD tracked devices should be relative to the camera view, i.e. the character's head.
	-- However, we cannot know the final position of the character's head before the IK has been simulated, which means we have to update
	-- the tracked device poses *after* the IK simulation.
	-- Unfortunately the IK hands are also controlled by tracked devices, which means they have to be updated *before* the IK simulation.
	-- There are two options:
	-- 1) Use the position of the character's head from the previous frame.
	-- 2) Use the actual HMD position, and not the character's head, as the reference point for the hands.
	-- Both solutions result in a mismatched placements of the hands relative to the head.
	-- We use solution 1) with some pose predicting to try and reduce the error.
	local entHmd = self:GetHMD()
	local hmdC = util.is_valid(entHmd) and entHmd:GetComponent(ents.COMPONENT_VR_HMD) or nil
	if hmdC ~= nil then
		-- local hmdRefPose = self.m_prevHmdHeadPose or self:GetHeadPose()
		-- TODO: Apply pose predicting
		local leftController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_LEFT_HAND)[1]
		if util.is_valid(leftController) and self.m_leftHandIkControlIdx ~= nil then
			local controllerPose = refPose * math.ScaledTransform(leftController:GetDevicePose())
			controllerPose = controllerPose * HMD_TO_IK_POSE_OFFSET_LEFT_HAND
			ikC:SetTransformMemberPose(self.m_leftHandIkControlIdx, math.COORDINATE_SPACE_OBJECT, controllerPose)
		end

		local rightController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_RIGHT_HAND)[1]
		if util.is_valid(rightController) and self.m_rightHandIkControlIdx ~= nil then
			local controllerPose = refPose * math.ScaledTransform(rightController:GetDevicePose())
			controllerPose = controllerPose * HMD_TO_IK_POSE_OFFSET_RIGHT_HAND
			ikC:SetTransformMemberPose(self.m_rightHandIkControlIdx, math.COORDINATE_SPACE_OBJECT, controllerPose)
		end
	end
end
function Component:UpdateHeadVisibility()
	if self.m_targetActorHeadData == nil then
		return
	end

	local showHead = not (self:IsActive() and self:IsPov() and not self:GetShowHead())
	if showHead == self.m_curHeadVisibility then
		return
	end
	self.m_curHeadVisibility = showHead

	local entHead = self.m_targetActorHeadData.headEntity
	if entHead ~= nil then
		if entHead:IsValid() then
			local renderC = entHead:GetComponent(ents.COMPONENT_RENDER)
			if renderC ~= nil then
				renderC:SetVisible(showHead)
			end
		end
		return
	end

	local entRef = self:GetTargetActor()
	local scale = (not showHead) and BONE_ZERO_SCALE or Vector(1, 1, 1)
	local animC = util.is_valid(entRef) and entRef:GetComponent(ents.COMPONENT_ANIMATED) or nil
	if animC == nil then
		return
	end
	local boneIds = { self.m_targetActorHeadData.headBoneId, self.m_targetActorHeadData.neckBoneId }
	for _, boneId in ipairs(boneIds) do
		animC:SetBoneScale(boneId, scale)
	end
end
ents.register_component("vr_pov_controller", Component, "vr")
Component.EVENT_ON_UPDATE_AVAILABILITY =
	ents.register_component_event(ents.COMPONENT_VR_POV_CONTROLLER, "on_update_availability")
