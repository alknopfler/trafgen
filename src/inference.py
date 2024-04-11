"""
# Take all data generate from monitor.pps and other script.
# Load to numpy and plot inference points.
# All logs read from metrics dir by default.
#
# pip install numpy
# pip install matplotlib
#
# Mus mbayramov@vwamrec.om
"""

import os
from typing import Optional

import numpy as np
import matplotlib.pyplot as plt
import argparse
import subprocess
import json


def dataset_files(
        directory
):
    """ List all files in the specified directory and parse their names.

    file name format expected

    rx_pps_1000_pairs_3_size_64_cores_1_pods-cores_2_4_6.log

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
        if file.startswith(('tx_', 'rx_')) and file.endswith('.log'):
            file_name = file[:-4]
            parts = file_name.split('_')
            # ['rx', 'pps', '400000', 'pairs', '3', 'size', '64', 'cores', '1', 'pods-cores', '2', '4', '6']
            if len(parts) >= 7:
                pps = int(parts[2].replace('pps', ''))
                pairs = int(parts[4])
                frame_size = int(parts[6])
                core_per_pod = int(parts[8])
                cores = [int(core) for core in parts[10:]]

                key = f"pps_{pps}_pair_{pairs}_cores_{'-'.join(str(c) for c in cores)}_size_{frame_size}"
                if key not in file_details:
                    file_details[key] = {
                        'rx': None,
                        'tx': None,
                        'pps': pps,
                        'pairs': pairs,
                        'core_per_pod': core_per_pod,
                        'cores': cores,
                        'size': frame_size,
                        'metadata': {
                            'rx_pps': {'description': 'Received PPS', 'position': 0},
                            'tx_pps': {'description': 'Transmitted PPS', 'position': 1},
                            'rx_drop': {'description': 'Received Drops', 'position': 2},
                            'tx_drop': {'description': 'Transmitted Drops', 'position': 3},
                            'rx_err': {'description': 'Received Errors', 'position': 4},
                            'tx_err': {'description': 'Transmitted Errors', 'position': 5},
                            'rx_bytes': {'description': 'Received Bytes', 'position': 6},
                            'tx_bytes': {'description': 'Transmitted Bytes', 'position': 7},
                            'irq_rate': {'description': 'IRQ Rate', 'position': 8},
                            's_irq_rate': {'description': 'Soft IRQ Rate', 'position': 9},
                            'net_tx_rate': {'description': 'Network Transmit Rate', 'position': 10},
                            'net_rx_rate': {'description': 'Network Receive Rate', 'position': 11},
                            'cpu_core': {'description': 'CPU Core', 'position': 12},
                            'cpu_usage': {'description': 'CPU Usage', 'position': 13}
                        }
                    }

                if file.startswith('tx_'):
                    data_file = os.path.join(directory, file)
                    file_details[key]['tx'] = data_file
                    file_details[key]['tx_data'] = np.loadtxt(data_file, delimiter=',')

                else:
                    data_file = os.path.join(directory, file)
                    file_details[key]['rx'] = data_file
                    np_data = np.loadtxt(data_file, delimiter=',')
                    file_details[key]['rx_data'] = np_data

    return file_details


def dataset_files_from_dict(
        combine_files: dict,
        base_dir: str,
        is_verbose: bool = False
):
    """
    Load data from files listed in combine_files dictionary into numpy arrays.

    :param base_dir:
    :param is_verbose:
    :param combine_files: Dictionary containing file information.
    :return: Updated dictionary with loaded numpy arrays.
    """
    file_details = {}

    for data_key, value in combine_files.items():

        pod_files = value.get('files', [])
        worker_metrics = value.get('worker_metrics', {})
        core_list = [int(core) for core in value.get('core_list', [])]

        if not pod_files:
            continue

        pps, pairs, frame_size, cores_per_pod = data_key
        key = (f"pps_{pps}_pair_{pairs}_"
               f"cores_per_pod_{cores_per_pod}_"
               f"cores_{'-'.join(str(c) for c in core_list)}_size_{frame_size}")

        if key not in file_details:
            file_details[key] = {
                'rx_files': [],
                'tx_files': [],
                'pps': pps,
                'pairs': pairs,
                'core_per_pod': cores_per_pod,
                'cores': core_list,
                'size': frame_size,
                'metadata': {
                    'rx_pps': {'description': 'Received PPS', 'position': 0},
                    'tx_pps': {'description': 'Transmitted PPS', 'position': 1},
                    'rx_drop': {'description': 'Received Drops', 'position': 2},
                    'tx_drop': {'description': 'Transmitted Drops', 'position': 3},
                    'rx_err': {'description': 'Received Errors', 'position': 4},
                    'tx_err': {'description': 'Transmitted Errors', 'position': 5},
                    'rx_bytes': {'description': 'Received Bytes', 'position': 6},
                    'tx_bytes': {'description': 'Transmitted Bytes', 'position': 7},
                    'irq_rate': {'description': 'IRQ Rate', 'position': 8},
                    's_irq_rate': {'description': 'Soft IRQ Rate', 'position': 9},
                    'net_tx_rate': {'description': 'Network Transmit Rate', 'position': 10},
                    'net_rx_rate': {'description': 'Network Receive Rate', 'position': 11},
                    'cpu_core': {'description': 'CPU Core', 'position': 12},
                    'cpu_usage': {'description': 'CPU Usage', 'position': 13}
                }
            }

        # load all metric collected form pods.
        # all TX loaded as one matrix same for RX
        for pod_file_name in pod_files:
            if 'server' in pod_file_name:
                if is_verbose:
                    print("Loading server file: ", pod_file_name)
                if 'tx_data' not in file_details[key]:
                    file_details[key]['tx_data'] = np.loadtxt(pod_file_name, delimiter=',')
                else:
                    file_details[key]['tx_data'] = np.append(
                        file_details[key]['tx_data'],
                        np.loadtxt(pod_file_name, delimiter=','), axis=0)
                file_details[key]['tx_files'].append(pod_file_name)
            else:
                if is_verbose:
                    print("Loading client file: ", pod_file_name)
                if 'rx_data' not in file_details[key]:
                    file_details[key]['rx_data'] = np.loadtxt(pod_file_name, delimiter=',')
                else:
                    file_details[key]['rx_data'] = np.append(
                        file_details[key]['rx_data'],
                        np.loadtxt(pod_file_name, delimiter=','), axis=0)
                    file_details[key]['rx_files'].append(pod_file_name)

        # load metric collected from each worker node
        for metric_type, files in worker_metrics.items():
            for metric_file in files:
                metric_full_path = os.path.join(base_dir, metric_file)
                if is_verbose:
                    print(f"Loading metric type: {metric_type} file: {metric_full_path}")
                try:
                    if metric_type not in file_details[key]:
                        file_details[key][metric_type] = np.loadtxt(metric_full_path)
                        if is_verbose:
                            print("Loaded shape", file_details[key][metric_type].shape)
                except ValueError as e:
                    print(f"Failed to load file: {metric_full_path}")
                    print(f"Error occurred in file '{metric_full_path}' at line {e.__traceback__.tb_lineno}: {e}")

        file_details[key]['tx_pod_cores'] = file_details[key]['tx_pod_int'].shape[1]
        file_details[key]['rx_pod_cores'] = file_details[key]['rx_pod_int'].shape[1]

        file_details[key]['tx_pod_n_queues'] = file_details[key]['tx_queues'].shape[1]
        file_details[key]['rx_pod_n_queues'] = file_details[key]['rx_queues'].shape[1]

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
        output: Optional[str] = None
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
        tolerance: Optional[float] = 0.02,
        output: Optional[str] = None
):
    """Plot observed TX PPS against target PPS.  Here we cross correlate tx and target.
    i.e. identify for given core set what we reached.

    :param dataset: Dictionary containing file details.
    :param size: Packet size for which experiments are conducted.
    :param cores: List of cores for which experiments are conducted.
    :param tolerance: Tolerance value for the plot.
    :param output: output path where we need save plot
    :return:
    """

    plt.figure(figsize=(10, 6))

    target_pps_list = []
    observed_pps_list = []

    for key, details in dataset.items():
        if details['size'] == size and tuple(details['cores']) == tuple(cores):
            target_pps = details['pps']
            tx_data = details['tx_data']
            observed_pps = np.mean(tx_data[:, 1])
            target_pps_list.append(target_pps)
            observed_pps_list.append(observed_pps)

    sorted_indices = np.argsort(target_pps_list)
    sorted_target_pps = np.array(target_pps_list, dtype=float)[sorted_indices]
    sorted_observed_pps = np.array(observed_pps_list, dtype=float)[sorted_indices]

    fig, ax = plt.subplots(figsize=(10, 7))

    ax.bar(sorted_target_pps.astype(str),
           sorted_observed_pps, label='Observed PPS', color='lightgray')

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
        tolerance: Optional[float] = 0.02,
        output: Optional[str] = None
):
    """ Plot a bar graph showing the target PPS, observed TX PPS, and observed RX PPS.
    Here we cross correlate TX / RX and target. Assume TX x and RX x while target y.
    i.e. TX bounded by busy wait / CPU etc.

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

    for key, details in dataset.items():
        if details['size'] == size and tuple(details['cores']) == tuple(cores):
            target_pps = details['pps']
            tx_data = details['tx_data']
            rx_data = details['rx_data']

            observed_tx_pps = np.mean(tx_data[:, 1])
            observed_rx_pps = np.mean(rx_data[:, 0])

            target_pps_list.append(float(target_pps))
            observed_tx_pps_list.append(observed_tx_pps)
            observed_rx_pps_list.append(observed_rx_pps)

    # Sorting by target PPS
    sorted_indices = np.argsort(target_pps_list)
    sorted_target_pps = np.array(target_pps_list)[sorted_indices]
    sorted_observed_tx_pps = np.array(observed_tx_pps_list)[sorted_indices]
    sorted_observed_rx_pps = np.array(observed_rx_pps_list)[sorted_indices]

    fig, ax = plt.subplots(figsize=(10, 7))

    bar_width = 0.2
    index = np.arange(len(sorted_target_pps))

    ax.bar(index - bar_width,
           sorted_observed_tx_pps,
           width=bar_width,
           label='Observed TX PPS',
           color='lightgray')
    ax.bar(index, sorted_observed_rx_pps,
           width=bar_width,
           label='Observed RX PPS',
           color='green',
           alpha=0.5)
    ax.scatter(index, sorted_target_pps, label='Target PPS', color='orange', marker='o', s=50)
    ax.plot(index, sorted_target_pps, color='orange', linestyle='-', alpha=1.0)

    ax.set_xlabel('Target PPS (Packets per Second)')
    ax.set_ylabel('PPS (Packets per Second)')
    ax.set_title(f'Observed TX vs. RX PPS for Cores {cores}, Packet Size {size}')
    ax.set_xticks(index)
    ax.set_xticklabels(sorted_target_pps.astype(int), rotation=45)
    ax.legend()
    ax.grid(True)

    plt.tight_layout()

    if output:
        plt.savefig(output)
        print(f"Plot saved to {output}")
    else:
        plt.show()


