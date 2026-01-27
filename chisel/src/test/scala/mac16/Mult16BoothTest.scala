package mac16

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import mac16.exp_d._
import scala.util.Random

class Mult16BoothTest extends AnyFlatSpec with ChiselScalatestTester {
  behavior of "Mult16Booth (3-stage pipelined Booth multiplier)"

  it should "multiply small unsigned numbers correctly" in {
    test(new Mult16Booth).withAnnotations(Seq(WriteVcdAnnotation)) { c =>
      val testCases = Seq(
        (2, 3, 6),
        (5, 7, 35),
        (8, 30, 240),     // Added this test case
        (10, 10, 100),
        (100, 100, 10000),
        (255, 255, 65025)
      )
      
      for ((a, b, expected) <- testCases) {
        // Apply inputs and trigger
        c.io.a.poke(a.U)
        c.io.b.poke(b.U)
        c.io.validIn.poke(true.B)
        c.clock.step(1)
        c.io.validIn.poke(false.B)
        
        // Wait for pipeline (3 stages)
        var cycles = 0
        while (!c.io.validOut.peek().litToBoolean && cycles < 10) {
          c.clock.step(1)
          cycles += 1
        }
        
        assert(c.io.validOut.peek().litToBoolean, s"validOut not asserted for $a * $b")
        
        val result = c.io.product.peek().litValue.toLong
        assert(result == expected, 
          s"Multiply failed: $a * $b = $result, expected $expected")
        
        c.clock.step(1)
      }
    }
  }

  it should "multiply with one operand being 1" in {
    test(new Mult16Booth).withAnnotations(Seq(WriteVcdAnnotation)) { c =>
      val testCases = Seq(
        (1, 1, 1L),
        (100, 1, 100L),
        (1, 100, 100L),
        (1000, 1, 1000L)
      )
      
      for ((a, b, expected) <- testCases) {
        c.io.a.poke(a.U)
        c.io.b.poke(b.U)
        c.io.validIn.poke(true.B)
        c.clock.step(1)
        c.io.validIn.poke(false.B)
        
        // Wait for valid
        var cycles = 0
        while (!c.io.validOut.peek().litToBoolean && cycles < 10) {
          c.clock.step(1)
          cycles += 1
        }
        
        val result = c.io.product.peek().litValue.toLong
        println(s"Test: $a * $b = $result (expected $expected)")
        assert(result == expected,
          s"Multiply failed: $a * $b = $result, expected $expected")
        
        c.clock.step(1)
      }
    }
  }

  it should "multiply medium numbers correctly" in {
    test(new Mult16Booth) { c =>
      val testCases = Seq(
        (100, 200, 20000L),
        (1000, 10, 10000L),
        (256, 256, 65536L)
      )
      
      for ((a, b, expected) <- testCases) {
        c.io.a.poke(a.U)
        c.io.b.poke(b.U)
        c.io.validIn.poke(true.B)
        c.clock.step(1)
        c.io.validIn.poke(false.B)
        
        var cycles = 0
        while (!c.io.validOut.peek().litToBoolean && cycles < 10) {
          c.clock.step(1)
          cycles += 1
        }
        
        val result = c.io.product.peek().litValue.toLong
        println(s"Medium test: $a * $b = $result (expected $expected)")
        assert(result == expected,
          s"Multiply failed: $a * $b = $result, expected $expected")
        
        c.clock.step(1)
      }
    }
  }

  it should "handle zero multiplication" in {
    test(new Mult16Booth) { c =>
      c.io.a.poke(0.U)
      c.io.b.poke(12345.U)
      c.io.validIn.poke(true.B)
      c.clock.step(1)
      c.io.validIn.poke(false.B)
      
      var cycles = 0
      while (!c.io.validOut.peek().litToBoolean && cycles < 10) {
        c.clock.step(1)
        cycles += 1
      }
      
      c.io.product.expect(0.U)
    }
  }

  it should "complete in exactly 3 cycles" in {
    test(new Mult16Booth) { c =>
      c.io.a.poke(100.U)
      c.io.b.poke(200.U)
      c.io.validIn.poke(true.B)
      
      // Cycle 0: input registered to S1
      c.clock.step(1)
      c.io.validIn.poke(false.B)
      assert(!c.io.validOut.peek().litToBoolean, "Should not be valid after 1 cycle")
      
      // Cycle 1: S1 -> S2
      c.clock.step(1)
      assert(!c.io.validOut.peek().litToBoolean, "Should not be valid after 2 cycles")
      
      // Cycle 2: S2 -> S3 (output)
      c.clock.step(1)
      assert(c.io.validOut.peek().litToBoolean, "Should be valid after 3 cycles")
      
      c.io.product.expect(20000.U)
    }
  }
}
