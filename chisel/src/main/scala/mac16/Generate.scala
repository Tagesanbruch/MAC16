package mac16

import circt.stage._

object Generate {
  private def getArg(args: Array[String], key: String, default: String): String = {
    val idx = args.indexOf(key)
    if (idx >= 0 && idx < args.length - 1) args(idx + 1) else default
  }

  def main(args: Array[String]): Unit = {
    val exp = getArg(args, "--exp", "exp_d")
    val out = getArg(args, "--out", "vsrc/exp_d")

    def createTop() = exp match {
      case "exp_d" => new mac16.exp_d.Mac16
      case "exp_i" => new mac16.exp_i.Mac16
      case other   => sys.error(s"Unknown exp: $other (use exp_d or exp_i)")
    }

    val chiselStageOptions = Seq(
      chisel3.stage.ChiselGeneratorAnnotation(() => createTop()),
      CIRCTTargetAnnotation(CIRCTTarget.SystemVerilog)
    )

    val firtoolOptions = Seq(
      FirtoolOption("--lowering-options=disallowLocalVariables"),
      FirtoolOption("--disable-all-randomization"),
      FirtoolOption("--strip-debug-info")
    )

    val executeOptions = chiselStageOptions ++ firtoolOptions
    val executeArgs = Array("-td", out)
    
    (new ChiselStage).execute(executeArgs, executeOptions)
  }
}
