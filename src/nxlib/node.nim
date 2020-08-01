import memfiles, streams, strutils, sequtils, algorithm
import nimlz4, nimpng
import util, compress

const NODE_OFFSET* = 52

type
  OffsetTable* = seq[uint64]
  NxVector* {.exportc.} = tuple
    x: int32
    y: int32
  NxBitmapSize* = tuple
    x: uint16
    y: uint16
  NxType* {.exportc.} = enum
    ntNone = 0,
    ntInt = 1,
    ntReal = 2,
    ntString = 3,
    ntVector = 4,
    ntBitmap = 5,
    ntAudio = 6,
  NxBaseObj* {.exportc.} = ref object of RootObj
    root*: NxFile
    relative*: NxData # relative data
    # when ntString -> NxString
    # when ntBitmap -> NxBitmap
    # when ntAudio -> NxAudio
    # else -> nil
    parent*: NxNode #
  NxNode* {.exportc.} = ref object of NxBaseObj
    id*: uint32 #
    next*: uint32 #
    children*: seq[NxNode] #
    name_id*: uint32
    first_child_id*: uint32
    children_count*: uint16
    kind*: NxType
    data*: DataBuffer
  NxData* {.exportc.} = ref object of NxBaseObj
    id*: uint32 #
    data*: seq[uint8]
  NxString* {.exportc.} = ref object of NxData
    length*: uint16
  NxBitmap* {.exportc.} = ref object of NxData
    length*: uint32
    png*: PngResult[string]
    width*: uint16 #
    height*: uint16 #
  NxAudio* {.exportc.} = ref object of NxData
  NxHeader* {.exportc.} = ref object of NxBaseObj
    magic*: string
    node_count*: uint32
    node_offset*: uint64
    string_count*: uint32
    string_offset*: uint64
    bitmap_count*: uint32
    bitmap_offset*: uint64
    audio_count*: uint32
    audio_offset*: uint64
  NxFile* {.exportc.} = ref object of RootObj
    length*: int64
    header*: NxHeader
    file*: Stream
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
proc vector*(node: NxNode): NxVector
proc newNxString(nx: NxFile, s: string): NxString
proc getName*(node: NxNode): string

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
    of ntNone, ntAudio, ntBitmap: default
    of ntInt: $ self.data.i64
    of ntReal: $ self.data.f64
    of ntVector:
      let
        v = self.vector
      $v.x & ", " & $v.y 
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
  var compressed = bitmap.data.toStringNoTermiate
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
  if bitmap.png.isNil:
    bitmap.png = decodePNG32(bitmap.image)
  result = (bitmap.png.width.uint16, bitmap.png.height.uint16)

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
  var count = 0
  for b in x.asBytes:
    result.data[count] = b
    count.inc
  for b in y.asBytes:
    result.data[count] = b
    count.inc

proc indexOf[T](arr: seq[T], data: T): int =
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

proc toNxType*(i: uint16): NxType =
  case i:
  of 1: ntInt
  of 2: ntReal
  of 3: ntString
  of 4: ntVector
  of 5: ntBitmap
  of 6: ntAudio
  else: ntNone

proc addStringNode*(parent: NxNode, s: string): NxNode

proc baseNode*(nx: NxFile): NxNode =
  result = nx.nodes[0]

proc newNodeId(nx: NxFile): uint32 =
  result = nx.nodes.len.uint32

proc appendNode(nx: NxFile, node: NxNode) =
  let id = nx.newNodeId
  node.id = id
  nx.nodes.add(node)

proc sortChild(a, b: NxNode): int =
  return a.id.int - b.id.int

proc updateChildId(node: NxNode) =
  if node.children.len > 0:
    node.first_child_id = node.children[0].id
    node.children.sort(sortChild)

proc appendChild*(nx: NxFile, parent, child: NxNode) =
  child.root = nx
  assert parent.children.filterIt(it == child).len <= 0
  child.parent = parent

  let isParentHasNoChildren = parent.first_child_id <= 0

  let prev = parent.children.len.uint32
  parent.children.add(child)
  parent.children_count = parent.children.len.uint16

  if isParentHasNoChildren:
    nx.appendNode(child)
  else:
    let last_child_id = parent.first_child_id + prev
    var new_nodes = newSeq[NxNode]()
    new_nodes.add(nx.nodes[0..<last_child_id])
    new_nodes.add(child)
    new_nodes.add(nx.nodes[last_child_id..<nx.nodes.len])
    nx.nodes = new_nodes
  
  for i,node in nx.nodes:
    node.id = i.uint32

  for node in nx.nodes:
    node.updateChildId

proc detachChild*(nx: NxFile, parent, child: NxNode, with_data: bool = false) =
  let
    abs_index = nx.nodes.indexOf(child)
    rel_index = if parent.isNil: 0 # base node
    else: parent.children.indexOf(child)
  
  echo "child at: ", abs_index, "rel: ", rel_index
  
  if abs_index >= 0:
    nx.nodes.delete(abs_index)
    if child.children.len > 0:
      let start = child.first_child_id
      nx.nodes.delete(start, start + child.children.len.uint32)
      echo child.first_child_id, ", ", start + child.children.len.uint32
  if rel_index >= 0:
    parent.children.delete(rel_index)

  for i, node in nx.nodes:
    node.id = i.uint32
  for node in nx.nodes:
    node.updateChildId

  nx.header.node_count = nx.nodes.len.uint32


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
  when defined(useNameRefNode):
    let name_node = node.addStringNode(name)
    node.name_id = name_node.relative.id
    node.root.appendChild(node, name_node)
  else:
    let nxs = newNxString(node.root, name)
    node.name_id = nxs.id

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
  result.root = parent.root

  var count = 0
  for b in nxs.id.asBytes:
    result.data[count] = b
    count.inc(1)

  parent.root.appendChild(parent, result)

