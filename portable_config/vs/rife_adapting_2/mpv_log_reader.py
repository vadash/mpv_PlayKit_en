"""
mpv_log_reader.py - Parse mpv-debug.log for errors and VapourSynth issues

Usage:
    python mpv_log_reader.py [log_path]

If no path given, searches for mpv-debug.log in common locations.
"""

import re
import sys
from pathlib import Path
from collections import defaultdict
from typing import Optional

# ANSI colors for terminal output
class Colors:
    RED = '\033[91m'
    YELLOW = '\033[93m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def find_log_file() -> Optional[Path]:
    """Find mpv-debug.log in common locations."""
    script_dir = Path(__file__).parent
    search_paths = [
        script_dir.parent.parent / "mpv-debug.log",  # mpv-lazy/mpv-debug.log
        script_dir.parent.parent.parent / "mpv-debug.log",
        Path.cwd() / "mpv-debug.log",
    ]
    for p in search_paths:
        if p.exists():
            return p
    return None

def parse_log(log_path: Path) -> dict:
    """Parse mpv log and extract relevant information."""
    results = {
        'errors': [],
        'lua_errors': [],
        'script_loading': [],
        'vapoursynth': [],
        'rife_adaptive': [],
        'rife_adaptive_debug': [],  # New: debug messages from rife_adaptive lua script
        'warnings': [],
        'python_traceback': [],
    }

    # Patterns to match
    patterns = {
        'error': re.compile(r'\[.*?\]\[(e|f)\]\[.*?\](.*)'),  # [e] or [f] level
        'lua_error': re.compile(r'\[.*?\]\[(e|f)\]\[.*?\].*?(Lua error:|attempt to call|attempt to compare|attempt to perform|Profile condition error)'),
        'script_loading': re.compile(r'Loading (lua )?script (.+)'),
        'vapoursynth': re.compile(r'\[vapoursynth\](.*)'),
        'rife_adaptive': re.compile(r'rife.adaptive', re.IGNORECASE),
        'rife_adaptive_debug': re.compile(r'\[rife_adaptive\]'),  # [rife_adaptive] module messages
        'lua_debug': re.compile(r'\[d\]\[(.*?)\](.*)'),  # Any [d] debug level message
        'python_exception': re.compile(r'(Python exception|Traceback|ModuleNotFoundError|ImportError|AttributeError)'),
    }

    try:
        with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except Exception as e:
        return {'error': f'Failed to read log: {e}'}

    in_traceback = False
    traceback_lines = []

    for i, line in enumerate(lines, 1):
        line = line.rstrip()

        # Track Python tracebacks
        if 'Traceback' in line or 'Python exception' in line:
            in_traceback = True
            traceback_lines = [(i, line)]
        elif in_traceback:
            if line.strip() and (line.startswith('[') or 'Error' in line or 'File' in line.strip() or line.strip().startswith('import')):
                traceback_lines.append((i, line))
            else:
                if traceback_lines:
                    results['python_traceback'].append(traceback_lines.copy())
                in_traceback = False
                traceback_lines = []

        # Check for error level messages
        if patterns['error'].search(line):
            results['errors'].append((i, line))

        # Check for Lua-specific errors
        if patterns['lua_error'].search(line):
            results['lua_errors'].append((i, line))

        # Track script loading
        match = patterns['script_loading'].search(line)
        if match:
            results['script_loading'].append((i, line, match.group(2)))

        # VapourSynth messages
        if patterns['vapoursynth'].search(line):
            results['vapoursynth'].append((i, line))

        # RIFE adaptive debug messages (from lua script mp.msg.debug)
        if patterns['rife_adaptive_debug'].search(line):
            results['rife_adaptive_debug'].append((i, line))

        # RIFE adaptive mentions (general)
        if patterns['rife_adaptive'].search(line):
            results['rife_adaptive'].append((i, line))

    return results

