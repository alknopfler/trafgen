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


def plot_drop_rate(
        dataset,
        size,
        cores
):
    """Plot PPS against drop rate for different target PPS values and cores.

    :param dataset: Dictionary containing file details.
    :param size: Packet size for which experiments are conducted.
    :param cores: List of cores for which experiments are conducted.
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
    plt.show()


def plot_tx_bound(
        dataset,
        size,
        cores,
        tolerance=0.02
):
    """Plot PPS against observed TX vs target PPS.
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
    plt.show()


def plot_rx_bound(dataset, size, cores, tolerance=0.02):
    """ Plot a bar graph showing the target PPS, observed TX PPS, and observed RX PPS.
    Here we cross corelate tx / rx and target.  Assume TX x and RX x while target y.
    i.e.TX bounded by busy wait / CPU etc.

    :param dataset:
    :param size:
    :param cores:
    :param tolerance:
    :return:
    """
    """
    Plot a bar graph showing the target PPS, observed TX PPS, and observed RX PPS.

    Args:
    dataset (dict): Dictionary containing file details.
    size (int): Packet size for which experiments are conducted.
    cores (list): List of cores for which experiments are conducted.
    tolerance (float): Acceptable error percentage.
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
    plt.show()


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

        print(f"Key: {key}")
        print(f"Packet Size: {details['size']}")
        print(f"Cores: {details['cores']}")
        print(f"Target PPS: {details['pps']}")
        print(f"Mean TX PPS: {mean_tx_pps}")
        print(f"Mean RX PPS: {mean_rx_pps}")
        print(f"Mean TX Drop: {mean_tx_drop}")
        print(f"Mean RX Drop: {mean_rx_drop}")
        print(f"Mean TX Error: {mean_tx_err}")
        print(f"Mean RX Error: {mean_rx_err}")
        print()


def plot_drop_rate_same_core(metric_dataset):
    """
    :param metric_dataset:
    :return:
    """
    grouped_experiments = set()
    for key, details in metric_dataset.items():
        size = details['size']
        cores = tuple(details['cores'])
        grouped_experiments.add((size, cores))

    for experiment in grouped_experiments:
        plot_drop_rate_same_core(metric_dataset, experiment[0], list(experiment[1]))


def plot_tx_bound_same_core(metric_dataset):
    """

    :param metric_dataset:
    :return:
    """
    grouped_experiments = set()
    for key, details in metric_dataset.items():
        size = details['size']
        cores = tuple(details['cores'])
        grouped_experiments.add((size, cores))

    for experiment in grouped_experiments:
        plot_tx_bound(metric_dataset, experiment[0], list(experiment[1]))


def plot_rx_bound_same_core(metric_dataset):
    """

    :param metric_dataset:
    :return:
    """
    grouped_experiments = set()
    for key, details in metric_dataset.items():
        size = details['size']
        cores = tuple(details['cores'])
        grouped_experiments.add((size, cores))

    for experiment in grouped_experiments:
        plot_rx_bound(metric_dataset, experiment[0], list(experiment[1]))


def plot_drop_bound_same_core(metric_dataset):
    """
    :param metric_dataset:
    :return:
    """
    grouped_experiments = set()
    for key, details in metric_dataset.items():
        size = details['size']
        cores = tuple(details['cores'])
        grouped_experiments.add((size, cores))

    for experiment in grouped_experiments:
        plot_drop_rate(metric_dataset, experiment[0], list(experiment[1]))


def _plot_irq_sirq_rates(
        dataset: dict,
        size: int,
        cores: list[int]
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

    plt.tight_layout()
    plt.show()


def plot_irq_sirq_rates(metric_dataset):
    """Plot for each packet size / core rate of irq vs target pps vs tx and rx pps.
    i.e. we want to see at target pps ( assume observed pps) < target pps we want to see
    how many irq generated in system. (i.e. potentially headline of blocking)

    :param metric_dataset:
    :return:
    """
    grouped_experiments = set()
    for key, details in metric_dataset.items():
        size = details['size']
        cores = tuple(details['cores'])
        grouped_experiments.add((size, cores))

    for experiment in grouped_experiments:
        _plot_irq_sirq_rates(metric_dataset, experiment[0], list(experiment[1]))


def main(cmd):
    """
    :return:
    """
    directory = os.path.join(os.getcwd(), cmd.metric_dir)
    metric_dataset = dataset_files(directory)

    if cmd.print_metric:
        print_metric(metric_dataset)

    plot_tx_bound_same_core(metric_dataset)
    plot_rx_bound_same_core(metric_dataset)
    plot_drop_bound_same_core(metric_dataset)
    plot_irq_sirq_rates(metric_dataset)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process metrics directory.')
    parser.add_argument('metric_dir', type=str, help='Directory path for metrics', default='metrics')
    parser.add_argument('-p', '--print', dest='print_metric', action='store_true', help='Print metric dataset')
    args = parser.parse_args()
    main(args)