def plot_tx_rx_interrupts(
        dataset: dict,
        size,
        cores,
        tolerance=0.02,
        output=None,
        pps=None,
        side='tx',
):
    """ Plot interrupts rate per queues.
    It takes a stride size = number of queues and aggregate and normalize rate
    for each core.  The output of aggregate is matrix of size (q, c)
    where q is number of queues and c is number of cores.

    :param dataset: Dictionary containing experiment data.
    :param size: Size parameter for the plot.
    :param cores: Cores used for the experiment.
    :param tolerance: Tolerance value for the plot.
    :param output: Optional. Filepath to save the plot. If not provided, the plot will be displayed.
    :param pps: Optional. PPS value for the plot.
    :param side: Optional. Side parameter for the plot (default is 'tx').

    :return: None
    """

    for key, details in dataset.items():
        if (
                details['size'] == size
                and tuple(details['cores']) == tuple(cores)
                and int(details['pps']) == int(pps)
        ):
            # data collected txrx is 9 entries.
            # stride across 9 to compute aggregate.
            # note interrupts in logs is rate sample each second
            m = details[f'{side}_pod_int']
            n_queue = int(np.max(m[:, 0]) + 1)
            m = m[:, 1:]

            n_cpu = m.shape[1]
            n_samples = m.shape[0]

            n_chunks = len(m) // n_queue
            reshaped_m = m.reshape(n_chunks, n_cpu, -1)
            reshaped_m = np.swapaxes(reshaped_m, 0, 1)
            # num of cpu, num_queue
            strided_sum = np.sum(reshaped_m, axis=1)
            strided_sum = strided_sum.reshape(n_queue, n_cpu)

            # filter cpu with zero interrupts
            non_zero_cpu_ids = np.where(np.sum(strided_sum, axis=0) > 0)[0]
            filtered_strided_sum = strided_sum[:, non_zero_cpu_ids]

            fig = plt.figure(figsize=(18, 6))
            ax = fig.add_subplot(111)

            width = 0.25
            for i, queue_id in enumerate(range(n_queue)):
                x = np.arange(len(non_zero_cpu_ids))
                ax.bar(x + i * width, filtered_strided_sum[queue_id],
                       width=width, label=f'Queue {queue_id}', alpha=0.7)

            ax.set_xlabel('core id')
            ax.set_ylabel('Number of Interrupts per queue')
            ax.set_title(f'({side.upper()} Side) Interrupts per Queue and CPU, pps {pps}')
            ax.set_xticks(x + (n_queue - 1) * width / 2)
            ax.set_xticklabels([f'{non_zero_cpu_ids[cpu_idx]}' for cpu_idx in range(len(non_zero_cpu_ids))])

            details_text = f"PPS: {details['pps']} pps\n" \
                           f"Side: {side.upper()} ({'Transmit' if side == 'tx' else 'Receive'})\n" \
                           f"Cores Used: {cores}\nSize: {size}\nTolerance: {tolerance}\n" \
                           f"Byte Size: {details['size']}"

            plt.text(1.01, 0.5, details_text, fontsize=10,
                     transform=ax.transAxes, verticalalignment='center')

            ax.legend()
            ax.grid(True)

    plt.tight_layout()

    if output:
        plt.savefig(output)
        print(f"Plot saved to {output}")
    else:
        plt.show()