proc newBitmapId(nx: NxFile): uint32 =
  result = nx.bitmaps.len.uint32

proc addBitmap(nx: NxFile, nxb: NxBitmap) =
  nxb.id = nx.newBitmapId
  nx.bitmaps.add(nxb)

proc newNxBitmap(nx: NxFile, uncompressed_data: string): NxBitmap =
  result.new
  result.png = decodePNG32(uncompressed_data)
  var
    data = result.png.data
    compressed = compress_frame(data, prefs)
  result.data = compressed.asBytes
  result.length = result.data.len.uint32
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

proc refCount(data: NxData): int =
  for node in data.root.nodes:
    if node.relative == data:
      result.inc

proc setDataId*(node: NxNode, id: uint32, remove_with_relative: bool = false) =
  case node.kind:
    of ntString, ntBitmap, ntAudio:
      var count = 0
      for b in id.asBytes:
        node.data[count] = b
        count.inc
    else: discard

proc remove(data: NxData) =
  if data is NxString:
    let nxs = cast[NxString](data)
    let index = data.root.strings.indexOf(nxs)
    for i, node in data.root.nodes:
      if not node.relative.isNil and node.relative.id > index.uint32:
        node.setDataId(node.relative.id + 1)
    data.root.strings.delete(index)
    for i, string in data.root.strings:
      string.id = i.uint32
  elif data is NxBitmap:
    let nxb = cast[NxBitmap](data)
    let index = data.root.bitmaps.indexOf(nxb)
    for i, node in data.root.nodes:
      if not node.relative.isNil and node.relative.id > index.uint32:
        node.setDataId(node.relative.id + 1)
    data.root.bitmaps.delete(index)
    for i, string in data.root.bitmaps:
      string.id = i.uint32
  elif data is NxAudio:
    let nxa = cast[NxAudio](data)
    let index = data.root.audios.indexOf(nxa)
    for i, node in data.root.nodes:
      if not node.relative.isNil and node.relative.id > index.uint32:
        node.setDataId(node.relative.id + 1)
    data.root.audios.delete(index)
    for i, string in data.root.audios:
      string.id = i.uint32
  data.parent = nil

proc cvtNoneNode*(node: NxNode, remove_noref_relative: bool = false) =
  node.kind = ntNone
  for i in 0..<8:
    node.data[i] = 0
  if not node.relative.isNil:
    if remove_noref_relative:
      node.relative.remove
    node.relative = nil

proc cvtIntNode*(node: NxNode, value: int64, remove_noref_relative: bool = false) =
  node.kind = ntInt
  var count = 0
  for b in value.asBytes:
    node.data[count] = b
    count.inc
  if not node.relative.isNil:
    if remove_noref_relative:
      node.relative.remove
    node.relative = nil

proc cvtRealNode*(node: NxNode, value: float64, remove_noref_relative: bool = false) =
  node.kind = ntReal
  var count = 0
  for b in value.asBytes:
    node.data[count] = b
    count.inc
  if not node.relative.isNil:
    if remove_noref_relative:
      node.relative.remove
    node.relative = nil

proc cvtVectorNode*(node: NxNode, x, y: int32, remove_noref_relative: bool = false) =
  node.kind = ntVector
  var count = 0
  for b in x.asBytes:
    node.data[count] = b
    count.inc
  for b in y.asBytes:
    node.data[count] = b
    count.inc
  if not node.relative.isNil:
    if remove_noref_relative:
      node.relative.remove
    node.relative = nil

proc cvtStringNode*(node: NxNode, data: string, remove_noref_relative: bool = false) =
  node.kind = ntString

  if not node.relative.isNil and remove_noref_relative:
    node.relative.remove
  
  let nxs = node.root.newNxString(data)
  node.relative = nxs
  nxs.parent = node
  nxs.root = node.root
  
  node.setDataId(nxs.id)

proc cvtBitmapNode*(node: NxNode, uncompressed_data: string, remove_noref_relative: bool = false) =
  node.kind = ntBitmap

  if not node.relative.isNil and remove_noref_relative:
    node.relative.remove

  let nxb = node.root.newNxBitmap(uncompressed_data)
  node.relative = nxb
  nxb.parent = node
  nxb.root = node.root
  
  node.setDataId(nxb.id)

proc cvtAudioNode*(node: NxNode, audio_data: string, remove_noref_relative: bool = false) =
  node.kind = ntAudio

  if not node.relative.isNil and remove_noref_relative:
    node.relative.remove

  let nxa = node.root.newNxBitmap(audio_data)

  node.relative = nxa
  nxa.parent = node
  nxa.root = node.root
  
  node.setDataId(nxa.id)
  var count = 4
  for b in audio_data.len.uint32.asBytes:
    node.data[count] = b
    count.inc