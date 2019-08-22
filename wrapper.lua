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
			-- clear gc.ptr[0] upon final release
			if gc.ptr[0] ~= nil then
				release(gc.ptr[0])
				gc.ptr[0] = nil
			end
		end,
	})

	local template = class()
	template.gcCType = gcCType

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
		-- single release() statement matches the cl.hpp code, which itself relied on retain/release calls to refcount
		--return release(self.id)
		-- but lua does its own refcounting, so retain just needs to be called once upon creation and release once upon delete
		if self.gc.ptr[0] ~= nil then
			local result = release(self.gc.ptr[0])
			self.gc.ptr[0] = nil
			self.id = nil
			return result
		end
	end

	return template
end

return Wrapper
