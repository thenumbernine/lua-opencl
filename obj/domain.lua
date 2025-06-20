local class = require 'ext.class'
local table = require 'ext.table'
local vec3sz = require 'vec-ffi.vec3sz'

local CLDomain = class()

--[[
args:
	env
	size = either a number or a table of numbers
	dim = optional, default is #size
	device = optional, default is env.devices[1]
--]]
function CLDomain:init(args)

	self.env = assert(args.env)
	self.device = args.device or self.env.devices[1]

	-- default kernel and buffer size
	local size = args.size
	if type(size) == 'number' then size = {size} end
	size = table(size)
	self.dim = args.dim or #size
	assert(self.dim >= 1 and self.dim <= 3, "got a bad dim: "..tostring(self.dim))
	for i=#size+1,3 do size[i] = 1 end
	self.size = vec3sz(size:unpack(1,3))
	self.volume = tonumber(self.size:volume())

	-- https://stackoverflow.com/questions/15912668/ideal-global-local-work-group-sizes-opencl
	-- product of all local sizes must be <= max workgroup size
	local maxWorkGroupSize = tonumber(self.device:getInfo'CL_DEVICE_MAX_WORK_GROUP_SIZE')
--DEBUG:print('maxWorkGroupSize',maxWorkGroupSize)

	-- for volumes
	self.localSize1d = vec3sz(math.min(maxWorkGroupSize, self.volume), 1,1)

	-- for boundaries
	do
		local localSizeX = math.min(tonumber(self.size.x), 2^math.ceil(math.log(maxWorkGroupSize,2)/2))
		local localSizeY = maxWorkGroupSize / localSizeX
		self.localSize2d = vec3sz(localSizeX, localSizeY, 1)
	end

	--	localSize3d = dim < 3 and vec3sz(16,16,16) or vec3sz(4,4,4)
	-- TODO better than constraining by math.min(self.size),
	-- look at which sizes have the most room, and double them accordingly, until all of maxWorkGroupSize is taken up
	self.localSize3d = vec3sz(1,1,1)
	local rest = maxWorkGroupSize
	local localSizeX = math.min(tonumber(self.size.x), 2^math.ceil(math.log(rest,2)/self.dim))
	self.localSize3d.x = localSizeX
	if self.dim > 1 then
		rest = rest / localSizeX
		if self.dim == 2 then
			self.localSize3d.y = math.min(tonumber(self.size.y), rest)
		elseif self.dim == 3 then
			local localSizeY = math.min(tonumber(self.size.y), 2^math.ceil(math.log(math.sqrt(rest),2)))
			self.localSize3d.y = localSizeY
			self.localSize3d.z = math.min(tonumber(self.size.z), rest / localSizeY)
		end
	end

--DEBUG:print('localSize1d',self.localSize1d)
--DEBUG:print('localSize2d',self.localSize2d:unpack())
--DEBUG:print('localSize3d',self.localSize3d:unpack())
	self.localSize = ({self.localSize1d, self.localSize2d, self.localSize3d})[self.dim]

	-- round up to next localSize factor
	self.globalSize = vec3sz()
	for i=0,2 do
		self.globalSize.s[i] = (self.size.s[i] / self.localSize.s[i]) * self.localSize.s[i]
		if self.size.s[i] % self.localSize.s[i] ~= 0 then
			self.globalSize.s[i] = self.globalSize.s[i] + self.localSize.s[i]
		end
	end
--DEBUG:print('globalSize',self.globalSize)
end

function CLDomain:buffer(args)
	return require 'cl.obj.buffer'(table(args or {}, {
		env = args and args.env or self.env,
		count = args and args.count or self.volume,
	}))
end

function CLDomain:kernel(args)
	return require 'cl.obj.kernel'(table(args, {
		env = self.env,
		domain = self,
	}))
end

return CLDomain
