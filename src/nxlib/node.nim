import memfiles
import util

const NODE_OFFSET* = 52

type
  OffsetTable* = seq[uint64]
  NxBitmapSize* = tuple
    x: uint16
    y: uint16
  NxType* = enum
    ntNone = 0,
    ntInt = 1,
    ntReal = 2,
    ntString = 3,
    ntVector = 4,
    ntBitmap = 5,
    ntAudio = 6,
  NxBaseObj* = ref object of RootObj
    root*: NxFile
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
    node_offset*: uint64 # ptr NxNode
    string_count*: uint32
    string_offset*: uint64 # ptr OffsetTable
    bitmap_count*: uint32
    bitmap_offset*: uint64 # ptr OffsetTable
    audio_count*: uint32
    audio_offset*: uint64 # ptr OffsetTable
  NxFile* = ref object of RootObj
    length*: int64
    header*: NxHeader
    file*: MemMapFileStream
    nodes*: seq[NxNode]
    strings*: seq[NxString]
    string_offsets*: OffsetTable
    bitmaps*: seq[NxBitmap]
    bitmap_offsets*: OffsetTable
    audios*: seq[NxAudio]
    audio_offsets*: OffsetTable

proc toNxType*(i: uint16): NxType =
  case i:
  of 1: ntInt
  of 2: ntReal
  of 3: ntString
  of 4: ntVector
  of 5: ntBitmap
  of 6: ntAudio
  else: ntNone