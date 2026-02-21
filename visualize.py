import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import re

# Load CSV
data_grid = pd.read_csv('grid_res.csv')
data_ratio = pd.read_csv('ratio_1000_res.csv')
data_vars = pd.read_csv('vars_1.8_res.csv')

# Extract ratio from filename
def extract_ratio(filename):
    match = re.search(r'_([\d\.]+)r(\d+)', filename)
    if match:
        return float(match.group(1))
    return np.nan

data_grid['ratio'] = data_grid['filename'].apply(extract_ratio)
data_ratio['ratio'] = data_ratio['filename'].apply(extract_ratio)
#data_vars['ratio'] = data_vars['filename'].apply(extract_ratio)


# Filter for first phases and heuristics
def plot_heatmap(df, phase_names, values, title, cmap='viridis'):
    # Only keep relevant phases
    df_phase = df[df['phase'].isin(phase_names)]
    # Pivot table: rows=num_vars, cols=ratio
    heatmap_data = df_phase.pivot_table(index='num_vars', columns='ratio', values=values, aggfunc='mean')
    plt.figure(figsize=(10, 8))
    sns.heatmap(heatmap_data, annot=False, cmap=cmap)
    plt.title(title)
    plt.xlabel('Ratio')
    plt.ylabel('Number of Variables')
    plt.tight_layout()
    # Save plot as PNG file
    # Replace spaces and colons in title for filename
    filename = title.replace(' ', '_').replace(':', '').lower() + '.png'
    plt.savefig(filename)
    plt.close()

first_phases = ['read_instance', 'alloc_graph', 'scc', 'topo_sort', 'backbone', 'wcc', 'wcc_grouped']
plot_heatmap(data_grid, first_phases, 'wall_ms', 'Heatmap: Time Taken by First Phases')

# Heuristics
heuristics = ['heuristic1', 'heuristic2', 'heuristic3', 'heuristic4']
for h in heuristics:
    plot_heatmap(data_grid, [h], 'wall_ms', f'Heatmap: Time Taken by {h}', cmap='magma')


# Additional heatmaps for num_scc, num_wcc, num_levels
def plot_value_heatmap(df, value_col, phase_names, title, cmap='viridis'):
    df_phase = df[df['phase'].isin(phase_names)]
    heatmap_data = df_phase.pivot_table(index='num_vars', columns='ratio', values=value_col, aggfunc='mean')
    plt.figure(figsize=(10, 8))
    sns.heatmap(heatmap_data, annot=False, cmap=cmap)
    plt.title(title)
    plt.xlabel('Ratio')
    plt.ylabel('Number of Variables')
    plt.tight_layout()
    filename = title.replace(' ', '_').replace(':', '').lower() + '.png'
    plt.savefig(filename)
    plt.close()

def plot_xy_graph(df, x_col, y_col, y_label, title, filename, color='b'):
    df = df.copy()
    grouped = df.groupby(x_col)[y_col].mean()
    plt.figure(figsize=(8, 6))
    plt.plot(grouped.index, grouped.values, marker='o', color=color)
    plt.xlabel(x_col)
    plt.ylabel(y_label)
    plt.title(title)
    plt.tight_layout()
    plt.savefig(filename)
    plt.close()

# Add columns for ratios
data_grid['num_scc_per_lit'] = data_grid['num_scc'] / 2 / data_grid['num_vars']
data_grid['num_wcc_per_scc'] = data_grid['num_wcc'] / data_grid['num_scc']

plot_value_heatmap(data_grid, 'num_levels', first_phases, 'Heatmap: num_levels', cmap='cividis')

# Plot num_scc/variables vs ratio
plot_xy_graph(
    data_grid,
    x_col='ratio',
    y_col='num_scc_per_lit',
    y_label='num_scc / num_lit',
    title='num_scc / num_lit vs Ratio',
    filename='num_scc_per_lit_vs_ratio.png',
    color='g'
)

# Plot num_wcc/num_scc vs ratio
plot_xy_graph(
    data_grid,
    x_col='ratio',
    y_col='num_wcc_per_scc',
    y_label='num_wcc / num_scc',
    title='num_wcc / num_scc vs Ratio',
    filename='num_wcc_per_scc_vs_ratio.png',
    color='r'
)

# Plot num_levels vs ratio
plot_xy_graph(
    data_grid,
    x_col='ratio',
    y_col='num_levels',
    y_label='num_levels', 
    title='num_levels vs Ratio',
    filename='num_levels_vs_ratio.png',
    color='m'
)

# Plot heuristic relative error vs ratio
for h in heuristics:
    data_ratio[f'{h}_relative_error'] = data_ratio[f'{h}_num_assignments'] / data_ratio['lower_bound'] -1
    plot_xy_graph(
        data_ratio,
        x_col='ratio',
        y_col=f'{h}_relative_error',
        y_label=f'{h} Relative Error',
        title=f'{h} Relative Error vs Ratio',
        filename=f'{h}_relative_error_vs_ratio.png',
        color='b'
    )
