-- SPDX-FileCopyrightText: (c) 2020 Silverlan <opensource@pragma-engine.com>
-- SPDX-License-Identifier: MIT

util.register_class("shader.VREquirectangular", shader.BaseGraphics)

shader.VREquirectangular.FragmentShader = "programs/vr/equirectangular"
shader.VREquirectangular.VertexShader = "programs/vr/equirectangular"

shader.VREquirectangular.RENDER_FLAG_NONE = 0
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT = 1
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT =
	bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT, 1)
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT =
	bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT, 1)
shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT =
	bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT, 1)
shader.VREquirectangular.RENDER_FLAG_ENABLE_MARGIN_BIT =
	bit.lshift(shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT, 1)

local SHADER_FLAG_NONE = 0
local SHADER_FLAG_2D_BIT = 1
local SHADER_FLAG_ENABLE_MARGIN = 2

local RENDER_PASS_TYPE_R8G8B8A8 = 0
local RENDER_PASS_TYPE_R16G16B16A16 = 1

function shader.VREquirectangular:Initialize()
	self.m_dsPushConstants =
		util.DataStream(util.SIZEOF_MAT4 + util.SIZEOF_VECTOR2 * 2 + util.SIZEOF_FLOAT * 2 + util.SIZEOF_INT)
	self:SetPipelineCount(2)
end
function shader.VREquirectangular:InitializeRenderPass(pipelineIdx)
	local rpCreateInfo = prosper.RenderPassCreateInfo()
	local format
	if pipelineIdx == RENDER_PASS_TYPE_R8G8B8A8 then
		format = prosper.FORMAT_R8G8B8A8_UNORM
	else
		format = prosper.FORMAT_R16G16B16A16_SFLOAT
	end
	rpCreateInfo:AddAttachment(
		format,
		prosper.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
		prosper.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
		prosper.ATTACHMENT_LOAD_OP_DONT_CARE,
		prosper.ATTACHMENT_STORE_OP_STORE
	)
	return { prosper.create_render_pass(rpCreateInfo) }
end
function shader.VREquirectangular:InitializeShaderResources()
	shader.BaseGraphics.InitializeShaderResources(self)
	self:AttachPushConstantRange(
		0,
		self.m_dsPushConstants:GetSize(),
		bit.bor(prosper.SHADER_STAGE_FRAGMENT_BIT, prosper.SHADER_STAGE_VERTEX_BIT)
	)
	self:AttachVertexAttribute(shader.VertexBinding(prosper.VERTEX_INPUT_RATE_VERTEX), {
		shader.VertexAttribute(prosper.FORMAT_R32G32_SFLOAT), -- Position
		shader.VertexAttribute(prosper.FORMAT_R32G32_SFLOAT), -- UV
	})
	self:AttachDescriptorSetInfo(shader.DescriptorSetInfo("TEXTURE", {
		shader.DescriptorSetBinding(
			"TEXTURE",
			prosper.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
			prosper.SHADER_STAGE_FRAGMENT_BIT
		),
	}))
end
function shader.VREquirectangular:InitializePipeline(pipelineInfo, pipelineIdx)
	shader.BaseGraphics.InitializePipeline(self, pipelineInfo, pipelineIdx)
	pipelineInfo:SetPolygonMode(prosper.POLYGON_MODE_FILL)
	pipelineInfo:SetPrimitiveTopology(prosper.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
end
function shader.VREquirectangular:Draw(drawCmd, dsTex, invVp, horizontalRange, zoom, flags)
	local baseShader = self:GetShader()
	if baseShader:IsValid() == false then
		return
	end
	local tex = dsTex:GetBindingTexture(0)
	if tex == nil then
		return
	end
	local format = tex:GetImage():GetFormat()
	local bindState = shader.BindState(drawCmd)
	local pipelineIdx = RENDER_PASS_TYPE_R8G8B8A8
	if format == prosper.FORMAT_R16G16B16A16_SFLOAT then
		pipelineIdx = RENDER_PASS_TYPE_R16G16B16A16
	end
	if baseShader:RecordBeginDraw(bindState, pipelineIdx) == false then
		return
	end
	flags = flags or shader.VREquirectangular.RENDER_FLAG_NONE
	local buf, numVerts = prosper.util.get_square_vertex_uv_buffer()
	baseShader:RecordBindVertexBuffers(bindState, { buf })
	baseShader:RecordBindDescriptorSet(bindState, dsTex)

	local uvFactor = Vector2(1, 1)
	local uvOffset = Vector2(0, 0)

	local shaderFlags = SHADER_FLAG_NONE
	if bit.band(flags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT) ~= 0 then
		if bit.band(flags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT) ~= 0 then
			uvFactor.x = 0.5
			if bit.band(flags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT) ~= 0 then
				uvOffset.x = uvOffset.x + 0.5
			end
		elseif bit.band(flags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT) ~= 0 then
			uvFactor.y = 0.5
			if bit.band(flags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT) ~= 0 then
				uvOffset.y = uvOffset.y + 0.5
			end
		end
	else
		shaderFlags = bit.bor(shaderFlags, SHADER_FLAG_2D_BIT)
	end

	local rangeFactor = 360.0 / horizontalRange
	uvOffset.x = uvOffset.x - (1.0 - 1.0 / rangeFactor)

	if bit.band(flags, shader.VREquirectangular.RENDER_FLAG_ENABLE_MARGIN_BIT) ~= 0 then
		shaderFlags = bit.bor(shaderFlags, SHADER_FLAG_ENABLE_MARGIN)
	end

	self.m_dsPushConstants:Seek(0)
	self.m_dsPushConstants:WriteMat4(invVp)
	self.m_dsPushConstants:WriteVector2(uvFactor)
	self.m_dsPushConstants:WriteVector2(uvOffset)
	self.m_dsPushConstants:WriteFloat(rangeFactor)
	self.m_dsPushConstants:WriteFloat(zoom)
	self.m_dsPushConstants:WriteUInt32(shaderFlags)
	baseShader:RecordPushConstants(bindState, self.m_dsPushConstants)

	baseShader:RecordDraw(bindState, prosper.util.get_square_vertex_count())
	baseShader:RecordEndDraw(bindState)
end
shader.register("vr_equirectangular", shader.VREquirectangular)
