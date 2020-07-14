import memfiles, streams, strutils, sequtils
import nimlz4, nimpng
import util, compress

const NODE_OFFSET* = 52

type
  OffsetTable* = seq[uint64]
  NxVector* = tuple
    x: int32
    y: int32
  NxBitmapSize* = tuple
    x: uint16
    y: uint16
  NxType* = enum
    ntNone = 0,
    ntInt = 1,
    ntReal = 2,
    ntString = 3,
    ntVector = 4,
    ntBitmap = 5,
    ntAudio = 6,
  NxBaseObj* = ref object of RootObj
    root*: NxFile
  NxNode* = ref object of NxBaseObj
    id*: uint32 #
    next*: uint32 #
    children*: seq[NxNode] #
    name_id*: uint32
    first_child_id*: uint32
    children_count*: uint16
    kind*: NxType
    data*: DataBuffer
  NxString* = ref object of NxBaseObj
    length*: uint16
    data*: seq[uint8]
  NxBitmap* = ref object of NxBaseObj
    length*: uint32
    data*: seq[uint8]
    png*: PngResult[string]
    width: uint16 #
    height: uint16 #
  NxAudio* = ref object of NxBaseObj
    data*: seq[uint8]
  NxHeader* = ref object of NxBaseObj
    magic*: string
    node_count*: uint32
    node_offset*: uint64
    string_count*: uint32
    string_offset*: uint64
    bitmap_count*: uint32
    bitmap_offset*: uint64
    audio_count*: uint32
    audio_offset*: uint64
  NxFile* = ref object of RootObj
    length*: int64
    header*: NxHeader
    file*: MemMapFileStream
    writer*: FileStream
    nodes*: seq[NxNode]
    strings*: seq[NxString]
    string_offsets*: OffsetTable
    bitmaps*: seq[NxBitmap]
    bitmap_offsets*: OffsetTable
    audios*: seq[NxAudio]
    audio_offsets*: OffsetTable

proc toString*(node: NxString): string
proc toNxString*(self: NxNode): NxString
proc `==`*(kind: NxType, i: SomeInteger): bool = kind.ord == i
proc `!=`*(kind: NxType, i: SomeInteger): bool = kind.ord != i

#[
proc children*(self: NxNode): seq[NxNode] =
  var nx = self.root
  result = nx.nodes[self.first_child_id..<self.children_count]
]#

proc toInt*(self: NxNode, default: int64 = 0): int64 =
  result = case self.kind:
  of ntNone, ntAudio, ntBitmap, ntVector: default
  of ntInt: self.data.i64
  of ntReal: self.data.f64.int64
  of ntString: 
    let s = self.toNxString.toString
    try:parseInt(s).int64
    except: default

proc toString*(self: NxNode, default: string = ""): string =
  result = case self.kind:
    of ntNone, ntAudio, ntBitmap, ntVector: default
    of ntInt: $ self.data.i64
    of ntReal: $ self.data.f64
    of ntString:
      var
        nx = self.root
        id = self.data.u32
      if nx.strings.len > id.int: nx.strings[id].toString
      else: default

proc toNxString*(self: NxNode): NxString =
  var
    nx = self.root
    id = self.data.u32
  result = if nx.strings.len > id.int:
    nx.strings[id]
  else:
    nil

proc toNxBitmap*(self: NxNode): NxBitmap =
  var
    nx = self.root
    id = self.data.u32
  result = if nx.bitmaps.len > id.int:
    nx.bitmaps[id]
  else:
    nil

proc image*(bitmap: NxBitmap): string =
  var compressed = bitmap.data.toString
  result = uncompress_frame(compressed)

proc vector*(node: NxNode): NxVector =
  var
    x = node.data.i32
    buf = node.data[4..7]
    y = buf.i32
  result = (x, y)

proc toNxAudio*(self: NxNode): NxAudio =
  var
    nx = self.root
    id = self.data.u32
  result = if nx.audios.len <= id.int:
    nx.audios[id]
  else:
    nil

