# This is just an example to get you started. Users of your library will
# import this file by writing ``import nxlib/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

type
  DataBuffer* = ptr array[8, uint8]

proc convert*[A](arr: var DataBuffer): A =
  result = cast[ptr A](arr)[]

proc u32*(arr: var DataBuffer): uint32 =
  result = convert[uint32](arr)

proc i32*(arr: var DataBuffer): int32 =
  result = convert[int32](arr)

proc i64*(arr: var DataBuffer): int64 =
  result = convert[int64](arr)

proc f64*(arr: var DataBuffer): float64 =
  result = convert[float64](arr)