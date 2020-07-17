# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/[node, util, read, write, sugar]

when defined(exportClib):
  import nxlib/compat

import nimpng

proc dbg() =
  # [
  var nx = "./test.nx".newNxFile
  let i1 = nx.baseNode.addIntNode(0xCCCC)
  i1.setName("int1")
  let i2 = nx.baseNode.addIntNode(0xBBBB)
  i2.setName("int2")
  let i3 = nx.baseNode.addIntNode(0xAAAA)
  i3.setName("int3")
  let c1 = i3.addIntNode(0xDDDDDDDD'i64)
  c1.setName("int3-int")
  
  i3["name"] = 1
  i3 += "subdir"
  i3["vector2"] = (x: 2, y: 3)
  i3["vector"] = [1, 2]

  let images = nx.baseNode.addNoneNode("images")
  let png = "./80038746_p0.png".open(fmRead)
  let data = png.readAll
  echo data.len
  let image1 = images.addBitmapNode(data)
  image1.setName("g11")
  let bitmap = cast[NxBitmap](image1.relative)
  echo bitmap.length
  echo bitmap.image.len
  
  let musics = nx.baseNode.addNoneNode("musics")
  let wav = "./bang.wav".open(fmRead)
  let audio1 = musics.addAudioNode(wav.readAll)
  audio1.setName("bang")
  

  nx.save()
  # ]#
  # [
  let nx2 = openNxFile("./test.nx")
  echo nx2["int3"].id
  echo nx2["int3"]["int3-int"].id

  # let nnode = nx2["int3"]["nil"].create()
  echo nx2["int3"].name

  # ]#

when isMainModule: 
  echo "nx library has been loaded"
  # dbg()

export node, read, write, util, sugar

when defined(exportClib):
  export compat