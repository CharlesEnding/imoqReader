import std/[macros, sequtils, streams, strutils]

import blas

type
  Normal* {.packed.} = object
    value*: Vec3B
    flags*: uint8

  DeformableVertex* {.packed.} = object
    value*: Vec3H
    joint: uint16

  AnimePrimitive {.packed.} = object
    `type`, size: uint32

  Anime {.packed.} = object
    id, frameCount, size: uint32

  Clump {.packed.} = object
    id, nodeCount: uint32
    nodeIds: seq[uint32]

  Clut {.packed.} = object
    id, blitGroup, unk1, unk2, colorCount: uint32
    colors: seq[ColorBGRA]

  ColorBGRA* {.packed.} = object
    b, g, r, a: uint8

  ColorRGBA* {.packed.} = object
    r, b, g, a: uint8

  Dummy {.packed.} = object
    id: uint32
    position: Vec3

  DummyPosRot {.packed.} = object
    id: uint32
    position, rotation: Vec3

  HitGroup {.packed.} = object
    vertexCount: uint64
    color: ColorRGBA
    vertices: seq[Vec3]

  HitMesh {.packed.} = object
    id, unk1, hitGroupCount, vertexCount: uint32
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
    parentId, matTexId, numVertices: uint32
    vertices*: seq[Vec3H]
    normals*:  seq[Normal]
    colors:   seq[ColorRGBA]
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
    vertexScale: float32
    `type`: ModelKind
    numPrimitives*, drawFlags*, unk1: uint16
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

  Object {.packed.} = object
    id, parentId, modelId, shadowId: uint32

  KnownTextureType = enum
    ttRGBA = 0x0
    ttI8   = 0x13
    ttI4   = 0x14

  TextureType = distinct uint8

  Texture* {.packed.} = object
    id*, clutId, blitGroupId: uint32
    flags: uint8
    `type`: TextureType
    mipCount, unk1, width, height: uint8
    unk2: uint16
    unk3, textureDataSize*: uint32
    data*: seq[byte]

macro enumElementsAsSet(enm: typed): untyped = result = newNimNode(nnkCurly).add(enm.getType[1][1..^1])
const KNOWN_TEXTURE_TYPES = enumElementsAsSet(KnownTextureType)
const KNOWN_MODEL_KINDS   = enumElementsAsSet(KnownModelKind)
proc `$`(t: TextureType): string = result = if t.KnownTextureType in KNOWN_TEXTURE_TYPES: $KnownTextureType(t) else: "UnknownTexType" & $t.int

proc readSeq[T](s: Stream, numItems: int, t: typedesc[T], discardPadding: bool = false): seq[T] =
  if numItems == 0: raise newException(ValueError, "0 number of items.")
  result.setLen(numItems)
  discard s.readData(result[0].addr, numItems * sizeof(t))
  if discardPadding and s.getPosition() mod 4 == 2: discard s.readInt16()

proc readAnime(s: Stream): Anime =
  discard s.readData(result.addr, sizeof(result))
  discard s.readSeq(result.size.int, byte)

proc readTexture*(s: Stream): Texture =
  discard s.readData(result.addr, sizeof(Texture)-sizeof(result.data))
  result.data = s.readSeq(result.textureDataSize.int * 4, uint8)
  for mi in 0..<(result.mipCount.int):
    discard s.readUint32()
    var mipSize: int32 = s.readInt32() * 4
    s.setPosition(s.getPosition() + mipSize)

proc readHitMesh(s: Stream): HitMesh =
  discard s.readData(result.addr, sizeof(HitMesh)-sizeof(result.hitGroups))
  for hgi in 0..<result.hitGroupCount:
    var hitGroup: HitGroup
    discard s.readData(hitGroup.addr, sizeof(HitGroup)-sizeof(hitGroup.vertices))
    hitGroup.vertices = s.readSeq(hitGroup.vertexCount.int, Vec3)
    result.hitGroups.add(hitGroup)

