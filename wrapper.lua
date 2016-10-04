--[[
if you want to make use of gc dtors ...
note that the gc only sees the ffi struct
and the ffi struct only has C data (no lua refs)
and the cl.hpp Wrapper dtor is custom per-parent-class
so this needs to be a behavior
--]]

local class = require 'ext.class'
local ffi = require 'ffi'

local function Wrapper(ctype, retain, release)

	local gcCType = 'autorelease_'..ctype

	ffi.cdef([[
struct ]]..gcCType..[[ {
	]]..ctype..[[ ptr[1];
};
typedef struct ]]..gcCType..' '..gcCType..[[;
]])
	local gcType = ffi.metatype(gcCType, {
		__gc = function(gc)
			-- TODO clear gc.ptr[0] upon final release?
			release(gc.ptr[0])
		end,
	})

	local template = class()

	-- TODO only use gc.ptr[0] instead of id?
	function template:init(id)
		-- release-upon-gc/dtor
		self.gc = gcType()
		self.gc.ptr[0] = id
		self.id = id
	end

	function template:retain()
		return retain(self.id)
	end

	function template:release()
		return release(self.id)
	end

	return template
end

return Wrapper
