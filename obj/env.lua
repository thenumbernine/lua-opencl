--[[
This is going to be more like my lua-gl than my lua-cl
Honestly lua-cl was just a port of cl.hpp -- no wrapping classes
This is the wrapping classes for cl.hpp

cl environment for execution
handles platform, devices, command queue
glSharing? fp64?
local sizes, global size
and ffi typedefs to match the OpenCL types
--]]

local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local table = require 'ext.table'
local string = require 'ext.string'
local getCmdline = require 'ext.cmdline'
local template = require 'template'

ffi.cdef[[
typedef union {
	unsigned short i;
	unsigned char ptr[2];
	struct {
		unsigned short mant : 10;
		unsigned short exp : 5;
		unsigned short sign : 1;
	};
} float16bits_t;	//in OpenCL, 'float8' means 8x 4-byte-float ... in some languages 'float16' means 2-byte float ...
typedef float16bits_t half;
]]
assert(ffi.sizeof'float16bits_t' == 2)

-- boilerplate so OpenCL types will work with ffi types
-- TODO for support for multiple environments ... 
--  you could check for previous type declaration with pcall(ffi.sizeof,'real')
for _,name in ipairs{'half', 'float', 'double', 'int'} do
	ffi.cdef(template([[
typedef union {
	<?=name?> s[2];
	struct { <?=name?> s0, s1; };
	struct { <?=name?> x, y; };
} <?=name?>2;

//for real4 I'm using x,y,z,w to match OpenCL
typedef union {
	<?=name?> s[4];
	struct { <?=name?> s0, s1, s2, s3; };
	struct { <?=name?> x, y, z, w; };	
} <?=name?>4;

typedef union {
	<?=name?> s[8];
	struct { <?=name?> s0, s1, s2, s3, s4, s5, s6, s7; };
} <?=name?>8;

]], {
		name = name,
	}))
end

local CLEnv = class()

local function isFP64(obj)
	return not not obj:getExtensions():mapi(string.lower):find(nil, function(ext) return ext:match'cl_.*_fp64' end)
end

local function isFP16(obj)
	return not not obj:getExtensions():mapi(string.lower):find(nil, function(ext) return ext:match'cl_.*_fp16' end)
end

