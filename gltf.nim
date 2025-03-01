import std/[json, options, paths, sequtils, streams, tables]

import blas
import blocks

type
  ResourceId = int
  AccessorId = ResourceId

  Primitive = object
    mode: int
    attributes: Table[string, AccessorId]
    indices: Option[AccessorId]
    # material: Option[ResourceId]

  Mesh = object
    primitives: seq[Primitive]

  Node = object
    mesh: ResourceId

  Scene = object
    nodes: seq[ResourceId]

  BaseColorTexture = object
    index, texCoord: ResourceId
    metallicFactor, roughnessFactor: float

  PbrMettalicRoughness = object
    baseColorFactor:  array[4, int]
    baseColorTexture: BaseColorTexture

  Material = object
    name: string
    pbrMettalicRoughness: PbrMettalicRoughness

  Buffer = object
    byteLength: int

  BufferView = object
    buffer: ResourceId
    byteOffset, byteLength: int
    target: int

  Accessor = object
    bufferView: ResourceId
    byteOffset, componentType, count: int
    `type`: string
    `max`, `min`: seq[float32]

  Texture = object
    source, sampler: ResourceId

  Image = object
    bufferView: ResourceId
    mimeType:   string

  Sampler = object

  Asset = object
    version: string

  GltfFile = object
    asset:     Asset
    scenes:    seq[Scene]
    nodes:     seq[Node]
    meshes:    seq[Mesh]
    materials: seq[Material]
    buffers:   seq[Buffer]
    bufferViews: seq[BufferView]
    accessors: seq[Accessor]
    textures:  seq[Texture]
    images:    seq[Image]
    samplers:  seq[Sampler]

  GltfHeader = object
    magic: uint32
    version: uint32
    length: uint32

  ChunkHeader = object
    chunkLength, chunkType: uint32

  Context* = object
    file: GltfFile
    buffer: Stream

const VEC_3H_TYPE = 5122
const VEC_3B_TYPE = 5120
const VEC_3_TYPE  = 5126
const UV_TYPE     = 5122
const COLOR_TYPE  = 5125
const INDICES_TYPE = 5125

proc serialize[T](context: var Context, data: seq[T]): int =
  var size: int = data.len * sizeof(T)
  context.buffer.writeData(data[0].addr, size)
  return size

proc createAccessor[T](context: var Context, data: seq[T], `type`: string, componentType: int, target: int): AccessorId =
  result = context.file.accessors.len() # One buffer view per accessor, they share the same id.
  while context.buffer.getPosition() mod 4 != 0: context.buffer.write(0.byte) # Offsets must be 4 bytes aligned
  var offset = context.buffer.getPosition()
  var length = context.serialize(data)
  context.file.bufferViews.add BufferView(buffer: 0, byteOffset: offset, byteLength: length, target: target) # buffer id always zero, we use a single big one

  var accessor =
    when T is uint32: Accessor(bufferView: result, `type`: `type`, componentType: componentType, count: data.len, max: @[max(data).float32], min: @[min(data).float32])
    else:             Accessor(bufferView: result, `type`: `type`, componentType: componentType, count: data.len, max: max(data).toSeq(),    min: min(data).toSeq())
  context.file.accessors.add(accessor)

proc toVec3Seq[T](s: seq[T]): seq[Vec3] = s.mapIt([it[0].float32, it[1].float32, it[2].float32])

# proc serialize(context: var Context, primitive: MorphTargetPrimitive): Primitive =
#   result.mode = 4
#   result.attributes["POSITION"] = context.createAccessor(primitive.vertices.toVec3Seq, "VEC3", VEC_3_TYPE)
#   result.attributes["NORMAL"]   = context.createAccessor(primitive.normals.mapIt(it.value).toVec3Seq, "VEC3", VEC_3_TYPE)