def plot_queue_rate(
        dataset: dict,
        size,
        cores,
        output=None,
        pps=None,
        side='tx',
        n_qs=8,
):
    """ Plot pps rate observed on each TX and RX queue.

    Note each sample collected on TX pod and RX, thus on TX POD RX queue almost 0.

    :param n_qs:
    :param dataset: Dictionary containing experiment data.
    :param size: Size parameter for the plot.
    :param cores: Cores used for the experiment.
    :param output: Optional. Filepath to save the plot. If not provided, the plot will be displayed.
    :param pps: Optional. PPS value for the plot.
    :param side: Optional. Side parameter for the plot (default is 'tx').

    :return: None
    """

    for key, details in dataset.items():
        if (
                details['size'] == size
                and tuple(details['cores']) == tuple(cores)
                and int(details['pps']) == int(pps)
        ):
            queues_data = details[f'{side}_queues']

            n_queues = n_qs * 2
            queue_means = np.mean(queues_data, axis=0)
            queue_means = queue_means[:n_qs * 2]

            fig, ax = plt.subplots(figsize=(12, 8))

            index = np.arange(n_queues)
            bar_width = 0.35

            tx_color = 'skyblue'
            rx_color = 'orange'

            tx_queue_means = queue_means[:n_qs]
            rx_queue_means = queue_means[n_qs:]

            ax.bar(index[:n_qs], tx_queue_means, bar_width, label=f'TX Queues PPS', color=tx_color)
            ax.bar(index[n_qs:], rx_queue_means, bar_width, label=f'RX Queues PPS', color=rx_color)

            if pps is not None:
                ax.axhline(y=float(pps), color='r',
                           linestyle='--', label=f'Target PPS ({pps})')

            ax.set_xlabel(f'Queue ID {n_qs}-TX / {n_qs} RX')
            ax.set_ylabel('Total PPS')
            ax.set_title(f'Mean PPS for POD-{side.upper()} Queue, Size {size}, Cores {cores} , pps {pps}')
            ax.set_xticks(range(n_qs * 2))
            ax.set_xticklabels([f'{i}' for i in range(n_qs * 2)])
            ax.legend()
            ax.grid(True, which="both", ls="-")

            plt.tight_layout()

            if output:
                plt.savefig(output)
                print(f"Plot saved to {output}")
            else:
                plt.show()


