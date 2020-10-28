--[[
    Copyright (C) 2019  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("/gui/pfm/slidercursor.lua")

util.register_class("gui.VRTimeline",gui.Base)

util.register_class("gui.VRTimeline.Chapter",gui.Base)
function gui.VRTimeline.Chapter:__init()
	gui.Base.__init(self)
end
function gui.VRTimeline.Chapter:OnInitialize()
	gui.Base.OnInitialize(self)

	self:SetSize(1,12)
	local el = gui.create("WIRect",self,0,0,self:GetWidth(),self:GetHeight(),0,0,1,1)
	el:SetColor(Color.Red)
end
gui.register("VRTimelineChapter",gui.VRTimeline.Chapter)

-------------------

function gui.VRTimeline:__init()
	gui.Base.__init(self)
end
function gui.VRTimeline:OnInitialize()
	gui.Base.OnInitialize(self)

	self.m_timeOffset = 0.0
	self.m_duration = 60.0

	self:SetSize(256,24)
	local progressBar = gui.create("WIProgressBar",self,0,0,self:GetWidth(),self:GetHeight(),0,0,1,1)
	progressBar:AddCallback("TranslateValue",function(progressBar,progress)
		return util.get_pretty_time(progress /100.0 *self.m_duration)
	end)
	progressBar:SetRange(0,1,0.001)
	self.m_progressBar = progressBar

	local cursor = gui.create("WIPFMSliderCursor",self)
	cursor:CenterToParentX()
	cursor:SetType(gui.PFMSliderCursor.TYPE_HORIZONTAL)
	cursor:AddCallback("OnFractionChanged",function(el,fraction,inputOrigin)
		self:SetTimeOffset(fraction *self:GetDuration(),inputOrigin)
	end)
	self.m_cursor = cursor
	cursor:SetSize(1,20)

	self.m_chapters = {}
	self:ScheduleUpdate()

	self:SetMouseInputEnabled(true)
end
function gui.VRTimeline:IsCursorBeingDragged() return self.m_cursor:IsActive() end
function gui.VRTimeline:OnMouseEvent(button,state,mods)
	local cursorPos = self.m_progressBar:GetCursorPos()
	self.m_cursor:InjectMouseInput(cursorPos,button,state,mods)
	self.m_cursor:CallCallbacks("OnCursorMoved",cursorPos.x,cursorPos.y)
	return util.EVENT_REPLY_HANDLED
end
function gui.VRTimeline:ClearChapters()
	for _,chapterData in ipairs(self.m_chapters) do
		if(chapterData.element:IsValid()) then chapterData.element:Remove() end
	end
	self.m_chapters = {}
end
function gui.VRTimeline:AddChapter(timestamp)
	local elChapter = gui.create("VRTimelineChapter",self)
	elChapter:SetX(50)
	elChapter:SetHeight(self:GetHeight())

	table.insert(self.m_chapters,{
		element = elChapter,
		timestamp = timestamp
	})
end
function gui.VRTimeline:SetDuration(duration)
	self.m_duration = duration
	self:UpdateProgressBar()
end
function gui.VRTimeline:GetDuration() return self.m_duration end
function gui.VRTimeline:SetTimeOffset(timeOffset,inputOrigin)
	self.m_timeOffset = timeOffset
	self:UpdateProgressBar()

	self:CallCallbacks("OnTimeOffsetChanged",timeOffset,inputOrigin)
end
function gui.VRTimeline:UpdateProgressBar()
	local progress = self.m_timeOffset /self.m_duration
	self.m_progressBar:SetProgress(progress)
end
function gui.VRTimeline:TimestampToXOffset(timestamp)
	local f = timestamp /self.m_duration
	return f *self:GetWidth()
end
function gui.VRTimeline:OnSizeChanged()
	self:ScheduleUpdate()
end
function gui.VRTimeline:OnUpdate()
	for _,chapterData in ipairs(self.m_chapters) do
		local el = chapterData.element
		if(el:IsValid()) then
			el:SetHeight(self:GetHeight())

			local x = self:TimestampToXOffset(chapterData.timestamp)
			el:SetX(x)
		end
	end
end
gui.register("VRTimeline",gui.VRTimeline)
