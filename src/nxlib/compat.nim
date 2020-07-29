import read, node, util, sugar
import strutils

proc nxOpen*(filename: cstring): NxFile {.exportc, cdecl.} =
  result = ($filename).openNxFile()

proc nxGetNodes*(nx: NxFile): seq[NxNode] {.exportc, cdecl.} =
  result = nx.nodes

proc nxGetStringTable*(nx: NxFile): seq[NxString] {.exportc, cdecl.} =
  result = nx.strings

proc nxGetBitmapTable*(nx: NxFile): seq[NxBitmap] {.exportc, cdecl.} =
  result = nx.bitmaps

proc nxGetAudioTable*(nx: NxFile): seq[NxAudio] {.exportc, cdecl.} =
  result = nx.audios

proc nxGetNodeId*(node: NxNode): cint {.exportc, cdecl.} =
  result = node.id.cint

proc nxGetDataId*(data: NxData): cint {.exportc, cdecl.} =
  result = data.id.cint

proc nxGetDataLen*(data: NxData): cint {.exportc, cdecl.} =
  result = data.data.len.cint

proc nxGetDataPrintString(nxs: NxString, until: cint, suffix: cstring): cstring {.exportc, cdecl.} =
  result = if nxs.toString.len > until:
    nxs.toString[0..until].cstring
  else:
    nxs.toString.cstring

proc nxGetDataPrintBitmap(nxb: NxBitmap, until: cint, suffix: cstring): cstring {.exportc, cdecl.} =
  var print = newSeq[string]()
  let bytes = nxb.data
  for i, byte in bytes:
    if i >= until:
      print.add($suffix)
      break
    print.add(byte.toHex)
  return print.join(", ").cstring

proc nxGetDataPrintAudio*(nxa: NxAudio, until: cint, suffix: cstring): cstring {.exportc, cdecl.} =
  var print = newSeq[string]()
  let bytes = nxa.data
  for i, byte in bytes:
    if i >= until:
      print.add($suffix)
      break
    print.add(byte.toHex)
  return print.join(", ").cstring

proc nxGetChildNodes*(node: NxNode): seq[NxNode] {.exportc, cdecl.} =
  result = node.children

proc nxGetName*(node: NxNode): cstring {.exportc, cdecl.} =
  result = node.getName.cstring

proc nxSetName*(node: NxNode, new_name: cstring) {.exportc, cdecl.} =
  node.name = $new_name;

proc nxGetType*(node: NxNode): cint {.exportc, cdecl.} =
  result = node.kind.ord.cint

proc nxGetTypeString*(node: NxNode): cstring {.exportc, cdecl.} =
  result = $node.kind

proc nxGetString*(node: NxNode): cstring {.exportc, cdecl.} =
  result = node.toString

proc nxGetRelativeId*(node: NxNode): cint {.exportc, cdecl.} =
  result = node.data_id.cint

proc nxGetData*(node: NxNode): seq[uint8] {.exportc, cdecl.} =
  if not node.relative.isNil:
    if node.kind == ntBitmap:
      let bitmap = cast[NxBitmap](node.relative)
      let image = bitmap.image
      let b = image.asBytes
      return b
    elif node.kind == ntAudio:
      return node.relative.data
  return @[]

proc nxGetDataDirectly*(data: NxData): seq[uint8] =
  result = data.data

proc nxGetParent*(node: NxNode): NxNode {.exportc, cdecl.} =
  result = node.parent

proc nxGetNamedChild*(node: NxNode, name: cstring): NxNode {.exportc, cdecl.} =
  result = node[$name]

proc nxGetRelative*(node: NxNode): NxData {.exportc, cdecl.}=
  result = node.relative

proc nxGetBitmapSize*(nxb: NxBitmap): tuple[x: cint, y: cint] {.exportc, cdecl.} =
  result = (nxb.width.cint, nxb.height.cint)

proc nxGetBitmapLength*(nxb: NxBitmap): cint {.exportc, cdecl.} =
  result = nxb.length.cint

proc nxDecodeBitmap*(nxb: NxBitmap): seq[uint8] {.exportc, cdecl.} =
  result = nxb.image.asBytes

proc nxConvertToNone*(node: NxNode) {.exportc, cdecl.} =
  node.cvtNoneNode()

proc nxConvertToInt*(node: NxNode, i: int64) {.exportc, cdecl.} =
  node.cvtIntNode(i)

proc nxConvertToReal*(node: NxNode, f: float64) {.exportc, cdecl.} =
  node.cvtRealNode(f)

proc nxConvertToVector*(node: NxNode, x: int32, y: int32) {.exportc, cdecl.} =
  node.cvtVectorNode(x, y)

proc nxConvertToString*(node: NxNode, str: cstring) {.exportc, cdecl.} =
  node.cvtStringNode($str)

proc nxConvertToBitmap*(node: NxNode, data: cstring, is_path: bool = false) {.exportc, cdecl.} =
  let buf = if is_path:
    ($data).open(fmRead).readAll
  else:
    $data
  
  node.cvtBitmapNode(buf)

proc nxConvertToAudio*(node: NxNode, data: cstring, is_path: bool = false) {.exportc, cdecl.} =
  let buf = if is_path:
    ($data).open(fmRead).readAll
  else:
    $data
  
  node.cvtAudioNode(buf)

proc nxAddNoneNode*(parent: NxNode, name: cstring): NxNode {.exportc, cdecl.} =
  parent.addNoneNode($name)