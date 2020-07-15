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
    relative*: NxData # relative data
    # when ntString -> NxString
    # when ntBitmap -> NxBitmap
    # when ntAudio -> NxAudio
    # else -> nil
    parent*: NxNode #
  NxNode* = ref object of NxBaseObj
    id*: uint32 #
    next*: uint32 #
    children*: seq[NxNode] #
    name_id*: uint32
    first_child_id*: uint32
    children_count*: uint16
    kind*: NxType
    data*: DataBuffer
  NxData = ref object of NxBaseObj
    id*: uint32 #
  NxString* = ref object of NxData
    length*: uint16
    data*: seq[uint8]
  NxBitmap* = ref object of NxData
    length*: uint32
    data*: seq[uint8]
    png*: PngResult[string]
    width: uint16 #
    height: uint16 #
  NxAudio* = ref object of NxData
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

proc toString*(nxs: NxString): string
proc toNxString*(self: NxNode): NxString
proc `==`*(kind: NxType, i: SomeInteger): bool = kind.ord == i
proc `!=`*(kind: NxType, i: SomeInteger): bool = kind.ord != i

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

proc toString*(nxs: NxString): string =
  result = nxs.data.toString

proc size*(bitmap: NxBitmap): NxBitmapSize =
  var
    xbuf = bitmap.data[4..5]
    ybuf = bitmap.data[6..7]
    x = xbuf.u16
    y = ybuf.u16
  
  result = (x, y)

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

proc indexOf(arr: seq[NxNode], data: NxNode): int =
  if data.isNil: return -1    
  result = -1
  for index, item in arr:
    if item == data:
      return index

proc data_id*(node: NxNode): uint32 =
  result = case node.kind:
  of ntString, ntBitmap, ntAudio:
    node.data.u32
  else:
    0.uint32

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
  nxb.id = nxb_id
  result.relative = nxb
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
  nxa.id = nxa_id
  result.relative = nxa
  var count = 0
  for b in nxa_id.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in sound_data.len.uint32.asBytes:
    result.data[count] = b
    count.inc(1)

proc toNxType*(i: uint16): NxType =
  case i:
  of 1: ntInt
  of 2: ntReal
  of 3: ntString
  of 4: ntVector
  of 5: ntBitmap
  of 6: ntAudio
  else: ntNone

proc decode*(bitmap: NxBitmap) =
  var data = bitmap.data.toString
  bitmap.png = decodePNG32(data.uncompress_frame)


proc addStringNode*(parent: NxNode, s: string): NxNode


proc baseNode*(nx: NxFile): NxNode =
  result = nx.nodes[0]

proc newNodeId(nx: NxFile): uint32 =
  result = nx.nodes.len.uint32

proc appendNode(nx: NxFile, node: NxNode) =
  let id = nx.newNodeId
  node.id = id
  nx.nodes.add(node)

proc updateChildId(node: NxNode) =
  if node.children.len > 0:
    node.first_child_id = node.children[0].id

proc appendChild*(nx: NxFile, parent, child: NxNode) =
  child.root = nx
  # = parent.root

  child.parent = parent
  parent.children.add(child)
  parent.children_count = parent.children.len.uint16

  if parent.first_child_id <= 0:
    nx.appendNode(child)
    parent.first_child_id = child.id
  else:
    let last_child_id = parent.first_child_id + parent.children_count - 1
    var new_nodes = newSeq[NxNode]()
    new_nodes.add(nx.nodes[0..<last_child_id])
    new_nodes.add(child)
    new_nodes.add(nx.nodes[last_child_id..<nx.nodes.len])
    # update node id
    for i, node in new_nodes:
      node.id = i.uint32
    # update child id
    for node in new_nodes:
      node.updateChildId
    nx.nodes = new_nodes
    

proc detachChild*(nx: NxFile, parent, child: NxNode, with_data: bool = false) =
  var index = -1
  for n, node in nx.nodes:
    if node == child:
      index = n
      break

  if index < 0:
    return
  return

proc detach*(node: NxNode) =
  if not node.parent.isNil:
    node.root.detachChild(node.parent, node)
  else:
    echo "Warning! No parent, not works."

