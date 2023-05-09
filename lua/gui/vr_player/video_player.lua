--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("/vr/video_player.lua")
include("/gui/aspectratio.lua")
include("/gui/vr_view.lua")

util.register_class("gui.VRVideoPlayer", gui.Base, gui.VRView)
function gui.VRVideoPlayer.get_video_settings(projectData)
	local settingsBlock = projectData:Get("settings")
	if settingsBlock == nil then
		return false
	end
	local videoBlock = settingsBlock:Get("video")
	if videoBlock == nil or (videoBlock:GetValue("enabled", udm.TYPE_BOOLEAN) or false) == false then
		return false
	end
	local fileName = videoBlock:GetValue("file", udm.TYPE_STRING)
	local url = videoBlock:GetValue("url", udm.TYPE_STRING)
	if fileName ~= nil then
		fileName = "projects/" .. fileName
		if file.exists(fileName) == false then
			return false
		end
	end
	local videoSettings = {}
	videoSettings.videoBlock = videoBlock
	videoSettings.fileName = fileName
	videoSettings.url = url

	local renderFlags = shader.VREquirectangular.RENDER_FLAG_NONE
	local type = videoBlock:GetValue("type", udm.TYPE_STRING)
	if type == "equirectangular" then
		renderFlags = bit.bor(renderFlags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT)
		local mode = videoBlock:GetValue("mode", udm.TYPE_STRING)
		if mode == "stereo" then
			local stereoAlignment = videoBlock:GetValue("stereo_alignment", udm.TYPE_STRING)
			if stereoAlignment == "vertical" then
				renderFlags =
					bit.bor(renderFlags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT)
			else
				renderFlags =
					bit.bor(renderFlags, shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_HORIZONTAL_BIT)
			end
		end

		local horizontalDegrees = videoBlock:GetValue("horizontal_degrees", udm.TYPE_FLOAT) or 360.0
		videoSettings.horizontalRange = horizontalDegrees
	end

	local previewBlock = videoBlock:Get("preview")
	if previewBlock ~= nil then
		videoSettings.preview = {
			startTime = previewBlock:GetValue("start_time", udm.TYPE_FLOAT) or 0.0,
			pitch = previewBlock:GetValue("pitch", udm.TYPE_FLOAT) or 0.0,
			yaw = previewBlock:GetValue("yaw", udm.TYPE_FLOAT) or 0.0,
			zoomLevel = previewBlock:GetValue("zoom", udm.TYPE_FLOAT) or 1.0,
		}
	end

	videoSettings.renderFlags = renderFlags
	return videoSettings
end
function gui.VRVideoPlayer.apply_video_settings(player, videoSettings)
	-- Immediately load the video
	local vp = player:GetVideoPlayer()
	if vp ~= nil then
		if videoSettings.fileName ~= nil then
			vp:LoadFile(videoSettings.fileName)
		elseif videoSettings.url ~= nil then
			vp:LoadURL(videoSettings.url)
		end
	end
	if videoSettings.horizontalRange ~= nil then
		player:SetHorizontalRange(videoSettings.horizontalRange)
	end
	player:SetRenderFlags(videoSettings.renderFlags)
end
function gui.VRVideoPlayer:__init()
	gui.Base.__init(self)
	gui.VRView.__init(self)
end
function gui.VRVideoPlayer:OnInitialize()
	gui.Base.OnInitialize(self)

	self:SetSize(256, 256)
	local elTex = gui.create("WITexturedRect", self, 0, 0, self:GetWidth(), self:GetHeight(), 0, 0, 1, 1)
	self.m_elTex = elTex

	self.m_videoPlayer = util.VideoPlayer.create()
	if self.m_videoPlayer ~= nil then
		self.m_videoPlayer:AddCallback("OnFrameRendered", function(drawSceneInfo)
			self:DrawFrame(drawSceneInfo)
		end)
		self.m_videoPlayer:AddCallback("OnFramebufferInitialized", function(fb, tex)
			self:InitializeTexture(tex)
		end)
	end
end
function gui.VRVideoPlayer:GetTexture()
	return self.m_videoPlayer:GetTexture()
end
function gui.VRVideoPlayer:GetVideoPlayer()
	return self.m_videoPlayer
