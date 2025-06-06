local assert = require 'ext.assert'
local class = require 'ext.class'
local range = require 'ext.range'
local tolua = require 'ext.tolua'
local string = require 'ext.string'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.req' 'OpenCL'
local classert = require 'cl.assert'

local band = bit.band

if not pcall(function()
	bit.band(ffi.new'cl_command_queue_properties', ffi.new'cl_command_queue_properties')
end) then
	-- luajit 2.0.5, band doesn't work on int64
	-- luajit 2.1.0 beta, it does
	-- and on ubuntu amd opencl, cl_command_queue_properties == uint64_t
	-- so for now I'm only seeing bits 0-3 used ...
	band = function(a,b)
		-- TODO test a and verify it will work, that it's not an out of bounds int
		return bit.band(
			tonumber(a),
			tonumber(b)
		)
	end
end


--[[
OpenCL #define enums are grouped.
The prefix to each group is the cl_* type associated with the constants.
These cl_* types fall into one of three categories:
1) cl_*_info types, wherein the whole group is associated with a getter and each enum is associated with a type.
	these are stored in the individual class wrappers
2) bitfields (bit combinations of integer values)
	these are stored in bitflagNamesForType, below
3) integer value
	these are stored in valueNamesForType below
--]]

local bitflagNamesForType = {
	cl_device_fp_config = {
		'CL_FP_DENORM',
		'CL_FP_INF_NAN',
		'CL_FP_ROUND_TO_NEAREST',
		'CL_FP_ROUND_TO_ZERO',
		'CL_FP_ROUND_TO_INF',
		'CL_FP_FMA',
		'CL_FP_SOFT_FLOAT',
		'CL_FP_CORRECTLY_ROUNDED_DIVIDE_SQRT',
	},
	cl_device_exec_capabilities = {
		'CL_EXEC_KERNEL',
		'CL_EXEC_NATIVE_KERNEL',
	},
	cl_command_queue_properties = {
		'CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE',
		'CL_QUEUE_PROFILING_ENABLE',
		'CL_QUEUE_ON_DEVICE',
		'CL_QUEUE_ON_DEVICE_DEFAULT',
	},
	cl_device_affinity_domain = {
		'CL_DEVICE_AFFINITY_DOMAIN_NUMA',
		'CL_DEVICE_AFFINITY_DOMAIN_L4_CACHE',
		'CL_DEVICE_AFFINITY_DOMAIN_L3_CACHE',
		'CL_DEVICE_AFFINITY_DOMAIN_L2_CACHE',
		'CL_DEVICE_AFFINITY_DOMAIN_L1_CACHE',
		'CL_DEVICE_AFFINITY_DOMAIN_NEXT_PARTITIONABLE',
	},
	cl_device_svm_capabilities = {
		'CL_DEVICE_SVM_COARSE_GRAIN_BUFFER',
		'CL_DEVICE_SVM_FINE_GRAIN_BUFFER',
		'CL_DEVICE_SVM_FINE_GRAIN_SYSTEM',
		'CL_DEVICE_SVM_ATOMICS',
	},
	cl_mem_flags = {
		'CL_MEM_READ_WRITE',
		'CL_MEM_WRITE_ONLY',
		'CL_MEM_READ_ONLY',
		'CL_MEM_USE_HOST_PTR',
		'CL_MEM_ALLOC_HOST_PTR',
		'CL_MEM_COPY_HOST_PTR',
		'CL_MEM_HOST_WRITE_ONLY',
		'CL_MEM_HOST_READ_ONLY',
		'CL_MEM_HOST_NO_ACCESS',
		'CL_MEM_SVM_FINE_GRAIN_BUFFER',
		'CL_MEM_SVM_ATOMICS',
		'CL_MEM_KERNEL_READ_AND_WRITE',
	},
	cl_svm_mem_flags = {
		'CL_MEM_READ_WRITE',
		'CL_MEM_WRITE_ONLY',
		'CL_MEM_READ_ONLY',
		'CL_MEM_USE_HOST_PTR',
		'CL_MEM_ALLOC_HOST_PTR',
		'CL_MEM_COPY_HOST_PTR',
		'CL_MEM_HOST_WRITE_ONLY',
		'CL_MEM_HOST_READ_ONLY',
		'CL_MEM_HOST_NO_ACCESS',
		'CL_MEM_SVM_FINE_GRAIN_BUFFER',
		'CL_MEM_SVM_ATOMICS',
		'CL_MEM_KERNEL_READ_AND_WRITE',
	},
	cl_mem_migration_flags = {
		'CL_MIGRATE_MEM_OBJECT_HOST',
		'CL_MIGRATE_MEM_OBJECT_CONTENT_UNDEFINED',
	},
	cl_map_flags = {
		'CL_MAP_READ',
		'CL_MAP_WRITE',
		'CL_MAP_WRITE_INVALIDATE_REGION',
	},
	cl_device_type = {
		'CL_DEVICE_TYPE_DEFAULT',
		'CL_DEVICE_TYPE_CPU',
		'CL_DEVICE_TYPE_GPU',
		'CL_DEVICE_TYPE_ACCELERATOR',
		'CL_DEVICE_TYPE_CUSTOM',
		'CL_DEVICE_TYPE_ALL',
	},
}