proc getName*(node: NxNode): string =
  let name_id = node.name_id
  var ns = node.root.strings[name_id]
  result = ns.toString

proc setName*(node: NxNode, name: string) =
  let name_node = node.addStringNode(name)
  node.name_id = name_node.relative.id
  node.root.appendChild(node, name_node)

proc addNode*(nx: NxFile, node: NxNode) =
  let index = nx.nodes.indexOf(node)
  if index < 0:
    node.root = nx
    node.id = nx.newNodeId
    nx.nodes.add(node)

proc addNoneNode*(parent: NxNode): NxNode =
  result = newNxNone()
  parent.root.appendChild(parent, result)

proc addNoneNode*(parent: NxNode, name: string): NxNode =
  result = parent.addNoneNode()
  result.setName(name)

proc addIntNode*(parent: NxNode, i: int64): NxNode =
  let v = i.int64
  result = newNxInt(v)
  parent.root.appendChild(parent, result)

proc addRealNode*(parent: NxNode, f: float64): NxNode =
  let v = f.float64
  result = newNxReal(v)
  parent.root.appendChild(parent, result)

proc addVectorNode*(parent: NxNode, x, y: int): NxNode =
  result = newNxVector(x.int32, y. int32)
  parent.root.appendChild(parent, result)

proc newStringId(nx: NxFile): uint32 =
  result = nx.strings.len.uint32

proc addString(nx: NxFile, nxs: NxString) =
  nxs.id = nx.newStringId
  nx.strings.add(nxs)

proc newNxString(nx: NxFile, s: string): NxString =
  let found = nx.strings.filterIt(it.toString == s)
  if found.len > 0: return found[0]
  result.new
  result.data = s.asBytes
  nx.addString(result)

proc addStringNode*(parent: NxNode, s: string): NxNode =
  let nxs = parent.root.newNxString(s)
  result = newNxNode(ntString)
  result.relative = nxs
  result.parent = parent

  var count = 0
  for b in nxs.id.asBytes:
    result.data[count] = b
    count.inc(1)

proc newBitmapId(nx: NxFile): uint32 =
  result = nx.bitmaps.len.uint32

proc addBitmap(nx: NxFile, nxb: NxBitmap) =
  nxb.id = nx.newBitmapId
  nx.bitmaps.add(nxb)

proc newNxBitmap(nx: NxFile, uncompressed_data: string): NxBitmap =
  var
    data = uncompressed_data
    compressed = compress_frame(data, prefs)
    bytes = compressed.asBytes
    found = nx.bitmaps.filterIt(it.data == bytes)
  if found.len > 0: return found[0]
  result.new
  result.data = bytes
  result.png = decodePNG32(uncompressed_data)
  result.width = result.png.width.uint16
  result.height = result.png.height.uint16
  nx.addBitmap(result)

proc addBitmapNode*(parent: NxNode, uncompressed_data: string): NxNode =
  let nxb = parent.root.newNxBitmap(uncompressed_data)
  result = newNxNode(ntBitmap)
  result.relative = nxb

  var count = 0
  for b in nxb.id.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in nxb.width.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in nxb.height.asBytes:
    result.data[count] = b
    count.inc(1)

  parent.root.appendChild(parent, result)

proc newAudioId(nx: NxFile): uint32 =
  result = nx.audios.len.uint32

proc addAudio(nx: NxFile, nxa: NxAudio) =
  nxa.id = nx.newAudioId
  nx.audios.add(nxa)

proc newNxAudio(nx: NxFile, data: string): NxAudio =
  result.new
  result.data = data.asBytes
  nx.addAudio(result)

proc addAudioNode*(parent: NxNode, data: string): NxNode =
  result = newNxNode(ntAudio)
  let nxa = parent.root.newNxAudio(data)
  result.relative = nxa
  
  var count = 0
  for b in nxa.id.asBytes:
    result.data[count] = b
    count.inc(1)
  for b in nxa.data.len.uint32.asBytes:
    result.data[count] = b
    count.inc(1)

  parent.root.appendChild(parent, result)
