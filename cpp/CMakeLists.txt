cmake_minimum_required(VERSION 3.5)
project(fast_flow)

set(CMAKE_CXX_STANDARD 11)

find_package(mFAST REQUIRED)

add_executable(fast_receiver src/fast_receiver.cpp)
target_compile_definitions(fast_receiver PRIVATE
    TEMPLATE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/src/templates"
)
target_link_libraries(fast_receiver
    mfast_xml_parser
    mfast_coder
    mfast
)

FASTTYPEGEN_TARGET(SimpleMD src/templates/SimpleMD.xml)
add_executable(fast_data_feed ${FASTTYPEGEN_SimpleMD_OUTPUTS} src/fast_data_feed.cpp)
target_compile_definitions(fast_data_feed PRIVATE
    TEMPLATE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/src/templates"
)
target_link_libraries(fast_data_feed
    mfast_xml_parser
    mfast_coder
    mfast
)
