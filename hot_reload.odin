package hot_reload

import "core:fmt"
import "core:dynlib"
import "core:os"
import "core:time"
import "core:log"
import "base:intrinsics"

// Lib :: struct {
//   foo : proc(int) -> int,
//
//   __last_time_modified : time.Time,
//   __swap: bool,
//   __handle : dynlib.Library,
// }

// TODO: add usage comment
load_lib :: proc(symbol_table: ^$T, file_path: string) -> (new: bool, ok: bool)
where
  intrinsics.type_has_field(T, "__last_time_modified") && type_of(symbol_table.__last_time_modified) == time.Time,
  intrinsics.type_has_field(T, "__swap") && type_of(symbol_table.__swap) == bool,
  intrinsics.type_has_field(T, "__handle") && type_of(symbol_table.__handle) == dynlib.Library
{

  tmp_file_path := fmt.tprintf("%s.%v.tmp", file_path, symbol_table.__swap ? 1 : 0)

  dlib_stats, dlib_stats_error := os.stat(file_path, context.temp_allocator)
  _, tmp_dlib_stats_error := os.stat(tmp_file_path, context.temp_allocator)

  first_load := symbol_table.__handle == nil

  if dlib_stats_error != os.ERROR_NONE {
    if first_load do log.errorf("lib %s not found", file_path)
    return false, !first_load
  }

  can_create_file := tmp_dlib_stats_error == os.ENOENT

  lib_is_old := time.diff(
    dlib_stats.modification_time,
    symbol_table.__last_time_modified,
  ) < 0

  if first_load || (can_create_file && lib_is_old) {
    dlib_data, dlib_data_ok := os.read_entire_file_from_filename(file_path)
    defer delete(dlib_data)
    if !dlib_data_ok {
      if first_load do log.error("could not copy library data")
      return false, !first_load
    }

    ok_write_file := os.write_entire_file(tmp_file_path, dlib_data)
    if !ok_write_file {
      log.errorf("could not write temporary file %s", tmp_file_path)
      return false, !first_load
    }
    // TODO: deletar o arquivo anterior no lugar de apagar o atual
    defer os.remove(tmp_file_path)
    

    // TODO: encontrar o uso para `count`
    _count , ok_lib := dynlib.initialize_symbols(symbol_table, tmp_file_path)
    if ok_lib {
      symbol_table.__last_time_modified = dlib_stats.modification_time
      symbol_table.__swap = !symbol_table.__swap
      return true, true
    } else {
      if first_load do log.errorf("could not initialize symbols from lib %s", file_path)
      return false, !first_load
    }
  }

  return false, true
}

