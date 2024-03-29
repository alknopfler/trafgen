"""
# take all data generate from monitor.pps load to numpy and plot.
# software irq rate vs target ps vs observed pps
# tx pps vs rx pps,  drop vs pps etc.
# pip install numpy
# pip install matplotlib
# Mus

"""

import os
import numpy as np
import matplotlib.pyplot as plt
import argparse
import subprocess


def dataset_files(directory):
    """ List all files in the specified directory and parse their names.

    Data it returns.
    Path to file generate at node that generate i.e. observation
    Path to a file generate at rx side i.e.e observation

    for how long we run it,
    target pps is 'pps' key
    cores a list used  [0]  single core 0 , [11-12] etc

    {
        '100pps_10_core_0_size_64': {
            'rx': 'rx_100pps_10_core_0_size_64.txt',
            'tx': 'tx_100pps_10_core_0_size_64.txt',
            'run_time': 10,
            'pps': 100,
            'cores': [0],
            'size': 64
        },
        ...
    }

    key tx_data and rx_data is matrix size of (n, 9) where
    n is number of samples and 9 is dim of col space
    where each coll rx_pps rx_drop, tx_pps, tx_drop

    All data sample at some const interval.

    :param directory: dir by default metrics
    :return:
    """

    files = os.listdir(directory)
    file_details = {}

    for file in files:
        if file.startswith(('tx_', 'rx_')) and file.endswith('.txt'):
            parts = file.split('_')
            if len(parts) >= 7:
                pps = int(parts[1].replace('pps', ''))
                run_time = int(parts[2])
                core_parts = parts[4].split('-') if '-' in parts[4] else [parts[4]]
                cores = [int(core.replace('core', '')) for core in core_parts]

                size = int(parts[6])
                key = f"{pps}pps_{run_time}_core_{'-'.join(str(c) for c in cores)}_size_{size}"

                if key not in file_details:
                    file_details[key] = {
                        'rx': None,
                        'tx': None,
                        'run_time': run_time,
                        'pps': pps,
                        'cores': cores,
                        'size': size
                    }

                if file.startswith('tx_'):
                    data_file = os.path.join(directory, file)
                    file_details[key]['tx'] = data_file
                    file_details[key]['tx_data'] = np.loadtxt(data_file, delimiter=',')
                else:
                    data_file = os.path.join(directory, file)
                    file_details[key]['rx'] = data_file
                    file_details[key]['rx_data'] = np.loadtxt(data_file, delimiter=',')

    return file_details


def print_metric(dataset):
    """
    Process the files and calculate metrics and output meat value if we need
    N sample we can check std for same core / pkt size.
    :param dataset:
    :return:
    """
    for key, details in dataset.items():
        tx_data = details['tx_data']
        rx_data = details['rx_data']

        mean_tx_pps = np.mean(tx_data[:, 1])
        mean_rx_pps = np.mean(rx_data[:, 0])

        tx_drop = tx_data[:, 2]
        rx_drop = rx_data[:, 2]
        tx_err = tx_data[:, 4]
        rx_err = rx_data[:, 4]

        mean_tx_drop = np.mean(tx_drop)
        mean_rx_drop = np.mean(rx_drop)
        mean_tx_err = np.mean(tx_err)
        mean_rx_err = np.mean(rx_err)

        print(f"""
        Packet Size: {details['size']}
        Cores: {details['cores']}
        Target PPS: {details['pps']}
        Mean TX PPS: {mean_tx_pps}
        Mean RX PPS: {mean_rx_pps}
        Mean TX Drop: {mean_tx_drop}
        Mean RX Drop: {mean_rx_drop}
        Mean TX Error: {mean_tx_err}
        Mean RX Error: {mean_rx_err}
        """)


def plot_drop_rate(
        dataset: dict,
        size: int,
        cores: list[int],
        output=None
):
    """Plot PPS against drop rate for different target PPS values and cores.
    :param dataset: Dictionary containing file details.
    :param size: Packet size for which experiments are conducted.
    :param cores: List of cores for which experiments are conducted.
    :param output:
    :return:
    """

    plt.figure(figsize=(10, 6))

    for core in cores:
        for key, details in dataset.items():
            if details['size'] == size and details['cores'] == cores:
                pps = details['pps']
                tx_data = details['tx_data']
                rx_data = details['rx_data']

                tx_pps = tx_data[:, 1]
                tx_drop = tx_data[:, 3]
                rx_pps = rx_data[:, 0]
                rx_drop = rx_data[:, 2]

                tx_drop_rate = np.divide(tx_drop, tx_pps, out=np.zeros_like(tx_drop), where=tx_pps != 0)
                rx_drop_rate = np.divide(rx_drop, rx_pps, out=np.zeros_like(rx_drop), where=rx_pps != 0)

                plt.scatter(tx_pps, tx_drop_rate, label=f"Core {core}, TX Drop Rate, Target PPS: {pps}")
                plt.scatter(rx_pps, rx_drop_rate, label=f"Core {core}, RX Drop Rate, Target PPS: {pps}")

    plt.xlabel('PPS (Packets per Second)')
    plt.ylabel('Drop Rate')
    plt.title(f'Drop Rate vs PPS for Packet Size {size} and Cores {cores}')
    plt.legend()
    plt.grid(True)
    if output:
        plt.savefig(output)
        print(f"Plot saved to {output}")
    else:
        plt.show()


