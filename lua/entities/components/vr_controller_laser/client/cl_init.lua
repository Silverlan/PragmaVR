--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VrControllerLaser", BaseEntityComponent)

local Component = ents.VrControllerLaser
Component.impl = Component.impl or {}
function Component:Initialize()
	BaseEntityComponent.Initialize(self)

	self:AddEntityComponent(ents.COMPONENT_TRANSFORM)
	self:AddEntityComponent(ents.COMPONENT_MODEL)
	self:AddEntityComponent(ents.COMPONENT_RENDER)
end

function Component:GetModel()
	if Component.impl.model ~= nil then
		return Component.impl.model
	end
	local mdl = game.create_model()
	local meshGroup = mdl:GetMeshGroup(0)

	local scale = 1.0
	scale = Vector(scale, scale, scale)
	local mesh = game.Model.Mesh.Create()
	local meshBase = game.Model.Mesh.Sub.create_cylinder(game.Model.CylinderCreateInfo(0.2, 1000.0))
	meshBase:SetSkinTextureIndex(0)
	meshBase:Scale(scale)
	mesh:AddSubMesh(meshBase)

	meshGroup:AddMesh(mesh)

	mdl:Update(game.Model.FUPDATE_ALL)
	mdl:AddMaterial(0, "pfm/gizmo")

	meshBase:SetCenter(Vector())

	return mdl
end

function Component:OnEntitySpawn()
	local mdl = self:GetModel()
	self:GetEntity():SetModel(mdl)
end
ents.COMPONENT_VR_CONTROLLER_LASER = ents.register_component("vr_controller_laser", Component)