def print_section(title: str, items: list, color: str = Colors.CYAN):
    """Print a section with colored header."""
    if not items:
        return
    print(f"\n{color}{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"{color}{Colors.BOLD}{title}{Colors.RESET}")
    print(f"{color}{'='*60}{Colors.RESET}")

    for item in items:
        if isinstance(item, tuple):
            line_num, text = item
            print(f"{Colors.YELLOW}L{line_num:5d}{Colors.RESET}: {text}")
        elif isinstance(item, list):  # Traceback
            for line_num, text in item:
                print(f"{Colors.RED}L{line_num:5d}{Colors.RESET}: {text}")
            print()

def print_script_loading(items: list):
    """Print script loading order with formatted output."""
    if not items:
        return
    print(f"\n{Colors.CYAN}{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}SCRIPT LOADING ORDER{Colors.RESET}")
    print(f"{Colors.CYAN}{'='*60}{Colors.RESET}")

    for item in items:
        line_num, line, script_path = item
        # Extract timestamp from line: [  0.010][v][cplayer] Loading...
        ts_match = re.search(r'\[\s*([\d.]+)\]', line)
        timestamp = ts_match.group(1) if ts_match else "?.???"

        # Get script name
        script_name = Path(script_path).name

        # Format: built-in scripts start with @
        if script_name.startswith('@'):
            print(f"  [{timestamp:>8s}s] {script_name} (built-in)")
        else:
            parent_dir = Path(script_path).parent.name
            print(f"  [{timestamp:>8s}s] {script_name} → .../{parent_dir}/")

def summarize(results: dict):
    """Print summary of findings."""
    print(f"\n{Colors.GREEN}{Colors.BOLD}SUMMARY{Colors.RESET}")
    print(f"{'─'*40}")
    print(f"  Errors found:           {len(results.get('errors', []))}")
    print(f"  Lua script errors:      {len(results.get('lua_errors', []))}")
    print(f"  Scripts loaded:         {len(results.get('script_loading', []))}")
    print(f"  VapourSynth msgs:       {len(results.get('vapoursynth', []))}")
    print(f"  RIFE adaptive refs:     {len(results.get('rife_adaptive', []))}")
    print(f"  RIFE adaptive debug:    {len(results.get('rife_adaptive_debug', []))}")
    print(f"  Python tracebacks:      {len(results.get('python_traceback', []))}")

def main():
    # Get log path
    if len(sys.argv) > 1:
        log_path = Path(sys.argv[1])
    else:
        log_path = find_log_file()

    if not log_path or not log_path.exists():
        print(f"{Colors.RED}Error: Could not find mpv-debug.log{Colors.RESET}")
        print("Usage: python mpv_log_reader.py [path/to/mpv-debug.log]")
        sys.exit(1)

    print(f"{Colors.CYAN}Parsing: {log_path}{Colors.RESET}")
    results = parse_log(log_path)

    if 'error' in results:
        print(f"{Colors.RED}{results['error']}{Colors.RESET}")
        sys.exit(1)

    # Print Python tracebacks first (most important)
    print_section("PYTHON TRACEBACKS", results['python_traceback'], Colors.RED)

    # Print Lua script errors
    print_section("LUA SCRIPT ERRORS", results['lua_errors'][:20], Colors.RED)

    # Print errors
    print_section("ERRORS", results['errors'][:20], Colors.RED)  # Limit to 20

    # Print VapourSynth messages
    print_section("VAPOURSYNTH MESSAGES", results['vapoursynth'][:30], Colors.YELLOW)

    # Print script loading order
    print_script_loading(results['script_loading'])

    # Print RIFE adaptive debug messages (from lua script)
    print_section("RIFE ADAPTIVE DEBUG", results['rife_adaptive_debug'][:50], Colors.CYAN)

    # Summary
    summarize(results)

    # Quick diagnosis
    all_text = ' '.join([line for _, line in results.get('errors', [])])
    if 'No module named' in all_text:
        print(f"\n{Colors.RED}{Colors.BOLD}DIAGNOSIS: Missing Python module{Colors.RESET}")
        print("The VapourSynth script cannot find a required module.")
        print("Check that the module is in Python's path or add sys.path manipulation.")

if __name__ == '__main__':
    main()
