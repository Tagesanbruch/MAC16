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
    
    // Output registers (must be registered to match original RTL timing)
    val outReadyReg = RegInit(false.B)
    val sumOutReg   = RegInit(false.B)

    // Operand isolation - only enable multiplier during mult stages
    val multEnable = (state === sMultStage1 || state === sMultStage2 || state === sMultStage3)

    // 3-stage pipeline Booth multiplier (matches original RTL)
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

    // Default output register updates
    outReadyReg := false.B
    sumOutReg   := false.B

    switch(state) {
      is(sInput) {
        outReadyReg := false.B
        sumOutReg   := false.B
        modeR       := mode
        multValidIn := false.B

        val shiftANext = Cat(shiftA(inputBits - 2, 0), inA)
        val shiftBNext = Cat(shiftB(inputBits - 2, 0), inB)
        shiftA := shiftANext
        shiftB := shiftBNext

        when(cnt === (inputBits - 1).U) {
          // shiftA/shiftB will have the complete value after this clock edge
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
        // Wait for multiplier pipeline to complete (3-stage)
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
          cnt    := 0.U
          outReadyReg := false.B  // Set out_ready low (registered output like original RTL)
          state  := sInput
          shiftA := 0.U
          shiftB := 0.U

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