def plot_cpu_core_utilization(
        dataset: dict,
        size,
        cores,
        output=None,
        pps=None,
        side='tx',
):
    """ Plot cpu utilization per core,
    direction either TX POD or RX POD.

    :param dataset: Dictionary containing experiment data.
    :param size: Size parameter for the plot.
    :param cores: Cores used for the experiment.
    :param output: Optional. Filepath to save the plot. If not provided, the plot will be displayed.
    :param pps: Optional. PPS value for the plot.
    :param side: Optional. Side parameter for the plot (default is 'tx').

    :return: None
    """

    for key, details in dataset.items():
        if (
                details['size'] == size
                and tuple(details['cores']) == tuple(cores)
                and int(details['pps']) == int(pps)
        ):
            cpu_core_util = details[f'{side}_cpu']
            n_cores = cpu_core_util.shape[1]
            core_util_means = np.mean(cpu_core_util, axis=0)

            fig, ax = plt.subplots(figsize=(12, 8))
            index = np.arange(n_cores)
            bar_width = 0.35

            ax.bar(index, core_util_means, bar_width, label=f'Mean CPU Utilization')

            ax.set_xlabel('Core ID')
            ax.set_ylabel('Mean Utilization (%)')
            ax.set_title(f'CPU Mean Core Utilization for '
                         f'POD-{side.upper()} '
                         f'Size {size}, '
                         f'Cores {cores}, '
                         f'Target PPS {pps}')
            ax.set_xticks(index)
            ax.set_xticklabels([f'{i}' for i in range(n_cores)])
            ax.legend()
            ax.grid(True, which="both", ls="-")

            plt.tight_layout()

            if output:
                plt.savefig(output)
                print(f"Plot saved to {output}")
            else:
                plt.show()