local valueNamesForType = {
	cl_bool = {
		'CL_FALSE',
		'CL_TRUE',
		'CL_BLOCKING',
	},
	cl_device_mem_cache_type = {
		'CL_NONE',
		'CL_READ_ONLY_CACHE',
		'CL_READ_WRITE_CACHE',
	},
	cl_device_local_mem_type = {
		'CL_LOCAL',
		'CL_GLOBAL',
	},
	cl_context_properties = {
		'CL_CONTEXT_PLATFORM',
		'CL_CONTEXT_INTEROP_USER_SYNC',
	},
	cl_device_partition_property = {
		'CL_DEVICE_PARTITION_EQUALLY',
		'CL_DEVICE_PARTITION_BY_COUNTS',
		'CL_DEVICE_PARTITION_BY_COUNTS_LIST_END',
		'CL_DEVICE_PARTITION_BY_AFFINITY_DOMAIN',
	},
	cl_channel_order = {
		'CL_R',
		'CL_A',
		'CL_RG',
		'CL_RA',
		'CL_RGB',
		'CL_RGBA',
		'CL_BGRA',
		'CL_ARGB',
		'CL_INTENSITY',
		'CL_LUMINANCE',
		'CL_Rx',
		'CL_RGx',
		'CL_RGBx',
		'CL_DEPTH',
		'CL_DEPTH_STENCIL',
		'CL_sRGB',
		'CL_sRGBx',
		'CL_sRGBA',
		'CL_sBGRA',
		'CL_ABGR',
	},
	cl_channel_type = {
		'CL_SNORM_INT8',
		'CL_SNORM_INT16',
		'CL_UNORM_INT8',
		'CL_UNORM_INT16',
		'CL_UNORM_SHORT_565',
		'CL_UNORM_SHORT_555',
		'CL_UNORM_INT_101010',
		'CL_SIGNED_INT8',
		'CL_SIGNED_INT16',
		'CL_SIGNED_INT32',
		'CL_UNSIGNED_INT8',
		'CL_UNSIGNED_INT16',
		'CL_UNSIGNED_INT32',
		'CL_HALF_FLOAT',
		'CL_FLOAT',
		'CL_UNORM_INT24',
		'CL_UNORM_INT_101010_2',
	},
	cl_mem_object_type = {
		'CL_MEM_OBJECT_BUFFER',
		'CL_MEM_OBJECT_IMAGE2D',
		'CL_MEM_OBJECT_IMAGE3D',
		'CL_MEM_OBJECT_IMAGE2D_ARRAY',
		'CL_MEM_OBJECT_IMAGE1D',
		'CL_MEM_OBJECT_IMAGE1D_ARRAY',
		'CL_MEM_OBJECT_IMAGE1D_BUFFER',
		'CL_MEM_OBJECT_PIPE',
	},
	cl_addressing_mode = {
		'CL_ADDRESS_NONE',
		'CL_ADDRESS_CLAMP_TO_EDGE',
		'CL_ADDRESS_CLAMP',
		'CL_ADDRESS_REPEAT',
		'CL_ADDRESS_MIRRORED_REPEAT',
	},
	cl_filter_mode = {
		'CL_FILTER_NEAREST',
		'CL_FILTER_LINEAR',
	},
	cl_program_binary_type = {
		'CL_PROGRAM_BINARY_TYPE_NONE',
		'CL_PROGRAM_BINARY_TYPE_COMPILED_OBJECT',
		'CL_PROGRAM_BINARY_TYPE_LIBRARY',
		'CL_PROGRAM_BINARY_TYPE_EXECUTABLE',
	},
	cl_build_status = {
		'CL_BUILD_SUCCESS',
		'CL_BUILD_NONE',
		'CL_BUILD_ERROR',
		'CL_BUILD_IN_PROGRESS',
	},
	cl_kernel_arg_address_qualifier = {
		'CL_KERNEL_ARG_ADDRESS_GLOBAL',
		'CL_KERNEL_ARG_ADDRESS_LOCAL',
		'CL_KERNEL_ARG_ADDRESS_CONSTANT',
		'CL_KERNEL_ARG_ADDRESS_PRIVATE',
	},
	cl_kernel_arg_access_qualifier = {
		'CL_KERNEL_ARG_ACCESS_READ_ONLY',
		'CL_KERNEL_ARG_ACCESS_WRITE_ONLY',
		'CL_KERNEL_ARG_ACCESS_READ_WRITE',
		'CL_KERNEL_ARG_ACCESS_NONE',
	},
	cl_kernel_arg_type_qualifer = {
		'CL_KERNEL_ARG_TYPE_NONE',
		'CL_KERNEL_ARG_TYPE_CONST',
		'CL_KERNEL_ARG_TYPE_RESTRICT',
		'CL_KERNEL_ARG_TYPE_VOLATILE',
		'CL_KERNEL_ARG_TYPE_PIPE',
	},
	cl_command_type = {
		'CL_COMMAND_NDRANGE_KERNEL',
		'CL_COMMAND_TASK',
		'CL_COMMAND_NATIVE_KERNEL',
		'CL_COMMAND_READ_BUFFER',
		'CL_COMMAND_WRITE_BUFFER',
		'CL_COMMAND_COPY_BUFFER',
		'CL_COMMAND_READ_IMAGE',
		'CL_COMMAND_WRITE_IMAGE',
		'CL_COMMAND_COPY_IMAGE',
		'CL_COMMAND_COPY_IMAGE_TO_BUFFER',
		'CL_COMMAND_COPY_BUFFER_TO_IMAGE',
		'CL_COMMAND_MAP_BUFFER',
		'CL_COMMAND_MAP_IMAGE',
		'CL_COMMAND_UNMAP_MEM_OBJECT',
		'CL_COMMAND_MARKER',
		'CL_COMMAND_ACQUIRE_GL_OBJECTS',
		'CL_COMMAND_RELEASE_GL_OBJECTS',
		'CL_COMMAND_READ_BUFFER_RECT',
		'CL_COMMAND_WRITE_BUFFER_RECT',
		'CL_COMMAND_COPY_BUFFER_RECT',
		'CL_COMMAND_USER',
		'CL_COMMAND_BARRIER',
		'CL_COMMAND_MIGRATE_MEM_OBJECTS',
		'CL_COMMAND_FILL_BUFFER',
		'CL_COMMAND_FILL_IMAGE',
		'CL_COMMAND_SVM_FREE',
		'CL_COMMAND_SVM_MEMCPY',
		'CL_COMMAND_SVM_MEMFILL',
		'CL_COMMAND_SVM_MAP',
		'CL_COMMAND_SVM_UNMAP',
		'CL_COMMAND_MIGRATE_SVM_MEM_OBJECTS',
	},
	command_execution_status = {
		'CL_COMPLETE',
		'CL_RUNNING',
		'CL_SUBMITTED',
		'CL_QUEUED',
	},
	cl_buffer_create_type = {
		'CL_BUFFER_CREATE_TYPE_REGION',
	},
}

