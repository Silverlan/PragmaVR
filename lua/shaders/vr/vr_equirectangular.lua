--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("shader.VREquirectangular",shader.BaseGraphics)

shader.VREquirectangular.FragmentShader = "vr/fs_equirectangular"
shader.VREquirectangular.VertexShader = "vr/vs_equirectangular"

shader.VREquirectangular.RENDER_FLAG_NONE = 0
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT = 1
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT = bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT,1)
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT = bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT,1)
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT = bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT,1)

local SHADER_FLAG_NONE = 0
local SHADER_FLAG_2D_BIT = 1

function shader.VREquirectangular:__init()
	shader.BaseGraphics.__init(self)

	self.m_dsPushConstants = util.DataStream(util.SIZEOF_MAT4 +util.SIZEOF_VECTOR2 *2 +util.SIZEOF_FLOAT *2 +util.SIZEOF_INT)
end
function shader.VREquirectangular:InitializePipeline(pipelineInfo,pipelineIdx)
	shader.BaseGraphics.InitializePipeline(self,pipelineInfo,pipelineIdx)
	pipelineInfo:AttachPushConstantRange(0,self.m_dsPushConstants:GetSize(),bit.bor(prosper.SHADER_STAGE_FRAGMENT_BIT,prosper.SHADER_STAGE_VERTEX_BIT))
	pipelineInfo:AttachVertexAttribute(shader.VertexBinding(prosper.VERTEX_INPUT_RATE_VERTEX),{
		shader.VertexAttribute(prosper.FORMAT_R32G32_SFLOAT), -- Position
		shader.VertexAttribute(prosper.FORMAT_R32G32_SFLOAT) -- UV
	})
	pipelineInfo:AttachDescriptorSetInfo(shader.DescriptorSetInfo({
		shader.DescriptorSetBinding(prosper.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,prosper.SHADER_STAGE_FRAGMENT_BIT)
	}))

	pipelineInfo:SetPolygonMode(prosper.POLYGON_MODE_FILL)
	pipelineInfo:SetPrimitiveTopology(prosper.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
end
function shader.VREquirectangular:Draw(drawCmd,dsTex,invVp,horizontalRange,zoom,flags)
	if(self:IsValid() == false or self:RecordBeginDraw(drawCmd) == false) then return end
	flags = flags or shader.VREquirectangular.RENDER_FLAG_NONE
	local buf,numVerts = prosper.util.get_square_vertex_uv_buffer()
	self:RecordBindVertexBuffers({buf})
	self:RecordBindDescriptorSet(dsTex)

	local uvFactor = Vector2(1,1)
	local uvOffset = Vector2(0,0)

	local shaderFlags = SHADER_FLAG_NONE
	if(bit.band(flags,shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT) ~= 0) then
		if(bit.band(flags,shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT) ~= 0) then
			uvFactor.x = 0.5
			if(bit.band(flags,shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT) ~= 0) then uvOffset.x = 0.5 end
		elseif(bit.band(flags,shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT) ~= 0) then
			uvFactor.y = 0.5
			if(bit.band(flags,shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT) ~= 0) then uvOffset.y = 0.5 end
		end
	else shaderFlags = bit.bor(shaderFlags,SHADER_FLAG_2D_BIT) end

	self.m_dsPushConstants:Seek(0)
	self.m_dsPushConstants:WriteMat4(invVp)
	self.m_dsPushConstants:WriteVector2(uvFactor)
	self.m_dsPushConstants:WriteVector2(uvOffset)
	self.m_dsPushConstants:WriteFloat(360.0 /horizontalRange)
	self.m_dsPushConstants:WriteFloat(zoom)
	self.m_dsPushConstants:WriteUInt32(shaderFlags)
	self:RecordPushConstants(self.m_dsPushConstants)

	self:RecordDraw(prosper.util.get_square_vertex_count())
	self:RecordEndDraw()
end
shader.register("vr_equirectangular",shader.VREquirectangular)

