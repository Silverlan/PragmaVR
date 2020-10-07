--[[
    Copyright (C) 2019  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VRController",BaseEntityComponent)

if(CLIENT) then include_component("vr_tracked_device") end

function ents.VRController:__init()
	BaseEntityComponent.__init(self)
end

function ents.VRController:Initialize()
	local ent = self:GetEntity()
  self:AddEntityComponent(ents.COMPONENT_MODEL,"InitializeModel")
  self:AddEntityComponent(ents.COMPONENT_PHYSICS,"InitializePhysics")
  self:AddEntityComponent(ents.COMPONENT_TOUCH,"InitializeTouch")
  self:AddEntityComponent(ents.COMPONENT_OWNABLE)
  self:AddEntityComponent(ents.COMPONENT_RENDER)
  
  if(CLIENT == true) then
    self:AddEntityComponent(ents.COMPONENT_LOGIC,"InitializeLogic")
    self:AddEntityComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
  end
  
	self:BindEvent(ents.TouchComponent.EVENT_ON_START_TOUCH,"OnStartTouch")
	self:BindEvent(ents.TouchComponent.EVENT_CAN_TRIGGER,"CanTrigger")
  self:BindEvent(ents.OwnableComponent.EVENT_ON_OWNER_CHANGED,"OnOwnerChanged")
end

function ents.VRController:InitializeModel(component)
  if(component:GetModel() ~= nil) then return end
  component:SetModel("vr/vr_controller_vive_1_5.wmd")
end

function ents.VRController:OnOwnerChanged(oldOwner,newOwner)
  local physComponent = self:GetEntity():GetComponent(ents.COMPONENT_PHYSICS)
  if(physComponent == nil) then return end
  if(oldOwner ~= nil) then
    local physComponentOldOwner = oldOwner:GetComponent(ents.COMPONENT_PHYSICS)
    if(physComponentOldOwner ~= nil) then
      physComponent:ResetCollisions(physComponentOldOwner)
    end
  end
  if(newOwner ~= nil) then
    local physComponentNewOwner = newOwner:GetComponent(ents.COMPONENT_PHYSICS)
    if(physComponentNewOwner ~= nil) then
      physComponent:SetCollisionsEnabled(physComponentNewOwner,false)
    end
  end
end

function ents.VRController:InitializePhysics(component)
	if(SERVER or self:GetEntity():IsClientsideOnly()) then
		component:InitializePhysics(phys.TYPE_DYNAMIC)
	end
	component:SetCollisionCallbacksEnabled(true)
	local owner = self:GetEntity():GetOwner()
	if(owner ~= nil) then
		local physComponentOwner = owner:GetComponent(ents.COMPONENT_PHYSICS)
		if(physComponentOwner ~= nil) then
			component:SetCollisionsEnabled(physComponentOwner,false)
		end
	end
end

function ents.VRController:CanTrigger(phys) return true end

function ents.VRController:GetPlayerOwner()
	local owner = self:GetEntity():GetOwner()
	local hmdC = (owner ~= nil) and owner:GetComponent(ents.COMPONENT_VR_HMD) or nil
	if(hmdC == nil) then return end
	owner = hmdC:GetOwner()
	if(owner:HasComponent(ents.COMPONENT_PLAYER) == false) then return end
	return owner
end

function ents.VRController:SetControllerTransform(pos,rot,vel)
	local hmdOwner = self:GetEntity():GetOwner()
	local owner = self:GetPlayerOwner()
	local charComponentOwner = (owner ~= nil) and owner:GetComponent(ents.COMPONENT_CHARACTER) or nil
	local trComponentOwner = (owner ~= nil) and owner:GetComponent(ents.COMPONENT_TRANSFORM) or nil
	if(util.is_valid(hmdOwner) == false or charComponentOwner == nil or trComponentOwner == nil) then return end

	--pos,rot = util.local_to_world(trComponentOwner:GetEyePos(),charComponentOwner:GetViewRotation(),pos,rot)

	-- TODO: Clean this up
	--pos,rot = util.local_to_world(_vr_pos,_vr_rot,pos,rot)
	--local hmdPose = hmdOwner:GetReferencePose()
	local hmdC = hmdOwner:GetComponent(ents.COMPONENT_VR_HMD)
	if(hmdC == nil) then return end
	local hmdPose = hmdC:GetReferencePose()
	hmdPose = hmdPose:Copy()
	--hmdPose:SetRotation(Quaternion())
	--hmdPose:SetOrigin(Vector())--Vector(2.20439, 86.3184, -2.29969))

	local ent = ents.get_local_player():GetEntity():GetComponent(ents.COMPONENT_CHARACTER)
	--hmdPose:SetPosition(ent:GetViewRotation())
	--hmdPose:SetRotation(ent:GetShootPos()) -- TODO

	--pos = Vector(-pos.x,pos.y,-pos.z)---pos.x,pos.y,-pos.z)
	--print(pos)
	--pos.z = pos.z *2
	--pos = Vector(0,0,100)
	--pos.z = pos.z *10