local function getForPrecision(list, precision)
	local all = list:mapi(function(item)
		local exts = item:getExtensions():mapi(string.lower)
		return {
			item = item, 
			fp64 = isFP64(item),
			fp16 = isFP16(item),
		}
	end)
	-- choose double if we must
	if precision == 'double' then
		all = all:filter(function(a) return a.fp64 end)
		assert(#all > 0, "couldn't find anything with 64 bit precision")
	-- otherwise prioritize it
	-- TODO what if the user wants gl sharing too?
	-- should I prioritize a search for that extension as well?
	elseif precision == 'half' then
		all = all:filter(function(a) return a.fp16 end)
		assert(#all > 0, "couldn't find anything with 16 bit precision")
	else
		all:sort(function(a,b)
			return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
		end)
	end

	return all:mapi(function(o) return o.item end)
end


-- predefined getPlatform and getDevice

local function getterForIdent(ident, identType)
	return function(objs)
		for i,obj in ipairs(objs) do
			if type(ident) == 'nil' then
				return {obj}
			elseif type(ident) == 'number' then
				if ident == i then return {obj} end
			elseif type(ident) == 'string' then
				if ident == obj:getName() then return {obj} end
			end
		end
		error("couldn't find "..identType)
	end
end

-- predefined option for args.getPlatform
-- () -> ( (platform list, precision) -> platform )
function CLEnv.getPlatformFromCmdLine(...)
	local cmdline = getCmdline(...)
	return getterForIdent(cmdline.platform, 'platform')
end

-- Predefined option for args.getDevices
-- () -> ( (platform list, precision) -> platform )
-- This allows for device=1 or "device=Intel OpenCL"
-- But does not yet handle multiple devices
function CLEnv.getDevicesFromCmdLine(devices, ...)
	local cmdline = getCmdline(...)
	if cmdline.device then
		return getterForIdent(cmdline.device, 'device')
	end
	return function(...) return ... end
end

-- Predefined option for args.deviceType
-- cmdline properties:
--	default = CL_DEVICE_TYPE_DEFAULT
--	cpu = CL_DEVICE_TYPE_CPU
--	gpu = CL_DEVICE_TYPE_GPU
--	accelerator = CL_DEVICE_TYPE_ACCELERATOR
--	all = CL_DEVICE_TYPE_ALL
--  deviceType=<type> = specifies the type above (default|cpu|gpu|accelerator|all)
-- 	deviceType=<number> = specifies the numeric CL device type
local deviceTypeValueForName = {
	default = cl.CL_DEVICE_TYPE_DEFAULT,
	cpu = cl.CL_DEVICE_TYPE_CPU,
	gpu = cl.CL_DEVICE_TYPE_GPU,
	accelerator = cl.CL_DEVICE_TYPE_ACCELERATOR,
	all = cl.CL_DEVICE_TYPE_ALL,
}
function CLEnv.getDeviceTypeFromCmdLine(...)
	local cmdline = getCmdline(...)
	local deviceType = cmdline.deviceType
	if type(deviceType) == 'string' then 
		deviceType = assert(deviceTypeValueForName[deviceType], "couldn't understand deviceType="..tostring(deviceType))
	end
	for k,v in pairs(deviceTypeValueForName) do
		if cmdline[k] then
			deviceType = bit.bor(deviceType or 0, v) 
		end
	end
	return deviceType or cl.CL_DEVICE_TYPE_ALL
end

--[[
args for CLEnv:
	precision = any | half | float | double 
		= precision type to support.  default 'any'.
			honestly 'any' and 'float' are the same, because any device is going to have floating precision.
			both of these also prefer devices with double precision.
			but only 'double' will error out if it can't find double precision.
	getPlatform = (optional) function(platforms) returns desired platform
	getDevice = (optional) function(devices) returns table of desired devices
	deviceType = (optional) function() returns CL_DEVICE_TYPE_*** 
	cpu = (optional) only use CL_DEVICE_TYPE_CPU
	gpu = (optional, default) only use CL_DEVICE_TYPE_GPU
	useGLSharing = (optional) set to false to disable GL sharing

args passed to CLCommandQueue:
	queue = (optional) command-queue arguments 

args passed along to CLDomain:
	size
	dim
	verbose
--]]
function CLEnv:init(args)
	args = args or {}
	self.verbose = args and args.verbose
	local precision = args and args.precision or 'any'
	
	local platforms = require 'cl.platform'.getAll()
	-- khr_fp16 isn't set on the platform, but it is on the device
	local getter = args.getPlatform or getForPrecision
	assert(getter, "expected either args.getPlatform or getForPrecision to exist")
	platforms = getter(platforms, precision == 'half' and 'float' or precision)
	self.platform = assert(platforms[1], "couldn't find any platforms with precision "..tostring(precision))
	if self.verbose then
		print(self.platform:getName())
	end

	self.devices = self.platform:getDevices{
		[args.cpu and 'cpu' or (args.deviceType and '' or 'gpu')] = true,
		[args.deviceType and 'deviceType' or ''] = args.deviceType or nil,
	}
	if args.getDevices then
		self.devices = table(args.getDevices(self.devices))
	else
		self.devices = table(getForPrecision(self.devices, precision))
		if #self.devices == 0 then
			error("couldn't get any devices for precision "..tostring(precision))
		end
	end

	if self.verbose then
		for i,device in ipairs(self.devices) do
			print(i, device:getName())
		end
	end

	local fp64 = #self.devices:filter(isFP64) == #self.devices
	local fp16 = #self.devices:filter(isFP16) == #self.devices
	
	-- don't use GL sharing if we're told not to
	if not args or args.useGLSharing ~= false then
		local numDevicesWithGLSharing = #self.devices:filter(function(device, deviceIndex)
			local exts = device:getExtensions()
			return exts:mapi(string.lower):find(nil, function(ext)
				local found = ext:match'cl_%w+_gl_sharing'
				if self.verbose and found then
					print('device '..device:getName()..' has gl sharing extension: '..ext)
				end
				return found
			end)
		end)
		if self.verbose then
			print(numDevicesWithGLSharing..'/'..#self.devices..' devices have gl sharing (according to device cl extensions)')
		end
		self.useGLSharing = numDevicesWithGLSharing == #self.devices
	end
	if self.verbose then
		print('using GL sharing: '..tostring(self.useGLSharing or false))
	end

	self.ctx = require 'cl.context'{
		platform = self.platform, 
		devices = self.devices,
		glSharing = self.useGLSharing,
		verbose = self.verbose,
	}

	local CommandQueue = require 'cl.commandqueue'
	self.cmds = self.devices:mapi(function(device)
		return CommandQueue{
			context = self.ctx,
			device = device,
			properties = args and args.queue and args.queue.properties,
		}
	end)

	-- if no size/dim is provided then don't make a base
	-- however, this will make constructing buffers and kernels difficult 
	-- (does that mean I shouldn't route those calls through domain -- though they are very domain-specific)
	if args and (args.size or args.dim) then
		self.base = self:domain{
			size = args.size,
			dim = args.dim,
			verbose = args.verbose,
			
			-- default domain gets a default device
			device = self.devices[1],
		}
		self.dim = self.dim or self.base.dim
	end

	-- initialize types
	
	self.real = (precision ~= 'float' and precision ~= 'half') and fp64 and 'double' 
		or (precision == 'half' and fp16 and 'half' 
			or 'float')
	if precision == 'float' then self.real = 'float' end
	if self.verbose then
		print('using '..self.real..' as real')
	end

	-- typeCode goes to ffi.cdef and to the CL code header
	local typeCode = self:getTypeCode()
	
	-- have luajit cdef the types so I can see the sizeof (I hope OpenCL agrees with padding)
	ffi.cdef(typeCode)

	-- the env CL code header goes on top of all compiled programs
	self.code = table{
		typeCode,
		[[
//macro for the index
#define globalInt4()	(int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0)

//macros for arbitrary sizes
#define indexForInt4ForSize(i, sx, sy, sz) (i.x + sx * (i.y + sy * i.z))
#define initKernelForSize(sx, sy, sz) \
	int4 i = globalInt4(); \
	if (i.x >= sx || i.y >= sy || i.z >= sz) return; \
	int index = indexForInt4ForSize(i, sx, sy, sz);
]],

	-- all this gets omitted if no base size is used in the env
	not self.base and '' or template([[
//static variables for the base domain
constant const int dim = <?=dim?>;
constant const int4 size = (int4)(<?=
	tonumber(size.x)?>, <?=
	tonumber(size.y)?>, <?=
	tonumber(size.z)?>, 0);
constant const int4 stepsize = (int4)(1, <?=
	tonumber(size.x)?>, <?=
	tonumber(size.x * size.y)?>, <?=
	tonumber(size.x * size.y * size.z)?>);

//macros for the base domain
#define indexForInt4(i)	indexForInt4ForSize(i, size.x, size.y, size.z)
#define initKernel()	initKernelForSize(size.x, size.y, size.z)
]], {
	dim = self.base.dim,
	size = self.base.size,
	clnumber = require 'cl.obj.number',
})}:concat'\n'

	-- buffer allocation
	
	self.totalGPUMem = 0
end

function CLEnv:getTypeCode()
	return template([[
<? if real == 'double' then ?>
#pragma OPENCL EXTENSION cl_khr_fp64 : enable
<? elseif real == 'half' then ?>
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
<? end ?>

typedef <?=real?> real;
typedef <?=real?>2 real2;
typedef <?=real?>4 real4;
typedef <?=real?>8 real8;
]], {
	real = self.real,
})
end

function CLEnv:buffer(args)
	-- if args.count is specified then we don't need to assume things from the domain
	if args and args.count then
		return require 'cl.obj.buffer'(table(args, {env=self}))
	end
	-- otherwise depend on the domain (or env's domain)'s size
	return (args and args.domain or self.base):buffer(args)
end

--[[
size = size in bytes
readwrite = (optional) default to 'rw'.  options are rw, read, write
--]]
function CLEnv:clalloc(size, name, ctype, readwrite)
	readwrite = readwrite or 'rw'
	self.totalGPUMem = self.totalGPUMem + size
	if self.verbose then
		print((name and (name..' ') or '')..'allocating '..tostring(size)..' bytes of type '..ctype..' size '..ffi.sizeof(ctype)..', total '..tostring(self.totalGPUMem)..' bytes')
	end
	return self.ctx:buffer{readwrite=readwrite, size=size}
end

function CLEnv:program(args)
	return require 'cl.obj.program'(table(args or {}, {env=self}))
end

function CLEnv:kernel(...)
	assert(self.base, "CLEnv:kernel only works if the CLEnv is initialized with a size / has a base domain")
	return self.base:kernel(...)
end

function CLEnv:domain(args)
	return require 'cl.obj.domain'(table(args or {}, {env=self}))
end

function CLEnv:reduce(args)
	return require 'cl.obj.reduce'(table(args or {}, {env=self}))
end

return CLEnv
