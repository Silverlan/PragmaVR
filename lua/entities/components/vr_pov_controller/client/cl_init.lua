--[[
    Copyright (C) 2024 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

local Component = util.register_class("ents.VrPovController", BaseEntityComponent)
Component:RegisterMember("Enabled", udm.TYPE_BOOLEAN, true, {
	onChange = function(self)
		self:UpdateActiveState()
	end,
}, "def+is")
Component:RegisterMember("Pov", ents.MEMBER_TYPE_BOOLEAN, true, {
	onChange = function(self)
		self:UpdatePovState()
	end,
}, "def+is")
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
function Component:SetTargetActor(actor)
	self.m_targetActor = actor
end
function Component:GetTargetActor()
	return self.m_targetActor
end
function Component:SetHMD(hmd)
	self.m_hmd = hmd
	self.m_wasPov = false
	self.m_prePovPose = nil
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
function Component:UpdateActiveState()
	local enabled = self:GetEntity():IsSpawned() and self:IsEnabled()
	if enabled then
		self:Activate()
	else
		self:Deactivate()
	end
end
function Component:Clear()
	self.m_headIkControlIdx = nil
	self.m_leftHandIkControlIdx = nil
	self.m_rightHandIkControlIdx = nil
	self.m_targetActorHeadBones = nil
	util.remove(self.m_cbUpdateHmdPose)
	util.remove(self.m_cbOnAnimationsUpdated)
end
function Component:Deactivate()
	self:UpdateHeadBoneScales()
	self:SetMetaBonesAnimated(false)
	self:Clear()
end
local BONE_ZERO_SCALE = Vector(0.0001, 0.0001, 0.0001) -- Not quite zero, since that can cause some odd graphical glitches in some cases
function Component:Activate()
	self:Clear()
	self:SetMetaBonesAnimated(true)

	local ent = self:GetEntity()
	local mdl = ent:GetModel()
	local metaRig = (mdl ~= nil) and mdl:GetMetaRig() or nil
	local ikC = ent:GetComponent(ents.COMPONENT_IK_SOLVER)
	if ikC ~= nil and metaRig ~= nil then
		local function getIkControlIdx(metaBoneId)
			local metaBone = metaRig:GetBone(metaBoneId)
			if metaBone ~= nil then
				local skel = mdl:GetSkeleton()
				local bone = skel:GetBone(metaBone.boneId)
				local memberIdx = ikC:GetMemberIndex("control/" .. bone:GetName() .. "/pose")
				if memberIdx ~= nil then
					return memberIdx
				end
			end
		end
		self.m_headIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_HEAD)
		self.m_leftHandIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_LEFT_HAND)
		self.m_rightHandIkControlIdx = getIkControlIdx(Model.MetaRig.BONE_TYPE_RIGHT_HAND)

		ikC:SetResetSolver(false)
	end

	local animC = ent:GetComponent(ents.COMPONENT_ANIMATED)
	if animC ~= nil then
		animC:SetPostAnimationUpdateEnabled(true)
	end

	self.m_targetActorHeadBones = {}
	local target = self:GetTargetActor()
	if util.is_valid(target) then
		local panimaC = target:GetComponent(ents.COMPONENT_PANIMA)
		if panimaC ~= nil then
			self.m_cbOnAnimationsUpdated = panimaC:AddEventCallback(
				ents.PanimaComponent.EVENT_ON_ANIMATIONS_UPDATED,
				function()
					self:UpdateHeadIkControl()
					self:HideHeadBones()
				end
			)
		end

		local mdl = target:GetModel()
		local metaRig = (mdl ~= nil) and mdl:GetMetaRig() or nil
		if metaRig ~= nil then
			local metaBoneHead = metaRig:GetBone(Model.MetaRig.BONE_TYPE_HEAD)
			local metaBoneNeck = metaRig:GetBone(Model.MetaRig.BONE_TYPE_NECK)
			self.m_targetActorHeadBones = {
				headBoneId = (metaBoneHead ~= nil) and metaBoneHead.boneId or nil,
				neckBoneId = (metaBoneNeck ~= nil) and metaBoneNeck.boneId or nil,
			}
		end
	end

	local entHmd = self:GetHMD()
	if util.is_valid(entHmd) then
		local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
		if hmdC ~= nil then
			self.m_cbUpdateHmdPose = hmdC:AddEventCallback(ents.VRHMD.EVENT_UPDATE_HMD_POSE, function(hmdPoseData)
				self:UpdateHmdPose(hmdPoseData)
				return util.EVENT_REPLY_HANDLED
			end)
		end
	end
