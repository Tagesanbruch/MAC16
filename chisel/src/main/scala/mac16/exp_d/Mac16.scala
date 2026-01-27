package mac16.exp_d

import chisel3._
import chisel3.util._

/**
 * MAC16 - Exp D (Structural Booth Multiplier)
 */
class Mac16 extends RawModule {
  val clk       = IO(Input(Clock()))
  val rst_n     = IO(Input(Bool()))
  val mode      = IO(Input(Bool()))
  val inA       = IO(Input(Bool()))
  val inB       = IO(Input(Bool()))
  val sum_out   = IO(Output(Bool()))
  val carry     = IO(Output(Bool()))
  val out_ready = IO(Output(Bool()))

  override def desiredName: String = "mac16"

  withClockAndReset(clk, (!rst_n).asAsyncReset) {
    val inputBits  = 16
    val outputBits = 24

    // State machine
    val sInput       = 0.U(3.W)
    val sMultStage1  = 1.U(3.W)
    val sMultStage2  = 2.U(3.W)
    val sMultStage3  = 3.U(3.W)
    val sAdd         = 4.U(3.W)
    val sOutput      = 5.U(3.W)

    val state = RegInit(sInput)
    val cnt   = RegInit(0.U(5.W))

    val shiftA = RegInit(0.U(inputBits.W))
    val shiftB = RegInit(0.U(inputBits.W))
    val accum  = RegInit(0.U(outputBits.W))
    val prevProduct = RegInit(0.U(outputBits.W))
    val outShiftReg = RegInit(0.U(outputBits.W))

    val carryReg = RegInit(false.B)
    val firstOp  = RegInit(true.B)
    val modeR    = RegInit(false.B)

    val multValidIn  = RegInit(false.B)
    val multReg      = RegInit(0.U(32.W))

    // Operand isolation
    val multEnable = (state === sInput && cnt === (inputBits - 1).U) ||
      (state >= sMultStage1 && state <= sMultStage3)

    // Structural Booth multiplier
    val mult = Module(new Mult16Booth)
    mult.io.a       := Mux(multEnable, shiftA, 0.U)
    mult.io.b       := Mux(multEnable, shiftB, 0.U)
    mult.io.validIn := multValidIn

    val addResult = Wire(UInt((outputBits + 1).W))
    val macResult = Wire(UInt(outputBits.W))

    when(modeR === false.B) {
      addResult := Cat(0.U(1.W), multReg(23, 0)) +& Cat(0.U(1.W), prevProduct)
    }.otherwise {
      addResult := Cat(0.U(1.W), multReg(23, 0)) +& Cat(0.U(1.W), accum)
    }

    when(firstOp && (modeR === false.B)) {
      macResult := multReg(23, 0)
    }.otherwise {
      macResult := addResult(23, 0)
    }

    // Default outputs
    sum_out   := false.B
    out_ready := false.B

    switch(state) {
      is(sInput) {
        out_ready := false.B
        sum_out   := false.B
        modeR       := mode
        multValidIn := false.B

        shiftA := Cat(shiftA(inputBits - 2, 0), inA)
        shiftB := Cat(shiftB(inputBits - 2, 0), inB)

        when(cnt === (inputBits - 1).U) {
          cnt         := 0.U
          state       := sMultStage1
          multValidIn := true.B
        }.otherwise {
          cnt := cnt + 1.U
        }
      }

      is(sMultStage1) {
        multValidIn := false.B
        state := sMultStage2
      }

      is(sMultStage2) {
        state := sMultStage3
      }

      is(sMultStage3) {
        when(mult.io.validOut) {
          multReg := mult.io.product
          state := sAdd
        }
      }

      is(sAdd) {
        outShiftReg := macResult

        when(modeR === false.B) {
          prevProduct := macResult
        }.otherwise {
          accum := macResult
        }

        when((!firstOp || modeR) && addResult(outputBits)) {
          carryReg := true.B
        }

        firstOp  := false.B
        out_ready := true.B
        sum_out   := macResult(outputBits - 1)
        state := sOutput
      }

      is(sOutput) {
        outShiftReg := Cat(outShiftReg(outputBits - 2, 0), 0.U(1.W))
        sum_out   := outShiftReg(outputBits - 2)

        when(cnt === (outputBits - 2).U) {
          cnt    := 0.U
          state  := sInput
          shiftA := 0.U
          shiftB := 0.U
        }.otherwise {
          cnt := cnt + 1.U
        }
      }
    }

    carry := carryReg
  }
}
