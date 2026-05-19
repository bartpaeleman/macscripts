import json
import sys
import os

def interactive_toggle(config_path):
    if not os.path.exists(config_path):
        print(f"Error: {config_path} not found.")
        sys.exit(1)

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error reading config: {e}")
        sys.exit(1)

    sources = config.get('sources', [])
    if not sources:
        print("No sources found in config.json.")
        sys.exit(0)

    page_size = 20
    current_page = 0
    total_sources = len(sources)

    while True:
        total_pages = (total_sources + page_size - 1) // page_size
        start_idx = current_page * page_size
        end_idx = min(start_idx + page_size, total_sources)

        print(f"\n=== Threat Intel Feed Manager (Page {current_page + 1}/{total_pages}) ===")
        for i in range(start_idx, end_idx):
            s = sources[i]
            is_active = s.get('active', True)
            status = "[ON] " if is_active else "[OFF]"
            print(f"{i+1}) {status} {s.get('name', 'Unknown')}")

        print("\nCommands:")
        print("  [Number] Toggle feed")
        print("  [n] Next Page | [p] Previous Page")
        print("  [a] Toggle All ON | [o] Toggle All OFF")
        print("  [q] Save and Exit")

        try:
            choice = input("\nEnter command: ").strip().lower()
            if not choice:
                continue

            if choice == 'q':
                break
            elif choice == 'n':
                if current_page < total_pages - 1:
                    current_page += 1
            elif choice == 'p':
                if current_page > 0:
                    current_page -= 1
            elif choice == 'a':
                for s in sources: s['active'] = True
                print("All feeds toggled ON.")
            elif choice == 'o':
                for s in sources: s['active'] = False
                print("All feeds toggled OFF.")
            else:
                try:
                    choice_idx = int(choice)
                    if 1 <= choice_idx <= total_sources:
                        src = sources[choice_idx - 1]
                        current_state = src.get('active', True)
                        src['active'] = not current_state
                        print(f"Toggled '{src.get('name')}' to {'ON' if not current_state else 'OFF'}")
                    else:
                        print("Invalid number.")
                except ValueError:
                    print("Invalid command. Please use a number, 'n', 'p', 'a', 'o', or 'q'.")

        except KeyboardInterrupt:
            print("\nExiting without saving.")
            sys.exit(0)

    # Save changes
    config['sources'] = sources
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2)
        print("\nConfig updated successfully.")
    except Exception as e:
        print(f"Error writing config: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 interactive_toggle.py <config_path>")
        sys.exit(1)

    interactive_toggle(sys.argv[1])
