import sys
import os
import datetime

def generate_readme(project_name, author, description, path):
    content = f"""# {project_name}

{description}

## Project Overview

*   **Author**: {author}
*   **Created**: {datetime.date.today()}
*   **Status**: Development

## Directory Structure

*   `assets/`: CSS, JS, and Image resources.
*   `includes/`: PHP includes and partials.
*   `config/`: Configuration files.
*   `index.php`: Application entry point.

## Installation

1.  Clone the repository.
2.  Configure `config/config.php`.
3.  Deploy to your web server.

## License

Copyright (c) {datetime.date.today().year} {author}. All rights reserved.
"""

    file_path = os.path.join(path, "README.md")
    try:
        with open(file_path, "w") as f:
            f.write(content)
        print(f"Generated README.md at {file_path}")
    except Exception as e:
        print(f"Error generating README: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 generate_readme.py <path> <project_name>")
        sys.exit(1)

    path = sys.argv[1]
    p_name = sys.argv[2]

    # Interactive inputs if not provided via args (though script calls this)
    # For simplicity, we just ask inputs here if we are running interactively,
    # but since this is called from bash, let's use input() for the extras.

    print(f"--- Generating Documentation for {p_name} ---")
    author = input("Author Name: ").strip()
    if not author: author = "Developer"

    desc = input("Short Description: ").strip()
    if not desc: desc = "A new web development project."

    generate_readme(p_name, author, desc, path)
