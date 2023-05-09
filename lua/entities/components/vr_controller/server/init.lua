--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("../shared.lua")

net.register("vr_controller_update_orientation")
net.receive("vr_controller_update_orientation", function(packet, pl)
	local ent = packet:ReadEntity()
	local vrControllerComponent = (ent ~= nil) and ent:GetComponent(ents.COMPONENT_VR_CONTROLLER) or nil
	if vrControllerComponent == nil then
		return
	end
	-- TODO: Check if this belongs to the player
	local pos = packet:ReadVector()
	local vel = packet:ReadVector()
	local rot = packet:ReadQuaternion()
	vrControllerComponent:SetControllerTransform(pos, rot, vel)
end)

function ents.VRController:OnStartTouch(physObj)
	local ent = physObj:GetOwner()
	if ent == nil then
		return
	end
	local damageableComponent = ent:GetComponent(ents.COMPONENT_DAMAGEABLE)
	if damageableComponent == nil then
		return
	end
	if self.m_tLastDamage == nil or time.cur_time() - self.m_tLastDamage > 0.3 then
		local owner = self:GetOwner()
		local dmg = game.DamageInfo()
		dmg:AddDamageType(game.DAMAGETYPE_BASH)
		dmg:SetDamage(25)
		if owner ~= nil then
			dmg:SetAttacker(owner)
		end
		dmg:SetInflictor(self:GetEntity())
		local trComponent = self:GetEntity():GetComponent(ents.COMPONENT_TRANSFORM)
		if trComponent ~= nil then
			dmg:SetSource(trComponent:GetPos())
		end
		dmg:SetForce(Vector(0, 0, 0)) --dir *MELEE_DAMAGE_PUSH_FORCE)
		if damageableComponent ~= nil then
			damageableComponent:TakeDamage(dmg)
		end
		self.m_tLastDamage = time.cur_time()
	end
end
