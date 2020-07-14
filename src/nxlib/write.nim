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
  result = newNxNode(ntNone)
  let name_node = newNxNodeString(name, nx)
  result.id = nx.nodes.len.uint32
  result.name_id = name_node.id
  result.root = nx
  nx.nodes.add(result)

proc zeros(t: typedesc): seq[uint8] =
  for i in 0..<sizeof(t):
    result.add(0)

proc childCount(node: NxNode): uint32 =
  result = node.children.len.uint32
  for child in node.children:
    result.inc(child.childCount.int)

proc nodeCount*(nx: NxFile): uint32 =
  result = 0
  for root in nx.rootNodes:
    result.inc(root.childCount.int)

proc `*`(header: NxHeader): seq[uint8] =
  result = @[]
  for c in header.magic: result.add(c.uint8)
  # result.add(header.root.nodes.len.uint32.asbytes)
  result.add(header.root.nodeCount.asBytes)
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
  result.add(node.first_child_id.asBytes)
  result.add(node.children.len.uint16.asBytes)
  result.add(node.kind.ord.uint16.asBytes)
  for i in 0..<sizeof(node.data[]):
    result.add(node.data[i])

  for child in node.children:
    result.add(*child)

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
  echo last_pos, ", ", pos, ", ", fs.getPosition, ", ", data
  fs.setPosition(last_pos)

proc writeZeroFillMod(fs: FileStream, by: int) =
  if fs.isNil: return

  let pos = fs.getPosition

  if pos mod by != 0:
    let tail_count = by - pos mod by
    var data: seq[uint8] = @[]
    data.setLen(tail_count)
    for i in 0..<data.len:
      data[i] = 0
    fs.write(data)
  

proc save*(nx: NxFile) =
  nx.writer.write(*nx.header)

  var
    last_pos = nx.writer.getPosition

  nx.writer[HEADER_NODE_OFFSET_AT] = last_pos.uint64.asBytes

  # do write nodes

  assert nx.nodes.len > 0

  nx.writer.writeZeroFillMod(4)

  for node in nx.nodes:
    nx.writer.write(*node)

  last_pos = nx.writer.getPosition
  nx.writer[HEADER_STRING_OFFSET_AT] = if nx.strings.len > 0:
    last_pos.uint64.asBytes
  else:
    0.uint64.asBytes

  for i in nx.strings:
    nx.writer.write(uint64.zeros)

  for i, nxs in nx.strings:
    let current_pos = nx.writer.getPosition
    nx.writer[last_pos + (i * 8)] = current_pos.uint64.asBytes
    nx.writer.write(*nxs)

  nx.writer.writeZeroFillMod(8)
  
  # [
  last_pos = nx.writer.getPosition
  nx.writer[HEADER_BITMAP_OFFSET_AT] = if nx.bitmaps.len > 0:
    last_pos.uint64.asBytes
  else:
    0.uint64.asBytes
  
  for i in nx.bitmaps:
    nx.writer.write(uint64.zeros)

  for i, nxb in nx.bitmaps:
    let current_pos = nx.writer.getPosition
    nx.writer[last_pos + (i * 8)] = current_pos.uint64.asBytes
    nx.writer.write(*nxb)

  nx.writer.writeZeroFillMod(8)

  last_pos = nx.writer.getPosition
  nx.writer[HEADER_AUDIO_OFFSET_AT] = if nx.audios.len > 0:
    last_pos.uint64.asBytes
  else:
    0.uint64.asBytes
  
  for i in nx.audios:
    nx.writer.write(uint64.zeros)

  for i, nxa in nx.audios:
    let current_pos = nx.writer.getPosition
    nx.writer[last_pos + (i * 8)] = current_pos.uint64.asBytes
    nx.writer.write(*nxa)

  # ]#

  nx.writer.close()