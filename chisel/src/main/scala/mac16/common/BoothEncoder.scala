package mac16.common

import chisel3._
import chisel3.util._

/**
 * Radix-4 Booth Encoder
 * Generates encoding signals for 8 partial products from 16-bit input B
 * 
 * Booth recoding reduces partial products from 16 to 8
 * Encoding: examines groups of 3 bits (b[2i+1], b[2i], b[2i-1])
 */
class BoothEncoder extends Module {
  val io = IO(new Bundle {
    val b    = Input(UInt(16.W))
    val neg  = Output(UInt(8.W))   // Negate partial product
    val zero = Output(UInt(8.W))  // Zero partial product  
    val two  = Output(UInt(8.W))  // Double partial product
  })

  // Extended B with implicit -1 bit = 0
  // b_ext[16:0] = {b[15:0], 1'b0}
  val bExt = Cat(io.b, 0.U(1.W))
  
  val negBits  = Wire(Vec(8, Bool()))
  val zeroBits = Wire(Vec(8, Bool()))
  val twoBits  = Wire(Vec(8, Bool()))
  
  // Generate 8 Booth encodings
  // Each group examines bits: b[2i+1], b[2i], b[2i-1]
  // NOTE: For group 0, we need to include the implicit b[-1]=0
  // group[0] = bExt[2:0] = {b[1], b[0], 0}
  // group[i] = bExt[2i+2 : 2i] = {b[2i+1], b[2i], b[2i-1]}
  for (i <- 0 until 8) {
    // Explicitly construct the 3-bit group to prevent CIRCT from optimizing away the LSB
    val group = Wire(UInt(3.W))
    if (i == 0) {
      // For group 0: {b[1], b[0], 0}
      group := Cat(io.b(1, 0), 0.U(1.W))
    } else {
      // For groups 1-7: {b[2i+1], b[2i], b[2i-1]}
      group := io.b(2*i + 1, 2*i - 1)
    }
    
    // Booth decoding truth table:
    // group | action | neg | zero | two
    // 000   |   0    |  0  |   1  |  0
    // 001   |  +1    |  0  |   0  |  0
    // 010   |  +1    |  0  |   0  |  0
    // 011   |  +2    |  0  |   0  |  1
    // 100   |  -2    |  1  |   0  |  1
    // 101   |  -1    |  1  |   0  |  0
    // 110   |  -1    |  1  |   0  |  0
    // 111   |   0    |  0  |   1  |  0
    
    negBits(i)  := group(2)
    zeroBits(i) := (group === 0.U) || (group === 7.U)
    twoBits(i)  := (group === 3.U) || (group === 4.U)
  }
  
  io.neg  := negBits.asUInt
  io.zero := zeroBits.asUInt
  io.two  := twoBits.asUInt
}

/**
 * Partial Product Generator for Radix-4 Booth Multiplier
 * Generates 8 partial products from 16-bit input A and Booth encoding
 * 
 * Each partial product is:
 *   - A, 2A, -A, -2A, or 0 based on Booth encoding
 *   - Sign extended to 33 bits (to handle signed multiplication)
 */
class PartialProductGen extends Module {
  val io = IO(new Bundle {
    val a    = Input(UInt(16.W))
    val neg  = Input(UInt(8.W))
    val zero = Input(UInt(8.W))
    val two  = Input(UInt(8.W))
    val pp   = Output(Vec(8, UInt(33.W)))
  })

  // For Booth multiplication, treat A as signed 16-bit value
  // a_ext[16:0] = sign_extend(a) = {a[15], a[15:0]} = 17 bits
  // a_2x[17:0]  = 2 * a (signed) = {a[15], a[15:0], 1'b0} = 18 bits
  //
  // The key insight is that a_2x is NOT just {a, 0} but {sign, a, 0}
  // This preserves the sign for proper Booth encoding
  
  // Explicitly construct bit patterns to avoid CIRCT optimization issues
  // a_ext = {a[15], a[15:0]} = 17 bits, sign extended to 18
  // a_2x  = {a[15], a[15:0], 0} = 18 bits
  val signBit = io.a(15)
  val aExt17 = Cat(signBit, io.a)                    // 17 bits: {sign, a}
  val a2x18  = Cat(signBit, io.a, 0.U(1.W))          // 18 bits: {sign, a, 0}
  
  def genPP(idx: Int): UInt = {
    val negBit  = io.neg(idx)
    val zeroBit = io.zero(idx)
    val twoBit  = io.two(idx)
    
    // Select A or 2A
    // a_2x is 18 bits, a_ext is 17 bits, so we sign-extend a_ext to 18 bits
    val aExt18 = Cat(signBit, aExt17)                // 18 bits: {sign, sign, a}
    val aSel = Mux(twoBit, a2x18, aExt18)           // 18 bits
    
    // Negate if needed (two's complement on 18-bit signed value)
    val aSelSInt = aSel.asSInt
    val aNeg = Mux(negBit, (-aSelSInt).asUInt, aSel)  // 18 bits
    
    // Zero if needed
    val aFinal = Mux(zeroBit, 0.U(18.W), aNeg)
    
    // Sign extend to 33 bits
    Cat(Fill(15, aFinal(17)), aFinal)
  }
  
  for (i <- 0 until 8) {
    io.pp(i) := genPP(i)
  }
}