def plot_tx_bound(
        dataset: dict,
        size: int,
        cores: list[int],
        tolerance=0.02,
        output=None
):
    """Plot PPS against observed TX vs target PPS.
    :param output:
    :param dataset: Dictionary containing file details.
    :param size: Packet size for which experiments are conducted.
    :param cores: List of cores for which experiments are conducted.
    :param tolerance:
    :return:
    """

    plt.figure(figsize=(10, 6))

    target_pps_list = []
    observed_pps_list = []

    for core in cores:
        for key, details in dataset.items():
            if details['size'] == size and core in details['cores']:
                target_pps = details['pps']
                tx_data = details['tx_data']
                rx_data = details['rx_data']

                tx_data = details['tx_data']
                observed_pps = np.mean(tx_data[:, 1])

                target_pps_list.append(target_pps)
                observed_pps_list.append(observed_pps)

    sorted_indices = np.argsort(target_pps_list)
    sorted_target_pps = np.array(target_pps_list)[sorted_indices]
    sorted_observed_pps = np.array(observed_pps_list)[sorted_indices]

    fig, ax = plt.subplots(figsize=(10, 7))

    ax.bar(sorted_target_pps.astype(str), sorted_observed_pps, label='Observed PPS', color='lightgray')
    ax.bar(sorted_target_pps.astype(str), sorted_target_pps - sorted_observed_pps,
           bottom=sorted_observed_pps, label='Target PPS', color='skyblue')

    ax.set_xlabel('Target PPS (Packets per Second)')
    ax.set_ylabel('PPS (Packets per Second)')
    ax.set_title(f'Observed vs. Target TX PPS for Cores {cores}, Packet Size {size}')
    ax.set_xticks(sorted_target_pps.astype(str))
    ax.set_xticklabels(sorted_target_pps.astype(str), rotation=45)
    ax.legend()
    ax.grid(True)

    plt.tight_layout()
    if output:
        plt.savefig(output)
        print(f"Plot saved to {output}")
    else:
        plt.show()


def plot_rx_bound(
        dataset: dict,
        size,
        cores,
        tolerance=0.02,
        output=None
):
    """ Plot a bar graph showing the target PPS, observed TX PPS, and observed RX PPS.
    Here we cross corelate tx / rx and target.  Assume TX x and RX x while target y.
    i.e.TX bounded by busy wait / CPU etc.

    :param dataset:
    :param size:
    :param cores:
    :param tolerance:
    :param output:
    :return:
    """

    target_pps_list = []
    observed_tx_pps_list = []
    observed_rx_pps_list = []

    for core in cores:
        for key, details in dataset.items():
            if details['size'] == size and core in details['cores']:
                target_pps = details['pps']
                tx_data = details['tx_data']
                rx_data = details['rx_data']

                observed_tx_pps = np.mean(tx_data[:, 1])
                observed_rx_pps = np.mean(rx_data[:, 0])

                target_pps_list.append(target_pps)
                observed_tx_pps_list.append(observed_tx_pps)
                observed_rx_pps_list.append(observed_rx_pps)

    # Sorting by target PPS
    sorted_indices = np.argsort(target_pps_list)
    sorted_target_pps = np.array(target_pps_list)[sorted_indices]
    sorted_observed_tx_pps = np.array(observed_tx_pps_list)[sorted_indices]
    sorted_observed_rx_pps = np.array(observed_rx_pps_list)[sorted_indices]

    fig, ax = plt.subplots(figsize=(10, 7))

    bar_width = 0.3
    index = np.arange(len(sorted_target_pps))

    ax.bar(sorted_target_pps.astype(str), sorted_observed_tx_pps, label='Observed TX PPS', color='lightgray')
    ax.bar(sorted_target_pps.astype(str), sorted_observed_rx_pps, label='Observed RX PPS', color='green', alpha=0.5)
    ax.plot(sorted_target_pps.astype(str), sorted_target_pps, label='Target PPS', color='skyblue', linestyle='--')

    ax.set_xlabel('Target PPS (Packets per Second)')
    ax.set_ylabel('PPS (Packets per Second)')
    ax.set_title(f'Observed TX vs. RX PPS for Cores {cores}, Packet Size {size}')
    ax.set_xticks(sorted_target_pps.astype(str))
    ax.set_xticklabels(sorted_target_pps.astype(str), rotation=45)
    ax.legend()
    ax.grid(True)

    plt.tight_layout()

    if output:
        plt.savefig(output)
        print(f"Plot saved to {output}")
    else:
        plt.show()


