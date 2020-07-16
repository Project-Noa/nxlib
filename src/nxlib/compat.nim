import read, node, util

proc nxOpen*(filename: cstring): NxFile {.exportc, cdecl.} =
  result = ($filename).openNxFile()

proc nxGetId*(node: NxNode): cint {.exportc, cdecl.} =
  result = node.id.cint

proc nxGetNodes*(file: NxFile): seq[NxNode] {.exportc, cdecl.} =
  result = file.nodes

proc nxGetChildNodes*(node: NxNode): seq[NxNode] {.exportc, cdecl.} =
  result = node.children

proc nxGetName*(node: NxNode): cstring {.exportc, cdecl.} =
  result = node.getName.cstring

proc nxGetType*(node: NxNode): cint {.exportc, cdecl.} =
  result = node.kind.ord.cint

proc nxGetTypeString*(node: NxNode): cstring {.exportc, cdecl.} =
  result = $node.kind

proc nxGetString*(node: NxNode): cstring {.exportc, cdecl.} =
  result = node.toString

proc nxGetDataId*(node: NxNode): cint {.exportc, cdecl.} =
  result = node.data_id.cint

proc nxGetData*(node: NxNode): seq[uint8] {.exportc, cdecl.} =
  if not node.relative.isNil:
    if node.kind == ntBitmap:
      let bitmap = cast[NxBitmap](node.relative)
      echo bitmap.length, ", ", bitmap.data.len
      let image = bitmap.image
      let b = image.asBytes
      return b
    elif node.kind == ntAudio:
      return node.relative.data
  return @[]