proc readClump(s: Stream): Clump =
  discard s.readData(result.addr, sizeof(Clump)-sizeof(result.nodeIds))
  result.nodeIds = s.readSeq(result.nodeCount.int, uint32)

proc readClut(s: Stream): Clut =
  discard s.readData(result.addr, sizeof(Clut)-sizeof(result.colors))
  result.colors = s.readSeq(result.colorCount.int, ColorBGRA)

proc readMorphTargetPrimitive(s: Stream, scale: float32): MorphTargetPrimitive =
  discard s.readData(result.addr, sizeof(result.parentId) + sizeof(result.matTexId) + sizeof(result.numVertices))
  result.vertices = s.readSeq(result.numVertices.int, Vec3H, discardPadding=true).mapIt(it * scale)
  result.normals = s.readSeq(result.numVertices.int, Normal)

proc readRigidPrimitive(s: Stream, scale: float32): RigidPrimitive =
  discard s.readData(result.addr, sizeof(result.parentId) + sizeof(result.matTexId) + sizeof(result.numVertices))
  result.vertices  = s.readSeq(result.numVertices.int, Vec3H, discardPadding=true).mapIt(it * scale)
  result.normals   = s.readSeq(result.numVertices.int, Normal)
  result.colors    = s.readSeq(result.numVertices.int, ColorRGBA)
  result.texCoords = s.readSeq(result.numVertices.int, UV)

proc readDeformRigidPrimitive(s: Stream, scale: float32): DeformRigidPrimitive =
  discard s.readData(result.addr, sizeof(result.matTexId) + sizeof(result.numVertices) + sizeof(result.unk1) + sizeof(result.parentId))
  result.vertices  = s.readSeq(result.numVertices.int, Vec3H, discardPadding=true).mapIt(it * scale)
  result.normals   = s.readSeq(result.numVertices.int, Normal)
  result.texCoords = s.readSeq(result.numVertices.int, UV)

proc readDeformablePrimitive(s: Stream, scale: float32): DeformablePrimitive =
  discard s.readData(result.addr, sizeof(result.matTexId) + sizeof(result.numVertices) + sizeof(result.numVerticesActual))
  result.vertices  = s.readSeq(result.numVerticesActual.int, DeformableVertex, discardPadding=true) # TODO: Add scale
  result.normals   = s.readSeq(result.numVerticesActual.int, Normal)
  result.texCoords = s.readSeq(result.numVertices.int, UV)

proc readShadowPrimitive(s: Stream, scale: float32): ShadowPrimitive =
  discard s.readData(result.addr, sizeof(result.numVertices) + sizeof(result.numIndices))
  result.vertices = s.readSeq(result.numVertices.int, Vec3H, discardPadding=true).mapIt(it * scale)
  result.indices  = s.readSeq(result.numIndices.int, uint32)

proc readModel*(s: Stream): Model =
  discard s.readData(result.header.addr, sizeof(result.header))

  var modelType: uint16 = result.header.`type`.uint16 and 0xFFFE
  var kind: KnownModelKind = modelType.KnownModelKind
  if kind notin KNOWN_MODEL_KINDS: raise newException(ValueError, "Unknown model: " & result.header.`type`.int.toHex)

  result = Model(header: result.header, kind: kind) # Can't assign kind w/ object variants so we have to recreate the model
  var indices: seq[int] = toSeq(0..<result.header.numPrimitives.int)
  var scale: float32 = result.header.vertexScale / 256.0 * 0.0625 # Magic value taken from StudioCCS
  case result.kind:
    of mkShadow:      result.shadowPrimitives      = indices.mapIt(s.readShadowPrimitive(scale))
    of mkRigid:       result.rigidPrimitives       = indices.mapIt(s.readRigidPrimitive(scale))
    of mkMorphTarget: result.morphTargetPrimitives = indices.mapIt(s.readMorphTargetPrimitive(scale))
    of mkDeformable:
      result.deformableRigidPrimitives = indices[0..^2].mapIt(s.readDeformRigidPrimitive(scale))
      result.deformablePrimitive = s.readDeformablePrimitive(result.header.vertexScale)

