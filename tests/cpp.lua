#!/usr/bin/env luajit
local ffi = require 'ffi'
require 'ext'

local function matchExt(obj, pat)
	local exts = obj:getExtensions():mapi(string.lower)
	return not not exts:find(nil, function(s) return s:match(pat) end)
end

local function isFP64(obj)
	return matchExt(obj, 'cl_%w+_fp64')
end

local function get64bit(list)
	local best = list:mapi(function(item)
		return {item=item, fp64=isFP64(item)}
	end):sort(function(a,b)
		return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
	end)[1]
	return best.item, best.fp64
end

local platform = get64bit(require 'cl.platform'.getAll())
local devices = platform:getDevices{gpu=true}:mapi(function(device)
	return isFP64(device) and device
end)
for i,device in ipairs(devices) do
	print('device '..i..': '..tostring(device:getName()))
end

local fp64 = #devices:filter(isFP64) == #devices

local n = 64
local real = fp64 and 'double' or 'float'
print('using real',real)

local ctx = require 'cl.context'{platform=platform, devices=devices}

local cl = require 'ffi.OpenCL'
local CommandQueue = require 'cl.commandqueue'
local cmds = devices:mapi(function(device)
	return CommandQueue{context=ctx, device=device, properties=cl.CL_QUEUE_PROFILING_ENABLE}
end)

local code =
'#define N '..n..'\n'..
'#define real '..real..'\n'..
(fp64 and '#pragma OPENCL EXTENSION cl_khr_fp64 : enable\n' or '')..
[[

#if 0
namespace notused {
};
#endif

#if 0
class T {
public:
	real value;
};
#else
typedef struct {
	real value;
} T;

#endif

kernel void test(
	global T* c,
	const global T* a,
	const global T* b
) {
	int i = get_global_id(0);
	if (i >= N) return;
	c[i].value = a[i].value * b[i].value;
}
]]

local Program = require 'cl.program'
--[[ C version
local program = Program{context=ctx, devices=devices, code=code}
--]]
--[[ not working, because -cl-std=CLC++ reuqires cl_ext_cxx_for_opencl, which I don't have on this machine 
local program = Program{context=ctx, devices=devices, code=code, buildOptions='-cl-std=CLC++'}
--]]
-- [[ C++ via ILn
file'cpptest.clcpp':write(code)
		--[=[
		https://github.com/KhronosGroup/SPIR/tree/spirv-1.1
		how to compile 32-bit SPIR-V:
			clang -cc1 -emit-spirv -triple <triple> -cl-std=c++ -I <libclcxx dir> -x cl -o <output> <input> 				#For OpenCL C++
			clang -cc1 -emit-spirv -triple <triple> -cl-std=<CLversion> -include opencl.h -x cl -o <output> <input> 		#For OpenCL C
		how to compile 64-bit SPIR-V:
			clang -cc1 -emit-spirv -triple=spir-unknown-unknown -cl-std=c++ -I include kernel.cl -o kernel.spv 				#For OpenCL C++
			clang -cc1 -emit-spirv -triple=spir-unknown-unknown -cl-std=CL2.0 -include opencl.h kernel.cl -o kernel.spv 	#For OpenCL C
		--]=]
local function echo(cmd)
	print('>'..cmd)
	return os.execute(cmd)
end
-- TODO the -I should be to a file opencl.h which is ... where?
-- https://clang.llvm.org/docs/OpenCLSupport.html
assert(echo(
	table{
		--[=[
		'clang',
		--'-cc1 -emit-spirv',
		--'-triple spir-unknown-unknown',
		'-target spir-unknown-unknown',
		'-c -emit-llvm -Xclang',
		-- '-cl-std=c++',
		-- '-I <libclcxx dir>',
		-- '-x cl',
		--]=]
		-- [=[
		--'clang -cl-std=CL3.0 -cl-ext=+cl_khr_fp64,+__opencl_c_fp64',	-- cpptest.clcpp:(.text+0x16): undefined reference to `get_global_id(unsigned int)'
		-- does that mean I need something extra?
		'clang -c -cl-std=CL3.0 -cl-ext=+cl_khr_fp64,+__opencl_c_fp64',	-- clang: warning: argument unused during compilation: '-cl-ext=+cl_khr_fp64,+__opencl_c_fp64' [-Wunused-command-line-argument]
		--'--spirv-max-version=1.0',	--https://community.khronos.org/t/clcreateprogramwithil-spir-v-failed-with-cl-invalid-value/109208 --clang: error: unsupported option '--spirv-max-version=1.0'
		-- and building gives: clCreateProgramWithIL failed with error -42: CL_INVALID_BINARY
		--]=]
		'-o', '"cpptest.spv"',
		'"cpptest.clcpp"',
	}:concat' '
))
local IL = file'cpptest.spv':read()
assert(IL, "failed to read file cpptest.spv")
local program = Program{context=ctx, devices=devices, IL=IL}
--]]

-- gpu mem
local aBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}
local bBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}
local cBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}

-- cpu mem
local aMem = ffi.new(real..'[?]', n)
local bMem = ffi.new(real..'[?]', n)
local cMem = ffi.new(real..'[?]', n)
for i=0,n-1 do 
	aMem[i] = i+1
	bMem[i] = i+1
end

cmds[1]:enqueueWriteBuffer{buffer=aBuffer, block=true, size=n*ffi.sizeof(real), ptr=aMem}
cmds[1]:enqueueWriteBuffer{buffer=bBuffer, block=true, size=n*ffi.sizeof(real), ptr=bMem}

local testKernel = program:kernel('test', cBuffer, aBuffer, bBuffer)
local maxWorkGroupSize = tonumber(testKernel:getWorkGroupInfo('CL_KERNEL_WORK_GROUP_SIZE', devices[1]))

local event = require 'cl.event'()
cmds[1]:enqueueNDRangeKernel{kernel=testKernel, globalSize=n, localSize=math.min(16, maxWorkGroupSize), event=event}
cmds[1]:finish()
local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
local fin = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
print('duration', tonumber(fin - start)..' ns')
cmds[1]:enqueueReadBuffer{buffer=cBuffer, block=true, size=n*ffi.sizeof(real), ptr=cMem}
for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()

print'done'
