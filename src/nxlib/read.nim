import node, util
import streams, times, sequtils
from memfiles import newMemMapFileStream, MemMapFileStream

proc readHeader*(fs: MemMapFileStream, root: var NxFile): NxHeader =
  result.new

  result.root = root

  result.magic = fs.readStr(4)

  assert result.magic == "PKG4"

  result.node_count = fs.readUint32
  result.node_offset = fs.readUint64
  assert result.node_offset mod 4 == 0

  result.string_count = fs.readUint32
  result.string_offset = fs.readUint64
  assert result.string_offset mod 8 == 0

  result.bitmap_count = fs.readUint32
  result.bitmap_offset = fs.readUint64
  assert result.bitmap_offset mod 8 == 0

  result.audio_count = fs.readUint32
  result.audio_offset = fs.readUint64
  assert result.audio_offset mod 8 == 0

proc readNode(fs: MemMapFileStream, id: SomeOrdinal, root: var NxFile): NxNode =
  result.new

  result.id = id
  result.root = root

  result.name_id = fs.readUint32
  result.first_child_id = fs.readUint32
  result.children_count = fs.readUint16
  result.kind = fs.readUint16.toNxType
  # if result.kind != ntNone:
  result.data = array[8, uint8].create()
  discard fs.readData(result.data, 8)

  #[
  echo "-------- [ node start (", id, ") ] --------"
  echo "name id: ", result.name_id
  echo "first child id: ", result.first_child_id
  echo "children count: ", result.children_count
  echo "type: ", result.kind
  var buf = newSeq[uint8](8)
  for i in 0..<sizeof(result.data[]):
    buf[i] = result.data[i]
  echo "raw data: ", buf
  # ]#

proc readNodes*(fs: MemMapFileStream, root: var NxFile, count: SomeInteger): seq[NxNode] =
  for i in 0..<count:
    result.add(fs.readNode(i, root))

proc readString(fs: MemMapFileStream, root: var NxFile, length: uint16): NxString =
  result.new
  result.root = root
  result.length = length
  result.data = @[]
  var buf = array[uint16.high, uint8].create()
  discard fs.readData(buf, length.int)
  for byte in buf[]:
    if byte == 0: break
    result.data.add(byte)

proc readStringNodes*(fs: MemMapFileStream, root: var NxFile, count: SomeInteger): seq[NxString] =
  for i in 0..<count:
    var length = fs.readUint16
    if length mod 2 == 1: length.inc(1)
    if length > 0:
      let node = fs.readString(root, length)
      result.add(node)
      # f.writeLine fs.getPosition, ": ", node.toString
      # echo fs.getPosition, ": ", node.toString, " (", i, "/", count - 1, ")"

proc readBitmap(fs: MemMapFileStream, root: var NxFile, length: uint32): NxBitmap =
  result.new
  result.root = root
  result.length = length
  result.data = @[]
  result.data.setLen(length)
  discard fs.readData(addr(result.data[0]), length.int)

proc readBitmapNodes*(fs: MemMapFileStream, root: var NxFile, count: SomeInteger): seq[NxBitmap] =
  for i in 0..<count:
    let length = fs.readUint32
    if length > 0:
      result.add(fs.readBitmap(root, length))

proc readAudio(fs: MemMapFileStream, root: var NxFile, length: uint32): NxAudio =
  result.new
  result.root = root
  result.data = @[]
  result.data.setLen(length)
  discard fs.readData(addr(result.data[0]), length.int)

proc readAudioNodes*(fs: MemMapFileStream, root: var NxFile, audio_nodes: seq[NxNode]): seq[NxAudio] =
  for node in audio_nodes:
    var c = node.data[4..7]
    let length = c.u32
    result.add(fs.readAudio(root, length))

proc setPosFromOffset(fs: MemMapFileStream, offset: uint64) =
  fs.setPosition(offset.int)
  fs.setPosition(fs.readUint64.int)

proc skip(fs: MemMapFileStream, count: SomeUnsignedInt) =
  fs.setPosition(fs.getPosition + count)

proc readOffsetTable(fs: MemMapFileStream, offset: int, count: SomeInteger): seq[uint64] =
  fs.setPosition(offset)
  for i in 0..<count:
    result.add(fs.readUint64)

proc openNxFile*(path: string): NxFile =
  result.new
  
  result.length = path.getFileLength()

  let fs = path.newMemMapFileStream(fmRead)
  result.file = fs

  result.header = fs.readHeader(result)

  # set to node block offset
  fs.setPosition(result.header.node_offset.int)

  let node_count = result.header.node_count
  result.nodes = fs.readNodes(result, node_count)

  # set to string table offset
  let string_offset = result.header.string_offset

  if string_offset > NODE_OFFSET:
    let string_count = result.header.string_count
    result.string_offsets = fs.readOffsetTable(string_offset.int, string_count)

    fs.setPosFromOffset(string_offset)

    if string_count > 0:
      result.strings = fs.readStringNodes(result, string_count)
    else:
      fs.skip(2)
  else:
    fs.skip(2)

  let bitmap_offset = result.header.bitmap_offset
  if bitmap_offset > NODE_OFFSET:
    let bitmap_count = result.header.bitmap_count
    result.bitmap_offsets = fs.readOffsetTable(bitmap_offset.int, bitmap_count)

    fs.setPosFromOffset(bitmap_offset)

    if bitmap_count > 0:
      result.bitmaps = fs.readBitmapNodes(result, bitmap_count)
    else:
      fs.skip(4)
  else:
    fs.skip(4)

  let audio_offset = result.header.audio_offset
  if audio_offset > NODE_OFFSET:
    let audio_count = result.header.audio_count
    result.bitmap_offsets = fs.readOffsetTable(audio_offset.int, audio_count)

    fs.setPosFromOffset(result.header.audio_offset)
    if audio_count > 0:
      let audio_nodes = result.nodes.filterIt(it.kind == ntAudio)
      result.audios = fs.readAudioNodes(result, audio_nodes)

  for node in result.nodes:
    if node.children_count > 0:
      let last = node.first_child_id + node.children_count
      node.children = result.nodes[node.first_child_id..<last]
      assert node.children_count == node.children.len.uint, "wrong children count"
