local class = require 'ext.class'
local range = require 'ext.range'
local tolua = require 'ext.tolua'
local string = require 'ext.string'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'

local function GetInfoBehavior(parent)
	local template = class(parent)

	function template:init(...)
		self.infoTypeMap = {}
		for _,info in ipairs(self.infos) do
			self.infoTypeMap[info.name] = info.type
		end
	
		if parent then return parent.init(self, ...) end
	end

	function template:getInfo(name)
		local getter = self.infoGetter
		local id = self.id
		
		local infoType = self.infoTypeMap[name]
		local nameValue = assert(cl[name])
		if infoType == 'string' then
			local size = ffi.new('size_t[1]', 0)
			classert(getter(id, nameValue, 0, nil, size))
			local n = size[0]
			local result = ffi.new('char[?]', n)
			classert(getter(id, nameValue, n, result, nil))
			-- some strings have an extra null term ...
			while n > 0 and result[n-1] == 0 do n = n - 1 end
			return ffi.string(result, n)
		elseif infoType:sub(-2) == '[]' then
			local baseType = infoType:sub(1,-3)
			local size = ffi.new('size_t[1]', 0)
			classert(getter(id, nameValue, 0, nil, size))
			local n = tonumber(size[0] / ffi.sizeof(baseType))	
			local result = ffi.new(baseType..'[?]', n)
			classert(getter(id, nameValue, size[0], result, nil))
			return range(0,n-1):mapi(function(i) return result[i] end)
		else
			local result = ffi.new(infoType..'[1]')
			classert(getter(id, nameValue, ffi.sizeof(infoType), result, nil))
			return result[0]
		end
	end
	
	function template:getInfoStrList(name)
		return string.split(string.trim(self:getInfo(name)), '%s+'):sort()
	end

	function template:printInfo()
		for _,info in ipairs(self.infos) do
			local value
			-- special case
			if info.name == 'CL_DEVICE_EXTENSIONS'
			or info.name == 'CL_PLATFORM_EXTENSIONS'
			then
				value = '\n\t'..self:getInfoStrList(info.name):concat'\n\t'
			else
				value = tolua(self:getInfo(info.name))
			end
			print(info.name, value)
		end
	end
	
	return template
end

return GetInfoBehavior
