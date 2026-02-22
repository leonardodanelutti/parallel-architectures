import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import re
from scipy.optimize import fsolve
import os

# Ensure images directory exists
images_dir = 'images'
os.makedirs(images_dir, exist_ok=True)

def solve_y(r, y0=0.5):
    func = lambda y: y - np.exp(r * (y - 1))
    y_solution, = fsolve(func, y0)
    return y_solution

# Load CSV
data_grid = pd.read_csv('./instances/res_grid.csv')
data_ratio = pd.read_csv('./instances/res_ratio_500.csv')
data_vars = pd.read_csv('./instances/res_vars_1.8.csv')
data_vars_all = pd.read_csv('./instances/res_vars_1.8_all.csv')

# Extract ratio from filename
def extract_ratio(filename):
    match = re.search(r'_([\d\.]+)r(\d+)', filename)
    if match:
        return float(match.group(1))
    return np.nan

data_grid['ratio'] = data_grid['filename'].apply(extract_ratio)
data_ratio['ratio'] = data_ratio['filename'].apply(extract_ratio)
data_vars['ratio'] = data_vars['filename'].apply(extract_ratio)
data_vars_all['ratio'] = data_vars_all['filename'].apply(extract_ratio)


def plot_heatmap(df, phase_names, values, title, cmap='viridis'):
    df_phase = df[df['phase'].isin(phase_names)]
    heatmap_data = df_phase.pivot_table(index='num_vars', columns='ratio', values=values, aggfunc='mean')
    plt.figure(figsize=(10, 8))
    sns.heatmap(heatmap_data, annot=False, cmap=cmap)
    plt.title(title)
    plt.xlabel('Ratio')
    plt.ylabel('Number of Variables')
    plt.tight_layout()
    filename = title.replace(' ', '_').replace(':', '').lower() + '.png'
    plt.savefig(os.path.join(images_dir, filename))
    plt.close()

# Plot heatmap for time taken by first phases
first_phases = ['read_instance', 'alloc_graph', 'scc', 'topo_sort', 'backbone', 'wcc', 'wcc_grouped']
plot_heatmap(data_grid, first_phases, 'wall_ms', 'Time Taken by First Phases')

# Plot heatmap for time taken by each heuristic
heuristics = ['heuristic1', 'heuristic2', 'heuristic3', 'heuristic4']
for h in heuristics:
    plot_heatmap(data_grid, [h], 'wall_ms', f'Time Taken by {h}', cmap='magma')


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
    plt.savefig(os.path.join(images_dir, filename))
    plt.close()

# Plot heatmap for num_levels
plot_value_heatmap(data_grid, 'num_levels', first_phases, 'Number of Levels', cmap='cividis')

def plot_xy_graph(df, x_col, y_col, x_label, y_label, title, filename, color='b'):
    df = df.copy()
    grouped = df.groupby(x_col)[y_col].mean()
    plt.figure(figsize=(8, 6))
    plt.plot(grouped.index, grouped.values, marker='o', color=color)
    plt.xlabel(x_label)
    plt.ylabel(y_label)
    plt.title(title)
    plt.tight_layout()
    plt.savefig(os.path.join(images_dir, filename))
    plt.close()

# Plot num_scc/variables vs ratio
data_grid['num_scc_per_lit'] = data_grid['num_scc'] / 2 / data_grid['num_vars']
plot_xy_graph(
    data_grid,
    x_col='ratio',
    y_col='num_scc_per_lit',
    x_label='Ratio',
    y_label='#SCC / #Literals',
    title='Number of SCCs per Literal vs Ratio',
    filename='num_scc_per_lit_vs_ratio.png',
    color='g'
)

# Plot num_wcc/num_scc vs ratio
data_grid['num_wcc_per_scc'] = data_grid['num_wcc'] / data_grid['num_scc']
plot_xy_graph(
    data_grid,
    x_col='ratio',
    y_col='num_wcc_per_scc',
    x_label='Ratio',
    y_label='#WCC / #SCC',
    title='Number of WCCs per SCC vs Ratio',
    filename='num_wcc_per_scc_vs_ratio.png',
    color='r'
)

# data_grid['theoretical_y'] = data_grid['ratio'].apply(solve_y)

