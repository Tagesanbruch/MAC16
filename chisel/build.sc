import mill._
import scalalib._

val chiselVersion = "6.5.0"
val chiseltestVersion = "6.0.0"
val defaultScalaVersion = "2.13.12"
val pwd = os.Path(sys.env("MILL_WORKSPACE_ROOT"))

object mac16 extends ScalaModule {
  override def scalaVersion = defaultScalaVersion
  override def millSourcePath = pwd
  override def sources = T.sources(millSourcePath / "src" / "main" / "scala")
  override def scalacOptions = super.scalacOptions() ++
    Agg("-language:reflectiveCalls", "-Ymacro-annotations", "-deprecation", "-feature", "-Xcheckinit")
  override def ivyDeps = super.ivyDeps() ++ Agg(
    ivy"org.chipsalliance::chisel:${chiselVersion}"
  )
  override def scalacPluginIvyDeps = super.scalacPluginIvyDeps() ++ Agg(
    ivy"org.chipsalliance:::chisel-plugin:${chiselVersion}"
  )
  def mainClass = Some("mac16.Generate")

  object test extends ScalaTests with TestModule.ScalaTest {
    override def sources = T.sources(pwd / "src" / "test" / "scala")
    override def ivyDeps = super.ivyDeps() ++ Agg(
      ivy"org.scalatest::scalatest:3.2.17",
      ivy"edu.berkeley.cs::chiseltest:${chiseltestVersion}"
    )
  }
}
