#!/usr/bin/env luajit
-- cl-cpp test by invoking clang through the cl.obj.program class
--[[ output:
>>
	clang
	-O0
	-DARRAY_SIZE=64
	-DREAL=double
	-c
	-cl-std=clc++
	-v
	--target=spirv64-unknown-unknown
	-emit-llvm
	-o
	"cpptest.bc"
	"cpptest.tmp.clcpp"
Ubuntu clang version 18.1.3 (1ubuntu1)
Target: spirv64-unknown-unknown
Thread model: posix
InstalledDir: /usr/bin
 (in-process)
 "/usr/lib/llvm-18/bin/clang" -cc1 -triple spirv64-unknown-unknown -Wspir-compat -emit-llvm-bc -emit-llvm-uselists -disable-free -clear-ast-before-backend -disable-llvm-verifier -discard-value-names -main-file-name cpptest.tmp.clcpp -mrelocation-model static -mframe-pointer=all -ffp-contract=on -fno-rounding-math -mconstructor-aliases -debugger-tuning=gdb -fdebug-compilation-dir=/home/chris/Projects/lua/cl/tests -v -fcoverage-compilation-dir=/home/chris/Projects/lua/cl/tests -resource-dir /usr/lib/llvm-18/lib/clang/18 -D ARRAY_SIZE=64 -D REAL=double -O0 -ferror-limit 19 -cl-std=clc++ -finclude-default-header -fdeclare-opencl-builtins -fgnuc-version=4.2.1 -fno-threadsafe-statics -fskip-odr-check-in-gmf -fcolor-diagnostics -o cpptest.bc -x clcpp cpptest.tmp.clcpp
clang -cc1 version 18.1.3 based upon LLVM 18.1.3 default target x86_64-pc-linux-gnu
#include "..." search starts here:
#include <...> search starts here:
 /usr/local/include
 /usr/lib/llvm-18/lib/clang/18/include
 /usr/include
End of search list.
 *** target up-to-date: cpptest.bc (2024-07-07 13:09:38.478535 vs 2024-07-07 13:09:38.444536)
>> llvm-spirv  "cpptest.bc" -o "cpptest.spv"
--]]
local ffi = require 'ffi'
require 'ext'

local n = 64

local CLEnv = require 'cl.obj.env'
local env = CLEnv{
	verbose = true,
	useGLSharing = false,
	getPlatform = CLEnv.getPlatformFromCmdLine(...),
	getDevices = CLEnv.getDevicesFromCmdLine(...),
	deviceType = CLEnv.getDeviceTypeFromCmdLine(...),
	precision = cmdline.real or 'double',
	size = n,
}
env.code = ''
local real = env.real
print('using real',real)

local clcppfn = 'cpptest.clcpp'
local bcfn = 'cpptest.bc'
local spvfn = 'cpptest.spv'

local program = env:program{
	-- Why is .spirvToolchainFileCL and .code both required? because CL is the write file and code is the read content
	code = path(clcppfn):read(),				-- code source
	spirvToolchainFileCL = 'cpptest.tmp.clcpp',	-- temp write file after adding env header
	spirvToolchainFileBC = bcfn,
	spirvToolchainFileSPV = spvfn,
}

-- has to be separate eh?
program:compile{
	buildOptions = table{
		'-O0',	-- sometimes amd chokes on this
		'-DARRAY_SIZE='..n,
		'-DREAL='..real,
		env.real == 'double' and '-DUSE_FP64' or '',
	}:concat' ',
}

-- gpu mem
local a = env:buffer{name='a', type='real', data=range(n)}
local b = env:buffer{name='b', type='real', data=range(n)}
local c = env:buffer{name='c', type='real', data=range(n)}

local testKernel = program:kernel('test', c.obj, a.obj, b.obj)

local event = require 'cl.event'()
testKernel.event = event
testKernel()
env.cmds[1]:finish()
local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
local fin = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
print('duration', tonumber(fin - start)..' ns')

-- cpu mem
local aMem = a:toCPU()
local bMem = b:toCPU()
local cMem = c:toCPU()

for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()

print'done'
