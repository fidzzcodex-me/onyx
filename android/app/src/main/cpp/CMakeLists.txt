cmake_minimum_required(VERSION 3.18.1)

project("onyxnative" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(onyxnative SHARED
    pty.cpp
    exec.cpp)

find_library(log-lib log)

target_compile_options(onyxnative PRIVATE -Wall -Wextra -fvisibility=hidden)

target_link_libraries(onyxnative ${log-lib})

target_link_options(onyxnative PRIVATE "-Wl,-z,max-page-size=16384")
