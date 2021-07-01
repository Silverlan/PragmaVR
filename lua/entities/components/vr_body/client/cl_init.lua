--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VrBody",BaseEntityComponent)

function ents.VrBody:__init()
	BaseEntityComponent.__init(self)
end

function ents.VrBody:Initialize()
	BaseEntityComponent.Initialize(self)

	local vrIkC = self:AddEntityComponent("vr_ik")
	--[[vrIkC:AddEventCallback(ents.VrIk.EVENT_ON_IK_TREES_UPDATED,function()
		self:HideHeadBone()
	end)]]
	self.m_cbPreIkTreesUpdates = vrIkC:AddEventCallback(ents.VrIk.EVENT_PRE_IK_TREES_UPDATED,function()
		self:AdjustUpperBody()
	end)
end

function ents.VrBody:OnRemove()
	util.remove(self.m_povCamOnAvailabilityChangedCb)
	util.remove(self.m_cbPreIkTreesUpdates)
	util.remove(self.m_cbOnTrackedDeviceAdded)
	util.remove(self.m_cbOnTrackedDeviceActivated)
end

function ents.VrBody:OnEntitySpawn()
	--[[local mdlC = self:GetEntity():GetComponent(ents.COMPONENT_PFM_MODEL)
	if(mdlC == nil) then return end
	mdlC:SetAnimationFrozen(true)]] -- TODO: Remove this once the issue with ik on animated entities is fixed
end

function ents.VrBody:ResetIk()
	local vrIkC = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(vrIkC == nil) then return end
	vrIkC:ResetIkTree("upper_body")
	vrIkC:ResetIkTree("left_arm")
	vrIkC:ResetIkTree("right_arm")
end

function ents.VrBody:AdjustUpperBody()
	local ent = self:GetEntity()
	local vrIkC = ent:GetComponent(ents.COMPONENT_VR_IK)
	if(vrIkC == nil or util.is_valid(self.m_povCamera) == false) then return end
	-- By default the ik component will place the effector position of the upper_body (i.e. the head/neck)
	-- at the position of the tracked device (i.e. the HMD), which is usually the same as the position of the camera
	-- and the position of the head/neck bone of the character.
	-- The HMD/camera position may, however, have an offset relative to the head/neck bone of the character, which
	-- can cause a feedback loop:
	-- 1) The HMD is placed at the position of the head/neck bone, and then the offset is applied
	-- 2) The upper_body ik will move the neck/head bone to the offset position (since that is the effector target)
	-- 3) Go to step 1, which applies the offset to the already offset position, etc.
	-- For this reason, we'll ignore the tracked device position and set the effector position to always be at
	-- the exact position of the head/neck bone (after the animation has been applied, which resets the previous ik step).
	local animC = ent:GetAnimatedComponent()
	if(animC ~= nil) then
		local boneChain = vrIkC:GetIkControllerBoneChain("upper_body")
		if(boneChain ~= nil) then
			local effectorBoneId = boneChain[#boneChain]
			local pose = self.m_povCamera:CalcBaseCameraPose() -- animC:GetGlobalBonePose(effectorBoneId)
			if(pose ~= nil) then
				-- TODO: This is a bit of a mess, clean this up!
				local td = vrIkC:GetTrackedDevice("upper_body")
				local tdC = util.is_valid(td) and td:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE) or nil
				if(tdC ~= nil) then
					local rotStatic = self.m_povCamera:GetStaticRotation()
					if(rotStatic ~= nil) then pose:SetRotation(rotStatic) end
					-- Note: This will only work if the relative pose of the pov_camera only applies a position offset and no rotation offset

					pose:TranslateLocal(tdC:GetDevicePose():GetOrigin())

					-- We'll offset the effector by a few units upwards to account for the downwards head-movement (relative to the configured seated/standing reference position)
					-- when the player is looking down with the HMD (which would cause the effector position to be placed inside the body).
					local chain = vrIkC:GetIkControllerBoneChain("upper_body")
					local rootPose = animC:GetGlobalBonePose(chain[1])
					local n = pose:GetOrigin() -rootPose:GetOrigin()
					n:Normalize()
					pose:TranslateGlobal(n *5.0)
					vrIkC:SetEffectorPose("upper_body",pose)
				end
			end
		end
	end

	-- Note: Due to ik, the upper body can twist to the side in some cases,
	-- but we want it to stay straight. Since there are no ik constraints yet,
	-- we'll just reset the rotation around the y-axis by hand.
	-- TODO: Replace this with an ik constraint once available
	--[[local ikChain = vrIkC:GetIkControllerBoneChain("upper_body")
	local ikSolver = vrIkC:GetIkSolver("upper_body")
	if(ikSolver == nil) then return end
	for i=1,#ikChain do
		local pose = ikSolver:GetLocalTransform(i -1)
		pose:SetRotation(EulerAngles():ToQuaternion()) -- TODO: Only reset yaw
		ikSolver:SetLocalTransform(i -1,pose)
	end]]
