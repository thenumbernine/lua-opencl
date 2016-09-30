local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local Wrapper = require 'cl.wrapper'

local Device = class(Wrapper(
	'cl_device_id',
	cl.clRetainDevice,
	cl.clReleaseDevice))

function Device:init(id)
	self.id = id
	Device.super.init(self, self.id)
end

return Device
