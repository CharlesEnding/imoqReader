import std/[json, options, paths, sequtils, streams, tables]

import stb_image/write as stbiw

import blas
import blocks

type
  ResourceId = int
  AccessorId = ResourceId

  Primitive = object
    mode: int
    attributes: Table[string, AccessorId]
    indices: Option[AccessorId]
    material: ResourceId

  Mesh = object
    primitives: seq[Primitive]

  Node = object
    mesh: ResourceId
    translation, scale: Vec3
    rotation: Vec4

  Scene = object
    nodes: seq[ResourceId]

  BaseColorTexture = object
    index, texCoord: ResourceId

  PbrMetallicRoughness = object
    baseColorFactor:  array[4, int] = [1, 1, 1, 1]
    baseColorTexture: BaseColorTexture
    metallicFactor, roughnessFactor: float

  Material = object
    name: string
    pbrMetallicRoughness: PbrMetallicRoughness
    doubleSided: bool = true

  Buffer = object
    byteLength: int

  BufferView = object
    buffer: ResourceId
    byteOffset, byteLength: int
    target: Option[int]

  Accessor = object
    bufferView: ResourceId
    byteOffset, componentType, count: int
    `type`: string
    `max`, `min`: seq[float32]

  Texture = object
    source: ResourceId
    # sampler: ResourceId

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
    ccsIdToGltfId: Table[tuple[`type`: string, id: int], ResourceId]

const VEC_3H_TYPE = 5122
const VEC_3B_TYPE = 5120
const GL_FLOAT  = 5126
const GL_INT = 5125
const UV_TYPE     = 5122
const COLOR_TYPE  = 5125

proc serialize[T](context: var Context, data: seq[T]): int =
  var size: int = data.len * sizeof(T)
  context.buffer.writeData(data[0].addr, size)
  return size

proc createBufferView[T](context: var Context, data: seq[T], target: Option[int] = none(int)): ResourceId =
  while context.buffer.getPosition() mod 4 != 0: context.buffer.write(0.byte) # Offsets must be 4 bytes aligned
  var offset = context.buffer.getPosition()
  var length = context.serialize(data)
  context.file.bufferViews.add BufferView(buffer: 0, byteOffset: offset, byteLength: length, target: target) # buffer id always zero, we use a single big one
  return context.file.bufferViews.len() - 1

proc createAccessor[T](context: var Context, data: seq[T], `type`: string, componentType: int, target: Option[int]): AccessorId =
  var bufViewId = context.createBufferView(data, target)
  var accessor =
    when T is uint32: Accessor(bufferView: bufViewId, `type`: `type`, componentType: componentType, count: data.len, max: @[max(data).float32], min: @[min(data).float32])
    else:             Accessor(bufferView: bufViewId, `type`: `type`, componentType: componentType, count: data.len, max:   max(data).toSeq(),  min:   min(data).toSeq())
  context.file.accessors.add(accessor)
  return context.file.accessors.len() - 1


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
  result.material = context.ccsIdToGltfId[("mat", primitive.matTexId.int)]
  result.attributes["POSITION"]   = context.createAccessor(primitive.vertices.toFloatVecs, "VEC3", GL_FLOAT, 34962.some)
  # result.attributes["NORMAL"]     = context.createAccessor(primitive.normals.mapIt(it.value).toFloatVecs, "VEC3", GL_FLOAT, 34962.some)
  var indices: seq[uint32] # Todo move to blocks?
  for i in 0..<primitive.vertices.len:
    if primitive.normals[i].flags == 0: indices &= @[i.uint32, (i-1).uint32, (i-2).uint32]
  result.indices = context.createAccessor(indices, "SCALAR", GL_INT, 34963.some).some()
  result.attributes["TEXCOORD_0"] = context.createAccessor(primitive.texCoords.toFloatVecs.mapIt([(it[0]/256.0).float32, it[1]/256.0].Vec2), "VEC2", GL_FLOAT, 34962.some)

