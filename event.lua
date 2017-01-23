local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local classert = require 'cl.assert'
local Wrapper = require 'cl.wrapper'
local GetInfo = require 'cl.getinfo'

local Event = class(GetInfo(Wrapper(
	'cl_event',
	cl.clRetainEvent,
	cl.clReleaseEvent)))

function Event:wait()
	classert(cl.clWaitForEvents(1, self.gc.ptr))
end

-- static
function Event.waitForEvents(...)
	local n = select('#', ...)
	local events 
	if n > 0 then
		events = ffi.new('cl_event[?]', n) 
		for i=1,n do
			events[i-1] = select(i).id
		end
	end
	classert(cl.clWaitForEvents(n, n > 0 and events or nil))
end

-- for getInfo

Event.infoGetter = cl.clGetEventInfo

Event.infos = {
    {name='CL_EVENT_COMMAND_QUEUE', type='cl_command_queue'},
    {name='CL_EVENT_COMMAND_TYPE', type='cl_command_type'},
    {name='CL_EVENT_REFERENCE_COUNT', type='cl_uint'},
    {name='CL_EVENT_COMMAND_EXECUTION_STATUS', type='cl_int'},
}

function Event:getProfilingInfo(name)
	local param = ffi.new('cl_ulong[1]', 0)
	classert(cl.clGetEventProfilingInfo(self.id, cl[name], ffi.sizeof(param), param, nil))
	return param[0]
end
--[[ TODO same thing as getInfo, but for multiple functions or something
	F(cl_profiling_info, CL_PROFILING_COMMAND_QUEUED, cl_ulong) \
    F(cl_profiling_info, CL_PROFILING_COMMAND_SUBMIT, cl_ulong) \
    F(cl_profiling_info, CL_PROFILING_COMMAND_START, cl_ulong) \
    F(cl_profiling_info, CL_PROFILING_COMMAND_END, cl_ulong) \
--]]

return Event