def plot_irq_sw_irq_rate(
        dataset: dict,
        size: int,
        cores: list[int],
        output=None,
):
    """
    :param dataset:  a dataset
    :param size:
    :param cores:
    :return:
    """
    plt.figure(figsize=(10, 6))

    target_pps_list = []
    irq_rates_list = []
    sirq_rates_list = []

    for core in cores:
        for key, details in dataset.items():
            if details['size'] == size and core in details['cores']:
                target_pps = details['pps']
                tx_data = details['tx_data']

                irq_rate = np.mean(tx_data[:, 8])
                sirq_rate = np.mean(tx_data[:, 9])

                target_pps_list.append(target_pps)
                irq_rates_list.append(irq_rate)
                sirq_rates_list.append(sirq_rate)

    sorted_indices = np.argsort(target_pps_list)
    sorted_target_pps = np.array(target_pps_list)[sorted_indices]
    sorted_irq_rates = np.array(irq_rates_list)[sorted_indices]
    sorted_sirq_rates = np.array(sirq_rates_list)[sorted_indices]

    fig, ax = plt.subplots(figsize=(12, 8))
    index = np.arange(len(sorted_target_pps))
    bar_width = 0.35

    ax.bar(index - bar_width / 2, sorted_irq_rates, bar_width, label='IRQ Rate', color='skyblue')
    ax.bar(index + bar_width / 2, sorted_sirq_rates, bar_width, label='SIRQ Rate', color='lightgreen')

    ax.set_xlabel('Target PPS (Packets per Second)')
    ax.set_ylabel('Rates')
    ax.set_title(f'IRQ and SIRQ Rates for Packet Size {size} and Cores {cores}')
    ax.set_xticks(index)
    ax.set_xticklabels(sorted_target_pps.astype(str), rotation=45)
    ax.set_yscale('log')
    ax.legend()
    ax.grid(True, which="both", ls="-")

    if output:
        plt.savefig(output)
        print(f"Plot saved to {output}")
    else:
        plt.show()


def plot_stats(
        metric_dataset: dict,
        plot_type: str,
        plotter: callable,
        output_dir=None
):
    """plot stats take metric dataset,
    callback that will plot and output dir (optional)

    :param plotter:
    :param output_dir:
    :param metric_dataset:
    :return:
    """
    grouped_experiments = set()
    for key, details in metric_dataset.items():
        size = details['size']
        cores = tuple(details['cores'])
        grouped_experiments.add((size, cores))

    for experiment in grouped_experiments:
        core_str = '-'.join(map(str, experiment[1]))
        if output_dir:
            output_file = os.path.join(
                output_dir,
                f"{plot_type}_{experiment[0]}_cores_{core_str}.png"
            )
        else:
            output_file = None
        plotter(metric_dataset, experiment[0], list(experiment[1]), output=output_file)


def run_sampling(pps_values):
    """Rn sampling script for each target pps.
    :param pps_values: list of pps value we collect samples for.
    :return:
    """
    for pps in pps_values:
        print(f"Running sampling for {pps} pps...")
        subprocess.run(['./run_monitor_pps.sh', '-p', str(pps)])
    print("Sampling completed.")


def main(cmd):
    """Run main , note sampling is optional arg, by default,
    we read metric dir and plot all samples collected.
    :return:
    """
    if cmd.sample:
        run_sampling(cmd.pps_values)

    if cmd.output_dir:
        os.makedirs(cmd.output_dir, exist_ok=True)

    directory = os.path.join(os.getcwd(), cmd.metric_dir)
    metric_dataset = dataset_files(directory)

    if cmd.print_metric:
        print_metric(metric_dataset)

    plot_stats(metric_dataset, "tx_bounded", plot_tx_bound, output_dir=cmd.output_dir)
    plot_stats(metric_dataset, "rx_bounded", plot_rx_bound, output_dir=cmd.output_dir)
    plot_stats(metric_dataset, "drop_bounded", plot_drop_rate, output_dir=cmd.output_dir)
    plot_stats(metric_dataset, "sw_irq_bounded", plot_irq_sw_irq_rate, output_dir=cmd.output_dir)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process metrics directory.')
    parser.add_argument('-m', '--metric_dir', type=str, default='metrics', help='Directory path for metrics')
    parser.add_argument('-p', '--print', dest='print_metric', action='store_true', help='Print metric dataset')
    parser.add_argument('-s', '--sample', action='store_true', help='Collect samples before processing metrics')
    parser.add_argument('--pps_values', nargs='*',
                        type=int, default=[1000, 10000, 20000, 50000, 100000, 200000, 500000, 1000000],
                        help='List of PPS values for sampling')
    parser.add_argument('-o', '--output_dir', type=str, help='Output directory for plots')
    args = parser.parse_args()
    main(args)