proc createNode*(context: var Context, model: blocks.Model, position, rotation: Vec3 = [0'f32, 0, 0].Vec3, scale: Vec3 = [1'f32, 1, 1]) =#, dummy: blocks.Dummy) =
  var meshId = context.file.meshes.len()
  context.file.meshes.add Mesh()
  var nodeId = context.file.nodes.len()
  context.file.nodes.add  Node(mesh: meshId, translation: position, rotation: eulerToQuaternion(rotation), scale: scale*model.header.vertexScale)#, translation: dummy.position, scale: [model.header.vertexScale, model.header.vertexScale, model.header.vertexScale])
  context.file.scenes[0].nodes.add(nodeId)

  case model.kind
  of mkRigid:
    for primitive in model.rigidPrimitives:
      if primitive.vertices.len != 0:
        context.file.meshes[^1].primitives.add context.serialize(primitive)
  else:
    raise newException(ValueError, "Can't serialize model type.")

proc bmpDeindex*(data: seq[byte], palette: seq[Color], width, height, `type`: int): seq[byte] =
  if `type` == 0x13:
    for pi in data:
      result.add palette[pi].r
      result.add palette[pi].b
      result.add palette[pi].g
      result.add min(0xFF, palette[pi].a.int * 2).byte
  else:
    raise newException(ValueError, "Texture indexing not supported.")

proc createMaterial*(context: var Context, material: blocks.Material, texture: blocks.Texture, palette: seq[blocks.Color]) =
  if ("tex", texture.id.int) notin context.ccsIdToGltfId:
    var width:  int = 1 shl texture.widthLog2.int
    var height: int = 1 shl texture.heightLog2.int
    var imgId = context.file.images.len
    var data: seq[byte] = bmpDeindex(texture.data, palette, width, height, texture.`type`.int)
    var textureAsPng: seq[byte] = stbiw.writePNG(width, height, 4, data)
    context.file.images.add Image(bufferView: context.createBufferView(textureAsPng), mimeType: "image/png") # IMOQ only ever uses BMPs
    var texId = context.file.textures.len
    context.ccsIdToGltfId[("tex", texture.id.int)] = texId
    context.file.textures .add Texture(source: imgId)
  var texId = context.ccsIdToGltfId[("tex", texture.id.int)]

  context.file.materials.add Material(doubleSided: true)
  context.file.materials[^1].pbrMetallicRoughness = PbrMetallicRoughness(baseColorTexture: BaseColorTexture(index: texId, texCoord: 0), metallicFactor: 1, roughnessFactor: 1)
  context.ccsIdToGltfId[("mat", material.id.int)] = context.file.materials.len - 1

proc writeToFile*(context: var Context, path: Path) =
  context.file.asset = Asset(version: "2.0")

  # Serialize binary buffer and add to file
  context.buffer.setPosition(0)
  var binData: string = context.buffer.readAll()
  if len(binData) == 0: return
  context.file.buffers.add Buffer(byteLength: binData.len)
  var binHeader = ChunkHeader(chunkLength: binData.len.uint32, chunkType: 0x004E4942)

  # File to json
  var jsonData = $(%* context.file)
  while jsonData.len mod 4 != 0: jsonData &= ' ' # Chunk length must be 4 bytes aligned.
  var jsonHeader = ChunkHeader(chunkLength: jsonData.len.uint32, chunkType: 0x4E4F534A)

  var fileHeader = GltfHeader(magic: 0x46_54_6C_67, version: 2, length: sizeof(GltfHeader) + sizeof(ChunkHeader)*2 + jsonHeader.chunkLength + binHeader.chunkLength)
  var output = newFileStream(path.string, fmWrite)
  defer: output.close()
  output.writeData(fileHeader.addr,  sizeof(GltfHeader))
  output.writeData(jsonHeader.addr,  sizeof(ChunkHeader))
  output.writeData(jsonData[0].addr, jsonData.len)
  output.writeData(binHeader.addr,   sizeof(ChunkHeader))
  output.writeData(binData[0].addr,  binData.len)

proc createScene*(): Context =
  result.buffer = newStringStream()
  result.file.scenes.add Scene()
