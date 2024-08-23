local myname, ns = ...
local _, myfullname = C_AddOns.GetAddOnInfo(myname)

---------------------------------------------------------
-- Addon declaration
HandyNotes_Directions = LibStub("AceAddon-3.0"):NewAddon("HandyNotes_Directions","AceEvent-3.0")
local HD = HandyNotes_Directions
local HandyNotes = LibStub("AceAddon-3.0"):GetAddon("HandyNotes")
local L = LibStub("AceLocale-3.0"):GetLocale("HandyNotes_Directions", true)

local debugf = tekDebug and tekDebug:GetFrame("Directions")
local function Debug(...) if debugf then debugf:AddMessage(string.join(", ", tostringall(...))) end end

---------------------------------------------------------
-- Our db upvalue and db defaults
local db
local defaults = {
	global = {
		landmarks = {
			["*"] = {},  -- [mapID] = {[coord] = "name", [coord] = "name", [coord] = {name="name", icon="atlas"}}
		},
	},
	profile = {
		icon_scale         = 1.0,
		icon_alpha         = 1.0,
	},
}
local landmarks

---------------------------------------------------------
-- Localize some globals
local next = next
local GameTooltip = GameTooltip
local HandyNotes = HandyNotes

---------------------------------------------------------
-- Constants

local function setupLandmarkIcon(texture, left, right, top, bottom)
	return {
		icon = texture,
		tCoordLeft = left,
		tCoordRight = right,
		tCoordTop = top,
		tCoordBottom = bottom,
		-- _string = CreateTextureMarkup(texture, 255, 512, 0, 0, left, right, top, bottom),
	}
end
local function setupAtlasIcon(atlas, scale, crop)
	local info = C_Texture.GetAtlasInfo(atlas)
	local icon = {
		icon = info.file,
		scale = scale or 1,
		tCoordLeft = info.leftTexCoord, tCoordRight = info.rightTexCoord, tCoordTop = info.topTexCoord, tCoordBottom = info.bottomTexCoord,
	}
	if crop then
		local xcrop = (icon.tCoordRight - icon.tCoordLeft) * crop
		local ycrop = (icon.tCoordBottom - icon.tCoordTop) * crop
		icon.tCoordRight = icon.tCoordRight - xcrop
		icon.tCoordLeft = icon.tCoordLeft + xcrop
		icon.tCoordBottom = icon.tCoordBottom - ycrop
		icon.tCoordTop = icon.tCoordTop + xcrop
	end
	-- icon._atlas = atlas
	-- icon._string = CreateAtlasMarkup(atlas)
	return icon
end

local icons = {}

---------------------------------------------------------
-- Plugin Handlers to HandyNotes
local HDHandler = {}
local info = {}
local lastGossip = nil
local currentOptions

function HDHandler:OnEnter(mapID, coord)
	local tooltip = GameTooltip
	if ( self:GetCenter() > UIParent:GetCenter() ) then -- compare X coordinate
		tooltip:SetOwner(self, "ANCHOR_LEFT")
	else
		tooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	tooltip:SetText(landmarks[mapID][coord].name)
	tooltip:Show()
end

local function deletePin(mapID, coord)
	landmarks[mapID][coord] = nil
	HD:SendMessage("HandyNotes_NotifyUpdate", "Directions")
end

local function createWaypoint(uiMapID, coord)
	local x, y = HandyNotes:getXY(coord)
	local name = landmarks[uiMapID][coord].name
	if MapPinEnhanced and MapPinEnhanced.AddPin then
		MapPinEnhanced:AddPin{
			mapID = uiMapID,
			x = x,
			y = y,
			setTracked = true,
			title = name,
		}
	elseif TomTom then
		TomTom:AddWaypoint(uiMapID, x, y, {
			title = name,
			world = false,
			minimap = true,
		})
	elseif C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(uiMapID) then
		local uiMapPoint = UiMapPoint.CreateFromCoordinates(uiMapID, x, y)
		C_Map.SetUserWaypoint(uiMapPoint)
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
end

