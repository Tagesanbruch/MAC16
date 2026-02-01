#!/usr/bin/env python3
"""
Systolic Array 16x16 Reference Model & Test Vector Generator

Generates test vectors for verification and provides golden reference.
"""

import numpy as np
import os
import argparse

def generate_matrix(size=16, mode='random', seed=None, signed=True):
    """Generate a test matrix."""
    if seed is not None:
        np.random.seed(seed)
    
    if mode == 'random':
        if signed:
            return np.random.randint(-32768, 32768, (size, size), dtype=np.int32)
        else:
            return np.random.randint(0, 65536, (size, size), dtype=np.int32)
    elif mode == 'identity':
        return np.eye(size, dtype=np.int32)
    elif mode == 'zeros':
        return np.zeros((size, size), dtype=np.int32)
    elif mode == 'ones':
        return np.ones((size, size), dtype=np.int32)
    elif mode == 'sequential':
        return np.arange(size*size, dtype=np.int32).reshape(size, size)
    elif mode == 'small':
        return np.random.randint(-128, 128, (size, size), dtype=np.int32)
    else:
        raise ValueError(f"Unknown mode: {mode}")

def matmul_reference(A, B):
    """Compute reference matrix multiplication."""
    return np.matmul(A.astype(np.int64), B.astype(np.int64))

def write_hex_file(filepath, matrix, width=16):
    """Write matrix to hex file (row-major order)."""
    with open(filepath, 'w') as f:
        for row in matrix:
            for val in row:
                # Handle signed values
                if val < 0:
                    val = val + (1 << width)
                f.write(f"{val:0{width//4}x}\n")

def write_csv_file(filepath, matrix):
    """Write matrix to CSV file."""
    np.savetxt(filepath, matrix, fmt='%d', delimiter=',')

def generate_test_vectors(output_dir, num_tests=5, size=16):
    """Generate multiple test cases."""
    os.makedirs(output_dir, exist_ok=True)
    
    test_configs = [
        ('zeros', 'zeros', 0),
        ('identity', 'identity', 1),
        ('small', 'small', 42),
        ('random', 'random', 123),
        ('random', 'random', 456),
    ]
    
    summary = []
    
    for i, (mode_a, mode_b, seed) in enumerate(test_configs[:num_tests]):
        A = generate_matrix(size, mode_a, seed)
        B = generate_matrix(size, mode_b, seed + 1000 if seed else None)
        C = matmul_reference(A, B)
        
        # Write hex files
        write_hex_file(f"{output_dir}/test{i}_a.hex", A)
        write_hex_file(f"{output_dir}/test{i}_b.hex", B)
        write_hex_file(f"{output_dir}/test{i}_c.hex", C, width=40)
        
        # Write CSV for debugging
        write_csv_file(f"{output_dir}/test{i}_a.csv", A)
        write_csv_file(f"{output_dir}/test{i}_b.csv", B)
        write_csv_file(f"{output_dir}/test{i}_c.csv", C)
        
        summary.append({
            'test': i,
            'mode_a': mode_a,
            'mode_b': mode_b,
            'seed': seed,
            'c_min': int(C.min()),
            'c_max': int(C.max()),
            'c_checksum': int(C.sum())
        })
        
        print(f"Generated test{i}: A({mode_a}) x B({mode_b}), C range: [{C.min()}, {C.max()}]")
    
    # Write summary
    with open(f"{output_dir}/test_summary.txt", 'w') as f:
        f.write("Test Vector Summary\n")
        f.write("=" * 60 + "\n")
        for s in summary:
            f.write(f"Test {s['test']}: A={s['mode_a']}, B={s['mode_b']}, seed={s['seed']}\n")
            f.write(f"  C range: [{s['c_min']}, {s['c_max']}]\n")
            f.write(f"  C checksum: {s['c_checksum']}\n")
    
    return summary

def verify_single(A, B, C_dut):
    """Verify DUT output against reference."""
    C_ref = matmul_reference(A, B)
    errors = np.sum(C_ref != C_dut)
    if errors > 0:
        print(f"MISMATCH: {errors} elements differ")
        diff_idx = np.where(C_ref != C_dut)
        for i in range(min(5, errors)):
            r, c = diff_idx[0][i], diff_idx[1][i]
            print(f"  [{r},{c}]: expected {C_ref[r,c]}, got {C_dut[r,c]}")
        return False
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='SA16x16 Test Vector Generator')
    parser.add_argument('-o', '--output', default='vectors', help='Output directory')
    parser.add_argument('-n', '--num', type=int, default=5, help='Number of tests')
    parser.add_argument('-s', '--size', type=int, default=16, help='Matrix size')
    args = parser.parse_args()
    
    generate_test_vectors(args.output, args.num, args.size)
    print(f"\nTest vectors generated in: {args.output}/")

