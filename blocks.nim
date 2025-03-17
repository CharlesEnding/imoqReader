import std/[macros, math, sequtils, streams, strutils]

import blas

type
  Normal* {.packed.} = object
    value*: Vec3B
    flags*: uint8

  DeformableVertex* {.packed.} = object
    value*: Vec3H
    joint: uint16

  Clump* {.packed.} = object
    id*, numNodeIds*: uint32
    nodeIds*: seq[uint32]

  Color* {.packed.} = object
    r*, b*, g*, a*: uint8

  Clut* {.packed.} = object
    id*, blitGroup*, unk1*, unk2*, numColors*: uint32
    palette*: seq[Color]

  Dummy* {.packed.} = object
    id*: uint32
    position*, rotation*: Vec3

  External* {.packed.} = object
    animId, unkFlags, targetObjectId: uint32

  Unk5* {.packed.} = object
    animId, unk1, targetMorpherId, unk2, unk3: uint32

  HitGroup {.packed.} = object
    numVertices: uint64
    color: Color
    vertices: seq[Vec3]

  HitMesh {.packed.} = object
    id, unk1, hitGroupCount, numHitgroups: uint32
    hitGroups: seq[HitGroup]

  Material* {.packed.} = object
    id*, textureId*: uint32
    alpha: float32
    textureOffset: UV

  MorphTargetPrimitive* = object
    parentId, matTexId, numVertices: uint32
    vertices*: seq[Vec3H]
    normals*:  seq[Normal]

  DeformRigidPrimitive* = object
    matTexId, numVertices, unk1, parentId: uint32
    vertices*: seq[Vec3H]
    normals*:  seq[Normal]
    texCoords*: seq[UV]

  DeformablePrimitive* = object
    matTexId, numVertices, numVerticesActual: uint32
    vertices*: seq[DeformableVertex]
    normals*:  seq[Normal]
    texCoords*: seq[UV]

  RigidPrimitive* = object
    parentId*, matTexId*, numVertices: uint32
    vertices*: seq[Vec3H]
    normals*:  seq[Normal]
    colors:    seq[Color]
    texCoords*: seq[UV]

  ShadowPrimitive = object
    numVertices, numIndices: uint32
    vertices: seq[Vec3H]
    indices: seq[uint32]

  # I suspect those are actually two types, hierarchical. Probably corresponding to the presence of specific components in the model.
  # If figured out they'll simplify greatly the model reading code but I'm too lazy.
  ModelKind = distinct uint16
  KnownModelKind* = enum mkRigid = 0x0, mkDeformable = 0x4, mkShadow = 0x8, mkMorphTarget = 0x600

  ModelHeader* {.packed.} = object
    id*: uint32
    vertexScale*: float32
    `type`: ModelKind
    numPrimitives*, drawFlags*, unk1*: uint16
    gifData*: array[4, uint8]

  Model* = object
    header*: ModelHeader
    case kind*: KnownModelKind
    of mkDeformable:
      deformableRigidPrimitives*: seq[DeformRigidPrimitive]
      deformablePrimitive*: DeformablePrimitive
    of mkMorphTarget:
      morphTargetPrimitives*: seq[MorphTargetPrimitive]
    of mkRigid:
      rigidPrimitives*:  seq[RigidPrimitive]
    of mkShadow:
      shadowPrimitives*: seq[ShadowPrimitive]

  Object* {.packed.} = object
    id*, parentId*, modelId*, shadowId: uint32

  KnownTextureType = enum ttRGBA = 0x0, ttI8   = 0x13, ttI4   = 0x14
  TextureType* = distinct uint8

  MipTexture* {.packed.} = object
    unk0, numData: uint32
    data: seq[uint32]

  Texture* {.packed.} = object
    id*, clutId*, blitGroupId: uint32
    flags, `type`*: uint8
    mipCount, unk1*, widthLog2*, heightLog2*: uint8
    unk2*: uint16
    unk3, textureDataSize*: uint32
    data*: seq[uint8]
    mips: seq[MipTexture]

  AnimePrimitiveCategory = enum apcNone = 0, apcKeyframe = 0x01, apcController1 = 0x02, apcController2 = 0x03, apcController3 = 0x09
  AnimePrimitiveObject   = enum apoNone = 0, apoObject = 0x01, apoMaterial = 0x02, apoLight = 0x06, apoMorph = 0x19, apoEnd = 0xFF
  AnimeControllerKind    = enum ackNone = 0, ackFixed = 1, ackAnimated = 2

  AnimePrimitiveHeader {.packed.} = object
    catType, objType: uint8
    magic: uint16
    size: uint32

  # ApFrame {.packed.} = object
  #   header: AnimePrimitiveHeader
  #   frameNumber: uint32
  AnimeControllerTrackKind = enum actkFixed = 1, actkAnimated = 2
  AnimeControllerParameter = object # parameters are uint32 with 3 bits per track denoting its type, up to 10 tracks
    numTracks: int                  # we store them as objects instead
    trackKinds: seq[uint32]
    # trackKinds: seq[AnimeControllerTrackKind]

  AnimeControllerHeader {.packed.} = object
    objectId*: uint32
    parameters: AnimeControllerParameter

  # ApFrameVec3 {.packed.} = object
  #   id: uint32
  #   value: Vec3
  # ApFrameFloat {.packed.} = object
  #   id: uint32
  #   value: float32

  # ApTrackVec3 {.packed.} = object
  #   numKeyframes: uint32
  #   keyframes: seq[ApFrameVec3]
  # ApTrackFloat {.packed.} = object
  #   numKeyframes: uint32
  #   keyframes: seq[ApFrameFloat]

  ApFrame[T] = object
    id: uint32
    value*: T

  ApTrack[T] = object
    numKeyframes: uint32
    keyframes*: seq[ApFrame[T]]

  ApObjectController {.packed.} = object
    header*: AnimeControllerHeader
    positionTrack*, rotationTrack*, scaleTrack*: ApTrack[Vec3]
    alphaTrack: ApTrack[float32]

  # ApMaterialController {.packed.} = object
  #   header: AnimeControllerHeader
  #   uOffsetTrack, vOffsetTrack, unkFTrack,unk2FTrack: ApTrack[Vec3]

  # ApLightDireController {.packed.} = object
  #   header: AnimeControllerHeader
  #   directionTrack, colorTrack, unkTrack: ApTrack[Vec3]

  # ApLightOmniController {.packed.} = object
  #   header: AnimeControllerHeader
  #   positionTrack, colorTrack, unkF32Track1, unkF34Track2, unkF32Track3: ApTrack[Vec3]

  # Better architecture (maybe):
  # Controller has header and tracks
  # Track is a variant object (not generic or they can't all belong to one list)
  # When reading controller associate trackKinds to trackType so that each
  # is read with the right type for the type of controller
  # Not sure.

  ApLightAmbientKeyframe {.packed.} = object
    header: AnimePrimitiveHeader

  ApLightMorphKeyframe {.packed.} = object
    header: AnimePrimitiveHeader

  Anime* {.packed.} = object
    id*, frameCount*, size*: uint32
    data: seq[uint8]
    objectControllers*: seq[ApObjectController]

