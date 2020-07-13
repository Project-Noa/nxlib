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

proc convert*[A](arr: var seq[uint8]): A =
  result = cast[ptr A](arr)[]

proc u16*(arr: var seq[uint8]): uint16 =
  result = cast[uint16](arr)

proc i16*(arr: var seq[uint8]): int16 =
  result = cast[int16](arr)

proc u32*(arr: var seq[uint8]): uint32 =
  result = convert[uint32](arr)

proc i32*(arr: var seq[uint8]): int32 =
  result = convert[int32](arr)

proc i64*(arr: var seq[uint8]): int64 =
  result = convert[int64](arr)

proc f64*(arr: var seq[uint8]): float64 =
  result = convert[float64](arr)

proc toString*(self: seq[uint8]): string =
  result = ""
  for byte in self:
    result.add(byte.char)

proc getFileLength*(filename: string): int64 =
  let tmp = filename.open(fmRead)
  result = tmp.getFileSize()
  tmp.close()

proc `+`*(a, p: pointer): pointer =
  result = cast[pointer](cast[int](a) + 1 * sizeof(p))

proc `+`*(a: pointer, i: SomeInteger): pointer =
  result = cast[pointer](cast[int](a) + 1 * i.int)

proc toByteArray*[T](i: var T): seq[uint8] =
  result.setLen(sizeof(typeof(i)))
  for n in 0..<sizeof(i):
    var
      v = cast[ptr uint8](addr(i) + n)
    result[n] = v[]

proc asBytes*(i: SomeNumber): seq[uint8] =
  var ii = i
  result = toByteArray[typeof(i)](ii)

proc asBytes*(s: string): seq[uint8] =
  for c in s: result.add(c.uint8)
  if result.len mod 2 == 1:
    result.add(0)