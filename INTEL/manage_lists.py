import json
import sys
import os

def manage_list(config_path, list_key):
    if not os.path.exists(config_path):
        print(f"Error: {config_path} not found.")
        sys.exit(1)

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error reading config: {e}")
        sys.exit(1)

    items = config.get(list_key, [])

    while True:
        print(f"\n=== Manage {list_key.capitalize()} ===")
        if not items:
            print("  (Empty List)")
        else:
            for i, item in enumerate(items):
                print(f"{i+1}) {item}")

        print("\nCommands:")
        print("  [add <text>] Add new item")
        print("  [del <number>] Delete item")
        print("  [q] Save and Exit")

        try:
            choice = input("\nEnter command: ").strip()
            if not choice:
                continue

            parts = choice.split(' ', 1)
            cmd = parts[0].lower()

            if cmd == 'q':
                break
            elif cmd == 'add' and len(parts) > 1:
                new_item = parts[1].strip()
                if new_item and new_item not in items:
                    items.append(new_item)
                    print(f"Added: {new_item}")
                else:
                    print("Item empty or already exists.")
            elif cmd == 'del' and len(parts) > 1:
                try:
                    idx = int(parts[1]) - 1
                    if 0 <= idx < len(items):
                        removed = items.pop(idx)
                        print(f"Removed: {removed}")
                    else:
                        print("Invalid number.")
                except ValueError:
                    print("Invalid number format.")
            else:
                print("Invalid command. Use 'add <text>', 'del <number>', or 'q'.")

        except KeyboardInterrupt:
            print("\nExiting without saving.")
            sys.exit(0)

    # Save changes
    config[list_key] = items
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2)
        print("\nConfig updated successfully.")
    except Exception as e:
        print(f"Error writing config: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 manage_lists.py <config_path> <list_key>")
        sys.exit(1)

    manage_list(sys.argv[1], sys.argv[2])
