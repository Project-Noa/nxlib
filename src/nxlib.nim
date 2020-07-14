# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/node, nxlib/util, nxlib/read, nxlib/write

import nimpng, nimlz4
proc dbg() =
  # [
  var nx = "./test.nx".newNxFile
  let base = nx << "" # base node
  
  let character = newNxNone()
  base["Character"] = character

  let skin0 = newNxNone()
  character["0002000.img"] = skin0

  let child = newNxInt(45)
  base["child"] = child

  let nxf = newNxReal(416.11)
  base["float"] = nxf

  let nxs = newNxNodeString("nine", nx)
  base["family"] = nxs

  let nxv = newNxVector(40, 404)
  base["vector"] = nxv

  let png = "./80038746_p0.png".open(fmRead)
  let nxb = nx.newNxNodeBitmap(png.readAll)
  base["bitmap"] = nxb

  let wav = "./bang.wav".open(fmRead)
  let nxa = nx.newNxNodeAudio(wav.readAll)
  base["audio"] = nxa

  nx.save()
  # ]#
  #[
  let nx2 = openNxFile("./Map.nx")
  for nxs in nx2.strings:
    echo nxs.toString
  for nxb in nx2.bitmaps:
    nxb.decode()
    echo nxb.png.width, ", ", nxb.png.height
  for root in nx2.rootNodes:
    for node in root.children:
      echo node.id

  # ]#

when isMainModule: dbg()

export node, read, write, util