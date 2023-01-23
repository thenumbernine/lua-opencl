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

// https://clang.llvm.org/docs/OpenCLSupport.html#c-libraries-for-opencl
#if 0 // cpptest.clcpp:8:10: fatal error: 'type_traits' file not found
#pragma OPENCL EXTENSION __cl_clang_function_pointers : enable
#pragma OPENCL EXTENSION __cl_clang_variadic_functions : enable
#include <type_traits>
#pragma OPENCL EXTENSION __cl_clang_function_pointers : disable
#pragma OPENCL EXTENSION __cl_clang_variadic_functions : disable

// C++ test:
// ex from https://clang.llvm.org/docs/OpenCLSupport.html#c-libraries-for-opencl
using sint_type = std::make_signed<unsigned int>::type;
static_assert(!std::is_same<sint_type, unsigned int>::value);

#endif

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

// C++ test that doesnt' need include files ...
using T2 = int;

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
local clcppfn = 'cpptest.clcpp'
local bcfn = 'cpptest.bc'
local spvfn = 'cpptest.spv'
-- [[ C++ via ILn
file(clcppfn):write(code)
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
assert(echo(table{
	'clang',
	'-v',
	--'-cc1','-emit-spirv',
	--'-triple spir-unknown-unknown',
	--'-target spir-unknown-unknown',
	--'-c','-emit-llvm',
	-- '-I <libclcxx dir>',
	-- from here: https://community.khronos.org/t/clcreateprogramwithil-spir-v-failed-with-cl-invalid-value/109208
	-- https://clang.llvm.org/docs/OpenCLSupport.html: says -Xclang or -cc1 is exclusive
	'-Xclang','-finclude-default-header',	-- -X<where> = pass arg to 
	--'-cc1','-finclude-default-header',	-- clang: error: unknown argument: '-cc1'
	--'-target spir-unknown-unknown',
	'--target=spirv64-unknown-unknown',	-- clang: error: unable to execute command: Executable "llvm-spirv" doesn't exist!
	--'--target=spirv-unknown-unknown',	-- error: unknown target triple 'unknown-unknown-unknown-spirv-unknown-unknown', please use -triple or -arch
	--'-triple spir-unknown-unknown',		-- (with --target=) clang: error: unknown argument: '-triple'
	'-emit-llvm',	-- error: Opaque pointers are only supported in -opaque-pointers mode (Producer: 'LLVM15.0.2' Reader: 'LLVM 14.0.6')
	--'-opaque-pointers',
	'-D SPIR',
	'-c',				-- without -c: clang: cpptest.cl:(.text+0x16): undefined reference to `get_global_id(unsigned int)' clang: error: linker command failed with exit code 1 (use -v to see invocation)
	'-o0',
	--'-x cl',	-- clang: error: no such file or directory: 'cl' 
	--'-cl-std=c++',	-- clang: error: invalid value 'c++' in '-cl-std=c++'
	-- does that mean I need something extra?
	--'-cl-std=CL3.0',
	--'-cl-ext=+cl_khr_fp64,+__opencl_c_fp64',
	 -- (if you omit -Xclang SOMETHING what tho?) clang: warning: argument unused during compilation: '-cl-ext=+cl_khr_fp64,+__opencl_c_fp64' [-Wunused-command-line-argument]
	--'--spirv-max-version=1.0',	-- clang: error: unsupported option '--spirv-max-version=1.0'
	-- and building gives: clCreateProgramWithIL failed with error -42: CL_INVALID_BINARY
	
	-- https://clang.llvm.org/docs/OpenCLSupport.html:
	--'-cl-kernel-arg-info',

	--'-o', ('%q'):format(spvfn),
	'-o', ('%q'):format(bcfn),
	('%q'):format(clcppfn),
}:concat' '))
-- [[ if you use -c :
-- according to the community.khronos.org post I should next run:
--  llvm-spirv cpptest.bc -o test.spv
assert(echo(table{
	'llvm-spirv',
	--'-Xclang','-finclude-default-header',
	--'--target=spirv64-unknown-unknown',	-- clang: error: unable to execute command: Executable "llvm-spirv" doesn't exist!
	--'-emit-llvm',	-- clang: error: -emit-llvm cannot be used when linking
	('%q'):format(bcfn),
	'-o', ('%q'):format(spvfn),
}:concat' '))
--]]
-- ... but I don't have it installed right now
local IL = file(spvfn):read()
assert(IL, "failed to read file "..spvfn)
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
