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


-- boilerplate so OpenCL types will work with ffi types
-- TODO for support for multiple environments ... 
--  you could check for previous type declaration with pcall(ffi.sizeof,'real')
for _,real in ipairs{'float', 'double'} do
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
	real = real,
}))
end

local CLEnv = class()

local function get64bit(list, precision)
	local all = list:map(function(item)
		local exts = string.trim(item:getExtensions():lower())
		return {item=item, fp64=exts:match'cl_%w+_fp64'}
	end)

	-- choose double if we must
	if precision == 'double' then
		all = all:filter(function(a) return a.fp64 end)
		assert(#all > 0, "couldn't find anything with 64 bit precision")
	-- otherwise prioritize it
	-- TODO what if the user wants gl sharing too?
	-- should I prioritize a search for that extension as well?
	else
		all:sort(function(a,b)
			return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
		end)
	end

	local best = all[1]
	return best.item, best.fp64
end

--[[
args for CLEnv:
	precision = any | float | double 
		= precision type to support.  default 'any'.
			honestly 'any' and 'float' are the same, because any device is going to have floating precision.
			both of these also prefer devices with double precision.
			but only 'double' will error out if it can't find double precision.

args passed along to CLDomain:
	size
	dim
	verbose
	queue = (optional) command-queue arguments 
--]]
function CLEnv:init(args)
	self.verbose = args and args.verbose
	local precision = args and args.precision or 'any'
	self.platform = get64bit(require 'cl.platform'.getAll(), precision)
	local fp64
	self.device, fp64 = get64bit(self.platform:getDevices{gpu=true}, precision)
	
	local exts = string.split(string.trim(self.device:getExtensions()):lower(),'%s+')
	self.useGLSharing = exts:find(nil, function(ext) 
		return ext:match'cl_%w+_gl_sharing' 
	end)

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
	if args then
		self.base = self:domain{
			size = args.size,
			dim = args.dim,
			verbose = args.verbose,
		}
	end

	-- initialize types
	
	self.real = fp64 and 'double' or 'float'
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
	not self.base and '' or template([[

//static variables for the base domain
constant const int dim = <?=dim?>;
constant const int4 size = (int4)(<?=
	clnumber(size.x)?>, <?=
	clnumber(size.y)?>, <?=
	clnumber(size.z)?>, 0);
constant const int4 stepsize = (int4)(1, <?=
	size.x?>, <?=
	size.x * size.y?>, <?=
	size.x * size.y * size.z?>);

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
<? end ?>

typedef <?=real?> real;
typedef <?=real?>2 real2;
typedef <?=real?>4 real4;
]], {
	real = self.real,
})
end

function CLEnv:buffer(args)
	return (args and args.domain or self.base):buffer(args)
end

function CLEnv:clalloc(size, name, ctype)
	self.totalGPUMem = self.totalGPUMem + size
	if self.verbose then
		print((name and (name..' ') or '')..'allocating '..tostring(size)..' bytes of type '..ctype..' with size '..ffi.sizeof(ctype)..', total '..self.totalGPUMem)
	end
	return self.ctx:buffer{rw=true, size=size}
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