proc toString*(node: NxString): string =
  result = node.data.toString

proc id*(bitmap: NxBitmap): uint32 =
  result = bitmap.data.u32

proc size*(bitmap: NxBitmap): NxBitmapSize =
  var
    xbuf = bitmap.data[4..5]
    ybuf = bitmap.data[6..7]
    x = xbuf.u16
    y = ybuf.u16
  
  result = (x, y)

proc len*(bitmap: NxBitmap): int = bitmap.length.int

proc newNxHeader*(nx: NxFile): NxHeader =
  result.new
  result.magic = "PKG4"
  result.root = nx

proc newNxNode*(kind: NxType): NxNode =
  result.new
  result.kind = kind
  result.data = array[8, uint8].create

proc newNxNone*(): NxNode =
  result.new
  result.kind = ntNone
  result.data = array[8, uint8].create()
  for n in 0..<8:
    result.data[n] = 0

proc newNxInt*(i: int64): NxNode =
  result = newNxNode(ntInt)
  var count = 0
  for b in i.asBytes:
    result.data[count] = b
    count.inc(1)

proc newNxReal*(f: float64): NxNode =
  result = newNxNode(ntReal)
  var count = 0
  for b in f.asBytes:
    result.data[count] = b
    count.inc(1)

proc newNxVector*(x, y: int32): NxNode =
  result.new
  result.first_child_id = 0
  result.children_count = 0
  result.kind = ntVector
  result.data = array[8, uint8].create()
  for n in 0..<4:
    var 
      x1 = x
      v = cast[ptr uint8](addr(x1) + n)
    result.data[n] = v[]
  for n in 4..<8:
    var 
      y1 = y
      v = cast[ptr uint8](addr(y1) + n)
    result.data[n] = v[]

proc newNxString*(data: string): NxString =
  result.new
  result.data.add(data.asBytes)
  result.length = result.data.len.uint16

proc indexOf[T](arr: seq[T], data: T): int =
  if data.isNil: return -1    
  result = -1
  for index, item in arr:
    if item == data:
      return index

proc newNxNodeString*(data: string, nx: NxFile): NxNode =
  result = newNxNode(ntString)
  result.root = nx

  let filtered = nx.strings.filterIt(it.toString == data)

  let name_nxs = if filtered.len > 0:
    filtered[0]
  else:
    let new_nxs = newNxString(data)
    nx.strings.add(new_nxs)
    new_nxs

  let id = nx.strings.indexOf(name_nxs)

  assert id >= 0

  var count = 0
  for b in id.asBytes:
    result.data[count] = b
    count.inc(1)

proc name*(self: NxNode): string =
  var nx = self.root
  let name_id = self.name_id
  var ns = nx.strings[name_id]
  result = ns.toString

proc `name=`*(self: NxNode, s: string) =
  assert not self.root.isNil, "you must add this node to nx file before set name"
  let nx = self.root
  var id = -1
  for i, nxs in nx.strings:
    if nxs.toString == s:
      id = i
  let name_node = if id < 0:
    s.newNxNodeString(nx)
  else:
    echo id
    let filtered = nx.nodes.filterIt(it.kind == ntString and it.data.u32 == id.uint32)
    if filtered.len > 0:
      filtered[0]
    else: s.newNxNodeString(nx)

  self.name_id = name_node.id

proc `+=`*(node: NxNode, child: NxNode) =
  child.root = node.root
  node.children.add(child)

proc `+=`*(nx: NxFile, child: NxNode) =
  nx.nodes.add(child)

type
  NxAddChildParameter = tuple
    name: string
    node: NxNode

proc `+=`*(node: NxNode, child: NxAddChildParameter) =
  child.node.root = node.root
  node.children.add(child.node)
  node.children_count = node.children.len.uint16
  child.node.name = child.name

proc `[]=`*(node: NxNode, name: string, child: NxNode) =
  node += (name, child)

