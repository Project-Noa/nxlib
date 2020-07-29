import node, util
import streams, times, sequtils
from memfiles import newMemMapFileStream, MemMapFileStream

proc readHeader*(fs: Stream, root: var NxFile): NxHeader =
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

proc readNode(fs: Stream, id: SomeOrdinal, root: var NxFile): NxNode =
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

proc readNodes*(fs: Stream, root: var NxFile, count: SomeInteger): seq[NxNode] =
  for i in 0..<count:
    result.add(fs.readNode(i, root))

proc readString(fs: Stream, root: var NxFile): NxString =
  result.new
  result.root = root
  result.length = fs.readUint16
  if result.length mod 2 == 1: result.length.inc(1)
  result.data = newSeq[uint8](result.length)
  if result.length > 0:
    discard fs.readData(addr result.data[0], result.length.int)

proc readStringNodes*(fs: Stream, root: var NxFile): seq[NxString] =
  for offset in root.string_offsets:
    fs.setPosition(offset.int)
    result.add(fs.readString(root))

proc readBitmap(fs: Stream, root: var NxFile): NxBitmap =
  result.new
  result.root = root
  result.length = fs.readUint32
  result.data = @[]
  result.data.setLen(result.length)
  discard fs.readData(addr(result.data[0]), result.length.int)

proc readBitmapNodes*(fs: Stream, root: var NxFile): seq[NxBitmap] =
  for offset in root.bitmap_offsets:
    fs.setPosition(offset.int)
    result.add(fs.readBitmap(root))

proc readAudio(fs: Stream, root: var NxFile, length: uint32): NxAudio =
  result.new
  result.root = root
  result.data = @[]
  result.data.setLen(length)
  discard fs.readData(addr(result.data[0]), length.int)

proc readAudioNodes*(fs: Stream, root: var NxFile, audio_nodes: seq[NxNode]): seq[NxAudio] =
  for node in audio_nodes:
    var c = node.data[4..7]
    let length = c.u32
    result.add(fs.readAudio(root, length))

proc setPosFromOffset(fs: Stream, offset: uint64) =
  fs.setPosition(offset.int)
  fs.setPosition(fs.readUint64.int)

proc skip(fs: Stream, count: SomeUnsignedInt) =
  fs.setPosition(fs.getPosition + count)

proc readOffsetTable(fs: Stream, offset, count: SomeInteger): seq[uint64] =
  fs.setPosition(offset.int)
  for i in 0..<count:
    result.add(fs.readUint64)

proc readStrings(nx: var NxFile) =
  let string_offset = nx.header.string_offset
  let string_count = nx.header.string_count
  nx.string_offsets = nx.file.readOffsetTable(string_offset, string_count)

  if string_count > 0:
    nx.strings = nx.file.readStringNodes(nx)

proc readBitmaps(nx: var NxFile) =
  let bitmap_offset = nx.header.bitmap_offset
  let bitmap_count = nx.header.bitmap_count
  nx.bitmap_offsets = nx.file.readOffsetTable(bitmap_offset, bitmap_count)

  if bitmap_count > 0:
    nx.bitmaps = nx.file.readBitmapNodes(nx)

proc readAudios(nx: var NxFile) =
  let audio_offset = nx.header.audio_offset
  let audio_count = nx.header.audio_count
  nx.bitmap_offsets = nx.file.readOffsetTable(audio_offset, audio_count)

  nx.file.setPosFromOffset(nx.header.audio_offset)
  if audio_count > 0:
    let audio_nodes = nx.nodes.filterIt(it.kind == ntAudio)
    nx.audios = nx.file.readAudioNodes(nx, audio_nodes)

proc openNxFile*(path: string): NxFile =
  result.new
  
  result.length = path.getFileLength()

  when defined(useFileStreamOnly):
    let fs = path.newFileStream(fmRead)
  else:
    let fs = path.newMemMapFileStream(fmRead)
  result.file = fs

  result.header = fs.readHeader(result)

  # set to node block offset
  fs.setPosition(result.header.node_offset.int)

  let node_count = result.header.node_count
  result.nodes = fs.readNodes(result, node_count)

  if result.header.string_count > 0:
    result.readStrings()

  if result.header.bitmap_count > 0:
    result.readBitmaps()

  if result.header.audio_count > 0:
    result.readAudios()

  for i, string in result.strings:
    string.id = i.uint32
  for i, bitmap in result.bitmaps:
    bitmap.id = i.uint32
  for i, audio in result.audios:
    audio.id = i.uint32

  for node in result.nodes:
    var data = node.data
    let id = node.data_id
    case node.kind:
    of ntString:
      node.relative = result.strings[id]
    of ntBitmap:
      node.relative = result.bitmaps[id]
      result.bitmaps[id].width = data[4..5].u16
      result.bitmaps[id].height = data[6..7].u16
    of ntAudio:
      node.relative = result.audios[id]
    else: discard

    if node.children_count > 0:
      let last = node.first_child_id + node.children_count
      echo "node id: ", node.id, " name: ", node.getName
      node.children = result.nodes[node.first_child_id..<last]
      for child in node.children:
        child.parent = node
      for child in node.children:
        echo child.id, ", ", child.getName
      # assert node.children_count == node.children.len.uint, "wrong children count (" & $node.children_count & "|" & $node.children.len & ")"
