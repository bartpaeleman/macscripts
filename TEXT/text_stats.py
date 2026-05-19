import sys
import collections
import re

def analyze_text(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        lines = content.splitlines()
        words = re.findall(r'\b\w+\b', content.lower())
        chars = len(content)
        non_space_chars = len(content) - content.count(" ") - content.count("\n")

        # Frequency
        word_counts = collections.Counter(words)
        top_10 = word_counts.most_common(10)

        print(f"--- Statistics for {filepath} ---")
        print(f"Lines:            {len(lines)}")
        print(f"Words:            {len(words)}")
        print(f"Characters:       {chars}")
        print(f"Chars (no space): {non_space_chars}")
        print("-" * 30)
        print("Top 10 Words:")
        for word, count in top_10:
            print(f"  {word}: {count}")

    except Exception as e:
        print(f"Error analyzing text: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 text_stats.py <file>")
        sys.exit(1)

    analyze_text(sys.argv[1])