macro enumElementsAsSet(enm: typed): untyped = result = newNimNode(nnkCurly).add(enm.getType[1][1..^1])
const KNOWN_TEXTURE_TYPES = enumElementsAsSet(KnownTextureType)
const KNOWN_MODEL_KINDS   = enumElementsAsSet(KnownModelKind)
proc `$`(t: TextureType): string = result = if t.KnownTextureType in KNOWN_TEXTURE_TYPES: $KnownTextureType(t) else: "UnknownTexType" & $t.int

proc readSeq[T](s: Stream, numItems: int, t: typedesc[T], discardPadding: bool = false): seq[T] =
  if numItems == 0: raise newException(ValueError, "0 number of items.")
  result.setLen(numItems)
  discard s.readData(result[0].addr, numItems * sizeof(t))
  if discardPadding and s.getPosition() mod 4 == 2: discard s.readInt16()

proc readDummy*(s: Stream, withRotation: bool = false): Dummy =
  if withRotation: discard s.readData(result.addr, sizeof(result))
  else:            discard s.readData(result.addr, sizeof(result)-sizeof(result.rotation))


createReaders(MipTexture, Color, Vec3, Vec4, Vec3B, Vec3H, UV, DeformableVertex, Normal, HitGroup, HitMesh, Clump, ShadowPrimitive, External, Unk5)
createReader(Texture, result.textureDataSize*4, result.mipCount.int)
createReader(Clut, result.numColors)
createReader(MorphTargetPrimitive, result.numVertices, result.numVertices)
createReader(RigidPrimitive,       result.numVertices, result.numVertices, result.numVertices, result.numVertices)
createReader(DeformRigidPrimitive, result.numVertices, result.numVertices, result.numVertices)
createReader(DeformablePrimitive,  result.numVerticesActual, result.numVerticesActual, result.numVertices)

# createReader(Anime, result.size*4)

proc readAnimeControllerParameter*(s: Stream): AnimeControllerParameter =
  var data = s.readuint32()
  # echo data.int.toBin(32)
  # echo data.toHex(), " ", log2(data.float), " ", log2(data.float) / 3, " "
  var numTracks: int = if data > 0: floor(log2(data.float) / 3.0 + 1).int else: 0# 3 bits per track
  # echo numTracks
  var trackKinds: seq[uint32] = newSeq[uint32](0)
  for ti in 0..<numTracks:
    trackKinds.add ((data shr (ti * 3)) and 0b111)#.AnimeControllerTrackKind
  return AnimeControllerParameter(numTracks: numTracks, trackKinds: trackKinds)

