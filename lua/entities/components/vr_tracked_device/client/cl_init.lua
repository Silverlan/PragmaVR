--[[
    Copyright (C) 2019  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VRTrackedDevice",BaseEntityComponent)

ents.VRTrackedDevice.USER_INTERACTION_INACTIVE = 0
ents.VRTrackedDevice.USER_INTERACTION_ACTIVE = 1

function ents.VRTrackedDevice:__init()
	BaseEntityComponent.__init(self)
end

function ents.VRTrackedDevice:Initialize()
	self:GetEntity():TurnOff()
end

function ents.VRTrackedDevice:Setup(trackedDeviceIndex,type,typeIndex)
	self:SetTrackedDeviceIndex(trackedDeviceIndex)
	self:SetType(type)
	self:SetTypeIndex(typeIndex)
end

function ents.VRTrackedDevice:SetTrackedDeviceIndex(trackedDeviceIndex) self.m_trackedDeviceIndex = trackedDeviceIndex end
function ents.VRTrackedDevice:GetTrackedDeviceIndex() return self.m_trackedDeviceIndex or -1 end
function ents.VRTrackedDevice:SetType(type) self.m_type = type end
function ents.VRTrackedDevice:GetType() return self.m_type end
function ents.VRTrackedDevice:SetTypeIndex(idx) self.m_typeIndex = idx end
function ents.VRTrackedDevice:GetTypeIndex() return self.m_typeIndex end
function ents.VRTrackedDevice:IsController() return self.m_type == openvr.TRACKED_DEVICE_CLASS_CONTROLLER end
function ents.VRTrackedDevice:IsHMD() return self.m_type == openvr.TRACKED_DEVICE_CLASS_HMD end
function ents.VRTrackedDevice:IsUserInteractionActive() return self:GetUserInteractionState() == ents.VRTrackedDevice.USER_INTERACTION_ACTIVE end
function ents.VRTrackedDevice:GetUserInteractionState() return self.m_userInteractionState or ents.VRTrackedDevice.USER_INTERACTION_INACTIVE end
function ents.VRTrackedDevice:SetUserInteractionState(state)
	self.m_userInteractionState = state
	self:BroadcastEvent(ents.VRTrackedDevice.EVENT_ON_USER_INTERACTION_STATE_CHANGED,{state})
end
function ents.VRTrackedDevice:GetDevicePose()
	local trackedDeviceId = self:GetTrackedDeviceIndex()
	local pose,vel = openvr.get_pose(trackedDeviceId)
	if(pose == nil) then return end
	--local rot = pose:GetRotation()
	--local ang = rot:ToEulerAngles()
	--ang = EulerAngles(-ang.r,ang.y,ang.p)
	--ang.y = -ang.y
	--ang.p = -ang.p
	--ang.r = -ang.r
	--ang = EulerAngles(0,-ang.y,0)
	--pose:SetOrigin(Vector())
	--if(self:IsController() == false) then print(ang) end
	--if(self:IsController()) then print(ang) end
	--rot = ang:ToQuaternion()
	--pose:SetRotation(rot)
	--print(self:IsController(),pose)
	return pose,vel
end
ents.COMPONENT_VR_TRACKED_DEVICE = ents.register_component("vr_tracked_device",ents.VRTrackedDevice)
ents.VRTrackedDevice.EVENT_ON_USER_INTERACTION_STATE_CHANGED = ents.register_component_event(ents.COMPONENT_VR_TRACKED_DEVICE,"user_interaction_state_changed")
