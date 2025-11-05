import json

# Generate the AddAllocations message with 5000 dummy entries
def generate_add_allocations_json():
    allocations = []
    
    # Create 5000 dummy entries
    for i in range(1, 5001):  # 1 to 5000 inclusive
        # Generate a dummy address: mantra1dummy + zero-padded index
        address = f"mantra1dummy{'{:040d}'.format(i)}"
        # Generate an amount: e.g., 1000, 2000, ..., 5000000
        amount = str(i * 1000)  # Convert to string to match Uint128 serialization
        allocations.append([address, amount])
    
    # Create the message structure
    msg = {
        "add_allocations": {
            "allocations": allocations
        }
    }
    
    return msg

# Generate and save the JSON
def main():
    msg = generate_add_allocations_json()
    
    # Serialize to JSON with proper formatting
    json_output = json.dumps(msg, indent=2)
    
    # Save to a file
    with open("add_allocations.json", "w") as f:
        f.write(json_output)
    
    # Optionally, print the first few entries to verify
    print("First 5 entries of the JSON:")
    print(json.dumps(msg["add_allocations"]["allocations"][:5], indent=2))
    print(f"\nTotal entries: {len(msg['add_allocations']['allocations'])}")
    print("JSON saved to 'add_allocations.json'")

if __name__ == "__main__":
    main()