function HDHandler:OnClick(button, down, mapID, coord)
	if button == "RightButton" and not down then
		if not (_G.MenuUtil and MenuUtil.CreateContextMenu) then
			return
		end
		MenuUtil.CreateContextMenu(nil, function(owner, rootDescription)
			rootDescription:SetTag("MENU_HANDYNOTES_DIRECTIONS_CONTEXT")
			local title = rootDescription:CreateTitle(myfullname)
			title:AddInitializer(function(frame, description, menu)
				local rightTexture = frame:AttachTexture()
				rightTexture:SetSize(18, 18)
				rightTexture:SetPoint("RIGHT")
				rightTexture:SetAtlas("poi-islands-table")

				frame.fontString:SetPoint("RIGHT", rightTexture, "LEFT")

				local pad = 20
				local width = pad + frame.fontString:GetUnboundedStringWidth() + rightTexture:GetWidth()
				local height = 20
				return width, height
			end)
			rootDescription:CreateButton("Create waypoint", function(data, event) createWaypoint(mapID, coord) end)
			do
				local icon = rootDescription:CreateButton("Icon...")
				local columns = 3
				icon:SetGridMode(MenuConstants.VerticalGridDirection, columns)
				local iconSelect = function(val)
					landmarks[mapID][coord].icon = val
					HD:SendMessage("HandyNotes_NotifyUpdate", "Directions")
					return MenuResponse.Close
				end
				for key, texdef in pairs(icons) do
					local b = icon:CreateButton(key, iconSelect, key)
					b:AddInitializer(function(frame, description, menu)
						frame.fontString:Hide()
						local texture = frame:AttachTexture()
						texture:SetSize(20, 20)
						texture:SetPoint("CENTER")
						texture:SetTexture(texdef.icon)
						texture:SetTexCoord(texdef.tCoordLeft, texdef.tCoordRight, texdef.tCoordTop, texdef.tCoordBottom)
						if
							(key == landmarks[mapID][coord].icon)
							or (key == "default" and not landmarks[mapID][coord].icon)
						then
							local highlight = frame:AttachTexture()
							highlight:SetAllPoints()
							highlight:SetAtlas("auctionhouse-nav-button-highlight")
							-- highlight:SetPoint("CENTER")
							-- highlight:SetSize(30, 30)
							-- highlight:SetAtlas("common-roundhighlight")
							highlight:SetBlendMode("ADD")
							highlight:SetDrawLayer("BACKGROUND")
						end
						return 30, 30
					end)
				end
			end

			rootDescription:CreateButton(DELETE, function(data, event) deletePin(mapID, coord) end)
		end)
	end
end

function HDHandler:OnLeave(mapFile, coord)
	GameTooltip:Hide()
end

do
	-- This is a custom iterator we use to iterate over every node in a given zone
	local function iter(t, prestate)
		if not t then return nil end
		local state, value = next(t, prestate)
		while state do -- Have we reached the end of this zone?
			if value then
				Debug("iter step", state, icon, db.icon_scale, db.icon_alpha)
				local icon = type(value) == "table" and icons[value.icon] or icons.default
				return state, nil, icon, db.icon_scale, db.icon_alpha
			end
			state, value = next(t, state) -- Get next data
		end
		return nil, nil, nil, nil
	end
	function HDHandler:GetNodes2(mapID)
		return iter, landmarks[mapID], nil
	end
end


---------------------------------------------------------
-- Core functions

local alreadyAdded = {}
function HD:CheckForLandmarks()
	Debug("CheckForLandmarks", lastGossip)
	if not lastGossip then return end
	local mapID = C_Map.GetBestMapForUnit('player')
	local poiID = C_GossipInfo.GetPoiForUiMapID(mapID)
	Debug("--> POI exists", mapID, poiID, alreadyAdded[poiID])
	if poiID and not alreadyAdded[lastGossip] then
		local gossipInfo = C_GossipInfo.GetPoiInfo(mapID, poiID);
		if gossipInfo and gossipInfo.textureIndex == 7 then
			Debug("Found POI", gossipInfo.name)
			alreadyAdded[lastGossip] = true
			self:AddLandmark(mapID, gossipInfo.position.x, gossipInfo.position.y, lastGossip)
		end
	end
end

function HD:AddLandmark(mapID, x, y, name)
	local loc = HandyNotes:getCoord(x, y)
	for coord, value in pairs(landmarks[mapID]) do
		if value and value:match("^"..name) then
			Debug("already a match on name", name, value)
			return
		end
	end
	landmarks[mapID][loc] = {name = name,}
	self:SendMessage("HandyNotes_NotifyUpdate", "Directions")
	createWaypoint(mapID, loc)
end

local replacements = {
	[L["A profession trainer"]] = L["Trainer"],
	[L["Profession Trainer"]] = L["Trainer"],
	[MINIMAP_TRACKING_TRAINER_PROFESSION] = L["Trainer"], -- Profession Trainers
	[L["A class trainer"]] = L["Trainer"],
	-- [L["Class Trainer"]] = L["Trainer"],
	[MINIMAP_TRACKING_TRAINER_CLASS] = L["Trainer"], -- Class Trainer
	[L["Alliance Battlemasters"]] = FACTION_ALLIANCE,
	[L["Horde Battlemasters"]] = FACTION_HORDE,
	[L["To the east."]] = L["East"],
	[L["To the west."]] = L["West"],
	[L["The east."]] = L["East"],
	[L["The west."]] = L["West"],
}
function HD:OnGossipSelectOption(key, identifier, ...)
	Debug("OnGossipSelectOption", key, identifier, currentOptions)
	if not currentOptions then return end
	local selected
	for _, option in ipairs(currentOptions) do
		if option[key] == identifier then
			selected = option
			break
		end
	end
	if not selected then return end
	local name = selected.name
	if replacements[name] then name = replacements[name] end
	if lastGossip then
		lastGossip = lastGossip .. ': ' .. name
	else
		lastGossip = name
	end
	Debug(" -> lastGossip", lastGossip)
