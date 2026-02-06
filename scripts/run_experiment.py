#!/usr/bin/env python3
"""
Run Claude experiments against Parseable observability data.

Reads prompt.md and sample_data.json from an experiment directory,
sends the combined prompt to the Claude API, saves the response,
and prints token usage with estimated cost.

Usage:
    python scripts/run_experiment.py --experiment 02-log-analysis
    python scripts/run_experiment.py --all
    python scripts/run_experiment.py --experiment 02-log-analysis --model claude-sonnet-4-5-20250929

Requires:
    pip install anthropic
    export ANTHROPIC_API_KEY=sk-ant-...
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import anthropic
except ImportError:
    print("Error: anthropic package not installed.")
    print("Install it with: pip install anthropic")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_MODEL = "claude-opus-4-6"
REPO_ROOT = Path(__file__).resolve().parent.parent
EXPERIMENTS_DIR = REPO_ROOT / "experiments"
RESULTS_DIR = REPO_ROOT / "results"

# Approximate pricing per 1M tokens (USD) -- update as pricing changes
MODEL_PRICING = {
    "claude-opus-4-6": {"input": 15.0, "output": 75.0},
    "claude-sonnet-4-5-20250929": {"input": 3.0, "output": 15.0},
    "claude-haiku-3-5-20241022": {"input": 0.80, "output": 4.0},
}


def estimate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    """Return estimated cost in USD for the given token counts."""
    pricing = MODEL_PRICING.get(model, MODEL_PRICING[DEFAULT_MODEL])
    input_cost = (input_tokens / 1_000_000) * pricing["input"]
    output_cost = (output_tokens / 1_000_000) * pricing["output"]
    return input_cost + output_cost


def discover_experiments() -> list[str]:
    """Return sorted list of experiment directory names that contain prompt.md."""
    experiments = []
    if not EXPERIMENTS_DIR.is_dir():
        return experiments
    for child in sorted(EXPERIMENTS_DIR.iterdir()):
        if child.is_dir() and (child / "prompt.md").exists():
            experiments.append(child.name)
    return experiments


def load_experiment(name: str) -> tuple[str, str | None]:
    """Load prompt.md and optional sample_data.json for an experiment.

    Returns (prompt_text, sample_data_json_string_or_None).
    """
    exp_dir = EXPERIMENTS_DIR / name
    if not exp_dir.is_dir():
        print(f"Error: experiment directory not found: {exp_dir}")
        sys.exit(1)

    prompt_path = exp_dir / "prompt.md"
    if not prompt_path.exists():
        print(f"Error: prompt.md not found in {exp_dir}")
        sys.exit(1)

    prompt_text = prompt_path.read_text(encoding="utf-8")

    sample_data = None
    sample_data_path = exp_dir / "sample_data.json"
    if sample_data_path.exists():
        sample_data = sample_data_path.read_text(encoding="utf-8")

    return prompt_text, sample_data


def build_user_message(prompt_text: str, sample_data: str | None) -> str:
    """Combine the prompt template with sample data."""
    if sample_data is None:
        return prompt_text

    # If the prompt contains the placeholder, substitute it; otherwise append.
    placeholder = "[Paste the contents of sample_data.json here]"
    if placeholder in prompt_text:
        return prompt_text.replace(placeholder, sample_data)
    else:
        return f"{prompt_text}\n\n## Data\n\n```json\n{sample_data}\n```"


def run_experiment(
    name: str,
    model: str,
    client: anthropic.Anthropic,
) -> dict:
    """Run a single experiment and return the result metadata."""
    print(f"\n{'='*60}")
    print(f"  Experiment: {name}")
    print(f"  Model:      {model}")
    print(f"{'='*60}")

    prompt_text, sample_data = load_experiment(name)
    user_message = build_user_message(prompt_text, sample_data)

    print(f"  Prompt length: {len(user_message):,} characters")
    print("  Sending to Claude API...")

    start = time.time()
    response = client.messages.create(
        model=model,
        max_tokens=4096,
        messages=[{"role": "user", "content": user_message}],
    )
    elapsed = time.time() - start

    # Extract response text
    response_text = ""
    for block in response.content:
        if block.type == "text":
            response_text += block.text

    input_tokens = response.usage.input_tokens
    output_tokens = response.usage.output_tokens
    cost = estimate_cost(model, input_tokens, output_tokens)

    # Print summary
    print(f"\n  Response received in {elapsed:.1f}s")
    print(f"  Input tokens:  {input_tokens:>8,}")
    print(f"  Output tokens: {output_tokens:>8,}")
    print(f"  Total tokens:  {input_tokens + output_tokens:>8,}")
    print(f"  Estimated cost: ${cost:.4f}")

    # Save results
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    result_dir = RESULTS_DIR / name
    result_dir.mkdir(parents=True, exist_ok=True)

    result_file = result_dir / f"response_{timestamp}.md"
    result_file.write_text(response_text, encoding="utf-8")
    print(f"  Saved to: {result_file.relative_to(REPO_ROOT)}")

    # Also save metadata alongside
    metadata = {
        "experiment": name,
        "model": model,
        "timestamp": timestamp,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "estimated_cost_usd": round(cost, 6),
        "elapsed_seconds": round(elapsed, 2),
        "stop_reason": response.stop_reason,
    }
    meta_file = result_dir / f"metadata_{timestamp}.json"
    meta_file.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run Claude experiments against Parseable observability data.",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--experiment",
        type=str,
        help='Experiment directory name (e.g., "02-log-analysis")',
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="Run all experiments that have a prompt.md",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=DEFAULT_MODEL,
        help=f"Claude model to use (default: {DEFAULT_MODEL})",
    )

    args = parser.parse_args()

    # Validate API key
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY environment variable is not set.")
        print("Export it with: export ANTHROPIC_API_KEY=sk-ant-...")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    # Determine which experiments to run
    if args.all:
        experiments = discover_experiments()
        if not experiments:
            print(f"No experiments found in {EXPERIMENTS_DIR}")
            sys.exit(1)
        print(f"Found {len(experiments)} experiment(s): {', '.join(experiments)}")
    else:
        experiments = [args.experiment]

    # Run experiments
    all_results = []
    for exp_name in experiments:
        try:
            result = run_experiment(exp_name, args.model, client)
            all_results.append(result)
        except anthropic.APIError as e:
            print(f"\n  API Error for {exp_name}: {e}")
            continue

    # Print summary
    if len(all_results) > 1:
        print(f"\n{'='*60}")
        print("  Summary")
        print(f"{'='*60}")
        total_input = sum(r["input_tokens"] for r in all_results)
        total_output = sum(r["output_tokens"] for r in all_results)
        total_cost = sum(r["estimated_cost_usd"] for r in all_results)
        print(f"  Experiments run:  {len(all_results)}")
        print(f"  Total input:      {total_input:>8,} tokens")
        print(f"  Total output:     {total_output:>8,} tokens")
        print(f"  Total cost:       ${total_cost:.4f}")


if __name__ == "__main__":
    main()
