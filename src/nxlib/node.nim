import memfiles, streams, strutils
import nimlz4
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
    name_id*: uint32
    first_id*: uint32
    children_count*: uint16
    kind*: NxType
    data*: DataBuffer # Any
  NxString* = ref object of NxBaseObj
    length*: uint16
    data*: seq[uint8]
  NxBitmap* = ref object of NxBaseObj
    length*: uint32
    data*: seq[uint8]
  NxAudio* = ref object of NxBaseObj
    data*: seq[uint8]
  NxHeader* = ref object of NxBaseObj
    magic*: string
    node_count*: uint32
    node_offset*: uint64 # ptr NxNode
    string_count*: uint32
    string_offset*: uint64 # ptr OffsetTable
    bitmap_count*: uint32
    bitmap_offset*: uint64 # ptr OffsetTable
    audio_count*: uint32
    audio_offset*: uint64 # ptr OffsetTable
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

proc name*(self: NxNode): string =
  var nx = self.root
  let name_id = self.name_id
  var ns = nx.strings[name_id]
  result = ns.toString

proc children*(self: NxNode): seq[NxNode] =
  var nx = self.root
  result = nx.nodes[self.first_id..<self.children_count]

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

proc newNxInt*(i: int64): NxNode =
  result.new
  result.name_id = 0
  result.first_id = 0
  result.children_count = 0
  result.kind = ntInt
  result.data = array[8, uint8].create()
  for n in 0..<8:
    var 
      ii = i
      v = cast[ptr uint8](addr(ii) + n)
    result.data[n] = v[]

proc newNxReal*(f: float64): NxNode =
  result.new
  result.first_id = 0
  result.children_count = 0
  result.kind = ntReal
  result.data = array[8, uint8].create()
  for n in 0..<8:
    var 
      ff = f
      v = cast[ptr uint8](addr(ff) + n)
    result.data[n] = v[]

proc newNxString*(data: string): NxString =
  result.new
  result.data.add(data.asBytes)
  result.length = result.data.len.uint16

proc newNxVector*(x, y: int32): NxNode =
  result.new
  result.first_id = 0
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

proc newNxBitmap*(uncompressed_data: var string): NxBitmap =
  result.new
  let compressed = compress_frame(uncompressed_data, prefs)
  for c in compressed:
    result.data.add(c.uint8)
  result.length = result.data.len.uint32

proc newNxAudio*(sound_data: string): NxAudio =
  result.new
  for c in sound_data:
    result.data.add(c.uint8)

proc addNxString*(nx: NxFile, data: string): NxString =
  result.new
  result.data = data.asBytes
  result.length = result.data.len.uint16
  nx.strings.add(result)

proc newNxFile*(filename: string): NxFile =
  result.new
  result.writer = filename.openFileStream(fmWrite)

  result.header = result.newNxHeader

proc toNxType*(i: uint16): NxType =
  case i:
  of 1: ntInt
  of 2: ntReal
  of 3: ntString
  of 4: ntVector
  of 5: ntBitmap
  of 6: ntAudio
  else: ntNone

proc `[]=`*(nx: NxFile, name: string, node: NxNode) =
  nx.nodes.add(node)
  nx.strings.add(name.newNxString)
  node.name_id = nx.strings.len.uint32
  node.root = nx

proc `[]=`*(node: NxNode, name: string, child: NxNode) =
  let nx = node.root

  assert nx.isNil, "Add child is required a nx file"

  nx.nodes.add(child)
  if node.first_id <= 0:
    node.first_id = nx.nodes.len.uint32
  nx.strings.add(name.newNxString)
  child.name_id = nx.strings.len.uint32

proc `<>`*(node: NxNode, i: SomeNumber) =
  node.kind = ntInt
  var count = 0
  for n in i.asBytes:
    node.data[count] = n
    count.inc(1)

proc `<>`*(node: NxNode, i: string) =
  node.kind = ntString
  var count = 0
  for n in i:
    node.data[count] = n.uint8
    count.inc(1)

proc `<>`*(node: NxNode, i: SomeFloat) =
  node.kind = ntReal
  var count = 0
  for n in i.asBytes:
    node.data[count] = n.uint8
    count.inc(1)

proc `<>`*(node: NxNode, i: NxVector) =
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

proc `<>`*(node: NxNode, data: NxFileParameter) =
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
