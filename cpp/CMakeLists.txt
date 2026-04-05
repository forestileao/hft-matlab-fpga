cmake_minimum_required(VERSION 3.5)
project(fast_flow)

set(CMAKE_CXX_STANDARD 11)
enable_testing()

# Auto-detect local mFAST install produced by the repository Makefile target.
# Keep this native-only so cross builds can supply their own package path.
set(_MFAST_LOCAL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/../mFAST/install")
if(NOT CMAKE_CROSSCOMPILING
   AND EXISTS "${_MFAST_LOCAL_PREFIX}/lib/cmake/mFAST/mFASTConfig.cmake")
    list(PREPEND CMAKE_PREFIX_PATH "${_MFAST_LOCAL_PREFIX}")
endif()

find_package(mFAST REQUIRED)
find_package(Threads REQUIRED)

if(DEFINED MFAST_FAST_TYPE_GEN_EXECUTABLE)
    if(NOT TARGET fast_type_gen)
        add_executable(fast_type_gen IMPORTED GLOBAL)
    endif()
    set_target_properties(fast_type_gen PROPERTIES
        IMPORTED_LOCATION "${MFAST_FAST_TYPE_GEN_EXECUTABLE}"
        IMPORTED_LOCATION_RELEASE "${MFAST_FAST_TYPE_GEN_EXECUTABLE}"
    )
endif()

FASTTYPEGEN_TARGET(SimpleMD src/templates/SimpleMD.xml)

add_executable(fast_receiver ${FASTTYPEGEN_SimpleMD_OUTPUTS} src/fast_receiver.cpp)
target_include_directories(fast_receiver PRIVATE ${mFAST_INCLUDE_DIR})
target_compile_definitions(fast_receiver PRIVATE
    TEMPLATE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/src/templates"
)
target_link_libraries(fast_receiver
    mfast_xml_parser_static
    mfast_coder_static
    mfast_static
)

add_executable(fast_data_feed ${FASTTYPEGEN_SimpleMD_OUTPUTS} src/fast_data_feed.cpp)
target_include_directories(fast_data_feed PRIVATE ${mFAST_INCLUDE_DIR})
target_compile_definitions(fast_data_feed PRIVATE
    TEMPLATE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/src/templates"
)
target_link_libraries(fast_data_feed
    mfast_xml_parser_static
    mfast_coder_static
    mfast_static
    Threads::Threads
    pthread
)

add_executable(fpga_shared_stream_test tests/fpga_shared_stream_test.cpp)
target_include_directories(fpga_shared_stream_test PRIVATE src)
add_test(NAME fpga_shared_stream_test COMMAND fpga_shared_stream_test)