def combine_cpu_interrupt_plots(
        dataset: dict,
        size,
        cores,
        output=None,
        pps=None,
        side='tx',
):
    """ Combine CPU utilization per core and interrupts per queue in one plot.
    We compute percentage per queue, so we get percentage of interrupts on each queue.
    Thus, some core will loaded from rate of interrupts.

    :param dataset: Dictionary containing experiment data.
    :param size: Size parameter for the plot.
    :param cores: Cores used for the experiment.
    :param output: Optional. Filepath to save the plot. If not provided, the plot will be displayed.
    :param pps: Optional. PPS value for the plot.
    :param side: Optional. Side parameter for the plot (default is 'tx').

    :return: None
    """
    for key, details in dataset.items():
        if (
                details['size'] == size
                and tuple(details['cores']) == tuple(cores)
                and int(details['pps']) == int(pps)
        ):
            fig, ax1 = plt.subplots(figsize=(12, 8))

            # utilization per core
            cpu_core_util = details[f'{side}_cpu']
            n_cores = cpu_core_util.shape[1]
            core_util_means = np.mean(cpu_core_util, axis=0)

            index = np.arange(n_cores)
            bar_width = 0.35

            ax1.bar(index, core_util_means, bar_width, label=f'Mean CPU Utilization')
            ax1.set_xlabel('CPU ID')
            ax1.set_ylabel('CPU Utilization (%)')
            ax1.set_title(f'CPU Core Utilization % vs Interrupts % for '
                          f'POD-{side.upper()} Queues\nSize {size}, '
                          f'Cores {cores}, PPS {pps}')
            ax1.set_xticks(index)
            ax1.set_xticklabels([f'{i}' for i in range(n_cores)])
            ax1.legend(loc='upper left')
            ax1.grid(True, which="both", ls="-")

            # Interrupts per queue and CPU.
            m = details[f'{side}_pod_int']
            n_queue = int(np.max(m[:, 0]) + 1)
            m = m[:, 1:]
            n_cpu = m.shape[1]

            n_chunks = len(m) // n_queue
            reshaped_m = m.reshape(n_chunks, n_cpu, -1)
            reshaped_m = np.swapaxes(reshaped_m, 0, 1)
            strided_sum = np.sum(reshaped_m, axis=1)
            strided_sum = strided_sum.reshape(n_queue, n_cpu)

            # calculate interrupt percentages
            total_interrupts = np.sum(strided_sum)
            core_interrupt_percentages = (strided_sum * 100) / total_interrupts
            core_interrupt_normalized = np.sum(core_interrupt_percentages, axis=0, keepdims=True)

            # plot interrupts per core
            bottom = np.zeros(n_cores)
            for i in range(n_queue):
                ax1.bar(index, core_interrupt_percentages[i],
                        bar_width, label=f'Queue {i} Interrupts (%)', bottom=bottom)
                bottom += core_interrupt_percentages[i]

            ax1.set_ylabel('Percentage')
            ax1.legend(loc='upper right')
            ax1.grid(True, which="both", ls="-")

            plt.tight_layout()

            if output:
                plt.savefig(output)
                print(f"Plot saved to {output}")
            else:
                plt.show()


