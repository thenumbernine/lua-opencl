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

--[[
args (all are passed along to CLDomain):
	size
	dim
	verbose
--]]
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

	self.domain = require 'cl.obj.domain'{
		env = self,
		size = args.size,
		dim = args.dim,
		verbose = args.verbose,
	}

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

#define globalInt4()	(int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0)

#define indexForInt4ForSize(i, sx, sy, sz) (i.x + sx * (i.y + sy * i.z))
#define initKernelForSize(sx, sy, sz) \
	int4 i = globalInt4(); \
	if (i.x >= sx || i.y >= sy || i.z >= sz) return; \
	int index = indexForInt4ForSize(i, sx, sy, sz);

constant const int dim = <?=domain.dim?>;
constant const int4 size = (int4)(<?=clnumber(domain.size.x)?>, <?=clnumber(domain.size.y)?>, <?=clnumber(domain.size.z)?>, 0);
constant const int4 stepsize = (int4)(1, <?=domain.size.x?>, <?=domain.size.x * domain.size.y?>, <?=domain.size.x * domain.size.y * domain.size.z?>);

#define indexForInt4(i)	indexForInt4ForSize(i, size.x, size.y, size.z)
#define INIT_KERNEL()	initKernelForSize(size.x, size.y, size.z)
]], self)

	-- buffer allocation
	
	self.totalGPUMem = 0
end

function CLEnv:buffer(args)
	return require 'cl.obj.buffer'(table(args or {}, {env=self}))
end

function CLEnv:clalloc(size, name, ctype)
	self.totalGPUMem = self.totalGPUMem + size
	if self.verbose then
		print((name and (name..' ') or '')..'allocating '..size..' bytes of type '..ctype..' with size '..ffi.sizeof(ctype)..', total '..self.totalGPUMem)
	end
	return self.ctx:buffer{rw=true, size=size} 
end

function CLEnv:program(args)
	return require 'cl.obj.program'(table(args or {}, {env=self}))
end

function CLEnv:kernel(args)
	return require 'cl.obj.kernel'(table(args, {env=self}))
end

--[[
function CLEnv:clcall(kernel, ...)
	if select('#', ...) then
		kernel:setArgs(...)
	end
	self.cmds:enqueueNDRangeKernel{kernel=kernel, dim=self.domain.dim, globalSize=self.domain.globalSize:ptr(), localSize=self.domain.localSize:ptr()}
end
--]]

--[[ but env.domain is already used ...
function CLEnv:domain(args)
	return require 'cl.obj.domain'(table(args, {env=self}))
end
--]]

function CLEnv:reduce(args)
	return require 'cl.obj.reduce'(table(args, {env=self}))
end

return CLEnv
