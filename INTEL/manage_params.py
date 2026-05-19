import json
import sys
import os

def manage_params(config_path):
    if not os.path.exists(config_path):
        print(f"Error: {config_path} not found.")
        sys.exit(1)

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error reading config: {e}")
        sys.exit(1)

    if 'parameters' not in config:
        config['parameters'] = {}

    params = config['parameters']

    while True:
        current_out = params.get('output_dir', 'public')
        current_sev = params.get('minimum_severity', 'High')
        current_lookback = params.get('lookback_days', 7)
        current_strict = params.get('strict_filtering', True)

        print("\n=== Manage Configuration Parameters ===")
        print(f"1) Output Directory: {current_out}")
        print(f"2) Minimum Severity: {current_sev}")
        print(f"3) Lookback Days:    {current_lookback}")
        print(f"4) Strict Filtering: {current_strict}")
        print("---------------------------------------")
        print("q) Save and Exit")

        choice = input("\nEnter number to edit (or 'q' to exit): ").strip().lower()

        if choice == 'q':
            break
        elif choice == '1':
            new_val = input(f"Enter new Output Directory [{current_out}]: ").strip()
            if new_val: params['output_dir'] = new_val
        elif choice == '2':
            new_val = input(f"Enter new Minimum Severity [{current_sev}]: ").strip()
            if new_val: params['minimum_severity'] = new_val
        elif choice == '3':
            new_val = input(f"Enter new Lookback Days [{current_lookback}]: ").strip()
            if new_val:
                try:
                    params['lookback_days'] = int(new_val)
                except ValueError:
                    print("Error: Lookback Days must be an integer.")
        elif choice == '4':
            new_val = input(f"Strict Filtering (true/false) [{current_strict}]: ").strip().lower()
            if new_val in ['true', 't', 'yes', 'y', '1']:
                params['strict_filtering'] = True
            elif new_val in ['false', 'f', 'no', 'n', '0']:
                params['strict_filtering'] = False
        else:
            print("Invalid choice.")

    config['parameters'] = params

    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2)
        print("\nParameters updated successfully.")
    except Exception as e:
        print(f"Error writing config: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 manage_params.py <config_path>")
        sys.exit(1)

    manage_params(sys.argv[1])
