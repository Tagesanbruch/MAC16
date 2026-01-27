package mac16.exp_i

import chisel3._
import chisel3.util._
import mac16.common._

/**
 * Booth Multiplier with Valid-Gated Pipeline Registers (2-stage version)
 * Stage 1: Booth encode + PP generation + First level compression
 * Stage 2: Final compression + Addition
 */
class Mult16BoothGated2Stage extends Module {
  val io = IO(new Bundle {
    val a        = Input(UInt(16.W))
    val b        = Input(UInt(16.W))
    val validIn  = Input(Bool())
    val product  = Output(UInt(32.W))
    val validOut = Output(Bool())
  })

  //=========================================================================
  // Stage 1: Booth Encoding + PP Generation + First Compression
  //=========================================================================
  
  val booth = Module(new BoothEncoder)
  booth.io.b := io.b

  val ppGen = Module(new PartialProductGen)
  ppGen.io.a    := io.a
  ppGen.io.neg  := booth.io.neg
  ppGen.io.zero := booth.io.zero
  ppGen.io.two  := booth.io.two

  // Align partial products
  val ppAligned = Wire(Vec(8, UInt(40.W)))
  ppAligned(0) := Cat(Fill(7, ppGen.io.pp(0)(32)), ppGen.io.pp(0))
  ppAligned(1) := Cat(Fill(5, ppGen.io.pp(1)(32)), ppGen.io.pp(1), 0.U(2.W))
  ppAligned(2) := Cat(Fill(3, ppGen.io.pp(2)(32)), ppGen.io.pp(2), 0.U(4.W))
  ppAligned(3) := Cat(ppGen.io.pp(3)(32), ppGen.io.pp(3), 0.U(6.W))
  ppAligned(4) := Cat(ppGen.io.pp(4)(30, 0), 0.U(8.W))
  ppAligned(5) := Cat(ppGen.io.pp(5)(28, 0), 0.U(10.W))
  ppAligned(6) := Cat(ppGen.io.pp(6)(26, 0), 0.U(12.W))
  ppAligned(7) := Cat(ppGen.io.pp(7)(24, 0), 0.U(14.W))

  // First level CSA compression (8 -> 4)
  val (csa1Sum, csa1Carry) = CSA(40, ppAligned(0), ppAligned(1), ppAligned(2))
  val (csa2Sum, csa2Carry) = CSA(40, ppAligned(3), ppAligned(4), ppAligned(5))
  val (csa3Sum, csa3Carry) = CSA(40, csa1Sum, Cat(csa1Carry(38, 0), 0.U(1.W)), ppAligned(6))
  val (csa4Sum, csa4Carry) = CSA(40, csa2Sum, Cat(csa2Carry(38, 0), 0.U(1.W)), ppAligned(7))

  // Pipeline register - Stage 1 (valid-gated)
  val row0S1  = RegInit(0.U(40.W))
  val row1S1  = RegInit(0.U(40.W))
  val row2S1  = RegInit(0.U(40.W))
  val row3S1  = RegInit(0.U(40.W))
  val validS1 = RegInit(false.B)

  when(io.validIn) {
    row0S1  := csa3Sum
    row1S1  := Cat(csa3Carry(38, 0), 0.U(1.W))
    row2S1  := csa4Sum
    row3S1  := Cat(csa4Carry(38, 0), 0.U(1.W))
    validS1 := true.B
  }.otherwise {
    validS1 := false.B
  }

  //=========================================================================
  // Stage 2: Final Compression + Addition
  //=========================================================================
  
  val comp42 = Module(new Compressor4to2Array(40))
  comp42.io.a := row0S1
  comp42.io.b := row1S1
  comp42.io.c := row2S1
  comp42.io.d := row3S1

  val finalProduct = comp42.io.sum +& Cat(comp42.io.carry(38, 0), 0.U(1.W))

  // Pipeline register - Stage 2 (valid-gated)
  val productS2 = RegInit(0.U(32.W))
  val validS2   = RegInit(false.B)

  when(validS1) {
    productS2 := finalProduct(31, 0)
    validS2   := true.B
  }.otherwise {
    validS2 := false.B
  }

  io.product  := productS2
  io.validOut := validS2
}