local function GetInfoBehavior(parent)
	local template = class(parent)

	template.infoVarForName = template.infoVarForName and table(template.infoVarForName) or table()

	-- accept extra args from the generated Lua getter
	local function getInfo(self, getter, vars, name, ...)
		local id = self.id

		local var = assert.index(self.infoVarForName, name, "tried to get an unknown name")
		assert.eq(var.getter, getter)
		local nameValue = assert.index(cl, name)

		if var.type == 'char[]' then 	-- convert to Lua string
			local size = ffi.new('size_t[1]', 0)
			classert(getter(id, nameValue, 0, nil, size, ...))
			local n = size[0]
			local result = ffi.new('char[?]', n)
			classert(getter(id, nameValue, n, result, nil, ...))
			-- some strings have an extra null term ...
			while n > 0 and result[n-1] == 0 do n = n - 1 end
			local s = ffi.string(result, n)
			if var.separator then
				return string.split(string.trim(s), var.separator)
			end
			return s
		elseif var.type == 'cl_bool' then	-- convert to Lua bool
			local result = ffi.new(var.type..'[1]')
			classert(getter(id, nameValue, ffi.sizeof(var.type), result, nil, ...))
			return result[0] ~= 0
		elseif var.type:sub(-2) == '[]' then
			local baseType = var.type:sub(1,-3)
			local size = ffi.new('size_t[1]', 0)
			classert(getter(id, nameValue, 0, nil, size, ...))
			local n = tonumber(size[0] / ffi.sizeof(baseType))
			local result = ffi.new(baseType..'[?]', n)
			classert(getter(id, nameValue, size[0], result, nil, ...))
			return range(0,n-1):mapi(function(i) return result[i] end)
		else
