#!/usr/bin/env python3
"""
Generate visual benchmark charts from verztable benchmark data.

Usage:
    pip install matplotlib numpy
    python scripts/generate_charts.py

Outputs PNG files to docs/images/
"""

import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# Configure matplotlib for clean output
plt.style.use('seaborn-v0_8-darkgrid')
plt.rcParams['figure.facecolor'] = '#0d1117'  # GitHub dark theme
plt.rcParams['axes.facecolor'] = '#161b22'
plt.rcParams['text.color'] = '#c9d1d9'
plt.rcParams['axes.labelcolor'] = '#c9d1d9'
plt.rcParams['xtick.color'] = '#c9d1d9'
plt.rcParams['ytick.color'] = '#c9d1d9'
plt.rcParams['axes.edgecolor'] = '#30363d'
plt.rcParams['grid.color'] = '#30363d'
plt.rcParams['legend.facecolor'] = '#161b22'
plt.rcParams['legend.edgecolor'] = '#30363d'

# Benchmark data from README (string keys, averaged across sizes)
STRING_KEYS_MIXED = {
    'operations': ['Churn', 'Mixed', 'Read-Heavy', 'Write-Heavy', 'Update-Heavy', 'Zipfian'],
    'verztable': [43, 39, 34, 113, 40, 33],
    'Abseil': [55, 75, 62, 123, 70, 63],
    'Boost': [50, 71, 58, 93, 65, 60],
    'Ankerl': [60, 85, 73, 93, 83, 72],
    'std.HashMap': [50, 39, 30, 91, 41, 29],
}

U64_KEYS_MIXED = {
    'operations': ['Churn', 'Mixed', 'Read-Heavy', 'Write-Heavy', 'Update-Heavy', 'Zipfian'],
    'verztable': [17, 12, 7, 35, 14, 9],
    'Abseil': [25, 13, 5, 30, 12, 12],
    'Boost': [20, 10, 6, 29, 12, 9],
    'Ankerl': [23, 17, 12, 29, 18, 16],
    'std.HashMap': [29, 15, 10, 28, 16, 11],
}

U32_KEYS_MIXED = {
    'operations': ['Churn', 'Mixed', 'Read-Heavy', 'Write-Heavy', 'Update-Heavy', 'Zipfian'],
    'verztable': [16, 10, 6, 35, 14, 8],
    'Abseil': [24, 12, 5, 27, 13, 11],
    'Boost': [21, 9, 5, 29, 13, 8],
    'Ankerl': [23, 16, 12, 28, 18, 16],
    'std.HashMap': [28, 15, 10, 27, 17, 10],
}


