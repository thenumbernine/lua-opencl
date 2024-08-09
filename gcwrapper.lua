require 'ext.gc'	-- add __gc to luajit
local class = require 'ext.class'

return function(cl)
	cl = class(cl)
	cl.__gc = cl.release
	return cl
end