end
function Component:UpdateHeadBoneScales()
	if self.m_targetActorHeadBones == nil then
		return
	end
	local entRef = self:GetTargetActor()
	local scale = (self:IsEnabled() and self:IsPov()) and BONE_ZERO_SCALE or Vector(1, 1, 1)
	local animC = util.is_valid(entRef) and entRef:GetComponent(ents.COMPONENT_ANIMATED) or nil
	if animC == nil then
		return
	end
	local boneIds = { self.m_targetActorHeadBones.headBoneId, self.m_targetActorHeadBones.neckBoneId }
	for _, boneId in ipairs(boneIds) do
		animC:SetBoneScale(boneId, scale)
	end
end
function Component:OnEntitySpawn()
	self:UpdateActiveState()
end
function Component:OnRemove()
	self:Deactivate()
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
-- Makes the head bone (and its parents) animated to avoid an IK feedback loop
function Component:SetMetaBonesAnimated(animated)
	local entRef = self:GetTargetActor()
	local mdl = util.is_valid(entRef) and entRef:GetModel() or nil
	local metaRig = (mdl ~= nil) and mdl:GetMetaRig() or nil
	if metaRig == nil then
		return
	end
	local metaBoneId = Model.MetaRig.BONE_TYPE_HEAD
	local metaBone = metaRig:GetBone(metaBoneId)
	local boneIds = {}
	while metaBone ~= nil do
		table.insert(boneIds, metaBone.boneId)
		metaBoneId = mdl:GetMetaRigBoneParentId(metaBoneId)
		metaBone = (metaBoneId ~= nil) and metaRig:GetBone(metaBoneId) or nil
	end

	local animC = entRef:GetComponent(ents.COMPONENT_ANIMATED)
	if animC == nil then
		return
	end
	local skel = mdl:GetSkeleton()
	for _, boneId in ipairs(boneIds) do
		local bone = skel:GetBone(boneId)
		if bone ~= nil then
			local boneName = bone:GetName()
			local bonePose = mdl:GetReferenceBonePose(boneName, math.COORDINATE_SPACE_LOCAL)
			if bonePose ~= nil then
				-- Reset bone pose
				-- TODO: Unless they are already animated?
				animC:SetBonePose(boneName, bonePose)
			end
			animC:SetPropertyAnimated("bone/" .. boneName .. "/position", animated)
			animC:SetPropertyAnimated("bone/" .. boneName .. "/rotation", animated)
		end
	end
end
-- Moves the HMD to the post-IK head location
function Component:UpdateHmdPose(hmdPoseData)
	local entHmd = self:GetHMD()
	if util.is_valid(entHmd) == false then
		return
	end
	local pose = self:GetHeadPose()
	self.m_prevHmdHeadPose = pose
	pose = self:GetEntity():GetPose() * pose

	local entCam = self:GetCamera()
	if self.m_wasPov == false and self:IsPov() then
		self.m_wasPov = true
		if util.is_valid(entCam) then
			self.m_prePovPose = entCam:GetPose()
		end
	end
	entHmd:SetPose(pose)

	local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
	if hmdC ~= nil then
		local leftController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_LEFT_HAND)[1]
		if util.is_valid(leftController) then
			local pose = self:GetMetaBonePose(Model.MetaRig.BONE_TYPE_LEFT_HAND)
			leftController:GetEntity():SetPose(pose)
		end

		local rightController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_RIGHT_HAND)[1]
		if util.is_valid(rightController) then
			local pose = self:GetMetaBonePose(Model.MetaRig.BONE_TYPE_RIGHT_HAND)
			rightController:GetEntity():SetPose(pose)
		end
	end

	if self:IsPov() then
		if util.is_valid(entCam) then
			entCam:SetPose(pose)
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
			controllerPose:RotateLocal(EulerAngles(0, 0, -90):ToQuaternion()) -- TODO: Why do we need this?
			ikC:SetTransformMemberPose(self.m_leftHandIkControlIdx, math.COORDINATE_SPACE_OBJECT, controllerPose)
		end

		local rightController = hmdC:GetControllersByRole(openvr.TRACKED_CONTROLLER_ROLE_RIGHT_HAND)[1]
		if util.is_valid(rightController) and self.m_rightHandIkControlIdx ~= nil then
			local controllerPose = refPose * math.ScaledTransform(rightController:GetDevicePose())
			controllerPose:RotateLocal(EulerAngles(0, 0, 90):ToQuaternion()) -- TODO: Why do we need this?
			ikC:SetTransformMemberPose(self.m_rightHandIkControlIdx, math.COORDINATE_SPACE_OBJECT, controllerPose)
		end
	end
end
function Component:HideHeadBones()
	self:UpdateHeadBoneScales()
end
ents.COMPONENT_VR_POV_CONTROLLER = ents.register_component("vr_pov_controller", Component)
