import std/[files, macros, math, paths, sequtils, setutils, streams, strutils, tables]

import blas
import blocks
import gltf

const CCS_MAGIC: array[4, char] = ['C', 'C', 'S', 'F']
const HEADER_MAGIC = [0xCC.char, 0xCC.char]

type
  CcsCatType = enum cctNone, cctHeader, cctIndex, cctSetup, cctUnk1, cctStream
  CcsObjType = enum cotNone, cotObject, cotMaterial, cotTexture, cotClut, cotCamera, cotLight, cotAnime, cotModel, cotClump, cotExternal, cotHitmesh, cotBbox, cotParticle, cotEffect, cotUnk1, cotBlitgroup, cotFrameBufferPage, cotFrameBufferRect, cotDummypos, cotDummyposrot, cotUnk2, cotUnk3, cotLayer, cotShadow, cotMorpher, cotObject2, cotUnk4, cotPcm, cotUnk5=32, cotBinary=36, cotEnd=255

  MaybeCatType = distinct uint8
  MaybeObjType = distinct uint8

  CcsStructType {.packed.} = object
    category:   MaybeCatType#uint8#CcsSupType
    objectType: MaybeObjType#uint8#CcsSubType
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

proc readFile(filePath: string, fileIndex: int) =
  if not fileExists(filePath.Path): raise newException(ValueError, "Input file does not exist.")
  let stream = newFileStream(filePath, fmRead)
  defer: stream.close()

  var fileInfo: FileHeader
  discard stream.readData(fileInfo.addr, sizeof(fileInfo))
  assert fileInfo.magic == CCS_MAGIC, "Wrong magic at the start of file."
  echo fileInfo

  var table: FileTable
  discard stream.readData(table.addr, sizeof(table))
  echo table
  echo "------------"

  echo "Files:"
  for fileIndex in 0..<table.numFiles:
    var name: string = stream.readStr(32)
    # if ".max" notin $name and ".bmp" notin $name:
    # if "tow" in $name:
    echo "\t", $name
  echo "------------"

  echo "Objects:"
  var outputdata: OrderedTable[uint32, string]
  outputdata[1000] = ""
  for objIndex in 0..<table.numObjects:
    var objEntry: EntryInfo
    discard stream.readData(objEntry.addr, sizeof(objEntry))
    # if "MDL" in $objEntry.name or "DMY" in $objEntry.name:
    # if "DMY_" in $(objEntry.name) or "OBJ_" in $(objEntry.name)  or "MDL_" in $(objEntry.name) :
    # if "MAT_" notin $(objEntry.name) and "TEX_" notin $(objEntry.name) :
    echo "\t", objIndex, " ", objEntry
    outputdata[objIndex.uint32] = $objIndex & " " & $objEntry

  # discard readLine(stdin)
  # return
  var dataInfo: DataHeader
  discard stream.readData(dataInfo.addr, sizeof(dataInfo))
  # echo dataInfo
  # echo "---------------"

  # macro transf(ccsType: varargs[untyped]): untyped =
  #   result = quote do:
  # template declareTable()
  var dummiesCount, modelsCount, primitivesCount: int

  var models:    Table[uint32, Model]
  var materials: Table[uint32, Material]
  var textures:  Table[uint32, Texture]
  var cluts:     Table[uint32, Clut]
  var dummies:   Table[uint32, Dummy]
  var objects:   Table[uint32, Object]
  var clumps:    Table[uint32, Clump]
  var animes:    Table[uint32, Anime]

  var i = 1
  while not stream.atEnd():
    # echo stream.getPosition().toHex()
    var header: EntryHeader
    discard stream.readData(header.addr, sizeof(header))
    if header.`type`.magic != [0xCC.char, 0xCC.char]: raise newException(ValueError, "Wrong header magic.")# & $prevObjectType)
    # echo header

    var size: int = header.size.int*sizeof(uint32)
    var iid: uint32
    # echo header.`type`.objectType.CcsObjType
    case header.`type`.objectType.CcsObjType: # Textures and models have incorrect object size in their header
      of cotTexture:
        var texture: Texture = stream.readTexture()
        textures[texture.id] = texture
        iid = texture.id
        # echo "id::tex:", texture.id
      of cotModel:
        var model: Model = stream.readModel()
        # echo model.header
        models[model.header.id] = model
        # echo "id::mdl:", model.header.id
        # echo model.header.numPrimitives
        # echo model.header.drawFlags
        # echo model.header.unk1
        # echo model.header.gifData
        iid = model.header.id
        modelsCount += 1
        primitivesCount += model.header.numPrimitives.int
      of cotMaterial:
        var material: Material
        discard stream.readData(material.addr, size)
        materials[material.id] = material
        iid = material.id
        # echo "id::mat:", material.id
      of cotClut:
        var clut: Clut = stream.readClut()
        cluts[clut.id] = clut
        iid = clut.id
        # echo "Clut: id-", clut.id.toHex, " blitgroup-", clut.blitGroup.toHex, " unk1-", clut.unk1, " unk2-", clut.unk2.toHex
      of cotDummypos:
        # echo stream.getPosition().toHex()
        var dummy: Dummy = stream.readDummy(withRotation=false)
        # echo dummy
        dummies[dummy.id] = dummy
        dummiesCount += 1
        iid = dummy.id
        # echo "id::dmy:", dummy.id
        # echo "Dummy: id-", dummy.id.toHex
      of cotDummyposrot:
        var dummy: Dummy = stream.readDummy(withRotation=true)
        # echo dummy
        dummies[dummy.id] = dummy
        dummiesCount += 1
        iid = dummy.id
        # echo "id::dmy:", dummy.id
      of cotAnime:
        var anime: Anime = stream.readAnime()
        animes[anime.id] = anime
        # echo "id::anm:", anime.id
        # echo anime.id, " ", anime.frameCount, " ", anime.size
        iid = anime.id
        # echo anime
        # if anime.id == 49:
        #   echo anime

      of cotObject:
        var obj: Object
        discard stream.readData(obj.addr, size)
        # echo obj
        objects[obj.id] = obj
        iid = obj.id
        # echo "id::obj:", obj.id
      of cotClump:
        var clump: Clump = stream.readClump()
        # echo "id::clp:", clump.id
        # echo clump
        clumps[clump.id] = clump
        iid = clump.id
        # echo clump
      of cotBlitgroup:
        var data: string = stream.readStr(size)
        iid = 1000
        # echo data.toHex
      of cotExternal:
        var external: External = stream.readExternal()
        iid = 1000
        # echo external
        # echo "ext: ", data.toHex
      of cotUnk5:
        var unk5: Unk5 = stream.readUnk5()
        iid = 1000
        # echo unk5
        # echo "unk5: ", data.toHex
      of cotMorpher:
        iid = stream.readuint32()
        discard stream.readuint32()
      of cotBinary:
        iid = 1000
        var data: string = stream.readStr(size)

      else:
        # echo header.`type`.objectType, " ", size#.CcsObjType
        # echo stream.getPosition().toHex()
        # echo header.`type`.objectType
        # echo size
        iid = 1000
        var data: string = stream.readStr(size)
        # if data.len < 100:
        #   for c in data:
        #     echo c.uint8
        # echo data[0..min(data.len-1,100)]
    outputdata[iid] = outputdata[iid] & "\t" & $(header.`type`.objectType) & "\t" & $iid
    i += 1

  # echo dummiesCount, " ", modelsCount, " ", primitivesCount
  var context: Context = createScene()
  # echo dummies.keys().toSeq()
  # echo objects.keys().toSeq()
  # echo models.keys().toSeq()
  # echo dummies.len()
  var p: int = 0
  var pris: seq[int]
  for i, m in models.mpairs:
    if m.kind == mkRigid:
      p += m.rigidPrimitives.len()
      for pri in m.rigidPrimitives:
        pris.add pri.parentId.int
  # echo p
  # echo objects.len()
  # echo models.len()
  # echo pris
  # for i, d in dummies.mpairs:
  #   echo d

  # for i, c in clumps.mpairs:
  #   echo c

  for id, material in materials.mpairs:
    if material.textureId in textures:
      var texture: Texture = textures[material.textureId]
      if texture.clutId in cluts:
        context.createMaterial(material, texture, cluts[texture.clutId].palette)

  # for id, dummy in dummies.mpairs:
  #   echo id
  #   echo id+1 in objects

  # echo "----------"
  # for anid, anim in animes.mpairs:
  #   for objTransform in anim.objectControllers:
  #     echo objTransform.header.objectId
  #     echo objTransform.header.objectId+1 in objects
  #     var children: int = 0
  #     for oid, o in objects.mpairs:
  #       if o.parentId == objTransform.header.objectId+1:
  #         children += 1
  #     echo children
  #     echo "--"
  # echo "----------"


  # TODO: Objects -> Models, Dummies for position, rotation, then add scale from model
  for objId, obj in objects.mpairs:
    if obj.modelId notin models:
      continue
      raise newException(ValueError, "Missing model.")
    # if objId notin dummies: raise newException(ValueError, "Missing dummy for model.")
    var model: Model = models[obj.modelId]
    # var dummy: Dummy = dummies[objId]
    if model.kind == mkRigid:
      var found: bool = false
      for anid, anim in animes.mpairs:
        for objTransform in anim.objectControllers:
          if objTransform.header.objectId+1 == objId or objTransform.header.objectId+1 == obj.parentId:
            var translation: Vec3 = if objTransform.positionTrack.keyframes.len > 0: objTransform.positionTrack.keyframes[0].value
            else: [0'f32, 0, 0].Vec3
            var rotation: Vec3 = if objTransform.rotationTrack.keyframes.len > 0: objTransform.rotationTrack.keyframes[0].value
            else: [0'f32, 0, 0].Vec3
            var scale: Vec3 = if objTransform.scaleTrack.keyframes.len > 0: objTransform.scaleTrack.keyframes[0].value
            else: [1'f32, 1, 1].Vec3

            # echo translation
            # echo rotation
            # echo scale
            context.createNode(model, translation, rotation, scale)#, dummy)
            found = true
            # echo "found"
            break
      if not found:
        # echo objId, " ", obj.modelId
        context.createNode(model)#, dummy)

  # for id, model in models.mpairs:
  #   if model.kind == mkRigid:
      # break
  # for oi, op in outputdata.mpairs:
  #   echo op
  context.writeToFile(("data/" & $fileIndex & ".glb").Path)

var errors: int = 0
var broken = [1031, 1032, 1039, 1143, 1145]
var investigate = [1235, 1240, 1245, 1250, 1255, 1260, 1275, 1282, 1289, 1296, 1303, 1312, 1393] # tow in name
var towns  = 1213..1224
var moretowninfo = 922..962
var single: seq[int] = @[1000]
for i in 0..<1447:
  echo i
# for i in single:
  let filePath  = "data/infection/unpacked/" & $i
  if not fileExists(filePath.Path): continue
  try:
    readFile(filePath, i)
  except ValueError as e:
    echo "ValueError in ", i, ": ", e.msg
    errors += 1
echo errors

