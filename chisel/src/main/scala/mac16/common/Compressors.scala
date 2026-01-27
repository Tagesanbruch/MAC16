package mac16.common

import chisel3._
import chisel3.util._

/**
 * 3:2 Carry Save Adder (Full Adder based compressor)
 */
class CSA(val width: Int) extends Module {
  val io = IO(new Bundle {
    val a     = Input(UInt(width.W))
    val b     = Input(UInt(width.W))
    val c     = Input(UInt(width.W))
    val sum   = Output(UInt(width.W))
    val carry = Output(UInt(width.W))
  })

  io.sum   := io.a ^ io.b ^ io.c
  io.carry := (io.a & io.b) | (io.b & io.c) | (io.a & io.c)
}

object CSA {
  def apply(width: Int, a: UInt, b: UInt, c: UInt): (UInt, UInt) = {
    val sum   = a ^ b ^ c
    val carry = (a & b) | (b & c) | (a & c)
    (sum, carry)
  }
}

/**
 * 4:2 Compressor - compresses 4 inputs + cin to sum, carry, cout
 */
class Compressor4to2 extends Module {
  val io = IO(new Bundle {
    val a     = Input(Bool())
    val b     = Input(Bool())
    val c     = Input(Bool())
    val d     = Input(Bool())
    val cin   = Input(Bool())
    val sum   = Output(Bool())
    val carry = Output(Bool())
    val cout  = Output(Bool())
  })

  val w1 = io.a ^ io.b
  val w2 = io.c ^ io.d
  val w3 = w1 ^ w2

  // Carry out - does not depend on cin (critical for timing)
  io.cout := Mux(w1, io.c, io.a)
  
  // Sum
  io.sum := w3 ^ io.cin
  
  // Carry - depends on cin
  io.carry := Mux(w3, io.cin, io.d)
}

/**
 * N-bit 4:2 Compressor Array
 */
class Compressor4to2Array(val width: Int) extends Module {
  val io = IO(new Bundle {
    val a     = Input(UInt(width.W))
    val b     = Input(UInt(width.W))
    val c     = Input(UInt(width.W))
    val d     = Input(UInt(width.W))
    val sum   = Output(UInt(width.W))
    val carry = Output(UInt(width.W))
  })

  val sumBits   = Wire(Vec(width, Bool()))
  val carryBits = Wire(Vec(width, Bool()))
  val coutChain = Wire(Vec(width + 1, Bool()))
  
  coutChain(0) := false.B
  
  for (i <- 0 until width) {
    val comp = Module(new Compressor4to2)
    comp.io.a   := io.a(i)
    comp.io.b   := io.b(i)
    comp.io.c   := io.c(i)
    comp.io.d   := io.d(i)
    comp.io.cin := coutChain(i)
    
    sumBits(i)       := comp.io.sum
    carryBits(i)     := comp.io.carry
    coutChain(i + 1) := comp.io.cout
  }
  
  io.sum   := sumBits.asUInt
  io.carry := carryBits.asUInt
}

object Compressor4to2Array {
  def apply(width: Int, a: UInt, b: UInt, c: UInt, d: UInt): (UInt, UInt) = {
    val comp = Module(new Compressor4to2Array(width))
    comp.io.a := a
    comp.io.b := b
    comp.io.c := c
    comp.io.d := d
    (comp.io.sum, comp.io.carry)
  }
}