end

function ents.VrBody:UpdateRelativeIkUpperBodyPose()
	-- pov_camera can have a relative pose that is added as an offset to the head bone, however
	-- we don't want that offset to affect our upper_body ik tree (because it would defeat the purpose of the offset).
	-- For this reason, we'll give the upper_body ik tree the inverse offset, effectively placing it at the exact location of the head bone.
	-- Obsolete; TODO: Remove this function!
	--[[local vrIk = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(util.is_valid(self.m_povCamera) == false or vrIk == nil) then return end
	local relPose = self.m_povCamera:GetRelativePose()
	vrIk:SetIkControllerPoseOffset("upper_body",relPose:GetInverse())]]
end

function ents.VrBody:HideHeadBone()
	if(self.m_headBone == nil) then return end
	local animC = self:GetEntity():GetComponent(ents.COMPONENT_ANIMATED)
	if(animC == nil) then return end
	animC:SetBoneScale(self.m_headBone,Vector(0,0,0))
	--self:AdjustUpperBody()
end

function ents.VrBody:SetPovCamera(cam)
	util.remove(self.m_povCamOnAvailabilityChangedCb)
	self.m_povCamera = cam
	local vrIkC = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(vrIkC ~= nil) then
		local enabled = true
		if(cam ~= nil) then enabled = cam:IsEnabled() end
		vrIkC:SetEnabled(enabled)
	end
	if(cam ~= nil) then
		self.m_povCamOnAvailabilityChangedCb = cam:AddEventCallback(ents.PovCamera.EVENT_ON_AVAILABILITY_CHANGED,function(enabled)
			local vrIkC = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
			if(vrIkC ~= nil) then vrIkC:SetEnabled(enabled) end
		end)
	end
	self:UpdateRelativeIkUpperBodyPose()
	self:UpdatePovCameraAvailability()
end

function ents.VrBody:SetHmd(hmd)
	util.remove(self.m_cbOnTrackedDeviceAdded)
	util.remove(self.m_cbOnTrackedDeviceActivated)
	self.m_hmdC = hmd
	self.m_cbOnTrackedDeviceAdded = hmd:AddEventCallback(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ADDED,function(trackedDevice)
		self:UpdateTrackedDevices()
	end)
	self.m_cbOnTrackedDeviceActivated = hmd:AddEventCallback(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATED,function(trackedDevice)
		self:UpdateTrackedDeviceVisibility()
	end)
	local tdC = hmd:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	if(tdC ~= nil) then
		tdC:AddEventCallback(ents.VRTrackedDevice.EVENT_ON_USER_INTERACTION_STATE_CHANGED,function(state)
			self:UpdatePovCameraAvailability()
		end)
	end
	self:UpdateTrackedDevices()
	self:UpdateTrackedDeviceVisibility()
	self:UpdatePovCameraAvailability()
end
function ents.VrBody:GetHmd() return self.m_hmdC end

function ents.VrBody:UpdatePovCameraAvailability()
	if(util.is_valid(self.m_povCamera) == false) then return end
	local enablePovCamera = true
	if(util.is_valid(self.m_hmdC)) then
		local tdC = self.m_hmdC:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		if(tdC ~= nil and tdC:IsUserInteractionActive() == false) then enablePovCamera = false end
	end
	self.m_povCamera:SetEnabled(enablePovCamera)
end