end
function gui.VRVideoPlayer:OnRemove()
	if self.m_videoPlayer ~= nil then
		self.m_videoPlayer:Close()
	end
end
function gui.VRVideoPlayer:DrawFrame(drawSceneInfo)
	local rpInfo = prosper.RenderPassInfo(self.m_rt)
	if drawSceneInfo.commandBuffer:RecordBeginRenderPass(rpInfo) then
		self:DrawVR(drawSceneInfo.commandBuffer, self.m_dsTex)
	end
end
function gui.VRVideoPlayer:InitializeTexture(vpTex)
	local w = vpTex:GetWidth()
	local h = vpTex:GetHeight()
	local szWindow = gui.get_window_size()
	-- Clamp size to window bounds (while keeping the original aspect ratio)
	if w > szWindow.x then
		h = szWindow.x * (w / h)
		w = szWindow.x
	end
	if h > szWindow.y then
		w = szWindow.y * (h / w)
		h = szWindow.y
	end
	w = math.round(w)
	h = math.round(h)
	if self.m_texture ~= nil and w == self.m_texture:GetWidth() and h == self.m_texture:GetHeight() then
		return
	end
	local imgCreateInfo = prosper.ImageCreateInfo()
	imgCreateInfo.width = w
	imgCreateInfo.height = h
	imgCreateInfo.format = prosper.FORMAT_R8G8B8A8_UNORM
	imgCreateInfo.usageFlags = bit.bor(prosper.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, prosper.IMAGE_USAGE_SAMPLED_BIT)
	imgCreateInfo.tiling = prosper.IMAGE_TILING_OPTIMAL
	imgCreateInfo.memoryFeatures = prosper.MEMORY_FEATURE_GPU_BULK_BIT
	imgCreateInfo.postCreateLayout = prosper.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	local img = prosper.create_image(imgCreateInfo)

	local imgViewCreateInfo = prosper.ImageViewCreateInfo()
	imgViewCreateInfo.swizzleAlpha = prosper.COMPONENT_SWIZZLE_ONE
	local tex = prosper.create_texture(img, prosper.TextureCreateInfo(), imgViewCreateInfo, prosper.SamplerCreateInfo())

	self.m_rt = prosper.create_render_target(prosper.RenderTargetCreateInfo(), tex, shader.Graphics.get_render_pass())

	self.m_dsTex = self:GetVRShader():CreateDescriptorSet(shader.BaseImageProcessing.DESCRIPTOR_SET_TEXTURE)
	self.m_dsTex:SetBindingTexture(shader.BaseImageProcessing.DESCRIPTOR_SET_TEXTURE_BINDING_TEXTURE, vpTex)

	self.m_elTex:SetTexture(tex)
	self:CallCallbacks("OnTextureSizeChanged", w, h)
	self:CallCallbacks("OnTextureUpdated", tex)
end
function gui.VRVideoPlayer:LinkToControls(aspectRatio, timeline, playControls)
	if aspectRatio ~= nil then
		self:AddCallback("OnTextureSizeChanged", function(el, w, h)
			aspectRatio:SetAspectRatio(w / h)
		end)
	end
	local vp = self:GetVideoPlayer()
	if vp == nil then
		return
	end
	if timeline ~= nil then
		vp:AddCallback("OnReady", function()
			timeline:SetDuration(vp:GetDuration())
		end)
	end
	if playControls ~= nil then
		playControls:AddCallback("OnButtonPressed", function(el, button)
			if self.m_skipCallbacks then
				return
			end
			if button == gui.PlaybackControls.BUTTON_PLAY then
				vp:Play()
			elseif button == gui.PlaybackControls.BUTTON_PAUSE then
				vp:Pause()
			end
		end)

		vp:AddCallback("OnOffsetChanged", function(oldOffset, newOffset)
			if timeline:IsCursorBeingDragged() then
				return
			end
			timeline:SetTimeOffset(newOffset, "player")
		end)
		vp:AddCallback("OnStateChanged", function()
			self.m_skipCallbacks = true
			local playButton = playControls:GetPlayButton()
			if vp:IsPlaying() then
				playButton:Play()
			else
				playButton:Pause()
			end
			self.m_skipCallbacks = nil
		end)
	end
end
gui.register("VRVideoPlayer", gui.VRVideoPlayer)
