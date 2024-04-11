# This script parse soft net stats col based on kernel version
# and output to stdout in tabular format and provide option to sort
# by rps, dropped, processed, flow_limit_count, cpu_collision etc
#
# Auto: Mus mbayramov@vmware.com
import argparse

column_indices = {
    'processed': 0,
    'dropped': 1,
    'time_squeeze': 2,
    'cpu_collision': 8,
    'rx_rps': 9,
    'flow_limit_count': 10,
}


def process_soft_net_stat(
        file_path,
        sort_column=None
):
    """
    Process and display soft net statistics from the given file in a tabular format.
    :param file_path: Path to the file containing soft net statistics.
    """
    # kernel 4

    # seq_printf(seq,
    # 		   "%08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x\n",
    # 		   sd->processed,     col 0
    # 		   sd->dropped,       col 1
    # 		   sd->time_squeeze,  col 2
    # 		   0,                 col 3
    # 		   0, 0, 0, 0, /* was fastroute */ col - 4 - 7
    # 		   0,	/* was cpu_collision */    col 8
    # 		   sd->received_rps,               col 9
    # 		   flow_limit_count);              col 10

    # https://elixir.bootlin.com/linux/v4.18/source/net/core/net-procfs.c#L162
    stat_labels_v4 = [
        'processed',     # 0
        'dropped',       # 1
        'time_squeeze',  # 2
        '0', # 3
        '0', # 4
        '0', # 5
        '0', # 6
        '0', # 7
        'cpu_collision',     # 8
        'rx_rps',            # 9
        'flow_limit_count',  # 10
    ]

    # kernel 5 https://elixir.bootlin.com/linux/v5.14/source/net/core/net-procfs.c#L169
    stat_labels_v5 = [
            'processed',
            'dropped',
            'time_squeeze',
            '0',
            '0',
            '0',
            '0',
            '0',
            'cpu_collision',
            'rx_rps',
            'flow_limit_count',
            'softnet_backlog_len',
            'index'
        ]

    # kernel 5 mapping 13 col
    # seq_printf(seq, "%08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x\n",
    #            sd->processed,
    #            sd->dropped,
    #            sd->time_squeeze,
    #            0,           / ? /
    #            0, 0, 0, 0, / *was fastroute * /
    #            0,          / *was cpu_collision * /
    #            sd->received_rps,
    #            flow_limit_count,
    #            softnet_backlog_len(sd),
    #            (int) seq->index);


    stat_labels_v6 = [
        'processed',
        'dropped',
        'time_squeeze',
        '0',  # Placeholder for columns not used
        '0',
        '0',
        '0',
        '0',
        'cpu_collision',
        'rx_rps',
        'flow_limit_count',
        'total_queue_len',  # Combined input_qlen + process_qlen
        'index',
        'input_qlen',
        'process_qlen',
    ]

    # kernel 6
    # https://elixir.bootlin.com/linux/v6.8.5/source/net/core/net-procfs.c
    # /* the index is the CPU id owing this sd. Since offline CPUs are not
	#  * displayed, it would be othrwise not trivial for the user-space
	#  * mapping the data a specific CPU
	#  */
	# seq_printf(seq,
	# 	   "%08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x "%08x %08x\n",
	# 	   sd->processed,
    # 	   sd->dropped,
    # 	   sd->time_squeeze,
    # 	   0,
	# 	   0, 0, 0, 0, /* was fastroute */
	# 	   0,	/* was cpu_collision */
	# 	   sd->received_rps, flow_limit_count,
	# 	   input_qlen + process_qlen,
    # 	   (int)seq->index,
	# 	   input_qlen,
    # 	   process_qlen);

    data = []
    with open(file_path) as file:
        for cpu_index, line in enumerate(file):
            stats = line.strip().split()
            if not stats:
                continue
            stats = [int(stat, 16) for stat in stats]
            data.append((cpu_index, stats))

    # sort by column
    if sort_column and sort_column in column_indices:
        sort_index = column_indices[sort_column]
        data.sort(key=lambda x: x[1][sort_index])

    for cpu_index, stats in data:
        if len(stats) <= 11:
            stat_labels = stat_labels_v4
        elif len(stats) <= 13:
            stat_labels = stat_labels_v5
        else:
            stat_labels = stat_labels_v6

        print(f"CPU {cpu_index}")
        label_width = max(len(label) for label in stat_labels) + 2
        stat_widths = [max(len(str(stat)), label_width) for stat in stats]

        # labels
        for label, width in zip(stat_labels, stat_widths):
            print(f"{label:<{width}}", end=' ')
        print()

        # values
        for stat, width in zip(stats, stat_widths):
            print(f"{stat:<{width}}", end=' ')
        print('\n')

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Process and display soft net statistics.")
    parser.add_argument("file_path", nargs='?', default='test.data', help="Path to the soft net statistics file")
    sort_help_message = f"Column name to sort by (options: {', '.join(column_indices.keys())})"
    parser.add_argument("--sort", type=str, choices=column_indices.keys(), help=sort_help_message)
    args = parser.parse_args()
    process_soft_net_stat(args.file_path, args.sort)
