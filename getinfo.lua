local class = require 'ext.class'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'

local function getInfo(getter, infos, id, name)
	local infoType = infos[name]
	local nameValue = assert(cl[name])
	if infoType == 'string' then
		local size = ffi.new('size_t[1]', 0)
		classert(getter(id, nameValue, 0, nil, size))
		local result = ffi.new('char[?]', size[0])
		classert(getter(id, nameValue, size[0], result, nil))
		return ffi.string(result, size[0])
	elseif infoType:sub(-2) == '[]' then
		local baseType = infoType:sub(1,-3)
		local size = ffi.new('size_t[1]', 0)
		classert(getter(id, nameValue, 0, nil, size))
		local n = tonumber(size[0] / ffi.sizeof(baseType))	
		local result = ffi.new(baseType..'[?]', n)
		classert(getter(id, nameValue, size[0], result, nil))
		return require 'ext.range'(0,n-1):map(function(i) return result[i] end)
	else
		local result = ffi.new(infoType..'[1]')
		classert(getter(id, nameValue, ffi.sizeof(infoType), result, nil))
		return result[0]
	end
end

local function GetInfoBehavior(parent)
	local template = class(parent)
	function template:getInfo(name)
		return getInfo(self.infoGetter, self.infos, self.id, name)
	end
	return template
end

return GetInfoBehavior
