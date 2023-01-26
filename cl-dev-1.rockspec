package = "cl"
version = "dev-1"
source = {
	url = "git+https://github.com/thenumbernine/lua-opencl.git"
}
description = {
	summary = "OpenCL bindings / OOP for Lua.",
	detailed = "OpenCL bindings / OOP for Lua.",
	homepage = "https://github.com/thenumbernine/lua-opencl",
	license = "MIT",
}
dependencies = {
	"lua >= 5.1",
}
build = {
	type = "builtin",
	modules = {
		["cl.assert"] = "assert.lua",
		["cl.assertparam"] = "assertparam.lua",
		["cl.buffer"] = "buffer.lua",
		["cl.checkerror"] = "checkerror.lua",
		["cl"] = "cl.lua",
		["cl.commandqueue"] = "commandqueue.lua",
		["cl.context"] = "context.lua",
		["cl.device"] = "device.lua",
		["cl.event"] = "event.lua",
		["cl.getinfo"] = "getinfo.lua",
		["cl.imagegl"] = "imagegl.lua",
		["cl.kernel"] = "kernel.lua",
		["cl.memory"] = "memory.lua",
		["cl.obj.buffer"] = "obj/buffer.lua",
		["cl.obj.domain"] = "obj/domain.lua",
		["cl.obj.env"] = "obj/env.lua",
		["cl.obj.half"] = "obj/half.lua",
		["cl.obj.kernel"] = "obj/kernel.lua",
		["cl.obj.number"] = "obj/number.lua",
		["cl.obj.program"] = "obj/program.lua",
		["cl.obj.reduce"] = "obj/reduce.lua",
		["cl.platform"] = "platform.lua",
		["cl.program"] = "program.lua",
		["cl.tests.cpp"] = "tests/cpp.lua",
		["cl.tests.getbin"] = "tests/getbin.lua",
		["cl.tests.info"] = "tests/info.lua",
		["cl.tests.obj"] = "tests/obj.lua",
		["cl.tests.obj-multi"] = "tests/obj-multi.lua",
		["cl.tests.readme-test"] = "tests/readme-test.lua",
		["cl.tests.reduce"] = "tests/reduce.lua",
		["cl.tests.test"] = "tests/test.lua"
	},
}