createReaders(AnimeControllerHeader)

proc readApFrame[T](s: Stream): ApFrame[T] =
  result.id = s.readuint32()
  when T is Vec3:    result.value = s.readVec3()
  elif T is Vec4:    result.value = s.readVec4()
  elif T is float32: result.value = s.readfloat32()

proc readApTrack[T](s: Stream, kind: uint32): ApTrack[T] =
  if kind == 2:
    result.numKeyframes = s.readuint32()
    for i in 0..<result.numKeyframes:
      result.keyframes.add readApFrame[T](s)
  elif kind == 1:
    result.numKeyframes = 1
    when T is Vec3:    result.keyframes = @[ApFrame[Vec3](id: 0, value: s.readVec3)]
    elif T is Vec4:    result.keyframes = @[ApFrame[Vec4](id: 0, value: s.readVec4)]
    elif T is float32: result.keyframes = @[ApFrame[float32](id: 0, value: s.readfloat32)]

proc readApObjectController(s: Stream, trackKinds: var seq[uint32]): ApObjectController =
  while trackKinds.len < 4: trackKinds.add 0.uint32
  result.positionTrack = readApTrack[Vec3](s,    trackKinds[0])
  result.rotationTrack = readApTrack[Vec3](s,    trackKinds[1])
  result.scaleTrack    = readApTrack[Vec3](s,    trackKinds[2])
  result.alphaTrack    = readApTrack[float32](s, trackKinds[3])

proc readAnime*(s: Stream): Anime =
  discard s.readData(result.id.addr,         sizeof(result.id))
  discard s.readData(result.frameCount.addr, sizeof(result.frameCount))
  discard s.readData(result.size.addr,       sizeof(result.size))
  var start = s.getPosition()
  while s.getPosition() < start + (result.size.int*4):
    var aph: AnimePrimitiveHeader
    discard s.readData(aph.addr, sizeof(aph))
    # echo "type: ", aph.catType.AnimePrimitiveCategory, " ", aph.objType.AnimePrimitiveObject

    var size: int = aph.size.int * 4
    if aph.catType.AnimePrimitiveCategory == apcController1 and aph.objType.AnimePrimitiveObject == apoObject:
      var head: AnimeControllerHeader = s.readAnimeControllerHeader()
      # echo head
      # echo "type: ", aph.catType.AnimePrimitiveCategory, " ", aph.objType.AnimePrimitiveObject
      var objContr: ApObjectController = s.readApObjectController(head.parameters.trackKinds)
      objContr.header = head
      result.objectControllers.add objContr
    # if aph.catType.AnimePrimitiveCategory == apcKeyframe and aph.objType.AnimePrimitiveObject == apoObject:
    # elif
    else:
      # if result.id == 49:
      #   echo aph.catType.AnimePrimitiveCategory, " ", aph.objType.AnimePrimitiveObject
      for i in 0 ..< (size):
        discard s.readuint8()
    # echo aph
    # if aph.objType.AnimePrimitiveObject == apoObject:

    # case aph.catType.AnimePrimitiveCategory
    # of apcController1, apcController2, apcController3:
    #   echo "type: ", aph.catType.AnimePrimitiveCategory, " ", aph.objType.AnimePrimitiveObject
    #   var head: AnimeControllerHeader = s.readAnimeControllerHeader()
    #   if aph.objType == apoObject:
    #     var apoc = s.readApObjectController()
    #   # else:
    #   #   size -= sizeof(uint64)
    #   size -= sizeof(uint64)
    #   echo head.parameters.numTracks, " ", head.parameters.trackKinds, " ", size / 4
    # else:
    #   discard


  while s.getPosition() mod 4 != 0: discard s.readuint8()


proc readModel*(s: Stream): Model =
  discard s.readData(result.header.addr, sizeof(result.header))

  var modelType: uint16 = result.header.`type`.uint16 and 0xFFFE
  var kind: KnownModelKind = modelType.KnownModelKind
  if kind notin KNOWN_MODEL_KINDS: raise newException(ValueError, "Unknown model: " & result.header.`type`.int.toHex)

  result = Model(header: result.header, kind: kind) # Can't assign kind w/ object variants so we have to recreate the model
  var indices: seq[int] = toSeq(0..<result.header.numPrimitives.int)
  case result.kind:
    of mkShadow:      result.shadowPrimitives      = indices.mapIt(s.readShadowPrimitive)
    of mkRigid:       result.rigidPrimitives       = indices.mapIt(s.readRigidPrimitive)
    of mkMorphTarget: result.morphTargetPrimitives = indices.mapIt(s.readMorphTargetPrimitive)
    of mkDeformable:
      result.deformableRigidPrimitives = indices[0..^2].mapIt(s.readDeformRigidPrimitive)
      result.deformablePrimitive = s.readDeformablePrimitive()