function ents.VrBody:UpdateTrackedDeviceVisibility()
	local vrIk = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(util.is_valid(self.m_hmdC) == false or vrIk == nil) then return end
	local primC = self.m_hmdC:GetPrimaryController()
	if(util.is_valid(primC)) then
		local renderC = primC:GetEntity():GetComponent(ents.COMPONENT_RENDER)
		if(renderC ~= nil) then renderC:SetRenderMode(ents.RenderComponent.RENDERMODE_NONE) end
	end

	local secC = self.m_hmdC:GetSecondaryController()
	if(util.is_valid(secC)) then
		local renderC = secC:GetEntity():GetComponent(ents.COMPONENT_RENDER)
		if(renderC ~= nil) then renderC:SetRenderMode(ents.RenderComponent.RENDERMODE_NONE) end
	end
end

function ents.VrBody:UpdateTrackedDevices()
	local vrIk = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(util.is_valid(self.m_hmdC) == false or vrIk == nil) then return end
	vrIk:SetIkControllerEnabled("left_arm",false)
	vrIk:SetIkControllerEnabled("right_arm",false)

	local trackedDevice = self.m_hmdC:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	if(trackedDevice ~= nil) then
		vrIk:LinkIkControllerToTrackedDevice("upper_body",self.m_hmdC)
		vrIk:SetIkControllerEnabled("upper_body",true)
		vrIk:SetIkControllerPriority("upper_body",10) -- Upper body has to be evaluated before the arms!

		local renderC = self.m_hmdC:GetEntity():GetComponent(ents.COMPONENT_RENDER)
		if(renderC ~= nil) then renderC:SetRenderMode(ents.RenderComponent.RENDERMODE_NONE) end
		self:UpdateRelativeIkUpperBodyPose()
	end

	local primC = self.m_hmdC:GetPrimaryController()
	if(util.is_valid(primC)) then
		local trackedDevice = primC:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		if(trackedDevice ~= nil) then
			vrIk:LinkIkControllerToTrackedDevice("right_arm",trackedDevice)
			vrIk:SetIkControllerEnabled("right_arm",true)
		end
	end

	local secC = self.m_hmdC:GetSecondaryController()
	if(util.is_valid(secC)) then
		local trackedDevice = secC:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		if(trackedDevice ~= nil) then
			vrIk:LinkIkControllerToTrackedDevice("left_arm",trackedDevice)
			vrIk:SetIkControllerEnabled("left_arm",true)
		end
	end
end

function ents.VrBody:SetLeftArm(boneChain)
	local vrIk = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(vrIk == nil) then return end

	vrIk:AddIkController("left_arm",boneChain,phys.Transform(Vector(),EulerAngles(-90,90,0):ToQuaternion()))
	vrIk:SetEffectorPos("left_arm",Vector(0,0,0))
	vrIk:SetIkControllerEnabled("left_arm",false)
end

function ents.VrBody:SetRightArm(boneChain)
	local vrIk = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(vrIk == nil) then return end

	vrIk:AddIkController("right_arm",boneChain,phys.Transform(Vector(),EulerAngles(90,-90,0):ToQuaternion()))
	vrIk:SetEffectorPos("right_arm",Vector(0,0,0))
	vrIk:SetIkControllerEnabled("right_arm",false)
end

function ents.VrBody:SetHeadBone(boneId)
	self.m_headBone = nil
	if(type(boneId) == "string") then
		local mdl = self:GetEntity():GetModel()
		if(mdl == nil) then return end
		boneId = mdl:LookupBone(boneId)
	end
	self.m_headBone = (boneId ~= -1) and boneId or nil
end

function ents.VrBody:GetHeadBoneId() return self.m_headBone end

function ents.VrBody:SetUpperBody(boneChain)
	local vrIk = self:GetEntity():GetComponent(ents.COMPONENT_VR_IK)
	if(vrIk == nil) then return end

	vrIk:AddIkController("upper_body",boneChain)
	vrIk:SetEffectorPos("upper_body",Vector(0,0,0))
	vrIk:SetIkControllerEnabled("upper_body",false)
end
ents.COMPONENT_VR_BODY = ents.register_component("vr_body",ents.VrBody)
