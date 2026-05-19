
import sys
import os
import re
import datetime

# --- HELPER FUNCTIONS ---

def calculate_hash(filepath):
    try:
        import hashlib
    except ImportError:
        print("Error: hashlib module missing. Cannot calculate checksums.")
        return None

    hash_md5 = hashlib.md5()
    try:
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    except Exception as e:
        print("Error hashing {}: {}".format(filepath, e))
        return None

def bulk_rename(directory, pattern, replacement, dry_run=False):
    print("Bulk Renaming in {} (Pattern: '{}' -> '{}')".format(directory, pattern, replacement))
    count = 0
    try:
        regex = re.compile(pattern)
        for root, dirs, files in os.walk(directory):
            for filename in files:
                if regex.search(filename):
                    new_filename = regex.sub(replacement, filename)
                    # Handle date placeholder {date}
                    if "{date}" in new_filename:
                        today = datetime.date.today().strftime("%Y-%m-%d")
                        new_filename = new_filename.replace("{date}", today)

                    old_path = os.path.join(root, filename)
                    new_path = os.path.join(root, new_filename)

                    if old_path != new_path:
                        print("  {} -> {}".format(filename, new_filename))
                        if not dry_run:
                            try:
                                os.rename(old_path, new_path)
                            except OSError as e:
                                print("    Error: {}".format(e))
                        count += 1
    except re.error as e:
        print("Invalid Regex: {}".format(e))
        return

    if dry_run:
        print("Dry run complete. {} files would be renamed.".format(count))
    else:
        print("Renamed {} files.".format(count))

def create_structure(template_file):
    print("Creating structure from {}...".format(template_file))
    try:
        with open(template_file, 'r') as f:
            lines = f.readlines()

        for line in lines:
            path = line.strip()
            if path:
                if not os.path.exists(path):
                    try:
                        os.makedirs(path)
                        print("  Created: {}".format(path))
                    except OSError as e:
                        print("  Error creating {}: {}".format(path, e))
                else:
                    print("  Exists: {}".format(path))
    except Exception as e:
        print("Error reading template: {}".format(e))

def archive_directory(directory, archive_type):
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = os.path.basename(os.path.normpath(directory))
    archive_name = "{}_{}".format(base_name, timestamp)

    print("Archiving {} to {}.{}...".format(directory, archive_name, archive_type))

    if archive_type == 'zip':
        try:
            import zipfile
        except ImportError:
            print("Error: zipfile module missing. Cannot create .zip archive.")
            return

        try:
            with zipfile.ZipFile("{}.zip".format(archive_name), "w", zipfile.ZIP_DEFLATED) as zf:
                for root, dirs, files in os.walk(directory):
                    for file in files:
                        abs_path = os.path.join(root, file)
                        rel_path = os.path.relpath(abs_path, directory)
                        zf.write(abs_path, rel_path)
            print("Created {}.zip".format(archive_name))
        except Exception as e:
            print("Error creating zip: {}".format(e))

    elif archive_type == 'tar':
        try:
            import tarfile
        except ImportError:
            print("Error: tarfile module missing. Cannot create .tar.gz archive.")
            return

        try:
            with tarfile.open("{}.tar.gz".format(archive_name), "w:gz") as tf:
                tf.add(directory, arcname=base_name)
            print("Created {}.tar.gz".format(archive_name))
        except Exception as e:
            print("Error creating tar: {}".format(e))