proc newNxBitmap*(uncompressed_data: var string): NxBitmap =
  result.new
  let compressed = compress_frame(uncompressed_data, prefs)
  for c in compressed:
    result.data.add(c.uint8)
  result.length = result.data.len.uint32
  result.png = uncompressed_data.decodePNG32()
  result.width = result.png.width.uint16
  result.height = result.png.height.uint16

# non-dependent bitmap node
proc newNxNodeBitmap*(nx: NxFile, uncompressed_data: string): NxNode =
  result = newNxNode(ntBitmap)
  var data = uncompressed_data
  let nxb = data.newNxBitmap
  let nxb_id = nx.bitmaps.len.uint32
  nx.bitmaps.add(nxb)
  var count = 0
  for b in nxb_id.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in nxb.width.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in nxb.height.asBytes:
    result.data[count] = b
    count.inc(1)

proc newNxAudio*(sound_data: string): NxAudio =
  result.new
  for c in sound_data:
    result.data.add(c.uint8)

proc newNxNodeAudio*(nx: NxFile, sound_data: string): NxNode =
  result = newNxNode(ntAudio)
  let nxa = sound_data.newNxAudio
  let nxa_id = nx.audios.len.uint32
  nx.audios.add(nxa)
  var count = 0
  for b in nxa_id.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in sound_data.len.uint32.asBytes:
    result.data[count] = b
    count.inc(1)

proc newNxFile*(filename: string): NxFile =
  result.new
  result.writer = filename.openFileStream(fmWrite)

  result.header = result.newNxHeader

  # base node
  # result[""] = nil 

proc toNxType*(i: uint16): NxType =
  case i:
  of 1: ntInt
  of 2: ntReal
  of 3: ntString
  of 4: ntVector
  of 5: ntBitmap
  of 6: ntAudio
  else: ntNone

proc none*(node: NxNode) =
  node.kind = ntNone
  for i in 0..<8:
    node.data[i] = 0

proc `int=`*(node: NxNode, i: SomeInteger) =
  node.kind = ntInt
  var count = 0
  for n in cast[int64](i).asBytes:
    node.data[count] = n
    count.inc(1)

proc `string=`*(node: NxNode, i: string) =
  node.kind = ntString
  var count = 0
  for n in i:
    node.data[count] = n.uint8
    count.inc(1)

proc `real=`*(node: NxNode, f: SomeFloat) =
  node.kind = ntReal
  var count = 0
  for n in cast[float64](f).asBytes:
    node.data[count] = n.uint8
    count.inc(1)

proc `vector=`*(node: NxNode, i: NxVector) =
  node.kind = ntVector
  var count = 0
  for x in i.x.asBytes:
    node.data[count] = x.uint8
    count.inc(1)
  for y in i.y.asBytes:
    node.data[count] = y.uint8
    count.inc(1)

type
  NxFileParameter* = tuple
    kind: NxType
    buf: string

import nimpng

proc `binary=`*(node: NxNode, data: NxFileParameter) =
  node.kind = data.kind
  var i = 0
  if node.kind == ntBitmap:
    var uncompressed = data.buf
    let nxb = newNxBitmap(uncompressed)
    node.root.bitmaps.add(nxb)

    for b in node.root.bitmaps.len.uint32.asBytes:
      node.data[i] = b
      i.inc(1)

    let png = decodePNG32(uncompressed)
    let 
      w = png.width
      h = png.height
    
    for b in w.uint16.asBytes:
      node.data[i] = b
      i.inc(1)
    
    for b in h.uint16.asBytes:
      node.data[i] = b
      i.inc(1)
  elif node.kind == ntAudio:
    let data = data.buf
    let nxa = newNxAudio(data)
    node.root.audios.add(nxa)
    
    for b in node.root.audios.len.uint32.asBytes:
      node.data[i] = b
      i.inc(1)
    
    for b in data.len.uint32.asBytes:
      node.data[i] = b
      i.inc(1)

proc decode*(bitmap: NxBitmap) =
  var data = bitmap.data.toString
  bitmap.png = decodePNG32(data.uncompress_frame)