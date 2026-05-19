import sys
import json
import subprocess

def inspect_container(container_id):
    try:
        # Get raw JSON from docker inspect
        result = subprocess.run(
            ["docker", "inspect", container_id],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)[0]

        # Parse key fields
        name = data.get("Name", "N/A").strip("/")
        state = data.get("State", {}).get("Status", "Unknown")
        ip = data.get("NetworkSettings", {}).get("IPAddress", "N/A")

        # If IP is empty, check networks
        if not ip:
            networks = data.get("NetworkSettings", {}).get("Networks", {})
            for net in networks.values():
                ip = net.get("IPAddress", "")
                if ip: break

        ports = data.get("NetworkSettings", {}).get("Ports", {})
        env = data.get("Config", {}).get("Env", [])
        volumes = data.get("Mounts", [])

        # Display Summary
        print(f"\n--- Container Inspection: {name} ---")
        print(f"ID:     {data.get('Id', '')[:12]}")
        print(f"Status: {state}")
        print(f"IP:     {ip}")

        print("\n[Ports]")
        if not ports:
            print("  None")
        else:
            for container_port, host_bindings in ports.items():
                if host_bindings:
                    for binding in host_bindings:
                        print(f"  {binding.get('HostPort')} -> {container_port}")
                else:
                    print(f"  {container_port}")

        print("\n[Volumes/Mounts]")
        if not volumes:
            print("  None")
        else:
            for v in volumes:
                print(f"  {v.get('Source')} -> {v.get('Destination')} ({v.get('Type')})")

        print("\n[Environment Variables] (Top 10)")
        if not env:
            print("  None")
        else:
            for e in env[:10]:
                print(f"  {e}")
            if len(env) > 10:
                print(f"  ... (+{len(env)-10} more)")

    except subprocess.CalledProcessError:
        print("Error: Could not inspect container.")
    except (json.JSONDecodeError, IndexError):
        print("Error: Failed to parse Docker output.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 inspect_viewer.py <container_id_or_name>")
        sys.exit(1)

    inspect_container(sys.argv[1])
