# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/node, nxlib/util, nxlib/read, nxlib/write

proc dbg() =
  var nx = "./test.nx".newNxFile
  let node = nx << "something"
  node <> 7777.int64

  let child = nx << "some2"
  var png = "./80038746_p0.png".open(fmRead)
  child <> (ntBitmap, png.readAll)

  nx.save()

  # [
  let nxf = openNxFile("./test.nx")
  echo nxf.header.node_offset
  echo nxf.header.node_count
  echo nxf.header.string_offset
  echo nxf.header.string_count
  echo nxf.header.bitmap_offset
  echo nxf.header.bitmap_count
  echo nxf.header.audio_offset
  echo nxf.header.audio_count
  # ]#

when isMainModule: dbg()

export node, read, write, util