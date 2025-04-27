package hot_reload

import "core:fmt"
import "core:dynlib"
import "core:os"
import "core:time"
import "core:reflect"
import "core:log"
import "base:intrinsics"

Metadata :: struct {
  last_time_modified : time.Time,
  handle : dynlib.Library,
  __swap: bool,
}

load_lib :: proc(symbol_table: ^$T, metadata: ^Metadata, file_path: string) -> (new: bool, ok: bool)
{
  ensure(metadata != nil)
  ensure(symbol_table != nil)

  old_tmp_file_path := fmt.tprintf("%s.%v.tmp", file_path, !metadata.__swap ? 1 : 0)
  tmp_file_path := fmt.tprintf("%s.%v.tmp", file_path, metadata.__swap ? 1 : 0)

  dlib_stats, dlib_stats_error := os.stat(file_path, context.temp_allocator)
  _, tmp_dlib_stats_error := os.stat(tmp_file_path, context.temp_allocator)

  ensure(dlib_stats_error == nil)

  first_load := metadata.handle == nil

  if dlib_stats_error != os.ERROR_NONE {
    if first_load do log.errorf("lib %s not found", file_path)
    return false, !first_load
  }

  can_create_file := tmp_dlib_stats_error == os.General_Error.Not_Exist

  lib_is_old := time.diff(
    dlib_stats.modification_time,
    metadata.last_time_modified,
  ) < 0

  if first_load || (can_create_file && lib_is_old) {

    dlib_data, dlib_data_ok := os.read_entire_file_from_filename(file_path)
    defer delete(dlib_data)
    if !dlib_data_ok {
      if first_load do log.error("could not copy library data")
      return false, !first_load
    }

    write_file_err := os.write_entire_file_or_err(tmp_file_path, dlib_data)
    if write_file_err != nil {
      log.errorf("could not write temporary file %s with error %v", tmp_file_path, write_file_err)
      return false, !first_load
    }

    // TODO: encontrar o uso para `count`
    _count, ok_lib := initialize_symbols(symbol_table, tmp_file_path, &metadata.handle)
    if ok_lib {
      metadata.last_time_modified = dlib_stats.modification_time
      metadata.__swap = !metadata.__swap

      old_tmp_file_del_err := os.remove(old_tmp_file_path)
      // FIXME: olhar se funciona no linux
      if old_tmp_file_del_err != nil && old_tmp_file_del_err != .FILE_NOT_FOUND {
        log.errorf("could not delete temporary file %s with error %v", old_tmp_file_path, old_tmp_file_del_err)
        // FIXME: o que deveria retornar aqui? já que na proxima vez isso pode dar um erro
        //        por enquanto vou retornar o mesmo já que deu certo
      }

      return true, true
    } else {
      if first_load do log.errorf("could not initialize symbols from lib %s", file_path)
      return false, !first_load
    }

  }

  return false, true
}

// modified version of core::dynlib initialize_symbols
initialize_symbols :: proc(
  symbol_table: ^$T, library_path: string, handle : ^dynlib.Library = nil,
  symbol_prefix := "",
) -> (count: int = -1, ok: bool = false) where intrinsics.type_is_struct(T) {
  assert(symbol_table != nil)

  if handle != nil && handle^ != nil {
    dynlib.unload_library(handle^) or_return
  }

  handle^ = dynlib.load_library(library_path) or_return

  // Buffer to concatenate the prefix + symbol name.
  prefixed_symbol_buf: [2048]u8 = ---

  count = 0
  for field in reflect.struct_fields_zipped(T) {
    // If we're not the library handle, the field needs to be a pointer type, be it a procedure pointer or an exported global.
    if !(reflect.is_procedure(field.type) || reflect.is_pointer(field.type)) {
      continue
    }

    // Calculate address of struct member
    field_ptr := rawptr(uintptr(symbol_table) + field.offset)

    // Let's look up or construct the symbol name to find in the library
    prefixed_name: string

    // Do we have a symbol override tag?
    if override, tag_ok := reflect.struct_tag_lookup(field.tag, "dynlib"); tag_ok {
      prefixed_name = override
    }

    // No valid symbol override tag found, fall back to `<symbol_prefix>name`.
    if len(prefixed_name) == 0 {
      offset := copy(prefixed_symbol_buf[:], symbol_prefix)
      copy(prefixed_symbol_buf[offset:], field.name)
      prefixed_name = string(prefixed_symbol_buf[:len(symbol_prefix) + len(field.name)])
    }

    // Assign procedure (or global) pointer if found.
    sym_ptr := dynlib.symbol_address(handle^, prefixed_name) or_continue
    (^rawptr)(field_ptr)^ = sym_ptr
    count += 1
  }
  return count, count > 0
}
