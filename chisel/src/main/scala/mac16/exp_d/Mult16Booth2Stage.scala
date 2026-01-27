package mac16.exp_d

import chisel3._
import chisel3.util._
import mac16.common._

/**
 * Structural Booth Multiplier with Wallace Tree (2-stage pipeline)
 * Modified to match original RTL's 2-cycle latency
 * 
 * Pipeline stages:
 *   Stage 1: Booth encode + Generate partial products + First level compression
 *   Stage 2: Second level compression + Final add
 */
class Mult16Booth2Stage extends Module {
  val io = IO(new Bundle {
    val a        = Input(UInt(16.W))
    val b        = Input(UInt(16.W))
    val validIn  = Input(Bool())
    val product  = Output(UInt(32.W))
    val validOut = Output(Bool())
  })

  //=========================================================================
  // Stage 1: Booth Encoding + Partial Product Generation + First Compression
  //=========================================================================
  
  // Booth encoder (combinational)
  val booth = Module(new BoothEncoder)
  booth.io.b := io.b
  
  // Partial product generation (combinational)
  val ppGen = Module(new PartialProductGen)
  ppGen.io.a    := io.a
  ppGen.io.neg  := booth.io.neg
  ppGen.io.zero := booth.io.zero
  ppGen.io.two  := booth.io.two

  // Align partial products to their correct bit positions
  val ppAligned = Wire(Vec(8, UInt(40.W)))
  
  ppAligned(0) := Cat(Fill(7, ppGen.io.pp(0)(32)), ppGen.io.pp(0))
  ppAligned(1) := Cat(Fill(5, ppGen.io.pp(1)(32)), ppGen.io.pp(1), 0.U(2.W))
  ppAligned(2) := Cat(Fill(3, ppGen.io.pp(2)(32)), ppGen.io.pp(2), 0.U(4.W))
  ppAligned(3) := Cat(ppGen.io.pp(3)(32), ppGen.io.pp(3), 0.U(6.W))
  ppAligned(4) := Cat(ppGen.io.pp(4)(30, 0), 0.U(8.W))
  ppAligned(5) := Cat(ppGen.io.pp(5)(28, 0), 0.U(10.W))
  ppAligned(6) := Cat(ppGen.io.pp(6)(26, 0), 0.U(12.W))
  ppAligned(7) := Cat(ppGen.io.pp(7)(24, 0), 0.U(14.W))
  
  // First level CSA compression: 8 -> 6 -> 4 (combinational in Stage 1)
  val (csa1Sum, csa1Carry) = CSA(40, ppAligned(0), ppAligned(1), ppAligned(2))
  val (csa2Sum, csa2Carry) = CSA(40, ppAligned(3), ppAligned(4), ppAligned(5))
  val (csa3Sum, csa3Carry) = CSA(40, csa1Sum, Cat(csa1Carry(38, 0), 0.U(1.W)), ppAligned(6))
  val (csa4Sum, csa4Carry) = CSA(40, csa2Sum, Cat(csa2Carry(38, 0), 0.U(1.W)), ppAligned(7))
  
  // Pipeline register - Stage 1 (4 rows after compression)
  val row0S1   = RegInit(0.U(40.W))
  val row1S1   = RegInit(0.U(40.W))
  val row2S1   = RegInit(0.U(40.W))
  val row3S1   = RegInit(0.U(40.W))
  val validS1  = RegInit(false.B)

  row0S1  := csa3Sum
  row1S1  := Cat(csa3Carry(38, 0), 0.U(1.W))
  row2S1  := csa4Sum
  row3S1  := Cat(csa4Carry(38, 0), 0.U(1.W))
  validS1 := io.validIn

  //=========================================================================
  // Stage 2: Second Level Compression (4->2) + Final Addition
  //=========================================================================
  
  // 4:2 compression (combinational)
  val comp42 = Module(new Compressor4to2Array(40))
  comp42.io.a := row0S1
  comp42.io.b := row1S1
  comp42.io.c := row2S1
  comp42.io.d := row3S1
  
  // Final addition (combinational)
  val finalProduct = comp42.io.sum +& Cat(comp42.io.carry(38, 0), 0.U(1.W))
  
  // Pipeline register - Stage 2 (output)
  val productS2 = RegInit(0.U(32.W))
  val validS2   = RegInit(false.B)

  productS2 := finalProduct(31, 0)
  validS2   := validS1
  
  io.product  := productS2
  io.validOut := validS2
}
