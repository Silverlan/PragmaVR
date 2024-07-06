--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VRTrackedDevice", BaseEntityComponent)

ents.VRTrackedDevice.USER_INTERACTION_INACTIVE = 0
ents.VRTrackedDevice.USER_INTERACTION_ACTIVE = 1

local cvForceAlwaysActive = console.get_convar("vr_force_always_active")
function ents.VRTrackedDevice:Initialize()
	self:GetEntity():TurnOff()

	self.m_forceActive = false
	self:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_INACTIVE)
	self:SetForceActive(cvForceAlwaysActive:GetBool())
end

local cvShowRenderModels = console.get_convar("vr_show_rendermodels")
function ents.VRTrackedDevice:UpdateRenderModel()
	local showRenderModel = cvShowRenderModels:GetBool()
	if showRenderModel == false or self:GetEntity():IsSpawned() == false then
		util.remove(self.m_renderModel)
		self:GetEntity():RemoveComponent("debug_draw_axis")
		return
	end
	if not util.is_valid(self.m_hmdC) then
		return
	end
	self:GetEntity():AddComponent("debug_draw_axis")
	self:InitializeRenderModel()
end

function ents.VRTrackedDevice:UpdateRenderModelVisibility()
	if self:IsHMD() == false or util.is_valid(self.m_renderModel) == false then
		return
	end
	local show = (self:IsUserInteractionActive() == false)
	local renderC = self.m_renderModel:GetComponent(ents.COMPONENT_RENDER)
	if renderC ~= nil then
		renderC:SetSceneRenderPass(show and game.SCENE_RENDER_PASS_WORLD or game.SCENE_RENDER_PASS_NONE)
	end
end

local rotY90 = EulerAngles(0, 180, 0):ToQuaternion()
local rotP90 = EulerAngles(90, 0, 0):ToQuaternion()
function ents.VRTrackedDevice:InitializeRenderModel()
	if util.is_valid(self.m_renderModel) == false then
		local ent = ents.create("prop_dynamic")
		self.m_renderModel = ent
		ent:Spawn()
		if util.is_valid(self.m_renderModel) == false then
			return
		end
	end
	self.m_renderModel:SetModel(self:GetRenderModelName())
	-- TODO: The models themselves should be rotated to point forward along the +z axis
	-- so that this rotation offset is not needed
	local renderModelOffsetPose = math.Transform(Vector(), rotY90)
	if self:IsController() then
		-- Controller models need an additional rotation offset, reason unclear
		renderModelOffsetPose:RotateLocal(rotP90)
	end
	self.m_renderModel:SetPose(self:GetEntity():GetPose() * renderModelOffsetPose)
	self.m_renderModel:SetParent(self:GetEntity())
end

function ents.VRTrackedDevice:OnEntitySpawn()
	self:UpdateRenderModel()
end

function ents.VRTrackedDevice:OnRemove()
	util.remove(self.m_renderModel)
end

function ents.VRTrackedDevice:GetRenderModelEntity()
	return self.m_renderModel
end

function ents.VRTrackedDevice:GetRenderModelName()
	local mdlName = openvr.get_tracked_device_render_model_name(self:GetTrackedDeviceIndex())
	if mdlName ~= nil then
		mdlName = "vr/" .. mdlName
	end
	if mdlName == nil or asset.exists("vr/arrow", asset.TYPE_MODEL) == false then
		if self:IsHMD() then
			mdlName = "vr/generic_hmd"
		elseif self:IsController() then
			mdlName = "vr/generic_controller"
		else
			mdlName = "vr/generic_tracker"
		end
	end
	return mdlName
end

function ents.VRTrackedDevice:Setup(hmdC, trackedDeviceIndex, type, typeIndex)
	self.m_hmdC = hmdC
	self:SetTrackedDeviceIndex(trackedDeviceIndex)
	self:SetType(type)
	self:SetTypeIndex(typeIndex)
	self:UpdateUserInteractionState()

	self:UpdateRenderModel()
	self:GetEntity():SetParent(hmdC:GetEntity())
end
function ents.VRTrackedDevice:GetHMD()
	return self.m_hmdC
end
function ents.VRTrackedDevice:GetRole()
	return openvr.get_controller_role(self:GetTrackedDeviceIndex())
end
function ents.VRTrackedDevice:SetTrackedDeviceIndex(trackedDeviceIndex)
	self.m_trackedDeviceIndex = trackedDeviceIndex
end
function ents.VRTrackedDevice:GetTrackedDeviceIndex()
	return self.m_trackedDeviceIndex or -1
end
function ents.VRTrackedDevice:GetSerialNumber()
	return openvr.get_tracked_device_serial_number(self:GetTrackedDeviceIndex())
end
function ents.VRTrackedDevice:GetDeviceType()
	return openvr.get_tracked_device_type(self:GetTrackedDeviceIndex())
end
function ents.VRTrackedDevice:TriggerHapticPulse()
	return openvr.trigger_haptic_pulse(self:GetTrackedDeviceIndex(), 0, 1)
end
function ents.VRTrackedDevice:SetType(type)
	self.m_type = type
end
function ents.VRTrackedDevice:GetType()
	return self.m_type
end
function ents.VRTrackedDevice:SetTypeIndex(idx)
	self.m_typeIndex = idx
