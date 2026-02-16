#!/usr/bin/env python3
import json
import subprocess
import sys
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
    
    # Simple chunking of the sorted list
    # Since the list is topologically sorted (leaves first),
    # Chunk 0 will have leaves, Chunk N will have roots.
    # This is perfect for sequential stages.
    
    k, m = divmod(len(data), num_chunks)
    return [data[i * k + min(i, m) : (i + 1) * k + min(i + 1, m)] for i in range(num_chunks)]

def main():
    if len(sys.argv) < 2:
        print("Usage: generate-build-matrix.py <target_element> [num_chunks]", file=sys.stderr)
        sys.exit(1)

    target = sys.argv[1]
    num_chunks = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    
    print(f"Generating build plan for {target} with {num_chunks} chunks...", file=sys.stderr)
    
    elements = get_build_plan(target)
    print(f"Found {len(elements)} elements to build.", file=sys.stderr)
    
    chunks = chunk_list(elements, num_chunks)
    
    # Output JSON for GHA
    # We produce a map where keys are 'chunk1', 'chunk2', etc.
    output = {}
    for i, chunk in enumerate(chunks):
        # Join with space for passing to bst build
        output[f"chunk{i+1}"] = " ".join(chunk)
        print(f"Chunk {i+1}: {len(chunk)} elements", file=sys.stderr)

    print(json.dumps(output))

if __name__ == "__main__":
    main()
