--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("../shared.lua")

ents.VRController.TRIGGER_STATE_RELEASE = 0
ents.VRController.TRIGGER_STATE_TOUCH = 1
ents.VRController.TRIGGER_STATE_PRESS = 2
function ents.VRController:UpdateTriggerState()
	local trackedDeviceC = self:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	if openvr == nil or trackedDeviceC == nil then
		return
	end
	local state = openvr.get_controller_state(trackedDeviceC:GetTrackedDeviceIndex())
	if state ~= nil then
		-- TODO: Implement this properly for all buttons / axes as generic key inputs
		local triggerAxis = state.axis1
		if triggerAxis.x >= 0.1 then
			if triggerAxis.x >= 0.8 then
				if self.m_triggerState ~= ents.VRController.TRIGGER_STATE_PRESS then
					self.m_triggerState = ents.VRController.TRIGGER_STATE_PRESS
					self:BroadcastEvent(self.EVENT_ON_TRIGGER_STATE_CHANGED, { self.m_triggerState })
				end
			else
				if self.m_triggerState ~= ents.VRController.TRIGGER_STATE_TOUCH then
					self.m_triggerState = ents.VRController.TRIGGER_STATE_TOUCH
					self:BroadcastEvent(self.EVENT_ON_TRIGGER_STATE_CHANGED, { self.m_triggerState })
				end
			end
		elseif self.m_triggerState ~= ents.VRController.TRIGGER_STATE_RELEASE then
			self.m_triggerState = ents.VRController.TRIGGER_STATE_RELEASE
			self:BroadcastEvent(self.EVENT_ON_TRIGGER_STATE_CHANGED, { self.m_triggerState })
		end
	end
end

function ents.VRController:InjectButtonInput(buttonId, state)
	self:BroadcastEvent(self.EVENT_ON_BUTTON_INPUT, { buttonId, state })
end

function ents.VRController:SetCursorEnabled(enabled)
	self.m_cursorEnabled = enabled

	-- TODO
end

function ents.VRController:IsControllerEnabled()
	return self.m_cursorEnabled or false
end

function ents.VRController:IsPrimaryController()
	local owner = self:GetEntity():GetOwner()
	local hmdC = util.is_valid(owner) and owner:GetComponent(ents.COMPONENT_VR_HMD) or nil
	if hmdC == nil then
		return
	end
	return util.is_same_object(hmdC:GetPrimaryController(), self)
end
function ents.VRController:IsSecondaryController()
	return not self:IsPrimaryController()
end

function ents.VRController:SetLaserEnabled(enabled)
	self.m_laserEnabled = enabled
	self:UpdateLaser()
end
function ents.VRController:IsLaserEnabled()
	return self.m_laserEnabled or false
end
function ents.VRController:UpdateLaser()
	if self:GetEntity():IsSpawned() == false then
		return
	end
	if self:IsLaserEnabled() == false then
		util.remove(self.m_laser)
		self:BroadcastEvent(self.EVENT_ON_LASER_DESTROYED)
		return
	end
	if util.is_valid(self.m_laser) then
		return
	end
	local entLaser = ents.create("vr_controller_laser")
	entLaser:Spawn()
	self.m_laser = entLaser

	local renderC = entLaser:GetComponent(ents.COMPONENT_RENDER)
	if renderC ~= nil then
		renderC:SetExemptFromOcclusionCulling(true)
		renderC:SetCastShadows(false)
	end

	self:BroadcastEvent(self.EVENT_ON_LASER_INITIALIZED, { entLaser })
end

function ents.VRController:GetLaser()
	return self.m_laser
end

function ents.VRController:OnEntitySpawn()
	self:UpdateLaser()
end

function ents.VRController:OnRemove()
	util.remove(self.m_laser)
end

local LASER_ROT_OFFSET = EulerAngles(-90 + 45, 0, 0):ToQuaternion()
function ents.VRController:GetLaserRaycastData()
	local ent = self:GetEntity()
	local pos = ent:GetPos()
	local rot = ent:GetRotation()
	rot = rot * LASER_ROT_OFFSET
	return ent:GetPos(), rot:GetForward()
end

function ents.VRController:Raycast()
	local pos, dir = self:GetLaserRaycastData()
	local maxDist = 32768
	return ents.ClickComponent.raycast(pos, dir, nil, maxDist)
end

function ents.VRController:OnTick(dt)
	if self.m_cursorEnabled and self.m_laserEnabled and util.is_valid(self.m_laser) then
		local owner = self:GetPlayerOwner()
		local charComponent = (owner ~= nil) and owner:GetComponent(ents.COMPONENT_CHARACTER) or nil
		if charComponent ~= nil then
			local pos, dir = self:GetLaserRaycastData()
			local posDst = pos + dir * 2048.0

			--[[local drawInfo = debug.DrawInfo()
			drawInfo:SetDuration(0.01)
			drawInfo:SetColor(Color.Red)
			debug.draw_line(pos, pos + dir * -1000, drawInfo)]]

			local srcPos = self:GetEntity():GetPos()
			self.m_laser:SetPos(srcPos)
			self.m_laser:SetRotation(self:GetEntity():GetRotation() * LASER_ROT_OFFSET)

			local hitActor, hitPos, startPos = self:Raycast()
			local l = 500
			if hitPos ~= nil then
				l = startPos:Distance(hitPos)
			end
			self.m_laser:SetScale(Vector(1, 1, l))

			self:BroadcastEvent(self.EVENT_UPDATE_LASER, { pos, dir })
			--[[local rayData = charComponent:GetAimRayData(1200.0)
			rayData:SetSource(pos)
			rayData:SetTarget(posDst)
			local ent = self:GetEntity()
			local renderC = ent:GetComponent(ents.COMPONENT_RENDER)
			local ray = phys.raycast(rayData)
			if(ray ~= false) then
				if(util.is_valid(self.m_laser)) then
					local srcPos = self:GetEntity():GetPos()
					self.m_laser:SetPos(srcPos)
					self.m_laser:SetRotation(self:GetEntity():GetRotation() *EulerAngles(0,180,0):ToQuaternion())
					local l = ray.position:Distance(srcPos)
					self.m_laser:SetScale(Vector(0,0,l))

					self:BroadcastEvent(self.EVENT_ON_LASER_HIT,{pos,-dir,ray})
				end
			end]]
		end
	end
end

ents.VRController.EVENT_ON_TRIGGER_STATE_CHANGED =
	ents.register_component_event(ents.COMPONENT_VR_CONTROLLER, "trigger_state_changed")
ents.VRController.EVENT_ON_LASER_INITIALIZED =
	ents.register_component_event(ents.COMPONENT_VR_CONTROLLER, "on_laser_initialized")
ents.VRController.EVENT_ON_LASER_DESTROYED =
	ents.register_component_event(ents.COMPONENT_VR_CONTROLLER, "on_laser_destroyed")
ents.VRController.EVENT_UPDATE_LASER = ents.register_component_event(ents.COMPONENT_VR_CONTROLLER, "update_laser")
ents.VRController.EVENT_ON_BUTTON_INPUT = ents.register_component_event(ents.COMPONENT_VR_CONTROLLER, "button_input")
