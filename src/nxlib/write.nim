import streams
import node, util

const
  HEADER_NODE_OFFSET_AT = 0x08
  HEADER_STRING_OFFSET_AT = 0x14
  HEADER_BITMAP_OFFSET_AT = 0x20
  HEADER_AUDIO_OFFSET_AT = 0x2C
  HEADER_SIZE = 52

# add named node
proc `<<`*(nx: NxFile, name: string): NxNode =
  result.new
  nx.nodes.add(result)
  nx.strings.add(name.newNxString)
  result.name_id = nx.strings.len.uint32
  result.data = array[8, uint8].create
  result.root = nx

proc zeros(t: typedesc): seq[uint8] =
  for i in 0..<sizeof(t):
    result.add(0)

proc `*`(header: NxHeader): seq[uint8] =
  result = @[]
  for c in header.magic: result.add(c.uint8)
  result.add(header.root.nodes.len.uint32.asbytes)
  result.add(uint64.zeros)
  result.add(header.root.strings.len.uint32.asbytes)
  result.add(uint64.zeros)
  result.add(header.root.bitmaps.len.uint32.asbytes)
  result.add(uint64.zeros)
  result.add(header.root.audios.len.uint32.asbytes)
  result.add(uint64.zeros)

  assert result.len == HEADER_SIZE

proc `*`(node: NxNode): seq[uint8] =
  result.add(node.name_id.asBytes)
  result.add(node.first_id.asBytes)
  result.add(node.children_count.asBytes)
  result.add(node.kind.ord.uint16.asBytes)
  for i in 0..<sizeof(node.data[]):
    result.add(node.data[i])

proc `*`(string: NxString): seq[uint8] =
  result.add(string.length.asBytes)
  result.add(string.data)

proc `*`(bitmap: NxBitmap): seq[uint8] =
  result.add(bitmap.length.asBytes)
  result.add(bitmap.data)

proc `*`(audio: NxAudio): seq[uint8] =
  result.add(audio.data)

proc write(fs: FileStream, data: seq[uint8]) =
  for b in data:
    fs.write(b)

proc `[]=`(fs: FileStream, pos: int, data: seq[uint8]) =
  let last_pos = fs.getPosition
  fs.setPosition(pos)
  fs.write(data)
  # echo last_pos, ", ", pos, ", ", fs.getPosition, ", ", data
  fs.setPosition(last_pos)

proc writeZeroFillMod8(nx: NxFile) =
  if nx.writer.isNil: return

  let pos = nx.writer.getPosition

  if pos mod 8 != 0:
    let tail_count = 8 - pos mod 8
    var data: seq[uint8] = @[]
    data.setLen(tail_count)
    for i in 0..<data.len:
      data[i] = 0
    nx.writer.write(data)
  

proc save*(nx: NxFile) =
  nx.writer.write(*nx.header)

  var
    last_pos = nx.writer.getPosition

  nx.writer[HEADER_NODE_OFFSET_AT] = last_pos.uint64.asBytes

  # do write nodes

  assert nx.nodes.len > 0

  for node in nx.nodes:
    nx.writer.write(*node)

  nx.writeZeroFillMod8()

  last_pos = nx.writer.getPosition
  nx.writer[HEADER_STRING_OFFSET_AT] = if nx.strings.len > 0:
    last_pos.uint64.asBytes
  else:
    0.uint64.asBytes

  for i in nx.strings:
    nx.writer.write(uint64.zeros)

  # [
  for nxs in nx.strings:
    let pos = nx.writer.getPosition
    let o = pos - last_pos
    nx.writer[pos - o] = pos.uint64.asBytes
    nx.writer.write(*nxs)

  nx.writeZeroFillMod8()

  last_pos = nx.writer.getPosition
  nx.writer[HEADER_BITMAP_OFFSET_AT] = if nx.bitmaps.len > 0:
    last_pos.uint64.asBytes
  else:
    0.uint64.asBytes
  
  for i in nx.bitmaps:
    nx.writer.write(uint64.zeros)

  for nxb in nx.bitmaps:
    let pos = nx.writer.getPosition
    let o = pos - last_pos
    nx.writer[pos - o] = pos.uint64.asBytes
    nx.writer.write(*nxb)
  
  nx.writeZeroFillMod8()

  last_pos = nx.writer.getPosition
  nx.writer[HEADER_AUDIO_OFFSET_AT] = if nx.audios.len > 0:
    last_pos.uint64.asBytes
  else:
    0.uint64.asBytes
  
  for i in nx.audios:
    nx.writer.write(uint64.zeros)

  for nxa in nx.audios:
    let pos = nx.writer.getPosition
    let o = pos - last_pos
    nx.writer[pos - o] = pos.uint64.asBytes
    nx.writer.write(*nxa)

  # ]#

  nx.writer.close()