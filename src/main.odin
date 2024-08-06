package main

import "core:fmt"
import "core:dynlib"
import "core:os"
import "core:time"

Lib :: struct {
  foo : proc(int) -> int,

  __last_time_modified : time.Time,
  __swap: bool,
  __handle : dynlib.Library,
}

load_lib :: proc(symbol_table: ^$T, file_path: string) -> (new: bool, ok: bool) {

  tmp_file_path := fmt.tprintf("%s.%v.tmp", file_path, symbol_table.__swap ? 1 : 0)

  dlib_stats, dlib_stats_error := os.stat(file_path, context.temp_allocator)
  _, tmp_dlib_stats_error := os.stat(tmp_file_path, context.temp_allocator)

  if dlib_stats_error != os.ERROR_NONE {
    return
  }

  can_create_file := tmp_dlib_stats_error == os.ENOENT

  lib_is_old := time.diff(
    dlib_stats.modification_time,
    symbol_table.__last_time_modified,
  ) < 0

  if symbol_table.__handle == nil || (can_create_file && lib_is_old) {
    dlib_data, dlib_data_ok := os.read_entire_file_from_filename(file_path)
    defer delete(dlib_data)
    if !dlib_data_ok do return false, symbol_table.__handle != nil

    os.write_entire_file(tmp_file_path, dlib_data)
    defer {
      os.remove(tmp_file_path)
    }

    _, ok_lib := dynlib.initialize_symbols(symbol_table, tmp_file_path)
    if ok_lib {
      symbol_table.__last_time_modified = dlib_stats.modification_time
      symbol_table.__swap = !symbol_table.__swap
      return true, ok_lib
    } else {
      return false, ok_lib
    }
  }

  return false, true
}

main :: proc() {
  lib: Lib

  for {
    new, ok_lib := load_lib(&lib, "bin/lib.so")
    if ok_lib {
      fmt.println(lib.foo(34))
    }
  }

}

