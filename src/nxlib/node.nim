import streams, memfiles
import util

type
  OffsetTable = seq[uint64]
  NxType* = enum
    ntNone = 0,
    ntInt = 1,
    ntReal = 2,
    ntString = 3,
    ntVector = 4,
    ntBitmap = 5,
    ntAudio = 6,
  NxBaseObj = ref object of RootObj
    root*: ptr NxFile
  NxNode* = ref object of NxBaseObj
    name_id*: uint32
    first_id*: uint32
    children_count*: uint16
    kind*: NxType
    data*: DataBuffer # Any
  NxString* = ref object of NxBaseObj
    length*: uint16
    data*: seq[uint8]
  NxBitmap* = ref object of NxBaseObj
    length*: uint32
    data*: seq[uint8]
  NxAudio* = ref object of NxBaseObj
    data*: seq[uint8]
  NxHeader* = ref object of NxBaseObj
    magic*: string
    node_count*: uint32
    node_offset*: ptr NxNode
    string_count*: uint32
    string_offset*: ptr OffsetTable
    bitmap_count*: uint32
    bitmap_offset*: ptr OffsetTable
    audio_count*: uint32
    audio_offset*: ptr OffsetTable
  NxFile* = ref object of RootObj
    header*: NxHeader
    file*: MemMapFileStream
    nodes*: seq[NxNode]

proc toNxType*(i: uint16): NxType =
  case i:
  of 1: ntInt
  of 2: ntReal
  of 3: ntString
  of 4: ntVector
  of 5: ntBitmap
  of 6: ntAudio
  else: ntNone