--	pos:Rotate(EulerAngles(0,-90,0):ToQuaternion())

	local ang = rot:ToEulerAngles()

	--pos.x = -pos.x
	--pos.y = 0
	pos.z = pos.z -- -4
	--pos.x = -pos.x -- -2
	pos.y = pos.y -- -0.81
	rot = EulerAngles(0,180,0):ToQuaternion() *EulerAngles(-ang.p,ang.y,-ang.r):ToQuaternion()--ctrlPose:GetRotation()
	local ctrlPose = phys.Transform(pos,rot)
	--ctrlPose:SetOrigin(Vector(0,0,100))--_vr_rot:GetForward() *100)
	ctrlPose = hmdPose *ctrlPose
	pos = ctrlPose:GetOrigin()
	rot = ctrlPose:GetRotation()
	--print(pos)

	pos = pos --+ents.get_players()[1]:GetViewForward() *100.0 -- TODO: Controller owner

	vel:Rotate(charComponentOwner:GetViewRotation()) -- TODO: Controller owner
	--debug.draw_line(pos,pos +vel,Color.White,0.02)

	local ent = self:GetEntity()
	local trComponent = ent:GetComponent(ents.COMPONENT_TRANSFORM)
	if(trComponent ~= nil) then




		trComponent:SetPos(pos)
		trComponent:SetRotation(rot)
	end
	local velComponent = ent:GetComponent(ents.COMPONENT_VELOCITY)
	if(velComponent ~= nil) then velComponent:SetVelocity(vel) end
	self.m_controllerVelocity = vel -- TODO
  
	--[[local owner = self:GetOwner()
  local charComponentOwner = (owner ~= nil) and owner:GetComponent(ents.COMPONENT_CHARACTER) or nil
  local trComponentOwner = (owner ~= nil) and owner:GetComponent(ents.COMPONENT_TRANSFORM) or nil
  if(charComponentOwner == nil or trComponentOwner == nil) then return end
  
	--pos,rot = util.local_to_world(trComponentOwner:GetEyePos(),charComponentOwner:GetViewRotation(),pos,rot)

  -- TODO: Clean this up
  --pos,rot = util.local_to_world(_vr_pos,_vr_rot,pos,rot)
  local _vr_pos = Vector() -- TODO?
  local hmdPose = phys.Transform(_vr_pos,Quaternion())--_vr_rot)
  pos = Vector(-pos.x,pos.y,-pos.z)---pos.x,pos.y,-pos.z)
  pos:Rotate(EulerAngles(0,-90,0):ToQuaternion())

  local ang = rot:ToEulerAngles()
  
  local ctrlPose = phys.Transform(pos,Quaternion())
  ctrlPose = hmdPose *ctrlPose
  pos = ctrlPose:GetOrigin()
  rot = EulerAngles(0,90,0):ToQuaternion() *EulerAngles(ang.p,ang.y,ang.r):ToQuaternion()--ctrlPose:GetRotation()
	
	pos = pos --+ents.get_players()[1]:GetViewForward() *100.0 -- TODO: Controller owner
	
	vel:Rotate(charComponentOwner:GetViewRotation()) -- TODO: Controller owner
	--debug.draw_line(pos,pos +vel,Color.White,0.02)
	
  local ent = self:GetEntity()
  local trComponent = ent:GetComponent(ents.COMPONENT_TRANSFORM)
  if(trComponent ~= nil) then
    trComponent:SetPos(pos)
    trComponent:SetRotation(rot)
  end
  local velComponent = ent:GetComponent(ents.COMPONENT_VELOCITY)
  if(velComponent ~= nil) then velComponent:SetVelocity(vel) end
	self.m_controllerVelocity = vel -- TODO
  ]]
end

ents.COMPONENT_VR_CONTROLLER = ents.register_component("vr_controller",ents.VRController,ents.EntityComponent.FREGISTER_BIT_NETWORKED)