def create_comparison_chart(data: dict, title: str, filename: str, highlight_winner: bool = True):
    """Create a grouped bar chart comparing hash table implementations."""
    operations = data['operations']
    implementations = ['verztable', 'Abseil', 'Boost', 'Ankerl', 'std.HashMap']
    colors = ['#58a6ff', '#f0883e', '#a371f7', '#3fb950', '#8b949e']
    
    x = np.arange(len(operations))
    width = 0.15
    
    fig, ax = plt.subplots(figsize=(14, 7))
    
    for i, (impl, color) in enumerate(zip(implementations, colors)):
        values = data[impl]
        offset = (i - 2) * width
        bars = ax.bar(x + offset, values, width, label=impl, color=color, alpha=0.9)
        
        # Highlight verztable bars
        if impl == 'verztable':
            for bar in bars:
                bar.set_edgecolor('#58a6ff')
                bar.set_linewidth(2)
    
    ax.set_xlabel('Workload Type', fontsize=12, fontweight='bold')
    ax.set_ylabel('Time per Operation (ns) — Lower is Better', fontsize=12, fontweight='bold')
    ax.set_title(title, fontsize=16, fontweight='bold', color='#58a6ff', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels(operations, fontsize=11)
    ax.legend(loc='upper right', fontsize=10)
    
    # Add grid
    ax.yaxis.grid(True, alpha=0.3)
    ax.set_axisbelow(True)
    
    plt.tight_layout()
    
    # Save
    output_dir = Path(__file__).parent.parent / 'docs' / 'images'
    output_dir.mkdir(parents=True, exist_ok=True)
    plt.savefig(output_dir / filename, dpi=150, bbox_inches='tight', 
                facecolor='#0d1117', edgecolor='none')
    plt.close()
    print(f"✓ Created {output_dir / filename}")


def create_summary_chart():
    """Create a simple summary chart showing overall performance."""
    implementations = ['verztable', 'Abseil', 'Boost', 'Ankerl', 'std.HashMap']
    
    # Average across all mixed workloads (from README summary tables)
    string_avg = [50, 75, 66, 78, 47]  # Approximate averages
    int_avg = [16, 16, 14, 19, 18]     # Approximate averages
    
    x = np.arange(len(implementations))
    width = 0.35
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    bars1 = ax.bar(x - width/2, string_avg, width, label='String Keys', color='#58a6ff', alpha=0.9)
    bars2 = ax.bar(x + width/2, int_avg, width, label='Integer Keys', color='#3fb950', alpha=0.9)
    
    # Highlight verztable
    bars1[0].set_edgecolor('#ffffff')
    bars1[0].set_linewidth(2)
    bars2[0].set_edgecolor('#ffffff')
    bars2[0].set_linewidth(2)
    
    ax.set_xlabel('Implementation', fontsize=12, fontweight='bold')
    ax.set_ylabel('Avg Time per Op (ns) — Lower is Better', fontsize=12, fontweight='bold')
    ax.set_title('verztable vs Industry Leaders — Mixed Workloads', 
                 fontsize=16, fontweight='bold', color='#58a6ff', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels(implementations, fontsize=11)
    ax.legend(loc='upper right', fontsize=10)
    ax.yaxis.grid(True, alpha=0.3)
    ax.set_axisbelow(True)
    
    plt.tight_layout()
    
    output_dir = Path(__file__).parent.parent / 'docs' / 'images'
    output_dir.mkdir(parents=True, exist_ok=True)
    plt.savefig(output_dir / 'summary.png', dpi=150, bbox_inches='tight',
                facecolor='#0d1117', edgecolor='none')
    plt.close()
    print(f"✓ Created {output_dir / 'summary.png'}")


def create_twitter_chart():
    """Create a compact chart optimized for Twitter/X (1200x675 or similar)."""
    operations = ['Mixed', 'Read-Heavy', 'Churn']
    implementations = ['verztable', 'Abseil', 'Boost', 'Ankerl']
    
    # String key data (most impressive for verztable)
    data = {
        'verztable': [39, 34, 43],
        'Abseil': [75, 62, 55],
        'Boost': [71, 58, 50],
        'Ankerl': [85, 73, 60],
    }
    
    colors = ['#58a6ff', '#f0883e', '#a371f7', '#3fb950']
    
    fig, ax = plt.subplots(figsize=(10, 5.625))  # 16:9 aspect ratio
    
    x = np.arange(len(operations))
    width = 0.2
    
    for i, (impl, color) in enumerate(zip(implementations, colors)):
        offset = (i - 1.5) * width
        bars = ax.bar(x + offset, data[impl], width, label=impl, color=color, alpha=0.9)
        if impl == 'verztable':
            for bar in bars:
                bar.set_edgecolor('#58a6ff')
                bar.set_linewidth(3)
    
    ax.set_ylabel('ns/op (lower = faster)', fontsize=14, fontweight='bold')
    ax.set_title('verztable vs Swiss Tables — String Keys', 
                 fontsize=18, fontweight='bold', color='#58a6ff', pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels(operations, fontsize=14, fontweight='bold')
    ax.legend(loc='upper right', fontsize=12, framealpha=0.9)
    ax.yaxis.grid(True, alpha=0.3)
    ax.set_axisbelow(True)
    
    # Add "2x faster" annotation
    ax.annotate('~2x faster!', xy=(0, 39), xytext=(0.3, 60),
                fontsize=12, color='#58a6ff', fontweight='bold',
                arrowprops=dict(arrowstyle='->', color='#58a6ff', lw=2))
    
    plt.tight_layout()
    
    output_dir = Path(__file__).parent.parent / 'docs' / 'images'
    output_dir.mkdir(parents=True, exist_ok=True)
    plt.savefig(output_dir / 'twitter_card.png', dpi=150, bbox_inches='tight',
                facecolor='#0d1117', edgecolor='none')
    plt.close()
    print(f"✓ Created {output_dir / 'twitter_card.png'}")


if __name__ == '__main__':
    print("Generating benchmark charts...\n")
    
    create_comparison_chart(
        STRING_KEYS_MIXED,
        'String Keys — Mixed Workload Performance',
        'string_keys_mixed.png'
    )
    
    create_comparison_chart(
        U64_KEYS_MIXED,
        'u64 Integer Keys — Mixed Workload Performance', 
        'u64_keys_mixed.png'
    )
    
    create_comparison_chart(
        U32_KEYS_MIXED,
        'u32 Integer Keys — Mixed Workload Performance', 
        'u32_keys_mixed.png'
    )
    
    create_summary_chart()
    create_twitter_chart()
    
    print("\n✅ All charts generated in docs/images/")
    print("\nTo use in README, add:")
    print('  ![Benchmark](docs/images/summary.png)')