# Plot num_levels vs ratio
plot_xy_graph(
    data_grid,
    x_col='ratio',
    y_col='num_levels',
    x_label='Ratio',
    y_label='Number of Levels',
    title='Number of Levels vs Ratio',
    filename='num_levels_vs_ratio.png',
    color='m'
)

# Plot heuristic approximation-ratio vs ratio
plt.figure(figsize=(8, 6))
colors = ['b', 'g', 'r', 'm']
for h, color in zip(heuristics, colors):
    df_h = data_ratio[(data_ratio['phase'] == h) & (data_ratio['lower_bound'] == data_ratio['upper_bound'])].copy()
    df_h['approx'] = df_h['num_assignments'] / df_h['lower_bound']
    grouped = df_h.groupby('ratio')['approx'].mean()
    plt.plot(grouped.index, grouped.values, marker='o', color=color, label=h)
plt.xlabel('ratio')
plt.ylabel('approximation ratio')
plt.title('Heuristic Approximation vs Ratio')
plt.legend()
plt.tight_layout()
plt.savefig(os.path.join(images_dir, 'approx_all_heuristics_vs_ratio.png'))
plt.close()

# Plot time taken by each heuristic vs number of variables and print slopes
def plot_time_vs_num_vars(df, heuristics, file_name, scale='linear'):
    plt.figure(figsize=(8, 6))
    colors = ['b', 'g', 'r', 'm']
    for h, color in zip(heuristics, colors):
        df_h = df[df['phase'] == h].copy()
        grouped = df_h.groupby('num_vars')['wall_ms'].mean()
        plt.plot(grouped.index, grouped.values, marker='o', color=color, label=h)
        # Compute and print slopes for log(time) vs log(num_vars)
        x = np.log10(grouped.index.values)
        y = np.log10(grouped.values)
        mask_low = grouped.index.values < 2**17
        mask_high = grouped.index.values >= 2**17
        if np.sum(mask_low) > 1:
            slope_low = np.polyfit(x[mask_low], y[mask_low], 1)[0]
            print(f"{h} slope for num_vars < 1e5: {slope_low:.4f}")
        else:
            print(f"{h} slope for num_vars < 1e5: Not enough points")
        if np.sum(mask_high) > 1:
            slope_high = np.polyfit(x[mask_high], y[mask_high], 1)[0]
            print(f"{h} slope for num_vars >= 1e5: {slope_high:.4f}")
        else:
            print(f"{h} slope for num_vars >= 1e5: Not enough points")
    plt.xlabel('Number of Variables')
    plt.ylabel('Time (ms)')
    plt.xscale(scale)
    plt.yscale(scale)
    plt.title('Time Taken by Heuristic vs Number of Variables')
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(images_dir, file_name))
    plt.close()

fast_heuristics = ['heuristic1', 'heuristic2', 'heuristic3']
plot_time_vs_num_vars(data_vars, fast_heuristics, 'time_vs_num_vars_fast_heuristics.png', scale='log')
plot_time_vs_num_vars(data_vars, fast_heuristics, 'time_vs_num_vars_fast_heuristics_linear.png')
plot_time_vs_num_vars(data_vars_all, heuristics, 'time_vs_num_vars_all_heuristics.png', scale='log')


# Plot average time taken by Clingo for each ratio in instances/res_ratio_500
ratio_dir = 'instances/ratio_500'
times = []
ratios = []
for fname in os.listdir(ratio_dir):
    if fname.endswith('.cnf'):
        with open(os.path.join(ratio_dir, fname), 'r') as f:
            first_line = f.readline().strip()
            values = first_line.split()
            if len(values) >= 5:
                time = float(values[4])
                ratio = extract_ratio(fname)
                times.append(time)
                ratios.append(ratio)

df_time = pd.DataFrame({'ratio': ratios, 'time': times})
avg_time = df_time.groupby('ratio')['time'].mean()

# Boxplot for time vs ratio
plt.figure(figsize=(10, 6))
sns.boxplot(x='ratio', y='time', data=df_time, color='skyblue')
plt.xlabel('Ratio')
plt.ylabel('Time (s)')
plt.yscale('log')
plt.title('Time taken by the Clingo solver vs Ratio')
plt.tight_layout()
plt.savefig(os.path.join(images_dir, 'boxplot_time_vs_ratio_res_ratio_500.png'))
plt.close()

