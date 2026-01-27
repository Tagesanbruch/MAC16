package mac16

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import mac16.common._
import scala.util.Random

class CSATest extends AnyFlatSpec with ChiselScalatestTester {
  behavior of "CSA (3:2 Compressor)"

  it should "compute sum and carry correctly for all 3-bit combinations" in {
    test(new CSA(1)) { c =>
      // Test all 8 combinations of 3 single-bit inputs
      for (a <- 0 to 1; b <- 0 to 1; cin <- 0 to 1) {
        c.io.a.poke(a.U)
        c.io.b.poke(b.U)
        c.io.c.poke(cin.U)
        
        val expectedSum = (a + b + cin) % 2
        val expectedCarry = (a + b + cin) / 2
        
        c.io.sum.expect(expectedSum.U, s"sum failed for a=$a, b=$b, c=$cin")
        c.io.carry.expect(expectedCarry.U, s"carry failed for a=$a, b=$b, c=$cin")
      }
    }
  }

  it should "work correctly for multi-bit inputs" in {
    test(new CSA(16)) { c =>
      val r = new Random(42)
      for (_ <- 0 until 100) {
        val a = r.nextInt(0x10000)
        val b = r.nextInt(0x10000)
        val cin = r.nextInt(0x10000)
        
        c.io.a.poke(a.U)
        c.io.b.poke(b.U)
        c.io.c.poke(cin.U)
        
        // CSA produces: a + b + c = sum + 2*carry
        val sum = c.io.sum.peek().litValue.toInt
        val carry = c.io.carry.peek().litValue.toInt
        
        // Verify: a + b + c == sum + 2*carry (considering overflow)
        val actualSum = (sum.toLong + (carry.toLong << 1)) & 0x1FFFFL
        val expectedSum = (a.toLong + b.toLong + cin.toLong) & 0x1FFFFL
        
        assert(actualSum == expectedSum, 
          s"CSA failed: a=$a, b=$b, c=$cin => sum=$sum, carry=$carry")
      }
    }
  }

  it should "verify XOR for sum bits" in {
    test(new CSA(8)) { c =>
      // Verify sum = a ^ b ^ c
      val testCases = Seq(
        (0xFF, 0x00, 0x00, 0xFF),
        (0xAA, 0x55, 0x00, 0xFF),
        (0xAA, 0x55, 0xFF, 0x00),
        (0x12, 0x34, 0x56, 0x12 ^ 0x34 ^ 0x56)
      )
      for ((a, b, cin, expectedSum) <- testCases) {
        c.io.a.poke(a.U)
        c.io.b.poke(b.U)
        c.io.c.poke(cin.U)
        c.io.sum.expect(expectedSum.U)
      }
    }
  }
}
