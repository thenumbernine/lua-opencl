local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local Wrapper = require 'cl.wrapper'
local GetInfo = require 'cl.getinfo'

local Device = class(GetInfo(Wrapper(
	'cl_device_id',
	cl.clRetainDevice,
	cl.clReleaseDevice)))

function Device:init(id)
	self.id = id
	Device.super.init(self, self.id)
end

Device.infoGetter = cl.clGetDeviceInfo

Device.infos = {
	{name='CL_DEVICE_NAME', type='string'},
	{name='CL_DEVICE_VERSION', type='string'},
	{name='CL_DRIVER_VERSION', type='string'},
	{name='CL_DEVICE_VENDOR', type='string'},
	{name='CL_DEVICE_VENDOR_ID', type='cl_uint'},
	{name='CL_DEVICE_PROFILE', type='string'},
	{name='CL_DEVICE_EXTENSIONS', type='string'},
	{name='CL_DEVICE_TYPE', type='cl_device_type'},
	{name='CL_DEVICE_MAX_COMPUTE_UNITS', type='cl_uint'},
	{name='CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS', type='cl_uint'},
	{name='CL_DEVICE_MAX_WORK_GROUP_SIZE', type='size_t'},
	{name='CL_DEVICE_MAX_WORK_ITEM_SIZES', type='size_t[]'},
	{name='CL_DEVICE_PREFERRED_VECTOR_WIDTH_CHAR', type='cl_uint'},
	{name='CL_DEVICE_PREFERRED_VECTOR_WIDTH_SHORT', type='cl_uint'},
	{name='CL_DEVICE_PREFERRED_VECTOR_WIDTH_INT', type='cl_uint'},
	{name='CL_DEVICE_PREFERRED_VECTOR_WIDTH_LONG', type='cl_uint'},
	{name='CL_DEVICE_PREFERRED_VECTOR_WIDTH_FLOAT', type='cl_uint'},
	{name='CL_DEVICE_PREFERRED_VECTOR_WIDTH_DOUBLE', type='cl_uint'},
	{name='CL_DEVICE_MAX_CLOCK_FREQUENCY', type='cl_uint'},
	{name='CL_DEVICE_ADDRESS_BITS', type='cl_uint'},
	{name='CL_DEVICE_MAX_READ_IMAGE_ARGS', type='cl_uint'},
	{name='CL_DEVICE_MAX_WRITE_IMAGE_ARGS', type='cl_uint'},
	{name='CL_DEVICE_MAX_MEM_ALLOC_SIZE', type='cl_ulong'},
	{name='CL_DEVICE_IMAGE2D_MAX_WIDTH', type='size_t'},
	{name='CL_DEVICE_IMAGE2D_MAX_HEIGHT', type='size_t'},
	{name='CL_DEVICE_IMAGE3D_MAX_WIDTH', type='size_t'},
	{name='CL_DEVICE_IMAGE3D_MAX_HEIGHT', type='size_t'},
	{name='CL_DEVICE_IMAGE3D_MAX_DEPTH', type='size_t'},
	{name='CL_DEVICE_IMAGE_SUPPORT', type='cl_bool'},
	{name='CL_DEVICE_MAX_PARAMETER_SIZE', type='size_t'},
	{name='CL_DEVICE_MAX_SAMPLERS', type='cl_uint'},
	{name='CL_DEVICE_MEM_BASE_ADDR_ALIGN', type='cl_uint'},
	{name='CL_DEVICE_MIN_DATA_TYPE_ALIGN_SIZE', type='cl_uint'},
	{name='CL_DEVICE_SINGLE_FP_CONFIG', type='cl_device_fp_config'},
	{name='CL_DEVICE_GLOBAL_MEM_CACHE_TYPE', type='cl_device_mem_cache_type'},
	{name='CL_DEVICE_GLOBAL_MEM_CACHELINE_SIZE', type='cl_uint'},
	{name='CL_DEVICE_GLOBAL_MEM_CACHE_SIZE', type='cl_ulong'},
	{name='CL_DEVICE_GLOBAL_MEM_SIZE', type='cl_ulong'},
	{name='CL_DEVICE_MAX_CONSTANT_BUFFER_SIZE', type='cl_ulong'},
	{name='CL_DEVICE_MAX_CONSTANT_ARGS', type='cl_uint'},
	{name='CL_DEVICE_LOCAL_MEM_TYPE', type='cl_device_local_mem_type'},
	{name='CL_DEVICE_LOCAL_MEM_SIZE', type='cl_ulong'},
	{name='CL_DEVICE_ERROR_CORRECTION_SUPPORT', type='cl_bool'},
	{name='CL_DEVICE_PROFILING_TIMER_RESOLUTION', type='size_t'},
	{name='CL_DEVICE_ENDIAN_LITTLE', type='cl_bool'},
	{name='CL_DEVICE_AVAILABLE', type='cl_bool'},
	{name='CL_DEVICE_COMPILER_AVAILABLE', type='cl_bool'},
	{name='CL_DEVICE_EXECUTION_CAPABILITIES', type='cl_device_exec_capabilities'},
	{name='CL_DEVICE_QUEUE_PROPERTIES', type='cl_command_queue_properties'},
	{name='CL_DEVICE_PLATFORM', type='cl_platform_id'},
}
function Device:getName() return self:getInfo'CL_DEVICE_NAME' end
function Device:getVendor() return self:getInfo'CL_DEVICE_VENDOR' end
function Device:getDriverVersion() return self:getInfo'CL_DRIVER_VERSION' end
function Device:getProfile() return self:getInfo'CL_DEVICE_PROFILE' end
function Device:getVersion() return self:getInfo'CL_DEVICE_VERSION' end
function Device:getVendor() return self:getInfo'CL_DEVICE_VENDOR' end
function Device:getExtensions() return self:getInfo'CL_DEVICE_EXTENSIONS' end


return Device