def plot_irq_sw_irq_rate(
        dataset: dict,
        size: int,
        cores: int,
        output: str = None,
):
    """Plots the IRQ and SIRQ rates for a given packet size and number of cores used.

    :param dataset: a dataset
    :param size: frame size
    :param cores: a list of cores that we plot [2, 4, 6] for example single core per pod.
    :param output: output file
    :return:
    """

    plt.figure(figsize=(10, 6))
    target_pps_list = []
    irq_rates_list = []
    sirq_rates_list = []

    for key, details in dataset.items():
        if details['size'] == size and cores == details['cores']:
            target_pps = details['pps']
            tx_data = details['tx_data']

            irq_idx = details['metadata']['irq_rate']['position']
            sirq_idx = details['metadata']['s_irq_rate']['position']

            irq_rate = np.mean(tx_data[:, irq_idx])
            sirq_rate = np.mean(tx_data[:, sirq_idx])

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
    ax.bar(index + bar_width / 2, sorted_sirq_rates, bar_width, label='SIRQ Rate', color='orange')

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
        output_dir=None,
        **kwargs
):
    """plot stats take metric dataset,
    callback that will plot and output dir (optional)

    :param metric_dataset:  a metric dataset.
    :param plot_type:  a type i.e. description for a callback what is plotting
    :param plotter: a callback that will use to plot
    :param output_dir: a output dir for where we store plots
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

        if kwargs:
            plotter(metric_dataset, experiment[0],
                    list(experiment[1]), output=output_file, **kwargs)
        else:
            plotter(metric_dataset, experiment[0],
                    list(experiment[1]), output=output_file)


def run_sampling(
        pps_values: list[int],
        num_cores: list[int]
):
    """Rn sampling script for each target pps.
    :param pps_values: list of pps value we collect samples for.
    :param num_cores: num cores to collect samples for.
    :return:
    """
    for pps in pps_values:
        for num_core in num_cores:
            print(f"Running sampling for {pps} pps , core count {num_core} ...")
            subprocess.run(
                [
                    './run_monitor_pps.sh', '-p', str(pps),
                    '-c', str(num_core)
                ]
            )
    print("Sampling completed.")


def find_files(
        key: tuple[int, int, int, int],
        files_dict: dict
):
    """
    Find files corresponding to the given key in the dictionary.
    Key is pps

    :param key: A tuple representing (pps, pairs, size, cores).
    :param files_dict: A dictionary containing lists of files for different types
    (tx_pod_int, rx_pod_int, tx_queues, rx_queues).
    :return: A dictionary containing file lists for each type corresponding to the key.
    """
    pps, pairs, size, cores = key
    result_files = {}

    for file_type, files_list in files_dict.items():
        # format of file we expect
        found_files = [file for file in files_list
                       if f"pr_{pps}_" in file and f"pairs_{pairs}_" in file
                       and f"size_{size}_" in file and f"cores_{cores}_" in file]
        result_files[file_type] = found_files

    return result_files


def combine_file_names(directory):
    """
    Combines file names under same experiment.
    based on PPS rate, number of pairs, and size.

    This method create single dict consisting of all files related to experiment.

    Example:
    {
        "200000 3 64 1": {
            "core_list": [
                "2",
                "4",
                "6"
            ],
            "files": [
                "/Users/spyroot/dev/trafgen/src/metrics/server_server2-ve-56377f29-e603-11ee-a122-179ee4765847_pr_200000_runtime_120_cores_1_pairs_3_size_64_core_list_6_ts_20240406063337.log",
                "/Users/spyroot/dev/trafgen/src/metrics/server_server1-ve-56377f29-e603-11ee-a122-179ee4765847_pr_200000_runtime_120_cores_1_pairs_3_size_64_core_list_4_ts_20240406063337.log",
                "/Users/spyroot/dev/trafgen/src/metrics/client_client0-ve-56377f29-e603-11ee-a122-179ee4765847_pr_200000_runtime_120_cores_1_pairs_3_size_64_core_list_2_ts_20240406063337.log",
                "/Users/spyroot/dev/trafgen/src/metrics/client_client1-ve-56377f29-e603-11ee-a122-179ee4765847_pr_200000_runtime_120_cores_1_pairs_3_size_64_core_list_4_ts_20240406063337.log",
                "/Users/spyroot/dev/trafgen/src/metrics/server_server0-ve-56377f29-e603-11ee-a122-179ee4765847_pr_200000_runtime_120_cores_1_pairs_3_size_64_core_list_2_ts_20240406063337.log",
                "/Users/spyroot/dev/trafgen/src/metrics/client_client2-ve-56377f29-e603-11ee-a122-179ee4765847_pr_200000_runtime_120_cores_1_pairs_3_size_64_core_list_6_ts_20240406063337.log"
            ],
            "worker_metrics": {
                "tx_pod_int": [
                    "tx-pod-int_pr_200000_runtime_120_cores_1_pairs_3_size_64_20240406063334.log"
                ],
                "rx_pod_int": [
                    "rx-pod-int_pr_200000_runtime_120_cores_1_pairs_3_size_64_20240406063334.log"
                ],
                "tx_queues": [
                    "tx-pod-queue_pr_200000_runtime_120_cores_1_pairs_3_size_64_ts_20240406063334.log"
                ],
                "rx_queues": [
                    "rx-pod-queue_pr_200000_runtime_120_cores_1_pairs_3_size_64_ts_20240406063334.log"
                ]
            }
        }
    }

    :param directory: The directory where the files are located.
    :return: A dictionary where keys are (PPS rate, number of pairs, size) tuples
    and values are lists of paths to combined files.
    """
    pod_files = [file for file in os.listdir(directory)
                 if (file.startswith('server_server') or
                     file.startswith('client_client')) and file.endswith('.log')]

    tx_pod_int_files = [file for file in os.listdir(directory)
                        if (file.startswith('tx-pod-int')) and file.endswith('.log')]
    rx_pod_int_files = [file for file in os.listdir(directory)
                        if (file.startswith('rx-pod-int')) and file.endswith('.log')]

    tx_queues_files = [file for file in os.listdir(directory)
                       if (file.startswith('tx-pod-queue')) and file.endswith('.log')]
    rx_queues_files = [file for file in os.listdir(directory)
                       if (file.startswith('rx-pod-queue')) and file.endswith('.log')]

    tx_cpu_files = [file for file in os.listdir(directory)
                    if file.startswith('tx-pod-cpu') and file.endswith('.log')]
    rx_cpu_files = [file for file in os.listdir(directory)
                    if file.startswith('rx-pod-cpu') and file.endswith('.log')]

    tx_softnet_files = [file for file in os.listdir(directory)
                    if file.startswith('tx-softnet-stat') and file.endswith('.log')]
    rx_softnet_files = [file for file in os.listdir(directory)
                    if file.startswith('rx-softnet-stat') and file.endswith('.log')]

    # all stats per experiment collected from worker node
    files_dict = {
        'tx_pod_int': tx_pod_int_files,
        'rx_pod_int': rx_pod_int_files,
        'tx_queues': tx_queues_files,
        'rx_queues': rx_queues_files,
        'tx_cpu': tx_cpu_files,
        'rx_cpu': rx_cpu_files,
        'tx_softnet': tx_softnet_files,
        'rx_softnet': rx_softnet_files

    }

    combined_files = {}
    for file in pod_files:
        file_parts = file.split('_')
        pps = file_parts[3].replace('pps', '')
        cores = file_parts[7]
        pairs = file_parts[9]
        size = file_parts[11]
        core_list = file_parts[14]
        key = (pps, pairs, size, cores)

        worker_metric_files = find_files(key, files_dict)

        if key not in combined_files:
            combined_files[key] = {'core_list': set(), 'files': [], 'worker_metrics': {}}

        combined_files[key]['core_list'].add(core_list)
        combined_files[key]['files'].append(os.path.join(directory, file))
        combined_files[key]['worker_metrics'].update(worker_metric_files)

    for key, value in combined_files.items():
        value['core_list'] = sorted(set(value['core_list']))

    return combined_files


def merge_file(
        files_list: list[str],
        output_file_name: str,
        output_directory: str
):
    """
    Merge a list of files into a single output file.

    :param files_list: List of paths to files to be merged.
    :param output_file_name: Name of the output merged file.
    :param output_directory: The directory where the merged file will be saved.
    """
    output_file_path = os.path.join(output_directory, output_file_name)
    with open(output_file_path, 'w') as outfile:
        for file in files_list:
            with open(file, 'r') as infile:
                outfile.write(infile.read())


def merge_files(
        combined_files: dict,
        metric_dir: str
):
    """
    Merge all experiments files under the same experiment
    for server and client pods.

    :param combined_files: A dictionary where keys are
                           (PPS rate, number of pairs, size, cores, core list)
    tuples and values are lists of paths to combined files.
    :param metric_dir: The directory where the merged files will be saved.
    """
    for key, file_data in combined_files.items():
        pps, pairs, size, cores = key
        files_list = file_data['files']
        cores_list = file_data['core_list']
        cores_list_str = "_".join(map(str, cores_list))
        server_files = [file for file in files_list if 'server_server' in file]
        client_files = [file for file in files_list if 'client_client' in file]

        if server_files:
            merge_file(server_files, f"tx_pps_{pps}_pairs_{pairs}_size_"
                                     f"{size}_cores_{cores}_"
                                     f"pods-cores_{cores_list_str}.log", metric_dir)

        if client_files:
            merge_file(client_files, f"rx_pps_{pps}_pairs_{pairs}_size_"
                                     f"{size}_cores_{cores}_"
                                     f"pods-cores_{cores_list_str}.log", metric_dir)


def sample_entry(metric_dataset):
    """
    Sample one entry and print what we loaded
    :param metric_dataset:
    :return:
    """
    first_record = next(iter(metric_dataset.values()))
    print("Dimension of first record's tx_data:",
          first_record['tx_data'].shape
          if first_record['tx_data'] is not None else None)
    print("Dimension of first record's rx_data:",
          first_record['rx_data'].shape
          if first_record['rx_data'] is not None else None)
    print(first_record)


def main(cmd):
    """Run main,
     note sampling is optional arg, by default,
     we read metric dir and plot all samples collected.

    :return:
    """

    if cmd.sample:
        run_sampling(cmd.pps_values, cmd.cores)

    if cmd.output_dir:
        os.makedirs(cmd.output_dir, exist_ok=True)

    directory = os.path.join(os.getcwd(), cmd.metric_dir)
    combine_files = combine_file_names(directory)

    if cmd.debug:
        sample_key, sample_value = next(iter(combine_files.items()))
        print(json.dumps(sample_value, indent=4))

    metric_dataset = dataset_files_from_dict(combine_files, directory)
    if cmd.debug:
        sample_entry(metric_dataset)

    experiments_dir = os.path.join(directory, "experiments")
    if not os.path.exists(experiments_dir):
        os.makedirs(experiments_dir)

    if cmd.print_metric:
        print_metric(metric_dataset)

    plot_stats(metric_dataset, "tx_bounded", plot_tx_bound, output_dir=cmd.output_dir)
    plot_stats(metric_dataset, "rx_bounded", plot_rx_bound, output_dir=cmd.output_dir)
    plot_stats(metric_dataset, "drop_bounded", plot_drop_rate, output_dir=cmd.output_dir)
    plot_stats(metric_dataset, "sw_irq_bounded", plot_irq_sw_irq_rate, output_dir=cmd.output_dir)

    all_pps_values = [details['pps'] for details in metric_dataset.values()]

    for pps in all_pps_values:
        plot_stats(metric_dataset,
                   f"plot_txrx_interrupts_rx_pps_{pps}",
                   plot_tx_rx_interrupts,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='rx')

        plot_stats(metric_dataset,
                   f"plot_txrx_interrupts_tx_pps_{pps}",
                   plot_tx_rx_interrupts,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='tx')

    for pps in all_pps_values:
        plot_stats(metric_dataset,
                   f"plot_rx_queue_rate_rx_pps_{pps}",
                   plot_queue_rate,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='rx')

        plot_stats(metric_dataset,
                   f"plot_queue_rate_tx_pps_{pps}",
                   plot_queue_rate,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='tx')

    for pps in all_pps_values:
        plot_stats(metric_dataset,
                   f"plot_cpu_core_utilization_rx_pps_{pps}",
                   plot_cpu_core_utilization,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='rx')

        plot_stats(metric_dataset,
                   f"plot_cpu_core_utilization_tx_pps_{pps}",
                   plot_cpu_core_utilization,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='tx')

    for pps in all_pps_values:
        plot_stats(metric_dataset,
                   f"combine_tx_cpu_interrupt_plots_{pps}",
                   combine_cpu_interrupt_plots,
                   output_dir=cmd.output_dir,
                   pps=pps,
                   side='tx')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process metrics directory.')
    parser.add_argument('-m', '--metric_dir', type=str, default='metrics', help='Directory path for metrics')
    parser.add_argument('-p', '--print', dest='print_metric', action='store_true', help='Print metric dataset')
    parser.add_argument('-s', '--sample', action='store_true', help='Collect samples before processing metrics')
    parser.add_argument('--pps_values', nargs='*',
                        type=int, default=[1000, 10000, 20000, 50000,
                                           100000, 200000, 500000, 1000000],
                        help='List of PPS values for sampling')
    parser.add_argument('--cores', nargs='*',
                        type=int, default=[1, 2, 3, 4],
                        help='List of num cores for each pps value to run')
    parser.add_argument('-o', '--output_dir', type=str, default='plots', help='Output directory for plots')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    args = parser.parse_args()
    main(args)