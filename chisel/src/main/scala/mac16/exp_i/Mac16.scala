package mac16.exp_i

import chisel3._
import chisel3.util._

/**
 * MAC16 - Exp I (Operand Isolation + Valid-Gated Pipeline Registers)
 * Modified to use 2-stage pipeline multiplier and registered outputs
 */
class Mac16 extends RawModule {
  val clk      = IO(Input(Clock()))
  val rst_n    = IO(Input(Bool()))
  val mode     = IO(Input(Bool()))
  val inA      = IO(Input(Bool()))
  val inB      = IO(Input(Bool()))
  val sum_out  = IO(Output(Bool()))
  val carry    = IO(Output(Bool()))
  val out_ready = IO(Output(Bool()))

  override def desiredName: String = "mac16"

  withClockAndReset(clk, (!rst_n).asAsyncReset) {
    val inputBits  = 16
    val outputBits = 24

    // State machine (2 mult stages for 2-stage pipeline)
    val sInput       = 0.U(3.W)
    val sMultStage1  = 1.U(3.W)
    val sMultStage2  = 2.U(3.W)
    val sAdd         = 3.U(3.W)
    val sOutput      = 4.U(3.W)

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

    val multInA = RegInit(0.U(inputBits.W))
    val multInB = RegInit(0.U(inputBits.W))
    val multInputValid = RegInit(false.B)

    val multReg = RegInit(0.U(32.W))

    // Output registers (must be registered to match original RTL timing)
    val outReadyReg = RegInit(false.B)
    val sumOutReg   = RegInit(false.B)

    // 2-stage pipeline Booth multiplier with valid gating
    val mult = Module(new Mult16BoothGated2Stage)
    mult.io.a := multInA
    mult.io.b := multInB
    mult.io.validIn := multInputValid

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

    // Default output register updates
    outReadyReg := false.B
    sumOutReg   := false.B
    multInputValid := false.B

    switch(state) {
      is(sInput) {
        outReadyReg := false.B
        sumOutReg   := false.B
        modeR       := mode

        shiftA := Cat(shiftA(inputBits - 2, 0), inA)
        shiftB := Cat(shiftB(inputBits - 2, 0), inB)

        when(cnt === (inputBits - 1).U) {
          cnt   := 0.U
          state := sMultStage1

          // Latch isolated inputs once
          multInA := Cat(shiftA(inputBits - 2, 0), inA)
          multInB := Cat(shiftB(inputBits - 2, 0), inB)
          multInputValid := true.B
        }.otherwise {
          cnt := cnt + 1.U
        }
      }

      is(sMultStage1) {
        state := sMultStage2
      }

      is(sMultStage2) {
        // Wait for multiplier pipeline to complete (2-stage)
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

        firstOp     := false.B
        outReadyReg := true.B
        sumOutReg   := macResult(outputBits - 1)
        cnt := 0.U
        state := sOutput
      }

      is(sOutput) {
        outReadyReg := true.B
        sumOutReg   := outShiftReg(outputBits - 2)
        outShiftReg := Cat(outShiftReg(outputBits - 2, 0), 0.U(1.W))

        when(cnt === (outputBits - 2).U) {
          cnt         := 0.U
          outReadyReg := false.B  // Set out_ready low (registered output)
          state       := sInput

          when(mode =/= modeR) {
            accum := 0.U
            prevProduct := 0.U
            carryReg := false.B
            firstOp := true.B
          }
        }.otherwise {
          cnt := cnt + 1.U
        }
      }
    }

    // Connect output registers to ports
    out_ready := outReadyReg
    sum_out   := sumOutReg
    carry     := carryReg
  }
}