end

function HD:GOSSIP_SHOW()
	Debug("GOSSIP_SHOW")
	currentOptions = C_GossipInfo.GetOptions()
end

function HD:GOSSIP_CLOSED()
	Debug("GOSSIP_CLOSED")
	lastGossip = nil
end

---------------------------------------------------------
-- Options table
local options = {
	type = "group",
	name = "Directions",
	desc = "Directions",
	get = function(info) return db[info.arg] end,
	set = function(info, v)
		db[info.arg] = v
		HD:SendMessage("HandyNotes_NotifyUpdate", "Directions")
	end,
	args = {
		desc = {
			name = "These settings control the look and feel of the icon. Note that HandyNotes_Directions does not come with any precompiled data, when you ask a guard for directions, it will automatically add the data into your database.",
			type = "description",
			order = 0,
		},
		icon_scale = {
			type = "range",
			name = "Icon Scale",
			desc = "The scale of the icons",
			min = 0.25, max = 2, step = 0.01,
			arg = "icon_scale",
			order = 10,
		},
		icon_alpha = {
			type = "range",
			name = "Icon Alpha",
			desc = "The alpha transparency of the icons",
			min = 0, max = 1, step = 0.01,
			arg = "icon_alpha",
			order = 20,
		},
	},
}


---------------------------------------------------------
-- Addon initialization, enabling and disabling


function HD:OnInitialize()
	-- Set up our database
	self.db = LibStub("AceDB-3.0"):New("HandyNotes_DirectionsDB", defaults)
	db = self.db.profile
	landmarks = self.db.global.landmarks

	for mapid, points in pairs(landmarks) do
		for coord, point in pairs(points) do
			if type(point) == "string" then
				points[coord] = {name=point}
			end
		end
	end

	icons.default = setupLandmarkIcon([[Interface\Minimap\POIIcons]], C_Minimap.GetPOITextureCoords(7)) -- the cute lil' flag
	icons.map = setupAtlasIcon([[poi-islands-table]])
	icons.banker = setupAtlasIcon([[Banker]])
	icons.barber = setupAtlasIcon([[Barbershop-32x32]])
	icons.battlemaster = setupAtlasIcon([[BattleMaster]])
	icons.class = setupAtlasIcon([[Class]])
	icons.chromie = setupAtlasIcon([[ChromieTime-32x32]])
	icons.innkeeper = setupAtlasIcon([[Innkeeper]])
	icons.creationcatalyst = setupAtlasIcon([[CreationCatalyst-32x32]])
	icons.ancientmana = setupAtlasIcon([[AncientMana]])
	icons.profession = setupAtlasIcon([[Profession]])
	icons.racing = setupAtlasIcon([[racing]])
	icons.reagents = setupAtlasIcon([[Reagents]])
	icons.repair = setupAtlasIcon([[Repair]])
	icons.portalblue = setupAtlasIcon([[MagePortalAlliance]])
	icons.portalred = setupAtlasIcon([[MagePortalHorde]])
	icons.loreobject = setupAtlasIcon([[loreobject-32x32]])
	icons.mailbox = setupAtlasIcon([[Mailbox]])
	icons.food = setupAtlasIcon([[Food]])
	icons.auctioneer = setupAtlasIcon([[Auctioneer]])
	icons.transmog = setupAtlasIcon([[poi-transmogrifier]])
	icons.crossedflags = setupAtlasIcon([[CrossedFlags]])
	icons.town = setupAtlasIcon([[poi-town]])
	icons.workorders = setupAtlasIcon([[poi-workorders]])
	icons.flightmaster = setupAtlasIcon([[FlightMaster]])
	icons.door = setupAtlasIcon([[delves-bountiful]])
	icons.fishing = setupAtlasIcon([[Fishing-Hole]])
	icons.rostrum = setupAtlasIcon([[dragon-rostrum]])
	icons.magnify = setupAtlasIcon([[None]])
	-- icons. = setupAtlasIcon([[]])

	-- Initialize our database with HandyNotes
	HandyNotes:RegisterPluginDB("Directions", HDHandler, options)
end

local orig_SelectGossipOption
function HD:OnEnable()
	self:RegisterEvent("DYNAMIC_GOSSIP_POI_UPDATED", "CheckForLandmarks")
	self:RegisterEvent("GOSSIP_CLOSED")
	self:RegisterEvent("GOSSIP_SHOW")

	hooksecurefunc(C_GossipInfo, "SelectOption", function(...)
		HD:OnGossipSelectOption("gossipOptionID", ...)
	end)
	hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(...)
		HD:OnGossipSelectOption("orderIndex", ...)
	end)
end
