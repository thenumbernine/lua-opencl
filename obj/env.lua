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
		local exts = string.trim(item:getExtensions():lower())
		return {item=item, fp64=exts:match'cl_%w+_fp64'}
	end):sort(function(a,b)
		return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
	end)[1]
	return best.item, best.fp64
end

function CLEnv:init(args)
	self.verbose = args.verbose
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

	local size = args.size or self.size
	if type(size) == 'number' then size = {size} end
	size = table(size)
	for i=#size+1,3 do size[i] = 1 end
	self.size = vec3sz(size:unpack())
	self.volume = tonumber(self.size:volume())

	self.gridDim = args.gridDim or #size

	-- https://stackoverflow.com/questions/15912668/ideal-global-local-work-group-sizes-opencl
	-- product of all local sizes must be <= max workgroup size
	local maxWorkGroupSize = tonumber(self.device:getInfo'CL_DEVICE_MAX_WORK_GROUP_SIZE')
	if self.verbose then
		print('maxWorkGroupSize',maxWorkGroupSize)
	end
	
	-- for volumes
	self.localSize1d = math.min(maxWorkGroupSize, self.volume)

	-- for boundaries
	local localSizeX = math.min(tonumber(self.size.x), 2^math.ceil(math.log(maxWorkGroupSize,2)/2))
	local localSizeY = maxWorkGroupSize / localSizeX
	self.localSize2d = table{localSizeX, localSizeY}

	--	localSize3d = gridDim < 3 and vec3sz(16,16,16) or vec3sz(4,4,4)
	-- TODO better than constraining by math.min(self.size),
	-- look at which sizes have the most room, and double them accordingly, until all of maxWorkGroupSize is taken up
	self.localSize3d = vec3sz(1,1,1)
	local rest = maxWorkGroupSize
	local localSizeX = math.min(tonumber(self.size.x), 2^math.ceil(math.log(rest,2)/self.gridDim))
	self.localSize3d.x = localSizeX
	if self.gridDim > 1 then
		rest = rest / localSizeX
		if self.gridDim == 2 then
			self.localSize3d.y = math.min(tonumber(self.size.y), rest)
		elseif self.gridDim == 3 then
			local localSizeY = math.min(tonumber(self.size.y), 2^math.ceil(math.log(math.sqrt(rest),2)))
			self.localSize3d.y = localSizeY
			self.localSize3d.z = math.min(tonumber(self.size.z), rest / localSizeY)
		end
	end

	if self.verbose then
		print('localSize1d',self.localSize1d)
		print('localSize2d',self.localSize2d:unpack())
		print('localSize3d',self.localSize3d:unpack())
	end
	self.localSize = ({self.localSize1d, self.localSize2d, self.localSize3d})[self.gridDim]
	
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
	
	self.typeCode = template([[
<? if real == 'double' then ?>
#pragma OPENCL EXTENSION cl_khr_fp64 : enable
<? end ?>

typedef <?=real?> real;
typedef <?=real?>2 real2;
typedef <?=real?>4 real4;
]], self)

	ffi.cdef(self.typeCode)

	-- only for the sake of using self as the template obj
	self.clnumber = require 'cl.obj.number'
	
	self.code = template([[
<?=typeCode?>

constant const int gridDim = <?=gridDim?>;

constant const int4 size = (int4)(<?=clnumber(size.x)?>, <?=clnumber(size.y)?>, <?=clnumber(size.z)?>, 0);
constant const int4 stepsize = (int4)(1, <?=size.x?>, <?=size.x * size.y?>, <?=size.x * size.y * size.z?>);

#define globalInt4()	(int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0)

#define indexForInt4(i) (i.x + size.x * (i.y + size.y * i.z))

#define INIT_KERNEL() \
	int4 i = globalInt4(); \
	if (i.x >= size.x || i.y >= size.y || i.z >= size.z) return; \
	int index = indexForInt4(i);
]], self)

	-- buffer allocation
	
	self.totalGPUMem = 0
end

function CLEnv:buffer(args)
	return require 'cl.obj.buffer'(table(args, {env=self}))
end

function CLEnv:clalloc(size, name, ctype)
	self.totalGPUMem = self.totalGPUMem + size
	if self.verbose then
		print((name and (name..' ') or '')..'allocating '..size..' bytes of type '..ctype..' with size '..ffi.sizeof(ctype)..', total '..self.totalGPUMem)
	end
	return self.ctx:buffer{rw=true, size=size} 
end

function CLEnv:program(args)
	return require 'cl.obj.program'(table(args, {env=self}))
end

function CLEnv:kernel(args)
	return require 'cl.obj.kernel'(table(args, {env=self}))
end

function CLEnv:clcall(kernel, ...)
	if select('#', ...) then
		kernel:setArgs(...)
	end
	self.cmds:enqueueNDRangeKernel{kernel=kernel, dim=self.gridDim, globalSize=self.size:ptr(), localSize=self.localSize:ptr()}
end

function CLEnv:reduce(args)
	return require 'cl.obj.reduce'(table(args, {env=self}))
end

return CLEnv
