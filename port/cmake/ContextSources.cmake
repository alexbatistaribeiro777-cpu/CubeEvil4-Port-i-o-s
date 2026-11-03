# The assembly files are unchanged Boost.Context 1.88.0 sources.
#   *_aapcs_elf_gas.S   Android (armeabi-v7a, arm64-v8a)
#   *_aapcs_macho_gas.S Apple (arm64; the iOS core)
function(re4_add_context_sources target)
    set(base "third_party/boost_context")
    if(APPLE)
        if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)$")
            message(FATAL_ERROR "No verified fcontext backend for Apple ${CMAKE_SYSTEM_PROCESSOR}")
        endif()
        re4_check_original("${CMAKE_CURRENT_SOURCE_DIR}" "${base}/make_arm64_aapcs_macho_gas.S"
            70f07951a0bd02415f8c36b0fec2007f6cd33f1e121e569396d313a637d399dd)
        re4_check_original("${CMAKE_CURRENT_SOURCE_DIR}" "${base}/jump_arm64_aapcs_macho_gas.S"
            948981fc56f53c319e709f17212d1b9c7a202c59ed3767a5b361cb5fa2b81f12)
        target_sources(${target} PRIVATE
            "${base}/make_arm64_aapcs_macho_gas.S"
            "${base}/jump_arm64_aapcs_macho_gas.S")
        return()
    endif()
    re4_check_original("${CMAKE_CURRENT_SOURCE_DIR}" "${base}/jump_arm_aapcs_elf_gas.S"
        7a9c50f5178778b4f920c7091235e9ea4fb9329ed73bd25d756bc4f36e335320)
    re4_check_original("${CMAKE_CURRENT_SOURCE_DIR}" "${base}/make_arm_aapcs_elf_gas.S"
        48b89b69b2ef51f49ee078b45a6a508ae0f61297410b5333cf707a1b07b64d1d)
    re4_check_original("${CMAKE_CURRENT_SOURCE_DIR}" "${base}/jump_arm64_aapcs_elf_gas.S"
        c7d0e3687cc8d678097befebc0a5072f3db0e87e1f1894b9287d0dbf0c9f248f)
    re4_check_original("${CMAKE_CURRENT_SOURCE_DIR}" "${base}/make_arm64_aapcs_elf_gas.S"
        6c4a66435182615097418217af504604ac28f233c4c5289fc2751f05f8aaa78e)
    if(ANDROID_ABI STREQUAL "armeabi-v7a")
        set(arch arm)
    elseif(ANDROID_ABI STREQUAL "arm64-v8a")
        set(arch arm64)
    else()
        message(FATAL_ERROR "No verified fcontext backend for ${ANDROID_ABI}")
    endif()
    set(sources "${base}/make_${arch}_aapcs_elf_gas.S" "${base}/jump_${arch}_aapcs_elf_gas.S")
    target_sources(${target} PRIVATE ${sources})
    if(arch STREQUAL "arm")
        # Android softfp still has callee-saved d8-d15. Force their preservation
        # in upstream's conditional assembly; this changes NO C++ calling ABI.
        # Compile assembly in ARM mode; Thumb callers interwork via BLX/PC bit.
        set_source_files_properties(${sources} PROPERTIES COMPILE_OPTIONS "-marm;-U__SOFTFP__")
    endif()
endfunction()
