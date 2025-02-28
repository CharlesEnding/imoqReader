import std/[files, macros, math, paths, sequtils, setutils, streams, strutils]

import blocks

const CCS_MAGIC: array[4, char] = ['C', 'C', 'S', 'F']
const HEADER_MAGIC = [0xCC.char, 0xCC.char]

type
  CcsCatType = enum cctNone, cctHeader, cctIndex, cctSetup, cctUnk1, cctStream
  CcsObjType = enum cotNone, cotObject, cotMaterial, cotTexture, cotClut, cotCamera, cotLight, cotAnime, cotModel, cotClump, cotExternal, cotHitmesh, cotBbox, cotParticle, cotEffect, cotUnk1, cotBltgroup, cotFbpage, cotFbrect, cotDummypos, cotDummyposrot, cotUnk2, cotUnk3, cotLayer, cotShadow, cotMorpher, cotObject2, cotUnk4, cotPcm, cotEnd=255

  MaybeCatType = distinct uint8
  MaybeObjType = distinct uint8

  CcsStructType {.packed.} = object
    category:   MaybeCatType
    objectType: MaybeObjType
    magic: array[2, char]

  FileHeader {.packed.} = object
    `type`:   CcsStructType
    size:     uint32
    magic:    array[4, char]
    fileName: array[32, char]
    version:  uint32
    unk:      array[12, uint8]

  FileTable {.packed.} = object
    `type`:   CcsStructType
    size, numFiles, numObjects: uint32

  EntryInfo {.packed.} = object
    name: array[30, char]
    id:   uint16

  DataHeader {.packed.} = object
    `type`, size: uint32

  EntryHeader {.packed.} = object
    `type`: CcsStructType
    size:   uint32 # Size is not valid for textures apparently.

macro enumElementsAsSet(enm: typed): untyped = result = newNimNode(nnkCurly).add(enm.getType[1][1..^1])
const CCS_CAT_TYPES = enumElementsAsSet(CcsCatType)
const CCS_OBJ_TYPES = enumElementsAsSet(CcsObjType)

proc `$`[N: static[int]](b: array[N, char]): string = result = if b == HEADER_MAGIC: "0xCCCC" else: "\"" & b.mapIt($it).join() & "\""
proc `$`(t: MaybeCatType): string = result = if t.CcsCatType in CCS_CAT_TYPES: $CcsCatType(t) else: "UnknownCatType" & $t.int
proc `$`(t: MaybeObjType): string = result = if t.CcsObjType in CCS_OBJ_TYPES: $CcsObjType(t) else: "UnknownObjType" & $t.int

proc readFile(filePath: string) =
  if not fileExists(filePath.Path): raise newException(ValueError, "Input file does not exist.")
  let stream = newFileStream(filePath, fmRead)
  defer: stream.close()

  var fileInfo: FileHeader
  discard stream.readData(fileInfo.addr, sizeof(fileInfo))
  assert fileInfo.magic == CCS_MAGIC, "Wrong magic at the start of file."

  var table: FileTable
  discard stream.readData(table.addr, sizeof(table))

  for fileIndex in 0..<table.numFiles:
    var name: string = stream.readStr(32)

  for objIndex in 0..<table.numObjects:
    var objEntry: EntryInfo
    discard stream.readData(objEntry.addr, sizeof(objEntry))

  var dataInfo: DataHeader
  discard stream.readData(dataInfo.addr, sizeof(dataInfo))

  var prevObjectType: CcsObjType = cotNone
  var prevHeader: EntryHeader
  while not stream.atEnd():
    var header: EntryHeader
    discard stream.readData(header.addr, sizeof(header))

    if header.`type`.magic != [0xCC.char, 0xCC.char]:
      raise newException(ValueError, "Wrong header magic." & $prevObjectType)
    prevObjectType = header.`type`.objectType.CcsObjType
    prevHeader = header

    var size: int = header.size.int*sizeof(uint32)
    case header.`type`.objectType.CcsObjType: # Textures and models have incorrect object size in their header
      of cotTexture:
        discard stream.readTexture()
      of cotModel:
        discard stream.readModel()
      else: discard stream.readStr(size)

var errors: int = 0
var broken = [1031, 1032, 1039, 1143, 1145]
for i in 0..<1447:
  let filePath  = "data/infection/unpacked/" & $i
  if not fileExists(filePath.Path): continue

  try:
    readFile(filePath)
  except ValueError as e:
    echo "ValueError in ", i, ": ", e.msg
    errors += 1
echo errors, " errors."

