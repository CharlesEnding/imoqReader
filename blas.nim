# Basic Linear Algebra Subprograms
import std/[macros, math, sequtils]

type
  Vec*[N: static[int]; T] = array[N, T]
  UV* = Vec[2, int16]
  Vec2*  = Vec[2, float32]
  Vec3*  = Vec[3, float32]
  Vec4*  = Vec[4, float32]
  Vec3H* = Vec[3, int16]
  Vec3B* = Vec[3, int8]

proc `*`*[N, T](v: Vec[N, T], s: float32): Vec[N, T] {.inline.} =
  for i in 0..<N:
    result[i] = (v[i].float32 * s).T

proc `*`*[N, T](v: Vec[N, T], s: T): Vec[N, T] {.inline.} =
  for i in 0..<N:
    result[i] = v[i] * s

proc min*[N, T](v0, v1: Vec[N, T]): Vec[N, T] {.inline.} =
  for i in 0..<N:
    result[i] = min(v0[i], v1[i])

proc max*[N, T](v0, v1: Vec[N, T]): Vec[N, T] {.inline.} =
  for i in 0..<N:
    result[i] = max(v0[i], v1[i])

proc min*[N, T](data: seq[Vec[N, T]]): Vec[N, T] {.inline.} =
  for i in 0..<N:
    result[i] = high(T)
  for v in data:
    result = min(result, v)

proc max*[N, T](data: seq[Vec[N, T]]): Vec[N, T] {.inline.} =
  for i in 0..<N:
    result[i] = low(T)
  for v in data:
    result = max(result, v)

proc toFloatVecs*[N, T](s: seq[Vec[N, T]]): seq[Vec[N, float32]] =
  for v in s:
    var newVertex: Vec[N, float32]
    for i in 0..<N:
      newVertex[i] = v[i].float32
    result.add(newVertex)

proc scale*[N](data: seq[Vec[N, float32]], scale: float32): seq[Vec[N, float32]] = data.mapIt(it * scale)

proc eulerToQuaternion*(euleur: Vec3): Vec4 =
  var
    cr = cos(euleur[0] * 0.5)
    sr = sin(euleur[0] * 0.5)
    cp = cos(euleur[1] * 0.5)
    sp = sin(euleur[1] * 0.5)
    cy = cos(euleur[2] * 0.5)
    sy = sin(euleur[2] * 0.5)

  var
    x: float32 = sr * cp * cy - cr * sp * sy
    y = cr * sp * cy + sr * cp * sy
    z = cr * cp * sy - sr * sp * cy
    w = cr * cp * cy + sr * sp * sy

  return [x, y, z, w].Vec4

proc `*`*(a, b: seq[string]): seq[string] =
  for i in a:
    for j in b:
      result.add i & j

macro createReader*(t: typedesc, seqLengthIdents: varargs[untyped]): untyped =
  let readerName = ident("read" & t.repr)
  let stream = ident("s")
  result = quote do:
    proc `readerName`*(`stream`: Stream): `t.repr` =
      discard

  let fields = getType(t)[1].getTypeImpl()[2]

  if fields.len == 0: # alias, e.g Vec3 = array[3, float32] . !!Making some heavy assumptions about how they're used!!
    let readExpr = quote do: discard s.readData(result.addr, sizeof(result))
    result[^1].add readExpr

  var currentSeqIndex: int = 0
  for field in fields:
    let fieldName: NimNode = field[0]
    let fieldType: NimNode = field[1]
    var readExpr:  NimNode
    let isSequence:     bool = fieldType.kind == nnkBracketExpr and fieldType[0].repr == "seq" # Corresponds to seq[T] but **not** array[N, T]
    let isExpectedType: bool = fieldType.kind == nnkSym or (fieldType.kind == nnkBracketExpr and fieldType[0].repr == "array")
    if isSequence:
      let itemType   = fieldType[1] # T of seq[T]
      let procName   = ident("read" & itemType.repr) # readT
      let lengthName = if seqLengthIdents.len == 0: newDotExpr(ident("result"), ident("num" & fieldName.repr)) # automatic naming: objects[] will have a count of numObjects
      else: seqLengthIdents[currentSeqIndex]
      readExpr = quote do:
        for i in 0..<(`lengthName`):
          result.`fieldName`.add s.`procName`()
        while s.getPosition() mod 4 != 0: discard s.readuint8() # discard padding
      currentSeqIndex += 1
    elif isExpectedType:
      if fieldType.repr in @["int", "uint", "float"] * @["", "8", "16", "32", "64"] or fieldType.kind == nnkBracketExpr : # Standard types and arrays
        readExpr = quote do: discard s.readData(result.`fieldName`.addr, sizeof(result.`fieldName`))
      else: # Custom type T: we call s.readT()
        let procName   = ident("read" & fieldType.repr)
        readExpr = quote do: result.`fieldName` = s.`procName`()
    else:
      raise newException(ValueError, "Unknown identifier " & $(fieldName.kind) & " in field " & $fieldName & " of type " & $t.type)
    result[^1].add readExpr
  echo result.repr

macro createReaders*(types: varargs[typed]) =
  result = newStmtList()
  for t in types:
    result.add quote do:
      createReader(`t`)
