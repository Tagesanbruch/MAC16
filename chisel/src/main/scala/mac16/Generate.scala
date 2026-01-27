package mac16

import circt.stage.ChiselStage

object Generate {
  private def getArg(args: Array[String], key: String, default: String): String = {
    val idx = args.indexOf(key)
    if (idx >= 0 && idx < args.length - 1) args(idx + 1) else default
  }

  def main(args: Array[String]): Unit = {
    val exp = getArg(args, "--exp", "exp_d")
    val out = getArg(args, "--out", "vsrc/exp_d")

    exp match {
      case "exp_d" =>
        ChiselStage.emitSystemVerilogFile(
          new mac16.exp_d.Mac16,
          Array("--target-dir", out)
        )
      case "exp_i" =>
        ChiselStage.emitSystemVerilogFile(
          new mac16.exp_i.Mac16,
          Array("--target-dir", out)
        )
      case other =>
        sys.error(s"Unknown exp: $other (use exp_d or exp_i)")
    }
  }
}
