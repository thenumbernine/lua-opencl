require 'ext.gc'	-- add __gc to luajit
local ffi = require 'ffi'
local class = require 'ext.class'

return function(cl)
	cl = class(cl)

	function cl:init(id)
		self.id = ffi.new(self.ctype, id)
	end

	cl.__gc = cl.release

	return cl
end