if var.type == nil or var.type == '' then error("you haven't defined the type for name "..name) end
			local result = ffi.new(var.type..'[1]')
			classert(getter(id, nameValue, ffi.sizeof(var.type), result, nil, ...))

			local allBitflagNames = bitflagNamesForType[var.type]
			if allBitflagNames then
				local usedFlagNames = table()
				for _,bitflagName in ipairs(allBitflagNames) do
					local bitflagValue = assert.index(cl, bitflagName)
					if band(result[0], bitflagValue) ~= 0 then
						usedFlagNames:insert(bitflagName)
					end
				end
				return result[0], usedFlagNames
			end

			local allValueNames = valueNamesForType[var.type]
			if allValueNames then
				local usedValueName
				for _,valueName in ipairs(allValueNames) do
					local value = assert.index(cl, valueName)
					if value == result[0] then
						usedValueName = valueName
						break
					end
				end
				return result[0], usedValueName
			end

			return result[0]
		end
	end

	--[[
	static function, so 'self' is the child class object
	args:
		getter = cl getter, of the signature (id, param name, param value size, param value, param value size ret)
		vars = table of vars. each entry contains:
			name
			type
			separator (optional) for char[] type, specifies string separator
	--]]
	function template:makeGetter(args)
		-- TODO this is a hack.  it assumes the first getter uses a default getter signature and requires no extra args
		if not self.printVars then self.printVars = args.vars end

		local getter = assert.index(args, 'getter')
		local vars = assert.index(args, 'vars')

		for _,var in ipairs(vars) do
			self.infoVarForName[var.name] = var
			var.getter = getter
		end

		-- accept extra args and forward to getInfo
		return function(self, name, ...)
			return getInfo(self, getter, vars, name, ...)
		end
	end

	function template:printInfo()
		for _,var in ipairs(self.printVars) do
			xpcall(function()
				print(var.name, tolua(self:getInfo(var.name)))
			end, function(err)
				print(var.name, 'error: '..err)
			end)
		end
	end

	return template
end

return GetInfoBehavior
