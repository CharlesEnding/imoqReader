# Basic Linear Algebra Subprograms
import std/[math, sequtils]

type
  Vec*[N: static[int]; T] = array[N, T]
  UV* = Vec[2, int16]
  Vec3*  = Vec[3, float32]
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
