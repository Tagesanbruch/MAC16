package mac16.exp_i

import chisel3._
import chisel3.util._
import mac16.common._

/**
 * Booth Multiplier with Valid-Gated Pipeline Registers
 * All pipeline registers only update when valid signal is high
 */
class Mult16BoothGated extends Module {
  val io = IO(new Bundle {
    val a        = Input(UInt(16.W))
    val b        = Input(UInt(16.W))
    val validIn  = Input(Bool())
    val product  = Output(UInt(32.W))
    val validOut = Output(Bool())
  })

  //=========================================================================
  // Stage 1: Booth Encoding + Partial Product Generation
  //=========================================================================
  
  val booth = Module(new BoothEncoder)
  booth.io.b := io.b

  val negS1   = RegInit(0.U(8.W))
  val zeroS1  = RegInit(0.U(8.W))
  val twoS1   = RegInit(0.U(8.W))
  val aS1     = RegInit(0.U(16.W))
  val validS1 = RegInit(false.B)

  when(io.validIn) {
    negS1  := booth.io.neg
    zeroS1 := booth.io.zero
    twoS1  := booth.io.two
    aS1    := io.a
    validS1 := true.B
  }.otherwise {
    validS1 := false.B
  }

  val ppGen = Module(new PartialProductGen)
  ppGen.io.a    := aS1
  ppGen.io.neg  := negS1
  ppGen.io.zero := zeroS1
  ppGen.io.two  := twoS1

  //=========================================================================
  // Stage 2: Alignment and First Level Compression
  //=========================================================================
  
  val ppAligned = Wire(Vec(8, UInt(40.W)))
  ppAligned(0) := Cat(Fill(7, ppGen.io.pp(0)(32)), ppGen.io.pp(0))              // << 0
  ppAligned(1) := Cat(Fill(5, ppGen.io.pp(1)(32)), ppGen.io.pp(1), 0.U(2.W))    // << 2
  ppAligned(2) := Cat(Fill(3, ppGen.io.pp(2)(32)), ppGen.io.pp(2), 0.U(4.W))    // << 4
  ppAligned(3) := Cat(ppGen.io.pp(3)(32), ppGen.io.pp(3), 0.U(6.W))             // << 6
  ppAligned(4) := Cat(ppGen.io.pp(4)(30, 0), 0.U(8.W))                          // << 8
  ppAligned(5) := Cat(ppGen.io.pp(5)(28, 0), 0.U(10.W))                         // << 10
  ppAligned(6) := Cat(ppGen.io.pp(6)(26, 0), 0.U(12.W))                         // << 12
  ppAligned(7) := Cat(ppGen.io.pp(7)(24, 0), 0.U(14.W))                         // << 14

  val (csa1Sum, csa1Carry) = CSA(40, ppAligned(0), ppAligned(1), ppAligned(2))
  val (csa2Sum, csa2Carry) = CSA(40, ppAligned(3), ppAligned(4), ppAligned(5))
  val (csa3Sum, csa3Carry) = CSA(40, csa1Sum, Cat(csa1Carry(38, 0), 0.U(1.W)), ppAligned(6))
  val (csa4Sum, csa4Carry) = CSA(40, csa2Sum, Cat(csa2Carry(38, 0), 0.U(1.W)), ppAligned(7))

  val row0S2  = RegInit(0.U(40.W))
  val row1S2  = RegInit(0.U(40.W))
  val row2S2  = RegInit(0.U(40.W))
  val row3S2  = RegInit(0.U(40.W))
  val validS2 = RegInit(false.B)

  when(validS1) {
    row0S2  := csa3Sum
    row1S2  := Cat(csa3Carry(38, 0), 0.U(1.W))
    row2S2  := csa4Sum
    row3S2  := Cat(csa4Carry(38, 0), 0.U(1.W))
    validS2 := true.B
  }.otherwise {
    validS2 := false.B
  }

  //=========================================================================
  // Stage 3: Final Compression + Addition
  //=========================================================================
  
  val comp42 = Module(new Compressor4to2Array(40))
  comp42.io.a := row0S2
  comp42.io.b := row1S2
  comp42.io.c := row2S2
  comp42.io.d := row3S2

  val finalProduct = comp42.io.sum +& Cat(comp42.io.carry(38, 0), 0.U(1.W))

  val productS3 = RegInit(0.U(32.W))
  val validS3   = RegInit(false.B)

  when(validS2) {
    productS3 := finalProduct(31, 0)
    validS3   := true.B
  }.otherwise {
    validS3 := false.B
  }

  io.product  := productS3
  io.validOut := validS3
}
