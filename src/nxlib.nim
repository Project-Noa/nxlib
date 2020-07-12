# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/node, nxlib/util
import streams, times, sequtils
from memfiles import newMemMapFileStream, MemMapFileStream

var f = open("./out.log", fmWrite)

proc readHeader(fs: MemMapFileStream): NxHeader =
  result.new
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

proc readNode(fs: MemMapFileStream): NxNode =
  result.new
  result.name_id = fs.readUint32
  result.first_id = fs.readUint32
  result.children_count = fs.readUint16
  result.kind = fs.readUint16.toNxType
  # if result.kind != ntNone:
  result.data = array[8, uint8].create()
  discard fs.readData(result.data, 8)

proc readNodes(fs: MemMapFileStream, count: SomeInteger): seq[NxNode] =
  for i in 0..<count:
    result.add(fs.readNode())

proc readString(fs: MemMapFileStream, length: uint16): NxString =
  result.new
  result.length = length
  result.data = @[]
  var buf = array[uint16.high, uint8].create()
  discard fs.readData(buf, length.int)
  for byte in buf[]:
    if byte == 0: break
    result.data.add(byte)

proc toString*(node: NxString): string =
  result = node.data.toString

proc readStringNodes(fs: MemMapFileStream, count: SomeInteger): seq[NxString] =
  for i in 0..<count:
    var length = fs.readUint16
    if length mod 2 == 1: length.inc(1)
    if length > 0:
      let node = fs.readString(length)
      result.add(node)
      # echo fs.getPosition, ": ", node.toString

proc readBitmap(fs: MemMapFileStream, length: uint32): NxBitmap =
  result.new
  result.length = length
  result.data = @[]
  var buf = array[uint32.high, uint8].create()
  discard fs.readData(buf, length.int)
  for byte in buf[]:
    if byte == 0: break
    result.data.add(byte)

proc readBitmapNodes(fs: MemMapFileStream, count: SomeInteger): seq[NxBitmap] =
  for i in 0..<count:
    let length = fs.readUint32
    if length > 0:
      result.add(fs.readBitmap(length))

proc readAudio(fs: MemMapFileStream, length: uint32): NxAudio =
  result.new
  result.data = @[]
  var buf = array[uint32.high, uint8].create()
  discard fs.readData(buf, length.int)
  for byte in buf[]:
    if byte == 0: break
    result.data.add(byte)

proc readAudioNodes(fs: MemMapFileStream, audio_nodes: seq[NxNode]): seq[NxAudio] =
  for node in audio_nodes:
    # let id = node.data.u32
    var c = node.data[4..7]
    let length = c.u32
    result.add(fs.readAudio(length))

proc setPosFromOffset(fs: MemMapFileStream, offset: uint64) =
  fs.setPosition(offset.int)
  fs.setPosition(fs.readUint64.int)

proc skip(fs: MemMapFileStream, count: SomeUnsignedInt) =
  fs.setPosition(fs.getPosition + count)

proc readOffsetTable(fs: MemMapFileStream, offset: int, count: SomeInteger): seq[uint64] =
  fs.setPosition(offset)
  for i in 0..<count:
    result.add(fs.readUint64)

proc openNxFile*(path: string, fm: FileMode = fmRead): NxFile =
  result.new
  
  result.length = path.getFileLength()

  let fs = path.newMemMapFileStream(fm)
  result.file = fs

  result.header = fs.readHeader

  # set to node block offset
  fs.setPosition(result.header.node_offset.int)

  let node_count = result.header.node_count
  result.nodes = fs.readNodes(node_count)

  # set to string table offset
  let string_offset = result.header.string_offset

  if string_offset > NODE_OFFSET:
    let string_count = result.header.string_count
    result.string_offsets = fs.readOffsetTable(string_offset.int, string_count)

    fs.setPosFromOffset(string_offset)

    if string_count > 0:
      result.strings = fs.readStringNodes(string_count)
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
      result.bitmaps = fs.readBitmapNodes(bitmap_count)
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
      result.audios = fs.readAudioNodes(audio_nodes)


  echo "done"

proc `[]`(nx: NxFile, name, default: string  = ""): NxNode =
  var id = 0


when isMainModule:
  let bef = cpuTime()
  let nx = openNxFile("./Character.nx")
  echo "parse elapsed: ", cpuTime() - bef, " seconds."

  for string in nx.nodes.filterIt(it.kind == ntString):
    let nxs = nx.strings[string.name_id]
    f.writeLine(nxs.toString)