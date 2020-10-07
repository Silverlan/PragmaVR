--[[
    Copyright (C) 2019  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("util.VideoPlayer",util.CallbackHandler)
util.VideoPlayer.create = function()
	local r = engine.load_library("mpv/pr_mpv")
	if(r ~= true) then
		console.print_warning("Unable to load MPV module: " .. r)
		return
	end
	local player,result = mpv.create_player()
	if(player == false) then
		console.print_warning("Unable to create MPV player: " .. mpv.result_to_string(result))
		return
	end
	return util.VideoPlayer(player)
end
function util.VideoPlayer:__init(player)
	util.CallbackHandler.__init(self)
	self.m_player = player

	player:SetVolume(console.get_convar_float("cl_audio_master_volume"))
	self.m_offset = 0.0
	self.m_cbUpdate = game.add_callback("PreRenderScenes",function(drawSceneInfo)
		self:Draw(drawSceneInfo)

		local newOffset = self:GetPlaybackTime()
		if(newOffset ~= self.m_offset) then
			local oldOffset = self.m_offset
			self.m_offset = newOffset
			self:CallCallbacks("OnOffsetChanged",oldOffset,newOffset)
		end
	end)
	self:SetVolume(1.0)
end
function util.VideoPlayer:GetTexture() return self.m_texture end
function util.VideoPlayer:IsFileLoaded() return self.m_fileLoaded or false end
function util.VideoPlayer:IsReady() return self.m_ready or false end
function util.VideoPlayer:LoadFile(...)
	local res = self.m_player:LoadFile(...)
	self.m_fileLoaded = (res == mpv.RESULT_SUCCESS)
	self.m_ready = false
end
function util.VideoPlayer:LoadURL(...)
	local res = self.m_player:LoadURL(...)
	self.m_fileLoaded = (res == mpv.RESULT_SUCCESS)
	self.m_ready = false
end
function util.VideoPlayer:ClearFile(...)
	self.m_player:ClearFile(...)
	self.m_fileLoaded = false
	self.m_ready = false
end
function util.VideoPlayer:IsPaused(...) return self.m_player:IsPaused(...) end
function util.VideoPlayer:IsPlaying(...) return self.m_player:IsPlaying(...) end
function util.VideoPlayer:Play(...)
	self.m_player:Play(...)
	self:CallCallbacks("OnStateChanged")
end
function util.VideoPlayer:Pause(...)
	self.m_player:Pause(...)
	self:CallCallbacks("OnStateChanged")
end
function util.VideoPlayer:Stop(...)
	self.m_player:Stop(...)
	self:CallCallbacks("OnStateChanged")
end
function util.VideoPlayer:Seek(...) self.m_player:Seek(...) end
function util.VideoPlayer:GoToNextFrame(...) self.m_player:GoToNextFrame(...) end
function util.VideoPlayer:GoToPreviousFrame(...) self.m_player:GoToPreviousFrame(...) end
function util.VideoPlayer:GetDuration(...) return self.m_player:GetDuration(...) end
function util.VideoPlayer:GetWidth(...) return self.m_player:GetWidth(...) end
function util.VideoPlayer:GetHeight(...) return self.m_player:GetHeight(...) end
function util.VideoPlayer:SetVolume(volume) self.m_volume = volume end
function util.VideoPlayer:GetVolume(...) return self.m_player:GetVolume(...) end
function util.VideoPlayer:GetPlaybackTime(...) return self.m_player:GetPlaybackTime(...) end

function util.VideoPlayer:Close()
	util.remove(self.m_cbUpdate)
	self.m_player:Close()

	self.m_framebuffer = nil
	self.m_texture = nil
end

function util.VideoPlayer:Draw(drawSceneInfo)
	local vol = self.m_volume *console.get_convar_float("cl_audio_master_volume")
	if(self.m_player:GetVolume() ~= vol) then self.m_player:SetVolume(vol) end

	self.m_player:UpdateEvents()
	if(self.m_player:IsReady() == false) then return end
	if(self.m_ready == false) then
		self.m_ready = true
		self.m_player:SetVolume(vol)
		self:CallCallbacks("OnReady")
	end
	self:InitializeTexture(self.m_player:GetWidth(),self.m_player:GetHeight())
	self.m_player:RenderFrame(self.m_framebuffer)
	self:CallCallbacks("OnFrameRendered",drawSceneInfo)
end

function util.VideoPlayer:InitializeTexture(w,h)
	if(self.m_framebuffer ~= nil and w == self.m_framebuffer:GetWidth() and h == self.m_framebuffer:GetHeight()) then return end
	local imgCreateInfo = prosper.ImageCreateInfo()
	imgCreateInfo.width = w
	imgCreateInfo.height = h
	imgCreateInfo.format = prosper.FORMAT_R8G8B8A8_UNORM
	imgCreateInfo.usageFlags = bit.bor(prosper.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,prosper.IMAGE_USAGE_SAMPLED_BIT)
	imgCreateInfo.tiling = prosper.IMAGE_TILING_OPTIMAL
	imgCreateInfo.memoryFeatures = prosper.MEMORY_FEATURE_GPU_BULK_BIT
	imgCreateInfo.postCreateLayout = prosper.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL

	local img = prosper.create_image(imgCreateInfo)
	local imgViewCreateInfo = prosper.ImageViewCreateInfo()
	imgViewCreateInfo.swizzleAlpha = prosper.COMPONENT_SWIZZLE_ONE
	local tex = prosper.create_texture(img,prosper.TextureCreateInfo(),imgViewCreateInfo,prosper.SamplerCreateInfo())
	local imgView = prosper.create_image_view(prosper.ImageViewCreateInfo(),img)
	local framebuffer = prosper.create_framebuffer(imgCreateInfo.width,imgCreateInfo.height,{imgView})
	self.m_framebuffer = framebuffer
	self.m_texture = tex

	self:CallCallbacks("OnFramebufferInitialized",self.m_framebuffer,self.m_texture)
end