def cleanup(directory, delete_dupes=False, delete_empty=False, delete_junk=False, dry_run=False):
    print("Cleaning up {}...".format(directory))

    if delete_dupes:
        print("Scanning for duplicates (Size + MD5)...")
        # Pass 1: Group by size
        files_by_size = {}
        for root, dirs, files in os.walk(directory):
            for file in files:
                filepath = os.path.join(root, file)
                try:
                    size = os.path.getsize(filepath)
                    if size in files_by_size:
                        files_by_size[size].append(filepath)
                    else:
                        files_by_size[size] = [filepath]
                except OSError:
                    continue

        # Pass 2: Hash only potential dupes
        hashes = {}
        dupes_found = 0
        for size, paths in files_by_size.items():
            if len(paths) > 1:
                for filepath in paths:
                    file_hash = calculate_hash(filepath)
                    if file_hash:
                        if file_hash in hashes:
                            print("  Duplicate found: {} (matches {})".format(filepath, hashes[file_hash]))
                            dupes_found += 1
                            if not dry_run:
                                try:
                                    os.remove(filepath)
                                    print("    Deleted.")
                                except OSError as e:
                                    print("    Error deleting: {}".format(e))
                        else:
                            hashes[file_hash] = filepath

        if dry_run:
            print("Dry run: {} duplicates found.".format(dupes_found))

    if delete_junk:
        print("Scanning for junk files (.DS_Store, Thumbs.db, ._*)")
        junk_files = []
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file in [".DS_Store", "Thumbs.db"] or file.startswith("._"):
                    junk_files.append(os.path.join(root, file))

        print("Found {} junk files.".format(len(junk_files)))
        for jf in junk_files:
            print("  {}".format(jf))
            if not dry_run:
                try:
                    os.remove(jf)
                    print("    Deleted.")
                except OSError as e:
                    print("    Error deleting: {}".format(e))

    if delete_empty:
        print("Scanning for empty directories...")
        empty_found = 0
        # Walk bottom-up
        for root, dirs, files in os.walk(directory, topdown=False):
            if not os.listdir(root):
                print("  Empty directory: {}".format(root))
                empty_found += 1
                if not dry_run:
                    try:
                        os.rmdir(root)
                        print("    Removed.")
                    except OSError as e:
                        print("    Error removing: {}".format(e))
        if dry_run:
            print("Dry run: {} empty directories found.".format(empty_found))

def compare_files(file1, file2):
    print("Comparing {} vs {}...".format(file1, file2))
    h1 = calculate_hash(file1)
    h2 = calculate_hash(file2)

    if h1 is None or h2 is None:
        print("Comparison failed due to missing hash module.")
        return

    if h1 == h2:
        print("Files are IDENTICAL (Match by MD5).")
    else:
        print("Files are DIFFERENT.")
        print("  {}: {}".format(file1, h1))
        print("  {}: {}".format(file2, h2))

# --- MANUAL ARGUMENT PARSING ---

def print_usage():
    print("Usage: python file_manager.py <command> [args...]")
    print("Commands:")
    print("  rename <dir> <pattern> <replace> [--run]")
    print("  structure <template_file>")
    print("  archive <dir> [--type zip|tar]")
    print("  cleanup <dir> [--dupes] [--empty] [--junk] [--run]")
    print("  compare <file1> <file2>")

def main():
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    command = sys.argv[1]
    args = sys.argv[2:]

    if command == 'rename':
        if len(args) < 3:
            print("Error: Missing arguments for rename.")
            print_usage()
            sys.exit(1)

        directory = args[0]
        pattern = args[1]
        replacement = args[2]

        run_flag = False
        if len(args) > 3 and args[3] == '--run':
            run_flag = True

        bulk_rename(directory, pattern, replacement, dry_run=not run_flag)

    elif command == 'structure':
        if len(args) < 1:
            print("Error: Missing template file.")
            sys.exit(1)
        create_structure(args[0])

    elif command == 'archive':
        if len(args) < 1:
            print("Error: Missing directory.")
            sys.exit(1)

        directory = args[0]
        archive_type = 'zip'

        # Simple flag parsing
        if '--type' in args:
            idx = args.index('--type')
            if idx + 1 < len(args):
                val = args[idx+1]
                if val in ['zip', 'tar']:
                    archive_type = val

        archive_directory(directory, archive_type)

    elif command == 'cleanup':
        if len(args) < 1:
            print("Error: Missing directory.")
            sys.exit(1)

        directory = args[0]
        delete_dupes = '--dupes' in args
        delete_empty = '--empty' in args
        delete_junk = '--junk' in args
        run_flag = '--run' in args

        cleanup(directory, delete_dupes=delete_dupes, delete_empty=delete_empty, delete_junk=delete_junk, dry_run=not run_flag)

    elif command == 'compare':
        if len(args) < 2:
            print("Error: Missing files.")
            sys.exit(1)
        compare_files(args[0], args[1])

    else:
        print("Unknown command: {}".format(command))
        print_usage()
        sys.exit(1)

if __name__ == "__main__":
    main()