end
function ents.VRTrackedDevice:GetTypeIndex()
	return self.m_typeIndex
end
function ents.VRTrackedDevice:IsController()
	return self.m_type == openvr.TRACKED_DEVICE_CLASS_CONTROLLER
end
function ents.VRTrackedDevice:IsHMD()
	return self.m_type == openvr.TRACKED_DEVICE_CLASS_HMD
end
function ents.VRTrackedDevice:SetForceActive(forceActive)
	if forceActive == self.m_forceActive then
		return
	end
	self.m_forceActive = forceActive
	self:SetUserInteractionState(self.m_userInteractionState)
end
function ents.VRTrackedDevice:IsUserInteractionActive()
	return self:GetUserInteractionState() == ents.VRTrackedDevice.USER_INTERACTION_ACTIVE
end
function ents.VRTrackedDevice:GetUserInteractionState()
	if self.m_forceActive then
		return ents.VRTrackedDevice.USER_INTERACTION_ACTIVE
	end
	return self.m_userInteractionState or ents.VRTrackedDevice.USER_INTERACTION_INACTIVE
end
function ents.VRTrackedDevice:SetUserInteractionState(state)
	if state == self.m_userInteractionState then
		return
	end
	self.m_userInteractionState = state
	state = self.m_forceActive and ents.VRTrackedDevice.USER_INTERACTION_ACTIVE or state
	self:BroadcastEvent(ents.VRTrackedDevice.EVENT_ON_USER_INTERACTION_STATE_CHANGED, { state })

	self:UpdateRenderModelVisibility()
end
function ents.VRTrackedDevice:UpdateUserInteractionState()
	local idx = self:GetTrackedDeviceIndex()
	local level = openvr.get_tracked_device_activity_level(idx)
	if level == openvr.DEVICE_ACTIVITY_LEVEL_USER_INTERACTION then
		self:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_ACTIVE)
	elseif level == openvr.DEVICE_ACTIVITY_LEVEL_IDLE then
		self:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_INACTIVE)
	end
end
local cvDebugLines = console.get_convar("vr_debug_show_controller_location_pointers")
function ents.VRTrackedDevice:UpdatePose(basePose)
	local pose, vel = self:GetDevicePose()
	if pose == nil then
		return
	end

	--[[if self:GetEntity():IsClientsideOnly() == false then
		local packet = net.Packet()
		packet:WriteEntity(self:GetEntity())
		packet:WriteVector(pose:GetOrigin())
		packet:WriteVector(vel)
		packet:WriteQuaternion(pose:GetRotation())
		net.send(net.PROTOCOL_FAST_UNRELIABLE, "vr_controller_update_orientation", packet)
	end]]

	pose = basePose * pose
	self:GetEntity():SetPose(pose)

	if cvDebugLines:GetBool() then
		local owner = self:GetOwner()
		if util.is_valid(owner) then
			debug.draw_line(owner:GetPos() + owner:GetForward() * 20, self:GetEntity():GetPos(), Color.Yellow, 0.1)
		end
		debug.draw_line(self:GetEntity():GetPos(), self:GetEntity():GetPos() + Vector(0, 100, 0), Color.Aqua, 0.1)
	end
end

local frozenPoses
console.add_change_callback("vr_freeze_tracked_device_poses", function(old, new)
	if toboolean(new) == false then
		frozenPoses = nil
		return
	end
	frozenPoses = nil
	local r = {}
	for ent in ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_TRACKED_DEVICE) }) do
		local vrC = ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		local pose, vel = vrC:GetDevicePose()
		if pose ~= nil then
			r[vrC:GetTrackedDeviceIndex()] = { pose, vel }
		end
	end
	frozenPoses = r
end)

local cvLockHmdPos = console.get_convar("vr_lock_hmd_pos_to_camera")
local cvLockHmdAng = console.get_convar("vr_lock_hmd_ang_to_camera")
local cvUpdateTrackedDevicePoses = console.get_convar("vr_update_tracked_device_poses")
function ents.VRTrackedDevice:GetDevicePose()
	local trackedDeviceId = self:GetTrackedDeviceIndex()
	if frozenPoses ~= nil and frozenPoses[trackedDeviceId] ~= nil then
		return unpack(frozenPoses[trackedDeviceId])
	end
	if cvUpdateTrackedDevicePoses:GetBool() == false then
		return
	end
	local pose, vel = openvr.get_pose(trackedDeviceId)
	if pose == nil then
		return
	end
	if self:IsHMD() then
		if cvLockHmdPos:GetBool() then
			pose:SetOrigin(Vector())
		end
		if cvLockHmdAng:GetBool() then
			pose:SetRotation(Quaternion())
		end
	end
	if self:IsController() then
		-- We need to rotate 90 degree around the x axis, reason unclear
		pose:RotateLocal(rotP90)
	end
	return pose, vel
end
ents.COMPONENT_VR_TRACKED_DEVICE = ents.register_component("vr_tracked_device", ents.VRTrackedDevice)
ents.VRTrackedDevice.EVENT_ON_USER_INTERACTION_STATE_CHANGED =
	ents.register_component_event(ents.COMPONENT_VR_TRACKED_DEVICE, "user_interaction_state_changed")
