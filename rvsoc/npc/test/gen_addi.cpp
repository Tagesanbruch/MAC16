#include <iostream>
#include <fstream>
#include <random>
#include <iomanip>
#include <sstream>

std::string registers[] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};

std::string decode_addi(int imm, int rd, int rs, int pc) {
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << pc << ":";
    ss << "\t" << std::setw(8) << std::setfill('0') << std::hex << (imm << 20 | rs << 15 | 0b000 << 12 | rd << 7 | 0b0010011);
    ss << "\taddi\t" << registers[rd] << ", " << registers[rs] << ", " << imm;
    return ss.str();
}

std::string decodex_addi(int imm, int rd, int rs, int pc) {
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << pc << ":";
    ss << "\t" << std::setw(8) << std::setfill('0') << std::hex << (imm << 20 | rs << 15 | 0b000 << 12 | rd << 7 | 0b0010011);
    ss << "\taddi\tx" << rd << ", x" << rs << ", " << imm;
    return ss.str();
}

int main() {
    std::ofstream hexfile("prog.hex");
    std::ofstream txtfile("prog.txt");
    std::ofstream txtfilex("prog_x.txt");

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> rd_dist(1, 31); // Excluding zero register
    std::uniform_int_distribution<> imm_dist(0, 4095);

    for (int i = 0; i < 100; ++i) {
        int rd = rd_dist(gen);
        int rs = rd_dist(gen);
        int imm = imm_dist(gen);
        int pc = 0x80000000 + i * 4; // Assuming each instruction is 4 bytes

        // RISC-V addi instruction encoding
        unsigned int instruction = (imm << 20) | (rs << 15) | (0b000 << 12) | (rd << 7) | 0b0010011;

        // Write the instruction to the hex file in hexadecimal format
        hexfile << std::hex << std::setw(8) << std::setfill('0') << instruction << std::endl;

        // Write the instruction details to the text files
        txtfile << decode_addi(imm, rd, rs, pc) << std::endl;
        txtfilex << decodex_addi(imm, rd, rs, pc) << std::endl;
    }
    unsigned int instruction_eb = 0x00100073;

    // Write the instruction to the hex file in hexadecimal format
    hexfile << std::hex << std::setw(8) << std::setfill('0') << instruction_eb << std::endl;

    // Write the instruction details to the text files
    // txtfile << decode_addi(imm, rd, rs, pc) << std::endl;
    // txtfilex << decodex_addi(imm, rd, rs, pc) << std::endl;
    std::cout << "100 RISC-V addi instructions and their details have been written to output.hex, output.txt, and output_x.txt." << std::endl;
    return 0;
}
