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
local ffi = require 'ffi'
local template = require 'template'

ffi.cdef'typedef short half;'

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

local function get64bit(list, precision)
	local all = list:mapi(function(item)
		local exts = item:getExtensions():mapi(string.lower)
		return {
			item=item, 
			fp64=not not exts:find(nil, function(ext) return ext:match'cl_.*_fp64' end),
			fp16=not not exts:find(nil, function(ext) return ext:match'cl_.*_fp16' end),
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

	local best = all[1]
	return best.item, best.fp64, best.fp16
end


-- predefined getPlatform and getDevice

local function getterForIdent(ident, identType)
	return function(objs)
		for i,obj in ipairs(objs) do
			if type(ident) == 'nil' then
				return obj
			elseif type(ident) == 'number' then
				if ident == i then return obj end
			elseif type(ident) == 'string' then
				if ident == obj:getName() then return obj end
			end
		end
		error("couldn't find "..identType)
	end
end

local function getCmdline(...)
	local cmdline = {}
	local fromlua = require 'ext.fromlua'
	for _,w in ipairs{...} do
		local k,v = w:match'^(.-)=(.*)$'
		if k then
			cmdline[k] = fromlua(v)
			if cmdline[k] == nil then cmdline[k] = v end
		else
			cmdline[w] = true
		end
	end
	return cmdline
end

-- predefined option for args.getPlatform
function CLEnv.getPlatformFromCmdLine(...)
	return getterForIdent(getCmdline(...).platform, 'platform')
end

-- predefined option for args.getDevice
function CLEnv.getDeviceFromCmdLine(...)
	local device = getCmdline(...).device
	return device and getterForIdent(device, 'device')
end


--[[
args for CLEnv:
	precision = any | half | float | double 
		= precision type to support.  default 'any'.
			honestly 'any' and 'float' are the same, because any device is going to have floating precision.
			both of these also prefer devices with double precision.
			but only 'double' will error out if it can't find double precision.

args passed along to CLDomain:
	size
	dim
	verbose
	queue = (optional) command-queue arguments 
	useGLSharing = (optional) set to false to disable GL sharing
--]]
function CLEnv:init(args)
	args = args or {}
	self.verbose = args and args.verbose
	local precision = args and args.precision or 'any'
	
	local platforms = require 'cl.platform'.getAll()
	-- khr_fp16 isn't set on the platform, but it is on the device
	self.platform = (args.getPlatform or get64bit)(platforms, precision == 'half' and 'float' or precision)
	if self.verbose then
		print(self.platform:getName())
	end

	local fp64
	self.device, fp64 = args.getDevice 
		and args.getDevice(self.platform:getDevices())
		or get64bit(self.platform:getDevices{[args.cpu and 'cpu' or 'gpu']=true}, precision)
	if self.verbose then
		print(self.device:getName())
	end

	local _, fp64, fp16 = get64bit(table{self.device}, precision)

	local exts = self.device:getExtensions():mapi(string.lower)
	
	-- don't use GL sharing if we're told not to
	if not args or args.useGLSharing ~= false then
		self.useGLSharing = not not exts:find(nil, function(ext) 
			return ext:match'cl_%w+_gl_sharing' 
		end)
	end

	self.ctx = require 'cl.context'{
		platform = self.platform, 
		device = self.device,
		glSharing = self.useGLSharing,
	}
	self.cmds = require 'cl.commandqueue'{	
		context = self.ctx,
		device = self.device,
		properties = args and args.queue and args.queue.properties,
	}
	
	-- if no size/dim is provided then don't make a base
	-- however, this will make constructing buffers and kernels difficult 
	-- (does that mean I shouldn't route those calls through domain -- though they are very domain-specific)
	if args and (args.size or args.dim) then
		self.base = self:domain{
			size = args.size,
			dim = args.dim,
			verbose = args.verbose,
		}
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
	return self.ctx:buffer{[readwrite]=true, size=size}
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
