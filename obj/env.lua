--[[
This is going to be more like my lua-gl than my lua-cl
Honestly lua-cl was just a port of cl.hpp -- no wrapping classes
This is the wrapping classes for cl.hpp

cl environment for execution
handles platform, device, command queue
glSharing? fp64?
local sizes, global size
and ffi typedefs to match the OpenCL types
--]]

local class = require 'ext.class'
local table = require 'ext.table'
local string = require 'ext.string'
local vec3sz = require 'ffi.vec.vec3sz'
local ffi = require 'ffi'
local template = require 'template'

local CLEnv = class()

local function get64bit(list)
	local best = list:map(function(item)
		local exts = item:getExtensions():lower():trim()
		return {item=item, fp64=exts:match'cl_%w+_fp64'}
	end):sort(function(a,b)
		return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
	end)[1]
	return best.item, best.fp64
end

function CLEnv:init(args)
	self.platform = get64bit(require 'cl.platform'.getAll())
	self.device, self.fp64 = get64bit(self.platform:getDevices{gpu=true})
	
	local exts = string.split(string.trim(self.device:getExtensions()):lower(),'%s+')
	self.useGLSharing = exts:find(nil, function(ext) 
		return ext:match'cl_%w+_gl_sharing' 
	end)

	self.ctx = require 'cl.context'{
		platform = self.platform, 
		device = self.device,
		glSharing = self.useGLSharing,
	}
	self.cmds = require 'cl.commandqueue'{context=self.ctx, device=self.device}
	
	self.size = vec3sz(table.unpack(assert(args.size)))
	self.volume = tonumber(self.size:volume())

	self.gridDim = assert(args.gridDim)

	-- https://stackoverflow.com/questions/15912668/ideal-global-local-work-group-sizes-opencl
	-- product of all local sizes must be <= max workgroup size
	local maxWorkGroupSize = tonumber(self.device:getInfo'CL_DEVICE_MAX_WORK_GROUP_SIZE')
	print('maxWorkGroupSize',maxWorkGroupSize)

	-- for volumes
	local localSize1d = math.min(maxWorkGroupSize, self.volume)

	-- for boundaries
	local localSizeX = math.min(tonumber(self.size.x), 2^math.ceil(math.log(maxWorkGroupSize,2)/2))
	local localSizeY = maxWorkGroupSize / localSizeX
	local localSize2d = table{localSizeX, localSizeY}

	--	localSize3d = gridDim < 3 and vec3sz(16,16,16) or vec3sz(4,4,4)
	-- TODO better than constraining by math.min(self.size),
	-- look at which sizes have the most room, and double them accordingly, until all of maxWorkGroupSize is taken up
	local localSize3d = vec3sz(1,1,1)
	local rest = maxWorkGroupSize
	local localSizeX = math.min(tonumber(self.size.x), 2^math.ceil(math.log(rest,2)/self.gridDim))
	localSize3d.x = localSizeX
	if self.gridDim > 1 then
		rest = rest / localSizeX
		if self.gridDim == 2 then
			localSize3d.y = math.min(tonumber(self.size.y), rest)
		elseif self.gridDim == 3 then
			local localSizeY = math.min(tonumber(self.size.y), 2^math.ceil(math.log(math.sqrt(rest),2)))
			localSize3d.y = localSizeY
			localSize3d.z = math.min(tonumber(self.size.z), rest / localSizeY)
		end
	end

	print('localSize1d',localSize1d)
	print('localSize2d',localSize2d:unpack())
	print('localSize3d',localSize3d:unpack())
	
	self.localSize1d = localSize1d
	self.localSize2d = localSize2d
	self.localSize3d = localSize3d
	self.localSize = ({localSize1d, localSize2d, localSize3d})[self.gridDim]
	
	-- initialize types
	
	self.real = self.fp64 and 'double' or 'float'

	-- boilerplate so OpenCL types will work with ffi types
	ffi.cdef(template([[
typedef union {
	<?=real?> s[2];
	struct { <?=real?> s0, s1; };
	struct { <?=real?> x, y; };
} <?=real?>2;

//for real4 I'm using x,y,z,w to match OpenCL
//...though for my own use I am storing t,x,y,z
typedef union {
	<?=real?> s[4];
	struct { <?=real?> s0, s1, s2, s3; };
	struct { <?=real?> x, y, z, w; };	
} <?=real?>4;

]], {
	real = self.real,
}))
	
	-- buffer allocation
	
	self.totalGPUMem = 0
end

function CLEnv:makeBuffer(args)
	return require 'clbuffer'(table(args, {env=self}))
end

function CLEnv:clalloc(size, name, ctype)
	self.totalGPUMem = self.totalGPUMem + size
	print((name and (name..' ') or '')..'allocating '..size..' bytes of type '..ctype..' with size '..ffi.sizeof(ctype)..', total '..self.totalGPUMem)
	return self.ctx:buffer{rw=true, size=size} 
end

function CLEnv:makeProgram(args)
	return require 'clprogram'(table(args, {env=self}))
end

function CLEnv:kernel(args)
	return require 'clkernel'(table(args, {env=self}))
end

function CLEnv:clcall(kernel, ...)
	if select('#', ...) then
		kernel:setArgs(...)
	end
	self.cmds:enqueueNDRangeKernel{kernel=kernel, dim=self.gridDim, globalSize=self.size:ptr(), localSize=self.localSize:ptr()}
end

return CLEnv
