#!/usr/bin/env python3
import json
import subprocess
import sys
import os
import math

def get_build_plan(target):
    """
    Returns a list of elements to build, topologically sorted (stage order),
    excluding those that are already cached.
    """
    cmd = [
        "bst", "show",
        "--deps", "all",
        "--order", "stage",
        "--format", "%{name}||%{state}",
        target
    ]
    
    try:
        output = subprocess.check_output(cmd, text=True).strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running bst show: {e}", file=sys.stderr)
        sys.exit(1)

    elements_to_build = []
    for line in output.splitlines():
        if not line:
            continue
        try:
            name, state = line.split("||")
            # We want to build things that are buildable, waiting, or inconsistent.
            # We skip 'cached'.
            if state.strip() != "cached":
                elements_to_build.append(name.strip())
        except ValueError:
            print(f"Skipping malformed line: {line}", file=sys.stderr)

    return elements_to_build

def chunk_list(data, num_chunks):
    """
    Splits a list into roughly equal chunks.
    """
    if not data:
        return [[] for _ in range(num_chunks)]
    
    # Round-robin distribution (Stride slicing)
    # This spreads the tail (heavy leaf nodes) across all chunks
    # instead of clumping them in the last chunk.
    return [data[i::num_chunks] for i in range(num_chunks)]

def main():
    if len(sys.argv) < 2:
        print("Usage: generate-build-matrix.py <target_element> [num_chunks]", file=sys.stderr)
        sys.exit(1)

    target = sys.argv[1]
    num_chunks = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    core_split = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    
    print(f"Generating build plan for {target} with {num_chunks} chunks (core split: {core_split})...", file=sys.stderr)
    
    elements = get_build_plan(target)
    
    # Separate the final target from the dependencies
    elements = [e for e in elements if not e.endswith(target)]
    
    print(f"Found {len(elements)} elements to build (excluding final target).", file=sys.stderr)

    # Split into Core and Leaves
    core_elements = []
    if core_split > 0 and len(elements) > core_split:
        core_elements = elements[:core_split]
        elements = elements[core_split:]
        print(f"Splitting {len(core_elements)} elements into Core stage.", file=sys.stderr)
    
    chunks = chunk_list(elements, num_chunks)
    
    # Output JSON for GHA
    matrix_map = {}
    for i, chunk in enumerate(chunks):
        if not chunk:
            continue
            
        representative = chunk[-1]
        element_path = representative.split(':')[-1]
        base = os.path.basename(element_path)
        safe_name = base.replace('.bst', '').replace('/', '-').replace(':', '-')
        safe_name = safe_name[:30]
        
        key = f"chunk{i+1}-{safe_name}"
        matrix_map[key] = " ".join(chunk)
        print(f"{key}: {len(chunk)} elements (ends with {representative})", file=sys.stderr)

    final_output = {
        "core": " ".join(core_elements),
        "matrix": matrix_map,
        "final": target
    }
    print(json.dumps(final_output))

if __name__ == "__main__":
    main()