# proc serialize(context: var Context, primitive: DeformRigidPrimitive): Primitive =
#   result.mode = 4
#   result.attributes["POSITION"]   = context.createAccessor(primitive.vertices.toVec3Seq, "VEC3", VEC_3_TYPE)
#   result.attributes["NORMAL"]     = context.createAccessor(primitive.normals.mapIt(it.value).toVec3Seq, "VEC3", VEC_3_TYPE)
#   # result.attributes["TEXCOORD_0"] = context.createAccessor(primitive.texCoords, "VEC2", UV_TYPE)

# proc serialize(context: var Context, primitive: DeformablePrimitive): Primitive =
#   result.mode = 4
#   result.attributes["POSITION"]   = context.createAccessor(primitive.vertices.mapIt(it.value).toVec3Seq, "VEC3", VEC_3_TYPE)
#   result.attributes["NORMAL"]     = context.createAccessor(primitive.normals.mapIt(it.value).toVec3Seq, "VEC3", VEC_3_TYPE)
#   # result.attributes["TEXCOORD_0"] = context.createAccessor(primitive.texCoords, "VEC2", UV_TYPE)

proc serialize(context: var Context, primitive: RigidPrimitive): Primitive =
  result.mode = 4
  result.attributes["POSITION"]   = context.createAccessor(primitive.vertices.toVec3Seq, "VEC3", VEC_3_TYPE, 34962)
  result.attributes["NORMAL"]     = context.createAccessor(primitive.normals.mapIt(it.value).toVec3Seq, "VEC3", VEC_3_TYPE, 34962)
  var indices: seq[uint32]
  for i in 0..<primitive.vertices.len:
    if primitive.normals[i].flags == 0: indices &= @[i.uint32, (i-1).uint32, (i-2).uint32]
  result.indices = context.createAccessor(indices, "SCALAR", INDICES_TYPE, 34963).some()
  # result.attributes["TEXCOORD_0"] = context.createAccessor(primitive.texCoords, "VEC2", UV_TYPE, 34962)

proc createNode*(context: var Context, model: Model) =
  var meshId = context.file.meshes.len()
  context.file.meshes.add Mesh()
  var nodeId = context.file.nodes.len()
  context.file.nodes.add  Node(mesh: meshId)
  context.file.scenes[0].nodes.add(nodeId)

  case model.kind
  of mkRigid:
    for primitive in model.rigidPrimitives:
      if primitive.vertices.len != 0:
        context.file.meshes[^1].primitives.add context.serialize(primitive)
  else:
    raise newException(ValueError, "Can't serialize model type.")

proc align(stream: Stream) =
  while stream.getPosition() mod 4 != 0:
    stream.write("0")

proc writeToFile*(context: var Context, path: Path) =
  context.file.asset = Asset(version: "2.0")

  # Serialize binary buffer and add to file
  context.buffer.setPosition(0)
  var binData: string = context.buffer.readAll()
  context.file.buffers.add Buffer(byteLength: binData.len)
  var binHeader = ChunkHeader(chunkLength: binData.len.uint32, chunkType: 0x004E4942)

  # File to json
  var jsonData = $(%* context.file)
  while jsonData.len mod 4 != 0: jsonData &= ' ' # Chunk length must be 4 bytes aligned.
  var jsonHeader = ChunkHeader(chunkLength: jsonData.len.uint32, chunkType: 0x4E4F534A)

  var fileHeader = GltfHeader(magic: 0x46_54_6C_67, version: 2, length: sizeof(GltfHeader) + sizeof(ChunkHeader)*2 + jsonHeader.chunkLength + binHeader.chunkLength)
  var output = newFileStream(path.string, fmWrite)
  output.writeData(fileHeader.addr,  sizeof(GltfHeader))
  output.writeData(jsonHeader.addr,  sizeof(ChunkHeader))
  output.writeData(jsonData[0].addr, jsonData.len)
  output.writeData(binHeader.addr,   sizeof(ChunkHeader))
  output.writeData(binData[0].addr,  binData.len)

proc createScene*(): Context =
  result.buffer = newStringStream()
  result.file.scenes.add Scene()
