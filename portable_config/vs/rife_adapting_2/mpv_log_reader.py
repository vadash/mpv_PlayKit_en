"""
mpv_log_reader.py - Parse mpv-debug.log for errors and VapourSynth issues

Usage:
    python mpv_log_reader.py [log_path]

If no path given, searches for mpv-debug.log in common locations.
"""

import re
import sys
import argparse
from pathlib import Path
from collections import defaultdict
from typing import Optional, List, Tuple
from dataclasses import dataclass, field

# ANSI colors for terminal output
class Colors:
    RED = '\033[91m'
    YELLOW = '\033[93m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

@dataclass
class RIFESession:
    """Represents a single RIFE toggle on/off cycle."""
    session_id: int
    start_line: int
    end_line: int = 0
    start_time: float = 0.0
    end_time: float = 0.0
    events: List[Tuple[int, float, str, str]] = field(default_factory=list)  # (line, time, category, message)

    @property
    def lua_events(self):
        return [e for e in self.events if not e[2].startswith('PY_')]

    @property
    def python_events(self):
        return [e for e in self.events if e[2].startswith('PY_')]

    @property
    def duration(self):
        if self.end_time > 0:
            return self.end_time - self.start_time
        return 0.0

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
        'rife_sessions': [],  # NEW: List of RIFESession objects
        'rife_by_category': defaultdict(list),  # NEW: Events grouped by category
        'warnings': [],
        'python_traceback': [],
    }

    # Patterns to match
    patterns = {
        'error': re.compile(r'\[.*?\]\[(e|f)\]\[.*?\](.*)'),  # [e] or [f] level
        'lua_error': re.compile(r'\[.*?\]\[(e|f)\]\[.*?\].*?(Lua error:|attempt to call|attempt to compare|attempt to perform|Profile condition error)'),
        'script_loading': re.compile(r'Loading (lua )?script (.+)'),
        'vapoursynth': re.compile(r'\[vapoursynth\](.*)'),
        'rife_adaptive_cat': re.compile(r'\[rife_adaptive\]\[([A-Z_]+)\]\s*(.*)'),  # NEW: Extract category
        'timestamp': re.compile(r'^\[\s*([0-9.]+)\]'),  # Extract timestamp
        'python_exception': re.compile(r'(Python exception|Traceback|ModuleNotFoundError|ImportError|AttributeError)'),
    }

    try:
        with open(log_path, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except Exception as e:
        return {'error': f'Failed to read log: {e}'}

    in_traceback = False
    traceback_lines = []
    current_session = None
    session_counter = 0

    for i, line in enumerate(lines, 1):
        line = line.rstrip()

        # Extract timestamp
        ts_match = patterns['timestamp'].search(line)
        timestamp = float(ts_match.group(1)) if ts_match else 0.0

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

        # Check for RIFE adaptive messages with categories
        cat_match = patterns['rife_adaptive_cat'].search(line)
        if cat_match:
            category = cat_match.group(1)
            message = cat_match.group(2)

            # Session boundary detection
            if category == 'TOGGLE':
                if 'activation requested' in message.lower():
                    # Start new session
                    session_counter += 1
                    current_session = RIFESession(
                        session_id=session_counter,
                        start_line=i,
                        start_time=timestamp
                    )
                    results['rife_sessions'].append(current_session)
                elif 'deactivation requested' in message.lower() and current_session:
                    # End current session
                    current_session.end_line = i
                    current_session.end_time = timestamp
                    current_session = None

            # Add event to current session
            if current_session:
                current_session.events.append((i, timestamp, category, message))

            # Add to category grouping
            results['rife_by_category'][category].append((i, timestamp, message))

            # Add to general rife_adaptive list
            results['rife_adaptive'].append((i, line))

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

    # Close any open session
    if current_session:
        current_session.end_line = len(lines)
        current_session.end_time = timestamp

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

def print_session_timeline(session: RIFESession, show_lua=True, show_python=True):
    """Print chronological timeline of a single session."""
    print(f"\n{Colors.CYAN}{Colors.BOLD}{'='*70}{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}RIFE SESSION #{session.session_id} "
          f"(lines {session.start_line}-{session.end_line}, duration: {session.duration:.1f}s){Colors.RESET}")
    print(f"{Colors.CYAN}{'─'*70}{Colors.RESET}")

    events_to_show = []
    if show_lua and show_python:
        events_to_show = session.events
    elif show_lua:
        events_to_show = session.lua_events
    elif show_python:
        events_to_show = session.python_events

    if not events_to_show:
        print(f"  {Colors.YELLOW}No events in this session{Colors.RESET}")
        return

    for line_num, timestamp, category, message in events_to_show:
        relative_time = timestamp - session.start_time

        # Color code by category
        if category.startswith('PY_'):
            cat_color = Colors.GREEN
        elif category in ['TOGGLE', 'INIT']:
            cat_color = Colors.CYAN
        elif category in ['CROP', 'PATH', 'VPY']:
            cat_color = Colors.YELLOW
        else:
            cat_color = Colors.RESET

        print(f"  L{line_num:5d} [{relative_time:6.2f}s] "
              f"{cat_color}[{category}]{Colors.RESET} {message}")

def print_session_summary(sessions: List[RIFESession]):
    """Print summary table of all sessions."""
    if not sessions:
        return

    print(f"\n{Colors.CYAN}{Colors.BOLD}{'='*70}{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}SESSION SUMMARY{Colors.RESET}")
    print(f"{Colors.CYAN}{'='*70}{Colors.RESET}")
    print(f"  {'ID':<4} {'Start':<8} {'End':<8} {'Duration':<10} {'Lua':<6} {'Python':<6} {'Total':<6}")
    print(f"  {'-'*70}")

    for session in sessions:
        lua_count = len(session.lua_events)
        py_count = len(session.python_events)
        total = len(session.events)

        print(f"  {session.session_id:<4} "
              f"L{session.start_line:<7} "
              f"L{session.end_line:<7} "
              f"{session.duration:>8.1f}s  "
              f"{lua_count:<6} {py_count:<6} {total:<6}")

def print_category_grouped(results: dict):
    """Print events grouped by category."""
    categories = results['rife_by_category']

    if not categories:
        return

    for category in sorted(categories.keys()):
        events = categories[category]
        print(f"\n{Colors.YELLOW}{Colors.BOLD}{'='*70}{Colors.RESET}")
        print(f"{Colors.YELLOW}{Colors.BOLD}[{category}] ({len(events)} events){Colors.RESET}")
        print(f"{Colors.YELLOW}{'─'*70}{Colors.RESET}")

        for line_num, timestamp, message in events[:20]:  # Limit to 20 per category
            print(f"  L{line_num:5d} [{timestamp:8.2f}s] {message}")

        if len(events) > 20:
            print(f"  {Colors.YELLOW}... and {len(events) - 20} more{Colors.RESET}")


def summarize(results: dict):
    """Print summary of findings."""
    print(f"\n{Colors.GREEN}{Colors.BOLD}SUMMARY{Colors.RESET}")
    print(f"{'─'*40}")
    print(f"  RIFE sessions:          {len(results.get('rife_sessions', []))}")
    print(f"  Total RIFE events:      {sum(len(s.events) for s in results.get('rife_sessions', []))}")
    print(f"  Errors found:           {len(results.get('errors', []))}")
    print(f"  Lua script errors:      {len(results.get('lua_errors', []))}")
    print(f"  Scripts loaded:         {len(results.get('script_loading', []))}")
    print(f"  VapourSynth msgs:       {len(results.get('vapoursynth', []))}")
    print(f"  Python tracebacks:      {len(results.get('python_traceback', []))}")

def main():
    parser = argparse.ArgumentParser(
        description='Parse mpv-debug.log for RIFE adaptive system debugging',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Auto-find log, show latest session
  %(prog)s --session 2              # Show session 2 timeline
  %(prog)s --grouped                # Group events by category
  %(prog)s --category CROP,PATH     # Show only CROP and PATH events
  %(prog)s --lua-only               # Show only Lua events
  %(prog)s --python-only            # Show only Python events
        """
    )

    parser.add_argument('log_path', nargs='?', help='Path to mpv-debug.log (auto-detect if not provided)')
    parser.add_argument('--session', type=int, help='Show specific session number')
    parser.add_argument('--category', help='Filter to specific categories (comma-separated)')
    parser.add_argument('--grouped', action='store_true', help='Group events by category instead of timeline')
    parser.add_argument('--lua-only', action='store_true', help='Show only Lua events')
    parser.add_argument('--python-only', action='store_true', help='Show only Python events')
    parser.add_argument('--all-sessions', action='store_true', help='Show all sessions (not just latest)')

    args = parser.parse_args()

    # Get log path
    if args.log_path:
        log_path = Path(args.log_path)
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

    # Print session summary
    sessions = results['rife_sessions']
    if sessions:
        print_session_summary(sessions)

        # Show specific session or latest
        if args.session:
            target = [s for s in sessions if s.session_id == args.session]
            if target:
                print_session_timeline(
                    target[0],
                    show_lua=not args.python_only,
                    show_python=not args.lua_only
                )
            else:
                print(f"{Colors.RED}Session {args.session} not found{Colors.RESET}")
        elif args.all_sessions:
            for session in sessions:
                print_session_timeline(
                    session,
                    show_lua=not args.python_only,
                    show_python=not args.lua_only
                )
        else:
            # Show latest session by default
            if sessions:
                print_session_timeline(
                    sessions[-1],
                    show_lua=not args.python_only,
                    show_python=not args.lua_only
                )

    # Grouped view if requested
    if args.grouped:
        if args.category:
            # Filter to specific categories
            filtered = {k: v for k, v in results['rife_by_category'].items()
                       if k in args.category.split(',') }
            print_category_grouped({'rife_by_category': filtered})
        else:
            print_category_grouped(results)

    # Print VapourSynth messages
    print_section("VAPOURSYNTH MESSAGES", results['vapoursynth'][:30], Colors.YELLOW)

    # Summary
    summarize(results)

if __name__ == '__main__':
    main()
